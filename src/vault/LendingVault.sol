// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {DecimalMath} from "../libraries/DecimalMath.sol";
import {Uniswap} from "../libraries/Uniswap.sol";
import {LiquidityDeployer} from "../libraries/LiquidityDeployer.sol";
import {IVault} from "../interfaces/IVault.sol";
import {ITokenRepo} from "../TokenRepo.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol"; 

import {
    LiquidityPosition, 
    LiquidityType,
    LoanPosition,
    OutstandingLoan
} from "../types/Types.sol";

interface INomaFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

// Custom errors
error NotInitialized();
error InsufficientLoanAmount();
error InvalidDuration();
error InsufficientFloorBalance();
error NoActiveLoan();
error ActiveLoan();
error LoanExpired();
error InsufficientCollateral();
error CantRollLoan();
error NoLiquidity();
error OnlyVault();
error InvalidRepayAmount();
error InvalidParams();
error NotPermitted();

/**
 * @title LendingVault
 * @notice A contract for managing lending and borrowing functionality within a vault.
 * @dev This contract extends the `BaseVault` contract and provides functionality for borrowing, repaying loans, and managing collateral.
 */
contract LendingVault is BaseVault {
    using SafeERC20 for IERC20;

    /**
     * @notice Calculates the total collateral required for a given borrow amount.
     * @param borrowAmount The amount of tokens to borrow.
     * @return collateralAmount The amount of collateral required.
     * @return intrinsicMinimumValue The intrinsic minimum value of the collateral.
     */
    function _getTotalCollateral(uint256 borrowAmount) internal view returns (uint256, uint256) {
        uint256 intrinsicMinimumValue = IModelHelper(modelHelper()).getIntrinsicMinimumValue(address(this));
        return (DecimalMath.divideDecimal(borrowAmount, intrinsicMinimumValue), intrinsicMinimumValue);
    }
    
    /**
     * @notice Calculate loan fees based on a daily rate of 0.057%
     * @param borrowAmount  principal amount borrowed
     * @param duration      loan duration in seconds
     * @return fees         total fees owed
     */
    function _calculateLoanFees(
        uint256 borrowAmount,
        uint256 duration
    ) internal view returns (uint256 fees) {
        uint256 SECONDS_IN_DAY = 86400;
        // daily rate = 0.057% -> 57 / 100_000
        uint256 daysElapsed = duration / SECONDS_IN_DAY;
        fees = (borrowAmount *_v.loanFee * daysElapsed) / 100_000;
    }
    /**
     * @notice Allows a user to borrow tokens from the vault's floor liquidity.
     * @param who The address of the borrower.
     * @param borrowAmount The amount of tokens to borrow.
     * @param duration The duration of the loan.
     */
    function borrowFromFloor(address who, uint256 borrowAmount, uint256 duration) public onlyInternalCalls {
        if (_v.timeLastMinted == 0) revert NotPermitted();
        if (borrowAmount == 0) revert InsufficientLoanAmount();
        if (duration < 30 days || duration > 365 days) revert InvalidDuration();
        if (_v.loanPositions[who].borrowAmount > 0) revert ActiveLoan(); 

        (uint256 collateralAmount,) = _getTotalCollateral(borrowAmount);
        uint256 loanFees = _calculateLoanFees(borrowAmount, duration);
        
        if (collateralAmount == 0) revert InsufficientCollateral();

        _fetchFromLiquidity(borrowAmount, true);

        IERC20(_v.pool.token0()).transferFrom(who, address(this), collateralAmount);  
        SafeERC20.safeTransfer(IERC20(address(_v.pool.token0())), _v.tokenRepo, collateralAmount);
        SafeERC20.safeTransfer(IERC20(address(_v.pool.token1())), who, borrowAmount - loanFees);

        uint256 totalLoans = _v.totalLoansPerUser[who];
        LoanPosition memory loanPosition = LoanPosition({
            borrowAmount: borrowAmount,
            collateralAmount: collateralAmount,
            fees: loanFees,
            expiry: block.timestamp + uint256(duration),
            duration: duration
        });

        _v.collateralAmount += collateralAmount;
        _v.loanPositions[who] = loanPosition;
        _v.totalLoansPerUser[who] = totalLoans++;
        _v.loanAddresses.push(who);
        _v.totalInterest += loanFees;
        
        _updatePositions([_v.floorPosition, _v.anchorPosition, _v.discoveryPosition]);
    }

    /**
     * @notice Pay back a portion or all of a loan.
     * @param who          borrower address
     * @param repayAmount  amount of borrowed token1 to repay
     */
    function paybackLoan(address who, uint256 repayAmount, bool isSelfRepaying) public onlyInternalCalls {
        if (_v.timeLastMinted == 0) revert NotPermitted();
        LoanPosition storage loan = _v.loanPositions[who];

        if (loan.borrowAmount == 0) revert NoActiveLoan();
        if (block.timestamp > loan.expiry) revert LoanExpired();

        // If repayAmount is zero, treat as full repayment
        if (repayAmount == 0) {
            repayAmount = loan.borrowAmount;
        } else if (repayAmount > loan.borrowAmount) {
            revert InvalidRepayAmount();
        }

        // Snapshot original values for proportional calculation
        uint256 originalBorrow    = loan.borrowAmount;
        uint256 originalCollateral = loan.collateralAmount;

        // Calculate how much collateral to return
        uint256 collateralToReturn = (originalCollateral * repayAmount) / originalBorrow;

        // Pull in repayment tokens
        if (!isSelfRepaying) {
            IERC20(_v.pool.token1()).transferFrom(who, address(this), repayAmount);
        }

        // Release proportional collateral
        ITokenRepo(_v.tokenRepo).transferToRecipient(
            _v.pool.token0(),
            who,
            collateralToReturn
        );

        _v.collateralAmount -= collateralToReturn;

        // Rebalance liquidity for the repaid amount
        _fetchFromLiquidity(repayAmount, false);

        // Update loan position
        loan.borrowAmount     = originalBorrow - repayAmount;
        loan.collateralAmount = originalCollateral - collateralToReturn;

        // If fully repaid, remove the position
        if (loan.borrowAmount == 0) {
            delete _v.loanPositions[who];
            _removeLoanAddress(who);
        }
    }
    
    /**
     * @notice Allows a user to roll over a loan.
     * @param who The address of the borrower.
     */
    function rollLoan(address who, uint256 newDuration) public onlyInternalCalls 
    returns (uint256 newBorrowAmount) {
        if (_v.timeLastMinted == 0) revert NotPermitted();
        // Fetch the loan position
        LoanPosition storage loan = _v.loanPositions[who];

        uint256 currentDuration = loan.duration;

        // Check if the loan exists
        if (loan.borrowAmount == 0) revert NoActiveLoan();

        // Check if the loan has expired
        if (block.timestamp > loan.expiry) revert LoanExpired();

        // Ensure the new duration is valid
        if (newDuration == 0 || newDuration > 30 days) revert InvalidDuration();

        // Recalculate the collateral value
        uint256 newCollateralValue = DecimalMath.multiplyDecimal(
            loan.collateralAmount, 
            IModelHelper(modelHelper()).getIntrinsicMinimumValue(address(this))
        ); 

        // Ensure the new collateral value is sufficient to cover the borrow amount
        if (newCollateralValue <= loan.borrowAmount) revert CantRollLoan();

        // Calculate the new borrow amount and fees
        newBorrowAmount = newCollateralValue - loan.borrowAmount;

        // Calculate the new fees
        uint256 newFees = _calculateLoanFees(newBorrowAmount, currentDuration + newDuration);

        // Update the loan's expiry to reflect the new duration 
        loan.expiry = loan.expiry + newDuration;
        loan.duration = currentDuration + newDuration;
        loan.borrowAmount = loan.borrowAmount + newBorrowAmount;
        
        _fetchFromLiquidity(newBorrowAmount, true);

        // Transfer the new borrow amount (minus fees) to the borrower
        IERC20(_v.pool.token1()).transfer(who, newBorrowAmount - newFees);     

        // Update the vault's liquidity positions
        _updatePositions([_v.floorPosition, _v.anchorPosition, _v.discoveryPosition]);             
    }

    function addCollateral(address who, uint256 amount) public onlyInternalCalls {
        if (_v.timeLastMinted == 0) revert NotPermitted();
        if (amount == 0) revert InsufficientCollateral();
        if (_v.loanPositions[who].borrowAmount == 0) revert NoActiveLoan();

        IERC20(_v.pool.token0()).transferFrom(who, address(this), amount);
        SafeERC20.safeTransfer(IERC20(address(_v.pool.token0())), _v.tokenRepo, amount);

        _v.collateralAmount += amount;
        _v.loanPositions[who].collateralAmount += amount;
    }

    /**
     * @notice Fetches liquidity from the floor position and redeploys it.
     * @param amount The amount to borrow.
     */
    function _fetchFromLiquidity(uint256 amount, bool remove) internal {
        (,, uint256 floorToken0Balance, uint256 floorToken1Balance) = IModelHelper(modelHelper())
        .getUnderlyingBalances(address(_v.pool), address(this), LiquidityType.Floor);

        if (amount <= 0) revert InvalidParams();

        if (remove) {
            if (floorToken1Balance < amount) revert InsufficientFloorBalance();
        }

        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];
        Uniswap.collect(address(_v.pool), address(this), _v.floorPosition.lowerTick, _v.floorPosition.upperTick);

        LiquidityDeployer
        .reDeployFloor(
            address(_v.pool), 
            address(this), 
            floorToken0Balance, 
            (
                remove ? 
                floorToken1Balance - amount : 
                floorToken1Balance + amount
            ), 
            positions
        );
        
    }

    /**
    * @notice Compute a pro-rata allocation of repayment funds across a set of loans.
    * @param funds            Total amount of debt token to distribute (units of token1).
    * @param pool             Array of eligible loans with their `who` and `borrowAmount`.
    * @param totalOutstanding Sum of all `borrowAmount` values in `pool`. Must be > 0.
    * @return toRepay         Array of per-loan repayment amounts aligned with `pool`.
    * @return spent           Total amount allocated (<= funds).
    */
    function _proRataAllocate(
        uint256 funds,
        OutstandingLoan[] memory pool,
        uint256 totalOutstanding
    ) internal pure returns (uint256[] memory toRepay, uint256 spent) {
        uint256 n = pool.length;
        toRepay = new uint256[](n);
        uint256 remaining = funds;

        // base pro-rata pass
        for (uint256 i = 0; i < n; i++) {
            if (remaining == 0) break;
            uint256 share = Math.mulDiv(funds, pool[i].borrowAmount, totalOutstanding);
            if (share > pool[i].borrowAmount) share = pool[i].borrowAmount;
            if (share > remaining) share = remaining;
            toRepay[i] = share;
            remaining -= share;
        }

        // distribute rounding leftovers
        for (uint256 i = 0; i < n && remaining > 0; i++) {
            uint256 room = pool[i].borrowAmount > toRepay[i] ? (pool[i].borrowAmount - toRepay[i]) : 0;
            if (room == 0) continue;
            uint256 add = room < remaining ? room : remaining;
            toRepay[i] += add;
            remaining -= add;
        }

        spent = funds - remaining;
    }

    /**
    * @notice Repay a window of loans (by LTV) using funds already held by the vault.
    * @param fundsToPull Amount of token1 to allocate across qualifying loans (must be <= vault balance).
    * @param start       Start index (inclusive) into `_v.loanAddresses`; may be 0.
    * @param limit       Max number of addresses to scan from `start`. If 0, scans until the end.
    * @return eligibleCount Number of qualifying loans found in the scanned window.
    * @return totalRepaid   Total token1 actually repaid across the window.
    * @return nextIndex     The index where scanning ended (`end`), for convenient batching.
    */
    function vaultSelfRepayLoans(
        uint256 fundsToPull,
        uint256 start,
        uint256 limit
    )
        public
        onlyInternalCalls
        returns (uint256 eligibleCount, uint256 totalRepaid, uint256 nextIndex)
    {
        address token1 = _v.pool.token1();
        uint256 availableFunds = IERC20(token1).balanceOf(address(this));
        if (fundsToPull == 0 || availableFunds < fundsToPull) {
            return (0, 0, start);
        }

        uint256 n = _v.loanAddresses.length;
        if (n == 0 || start >= n) {
            return (0, 0, start);
        }

        uint256 end = (limit == 0) ? n : start + limit;
        if (end > n) end = n;

        uint256 LTV_THRESHOLD_1E18 = _v.protocolParameters.selfRepayLtvTreshold * 1e15;

        // PASS 1: count
        uint256 count = 0;
        for (uint256 i = start; i < end; i++) {
            if (loanLTV(_v.loanAddresses[i]) >= LTV_THRESHOLD_1E18) {
                unchecked { count++; }
            }
        }
        if (count == 0) {
            return (0, 0, end);
        }

        // PASS 2: build pool
        OutstandingLoan[] memory pool = new OutstandingLoan[](count);
        uint256 totalOutstanding = 0;
        {
            uint256 idx = 0;
            for (uint256 i = start; i < end; i++) {
                address who = _v.loanAddresses[i];
                if (loanLTV(who) >= LTV_THRESHOLD_1E18) {
                    LoanPosition memory loan = _v.loanPositions[who];
                    if (loan.borrowAmount > 0) {
                        pool[idx] = OutstandingLoan({ who: who, borrowAmount: loan.borrowAmount });
                        totalOutstanding += loan.borrowAmount;
                        unchecked { idx++; }
                        if (idx == count) break;
                    }
                }
            }
            if (totalOutstanding == 0) {
                return (0, 0, end);
            }
        }

        // PRO-RATA via helper (reduces locals here)
        (uint256[] memory toRepay, /*spent*/) =
            _proRataAllocate(fundsToPull, pool, totalOutstanding);

        // Apply repayments
        for (uint256 i = 0; i < pool.length; i++) {
            uint256 amt = toRepay[i];
            if (amt == 0) continue;
            paybackLoan(pool[i].who, amt, true);
            totalRepaid += amt;
        }

        nextIndex = end;
        return (count, totalRepaid, nextIndex);
    }

    /**
     * @notice Defaults all expired loans and seizes the collateral.
     */
    function vaultDefaultLoans() public onlyInternalCalls returns (uint256 totalBurned, uint256 loansDefaulted) {
        totalBurned = 0;
        loansDefaulted = 0;
        for (uint256 i = 0; i < _v.loanAddresses.length; i++) {
            address who = _v.loanAddresses[i];
            LoanPosition storage loan = _v.loanPositions[who];
            if (block.timestamp > loan.expiry) {
                loansDefaulted++;
                uint256 seized = _seizeCollateral(who);
                totalBurned += seized;
                delete _v.loanPositions[who];
                _removeLoanAddress(who);
            }
        }
    }

    function vaultDefaultLoansRange(uint256 start, uint256 limit)
        public
        onlyInternalCalls
        returns (uint256 totalBurned, uint256 loansDefaulted, uint256 nextIndex)
    {
        totalBurned = 0;
        loansDefaulted = 0;

        uint256 n = _v.loanAddresses.length;
        if (n == 0 || start >= n || limit == 0) {
            nextIndex = start;
            return (totalBurned, loansDefaulted, nextIndex);
        }

        uint256 i = start;
        uint256 processed = 0;

        while (processed < limit && i < _v.loanAddresses.length) {
            address who = _v.loanAddresses[i];
            LoanPosition storage loan = _v.loanPositions[who];

            if (block.timestamp > loan.expiry && loan.borrowAmount > 0) {
                loansDefaulted++;
                uint256 seized = _seizeCollateral(who);
                totalBurned += seized;

                delete _v.loanPositions[who];
                _removeLoanAddress(who);
                // do not increment i; re-check the swapped-in entry
            } else {
                unchecked { i++; }
            }

            processed++;
        }

        nextIndex = i;
    }

    /**
     * @notice Seizes the collateral of a borrower.
     * @param who The address of the borrower.
     */
    function _seizeCollateral(address who) internal returns (uint256) {
        LoanPosition storage loan = _v.loanPositions[who];
        _v.collateralAmount -= loan.collateralAmount;
        ITokenRepo(_v.tokenRepo).transferToRecipient(_v.pool.token0(), address(this), loan.collateralAmount);
        
        IVault(address(this))
        .burnTokens(
            loan.collateralAmount
        );

        return loan.collateralAmount;
    }

    /**
     * @notice Removes a borrower's address from the list of loan addresses.
     * @param who The address of the borrower.
     */
    function _removeLoanAddress(address who) internal {
        for (uint256 i = 0; i < _v.loanAddresses.length; i++) {
            if (_v.loanAddresses[i] == who) {
                _v.loanAddresses[i] = _v.loanAddresses[_v.loanAddresses.length - 1];
                _v.loanAddresses.pop();
                break;
            }
        }
    }

    /**
     * @notice Internal function to update the liquidity positions.
     * @param _positions The new liquidity positions.
     */
    function _updatePositions(LiquidityPosition[3] memory _positions) internal {   
        if (_positions[0].liquidity == 0 || _positions[1].liquidity == 0 || _positions[2].liquidity == 0) revert NoLiquidity();

        _v.floorPosition = _positions[0];
        _v.anchorPosition = _positions[1];
        _v.discoveryPosition = _positions[2];
    }
   
    /**
    * @notice Retrieves the active loan details for a specific user.
    * @param who The address of the borrower.
    * @return borrowAmount The amount borrowed.
    * @return collateralAmount The collateral amount locked.
    * @return fees The total loan fees.
    * @return expiry The loan expiry timestamp.
    * @return duration The total loan duration.
    */
    function getActiveLoan(address who)
        public
        view
        returns (
            uint256 borrowAmount,
            uint256 collateralAmount,
            uint256 fees,
            uint256 expiry,
            uint256 duration
        )
    {
        LoanPosition storage loan = _v.loanPositions[who];

        if (loan.borrowAmount == 0) {
            return (0, 0, 0, 0, 0);
        }

        return (
            loan.borrowAmount,
            loan.collateralAmount,
            loan.fees,
            loan.expiry,
            loan.duration
        );
    }


    /**
     * @notice Retrieves the total collateral amount.
     * @return The total collateral amount.
     */
    function getCollateralAmount() public view returns (uint256) {
        return _v.collateralAmount;
    }

    // Count / index access
    function loanCount() public view returns (uint256) { 
        return _v.loanAddresses.length; 
    }
    
    function loanLTV(address who) public view returns (
        uint256 ltv1e18
    ) {
        LoanPosition storage loan = _v.loanPositions[who];
        uint256 borrowAmount = loan.borrowAmount;
        uint256 collateralAmount = loan.collateralAmount;
        if (borrowAmount == 0 || collateralAmount == 0) {
            return (0);
        }
        uint256 imv = IModelHelper(modelHelper()).getIntrinsicMinimumValue(address(this));
        uint256 collateralValue1e18 = DecimalMath.multiplyDecimal(collateralAmount, imv);
        if (collateralValue1e18 == 0)  {
            return (type(uint256).max);
        }
        ltv1e18 = DecimalMath.divideDecimal(collateralValue1e18, borrowAmount);
    }

    function selfRepayLtvTreshold() public view returns (uint256) {
        return _v.protocolParameters.selfRepayLtvTreshold;
    }

    function calculateLoanFees(uint256 borrowAmount, uint256 duration) public view returns (uint256) {
        return _calculateLoanFees(borrowAmount, duration);
    }

    /**
     * @notice Modifier to restrict access to the vault contract.
     */
    modifier onlyVault() {
        if (msg.sender != address(this)) revert OnlyVault();
        _;
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](13);

        selectors[0] = bytes4(keccak256(bytes("borrowFromFloor(address,uint256,uint256)")));    
        selectors[1] = bytes4(keccak256(bytes("paybackLoan(address,uint256,bool)")));
        selectors[2] = bytes4(keccak256(bytes("rollLoan(address,uint256)")));
        selectors[3] = bytes4(keccak256(bytes("getCollateralAmount()")));
        selectors[4] = bytes4(keccak256(bytes("getActiveLoan(address)")));
        selectors[5] = bytes4(keccak256(bytes("calculateLoanFees(uint256,uint256)")));
        selectors[6] = bytes4(keccak256(bytes("addCollateral(address,uint256)")));
        selectors[7] = bytes4(keccak256(bytes("vaultDefaultLoans()")));
        selectors[8] = bytes4(keccak256(bytes("vaultSelfRepayLoans(uint256,uint256,uint256)")));
        selectors[9] = bytes4(keccak256(bytes("loanLTV(address)")));
        selectors[10] = bytes4(keccak256(bytes("loanCount()")));
        selectors[11] = bytes4(keccak256(bytes("vaultDefaultLoansRange(uint256,uint256)")));
        selectors[12] = bytes4(keccak256(bytes("selfRepayLtvTreshold()")));

        return selectors;
    }
}