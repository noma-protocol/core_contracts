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

import {
    LiquidityPosition, 
    LiquidityType,
    LoanPosition
} from "../types/Types.sol";

interface IOikosFactory {
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

        _updatePositions([_v.floorPosition, _v.anchorPosition, _v.discoveryPosition]);
    }

    /**
     * @notice Pay back a portion or all of a loan.
     * @param who          borrower address
     * @param repayAmount  amount of borrowed token1 to repay
     */
    function paybackLoan(address who, uint256 repayAmount) public onlyInternalCalls {
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
        IERC20(_v.pool.token1()).transferFrom(who, address(this), repayAmount);

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
    function rollLoan(address who, uint256 newDuration) public onlyInternalCalls {
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
        uint256 newBorrowAmount = newCollateralValue - loan.borrowAmount;

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
     * @notice Defaults all expired loans and seizes the collateral.
     */
    function defaultLoans() public onlyInternalCalls returns (uint256 totalBurned, uint256 loansDefaulted) {
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
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = bytes4(keccak256(bytes("borrowFromFloor(address,uint256,uint256)")));    
        selectors[1] = bytes4(keccak256(bytes("paybackLoan(address,uint256)")));
        selectors[2] = bytes4(keccak256(bytes("rollLoan(address,uint256)")));
        selectors[3] = bytes4(keccak256(bytes("defaultLoans(address)")));
        selectors[4] = bytes4(keccak256(bytes("getCollateralAmount()")));
        selectors[5] = bytes4(keccak256(bytes("getActiveLoan(address)")));
        selectors[6] = bytes4(keccak256(bytes("calculateLoanFees(uint256,uint256)")));
        selectors[7] = bytes4(keccak256(bytes("addCollateral(address,uint256)")));
        return selectors;
    }
}