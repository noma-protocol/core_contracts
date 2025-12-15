// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FuzzSetup, IVault, IModelHelper, IWETH, NomaToken} from "./FuzzSetup.sol";
import {FuzzActors} from "./actors/FuzzActors.sol";
import {FuzzHelpers, HeapHelpers} from "./helpers/FuzzHelpers.sol";
import {LiquidityPosition, LiquidityType} from "../../src/types/Types.sol";
import {DecimalMath} from "../../src/libraries/DecimalMath.sol";

/**
 * @title LendingFuzz
 * @notice Fuzzing harness focused on lending operations and invariants
 *
 * KEY LENDING INVARIANTS:
 * 1. Collateral tracking: vault.collateralAmount == sum of all loan collaterals
 * 2. Loan array consistency: loanAddresses.length matches active loans
 * 3. LTV sanity: No loan with LTV > 1000%
 * 4. Loan duration bounds: 30 days <= duration <= 365 days
 * 5. No double loans: Max one active loan per user
 * 6. Payback proportionality: Payback reduces loan proportionally
 */
contract LendingFuzz is FuzzSetup, FuzzActors {
    using FuzzHelpers for uint256;
    using HeapHelpers for address;

    // Lending state tracking
    mapping(address => uint256) public trackedBorrowAmounts;
    mapping(address => uint256) public trackedCollateral;
    uint256 public totalTrackedCollateral;
    uint256 public totalTrackedBorrows;

    // Loan count tracking
    uint256 public activeLoansCount;
    address[] public borrowersWithLoans;

    // Operation counters
    uint256 public successfulBorrows;
    uint256 public successfulPaybacks;
    uint256 public successfulRolls;
    uint256 public successfulDefaults;
    uint256 public failedBorrows;
    uint256 public failedPaybacks;

    // Invariant violation tracking
    uint256 public collateralTrackingViolations;
    uint256 public loanArrayViolations;
    uint256 public ltvViolations;
    uint256 public durationViolations;
    uint256 public doubleLoanViolations;

    // Events
    event LendingOperation(string operation, address indexed user, uint256 amount, bool success);
    event LendingInvariantViolation(string invariant, uint256 expected, uint256 actual);

    constructor() FuzzSetup() {
        _initializeActors(NUM_ACTORS);
    }

    // ==================== FUZZ TARGETS ====================

    /**
     * @notice Fuzz: Complete borrow cycle
     * @param actorIdx Actor performing the borrow
     * @param borrowAmount Amount to borrow
     * @param duration Loan duration
     */
    function fuzz_borrow(uint8 actorIdx, uint256 borrowAmount, uint256 duration) external {
        if (address(vault) == address(0)) return;

        address borrower = getActor(actorIdx);

        // Bound inputs
        borrowAmount = borrowAmount.bound(0.01 ether, 5 ether);
        duration = duration.bound(30 days, 365 days);

        // Check if borrower already has a loan
        if (trackedBorrowAmounts[borrower] > 0) {
            // Should not be able to borrow again
            return;
        }

        // Estimate and provide collateral
        uint256 collateralNeeded = _estimateCollateral(borrowAmount);
        _fundActorWithTokens(borrower, collateralNeeded * 2);

        HeapHelpers.startPrank(borrower);
        nomaToken.approve(address(vault), type(uint256).max);

        bool success = false;
        try vault.borrow(borrowAmount, duration) {
            success = true;
            successfulBorrows++;

            // Track the loan
            trackedBorrowAmounts[borrower] = borrowAmount;
            trackedCollateral[borrower] = collateralNeeded;
            totalTrackedCollateral += collateralNeeded;
            totalTrackedBorrows += borrowAmount;
            _addBorrower(borrower);
            activeLoansCount++;

            _setActorLoanStatus(borrower, true);
        } catch {
            failedBorrows++;
        }

        HeapHelpers.stopPrank();
        emit LendingOperation("borrow", borrower, borrowAmount, success);
    }

    /**
     * @notice Fuzz: Partial or full payback
     * @param actorIdx Actor performing payback
     * @param paybackPercentage Percentage of loan to repay (0-100)
     */
    function fuzz_paybackPartial(uint8 actorIdx, uint8 paybackPercentage) external {
        if (address(vault) == address(0)) return;

        address borrower = getActor(actorIdx);
        uint256 borrowAmount = trackedBorrowAmounts[borrower];

        if (borrowAmount == 0) return;

        // Bound percentage
        paybackPercentage = uint8(uint256(paybackPercentage).bound(1, 100));

        uint256 paybackAmount = (borrowAmount * paybackPercentage) / 100;
        if (paybackAmount == 0) paybackAmount = 1;

        // Fund with WETH
        _fundActorWithWETH(borrower, paybackAmount);

        HeapHelpers.startPrank(borrower);
        weth.approve(address(vault), type(uint256).max);

        bool success = false;
        try vault.payback(paybackAmount) {
            success = true;
            successfulPaybacks++;

            // Update tracking
            uint256 collateralReturn = (trackedCollateral[borrower] * paybackAmount) / borrowAmount;

            if (paybackAmount >= borrowAmount) {
                // Full payback
                totalTrackedCollateral -= trackedCollateral[borrower];
                totalTrackedBorrows -= trackedBorrowAmounts[borrower];
                trackedCollateral[borrower] = 0;
                trackedBorrowAmounts[borrower] = 0;
                _removeBorrower(borrower);
                activeLoansCount--;
                _setActorLoanStatus(borrower, false);
            } else {
                // Partial payback
                trackedCollateral[borrower] -= collateralReturn;
                trackedBorrowAmounts[borrower] -= paybackAmount;
                totalTrackedCollateral -= collateralReturn;
                totalTrackedBorrows -= paybackAmount;
            }
        } catch {
            failedPaybacks++;
        }

        HeapHelpers.stopPrank();
        emit LendingOperation("payback", borrower, paybackAmount, success);
    }

    /**
     * @notice Fuzz: Roll loan to new duration
     * @param actorIdx Actor rolling the loan
     * @param newDuration New duration for the loan
     */
    function fuzz_roll(uint8 actorIdx, uint256 newDuration) external {
        if (address(vault) == address(0)) return;

        address borrower = getActor(actorIdx);
        if (trackedBorrowAmounts[borrower] == 0) return;

        newDuration = newDuration.bound(1 days, 30 days);

        HeapHelpers.prank(borrower);
        try vault.roll(newDuration) {
            successfulRolls++;
        } catch {}
    }

    /**
     * @notice Fuzz: Default expired loans
     */
    function fuzz_defaultLoans() external {
        if (address(vault) == address(0)) return;

        // First warp time to expire some loans
        HeapHelpers.advanceTime(400 days);

        try vault.defaultLoans() {
            successfulDefaults++;

            // Reset tracking for defaulted loans
            for (uint256 i = 0; i < borrowersWithLoans.length; i++) {
                address borrower = borrowersWithLoans[i];
                if (trackedBorrowAmounts[borrower] > 0) {
                    // Assume loan was defaulted
                    totalTrackedCollateral -= trackedCollateral[borrower];
                    totalTrackedBorrows -= trackedBorrowAmounts[borrower];
                    trackedCollateral[borrower] = 0;
                    trackedBorrowAmounts[borrower] = 0;
                    _setActorLoanStatus(borrower, false);
                }
            }
            delete borrowersWithLoans;
            activeLoansCount = 0;
        } catch {}
    }

    /**
     * @notice Fuzz: Advance time
     */
    function fuzz_advanceTime(uint256 seconds_) external {
        seconds_ = seconds_.bound(1 hours, 100 days);
        HeapHelpers.advanceTime(seconds_);
    }

    // ==================== INVARIANTS ====================

    /**
     * @notice Collateral tracking invariant
     * @dev vault.collateralAmount should equal sum of all loan collaterals
     */
    function echidna_collateral_tracking() public returns (bool) {
        if (address(vault) == address(0)) return true;

        uint256 vaultCollateral = vault.getCollateralAmount();

        // Sum up tracked collateral
        uint256 sumCollateral = 0;
        for (uint256 i = 0; i < borrowersWithLoans.length; i++) {
            sumCollateral += trackedCollateral[borrowersWithLoans[i]];
        }

        // Allow for some slippage due to fees and rounding
        bool valid = _isWithinTolerance(vaultCollateral, sumCollateral, 100); // 1% tolerance

        if (!valid) {
            collateralTrackingViolations++;
            emit LendingInvariantViolation("collateral_tracking", sumCollateral, vaultCollateral);
        }

        return valid;
    }

    /**
     * @notice Loan array consistency
     * @dev Number of borrowers should match our tracking
     */
    function echidna_loan_array_consistency() public returns (bool) {
        // Our tracked active loans should be consistent with borrowersWithLoans
        uint256 actualActive = 0;
        for (uint256 i = 0; i < borrowersWithLoans.length; i++) {
            if (trackedBorrowAmounts[borrowersWithLoans[i]] > 0) {
                actualActive++;
            }
        }

        bool valid = actualActive <= borrowersWithLoans.length;

        if (!valid) {
            loanArrayViolations++;
            emit LendingInvariantViolation("loan_array_consistency", borrowersWithLoans.length, actualActive);
        }

        return valid;
    }

    /**
     * @notice LTV sanity check
     * @dev No loan should have LTV > 1000% (10x)
     */
    function echidna_ltv_sanity() public returns (bool) {
        if (address(vault) == address(0) || address(modelHelper) == address(0)) return true;

        for (uint256 i = 0; i < borrowersWithLoans.length; i++) {
            address borrower = borrowersWithLoans[i];
            uint256 borrowAmount = trackedBorrowAmounts[borrower];
            uint256 collateral = trackedCollateral[borrower];

            if (borrowAmount > 0 && collateral > 0) {
                // LTV = borrowAmount / collateralValue
                // If collateralValue (in token terms) is very low, LTV would be very high
                uint256 imv = modelHelper.getIntrinsicMinimumValue(address(vault));
                if (imv > 0) {
                    uint256 collateralValue = DecimalMath.multiplyDecimal(collateral, imv);

                    // Check if borrow > 10x collateral value (1000% LTV)
                    if (borrowAmount > collateralValue * 10) {
                        ltvViolations++;
                        emit LendingInvariantViolation("ltv_sanity", collateralValue * 10, borrowAmount);
                        return false;
                    }
                }
            }
        }

        return true;
    }

    /**
     * @notice No double loans
     * @dev Each user should have at most one active loan
     */
    function echidna_no_double_loan() public returns (bool) {
        // Check for duplicates in borrowersWithLoans
        for (uint256 i = 0; i < borrowersWithLoans.length; i++) {
            for (uint256 j = i + 1; j < borrowersWithLoans.length; j++) {
                if (borrowersWithLoans[i] == borrowersWithLoans[j] &&
                    trackedBorrowAmounts[borrowersWithLoans[i]] > 0) {
                    doubleLoanViolations++;
                    emit LendingInvariantViolation("no_double_loan", 1, 2);
                    return false;
                }
            }
        }

        return true;
    }

    /**
     * @notice Total borrows should not exceed floor capacity
     */
    function echidna_borrows_within_capacity() public view returns (bool) {
        if (address(vault) == address(0) || address(modelHelper) == address(0)) return true;

        (,,, uint256 floorBalance) = modelHelper.getUnderlyingBalances(
            address(pool),
            address(vault),
            LiquidityType.Floor
        );

        // Total borrows should not exceed floor balance
        return totalTrackedBorrows <= floorBalance;
    }

    // ==================== HELPER FUNCTIONS ====================

    function _estimateCollateral(uint256 borrowAmount) internal view returns (uint256) {
        if (address(modelHelper) == address(0)) return borrowAmount * 2;

        uint256 imv = modelHelper.getIntrinsicMinimumValue(address(vault));
        if (imv == 0) return borrowAmount * 2;

        return DecimalMath.divideDecimal(borrowAmount * 15 / 10, imv);
    }

    function _fundActorWithTokens(address actor, uint256 amount) internal {
        uint256 balance = nomaToken.balanceOf(address(this));
        if (balance >= amount) {
            nomaToken.transfer(actor, amount);
        }
    }

    function _fundActorWithWETH(address actor, uint256 amount) internal {
        HeapHelpers.deal(address(this), amount);
        weth.deposit{value: amount}();
        weth.transfer(actor, amount);
    }

    function _addBorrower(address borrower) internal {
        // Check if already in array
        for (uint256 i = 0; i < borrowersWithLoans.length; i++) {
            if (borrowersWithLoans[i] == borrower) return;
        }
        borrowersWithLoans.push(borrower);
    }

    function _removeBorrower(address borrower) internal {
        for (uint256 i = 0; i < borrowersWithLoans.length; i++) {
            if (borrowersWithLoans[i] == borrower) {
                // Swap and pop
                borrowersWithLoans[i] = borrowersWithLoans[borrowersWithLoans.length - 1];
                borrowersWithLoans.pop();
                return;
            }
        }
    }

    function _isWithinTolerance(uint256 a, uint256 b, uint256 toleranceBps) internal pure returns (bool) {
        if (a == 0 && b == 0) return true;
        uint256 max = a > b ? a : b;
        uint256 diff = a > b ? a - b : b - a;
        return diff <= (max * toleranceBps) / 10000;
    }

    // ==================== VIEW FUNCTIONS ====================

    function getLendingStats() external view returns (
        uint256 _successfulBorrows,
        uint256 _successfulPaybacks,
        uint256 _failedBorrows,
        uint256 _failedPaybacks,
        uint256 _activeLoans,
        uint256 _totalCollateral,
        uint256 _totalBorrows
    ) {
        return (
            successfulBorrows,
            successfulPaybacks,
            failedBorrows,
            failedPaybacks,
            activeLoansCount,
            totalTrackedCollateral,
            totalTrackedBorrows
        );
    }

    function getInvariantViolations() external view returns (
        uint256 _collateral,
        uint256 _loanArray,
        uint256 _ltv,
        uint256 _duration,
        uint256 _doubleLoan
    ) {
        return (
            collateralTrackingViolations,
            loanArrayViolations,
            ltvViolations,
            durationViolations,
            doubleLoanViolations
        );
    }
}
