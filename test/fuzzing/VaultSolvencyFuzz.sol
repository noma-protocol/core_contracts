// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FuzzSetup, IVault, IModelHelper, IStaking, IWETH, NomaToken, IsNomaToken} from "./FuzzSetup.sol";
import {FuzzActors} from "./actors/FuzzActors.sol";
import {FuzzHelpers, HeapHelpers} from "./helpers/FuzzHelpers.sol";
import {
    LiquidityPosition,
    LiquidityType,
    VaultInfo
} from "../../src/types/Types.sol";
import {DecimalMath} from "../../src/libraries/DecimalMath.sol";
import {Conversions} from "../../src/libraries/Conversions.sol";

/**
 * @title VaultSolvencyFuzz
 * @notice Main fuzzing harness for vault solvency invariants
 * @dev Tests critical protocol invariants using Echidna/Medusa
 *
 * KEY INVARIANTS:
 * 1. Solvency: anchorCapacity + floorCapacity >= circulatingSupply
 * 2. Collateral tracking: TokenRepo balance >= vault.collateralAmount
 * 3. Position validity: All 3 positions have liquidity > 0
 * 4. Position continuity: floor.upperTick == anchor.lowerTick
 * 5. Supply cap: totalSupply <= maxTotalSupply
 * 6. Fee monotonicity: Accumulated fees never decrease
 * 7. Liquidity ratio bounds: Ratio stays within expected range
 */
contract VaultSolvencyFuzz is FuzzSetup, FuzzActors {
    using FuzzHelpers for uint256;
    using HeapHelpers for address;

    // State tracking for invariant verification
    uint256 public feesToken0Previous;
    uint256 public feesToken1Previous;
    uint256 public totalBorrowsExecuted;
    uint256 public totalPaybacksExecuted;
    uint256 public totalShiftsExecuted;
    uint256 public totalSlidesExecuted;
    uint256 public totalDefaultsExecuted;

    // Time tracking
    uint256 public lastWarpTimestamp;

    // Invariant violation counters (for debugging)
    uint256 public solvencyViolations;
    uint256 public collateralViolations;
    uint256 public positionViolations;
    uint256 public supplyCapViolations;

    // Events for fuzzer analysis
    event FuzzBorrow(address indexed borrower, uint256 amount, uint256 duration, bool success);
    event FuzzPayback(address indexed borrower, uint256 amount, bool success);
    event FuzzShift(bool success);
    event FuzzSlide(bool success);
    event FuzzDefaultLoans(uint256 start, uint256 limit, bool success);
    event FuzzTimeWarp(uint256 newTimestamp);
    event InvariantViolation(string invariantName);

    constructor() FuzzSetup() {
        _initializeActors(NUM_ACTORS);
        lastWarpTimestamp = block.timestamp;

        // Record initial fees if vault is initialized
        if (address(vault) != address(0)) {
            (feesToken0Previous, feesToken1Previous) = vault.getAccumulatedFees();
        }
    }

    // ==================== FUZZ TARGETS ====================

    /**
     * @notice Fuzz target: Borrow from vault
     * @param actorIdx Actor index
     * @param amount Borrow amount (will be bounded)
     * @param duration Loan duration in seconds (will be bounded)
     */
    function fuzz_borrow(uint8 actorIdx, uint256 amount, uint256 duration) external {
        if (address(vault) == address(0)) return;

        address borrower = getActor(actorIdx);

        // Bound inputs to reasonable ranges
        amount = amount.bound(0.01 ether, 10 ether);
        duration = duration.bound(30 days, 365 days);

        // Setup: Get collateral for the borrower
        uint256 collateralNeeded = _estimateCollateral(amount);
        if (collateralNeeded == 0) return;

        // Fund borrower with tokens for collateral
        _fundActorWithTokens(borrower, collateralNeeded * 2);

        // Approve vault
        HeapHelpers.startPrank(borrower);
        nomaToken.approve(address(vault), type(uint256).max);

        bool success = false;
        try vault.borrow(amount, duration) {
            success = true;
            totalBorrowsExecuted++;
            _setActorLoanStatus(borrower, true);
            _recordBorrow();
        } catch {}

        HeapHelpers.stopPrank();
        emit FuzzBorrow(borrower, amount, duration, success);
    }

    /**
     * @notice Fuzz target: Payback loan
     * @param actorIdx Actor index
     * @param amount Payback amount (0 = full payback)
     */
    function fuzz_payback(uint8 actorIdx, uint256 amount) external {
        if (address(vault) == address(0)) return;

        address borrower = getActor(actorIdx);

        // Get active loan info
        (uint256 borrowAmount,,,, ) = _getActiveLoan(borrower);
        if (borrowAmount == 0) return;

        // Bound amount (0 means full payback)
        if (amount == 0) {
            amount = borrowAmount;
        } else {
            amount = amount.bound(1, borrowAmount);
        }

        // Fund borrower with WETH to repay
        _fundActorWithWETH(borrower, amount);

        HeapHelpers.startPrank(borrower);
        weth.approve(address(vault), type(uint256).max);

        bool success = false;
        try vault.payback(amount) {
            success = true;
            totalPaybacksExecuted++;
            if (amount == borrowAmount) {
                _setActorLoanStatus(borrower, false);
            }
            _recordPayback();
        } catch {}

        HeapHelpers.stopPrank();
        emit FuzzPayback(borrower, amount, success);
    }

    /**
     * @notice Fuzz target: Roll loan to new duration
     * @param actorIdx Actor index
     * @param newDuration New loan duration
     */
    function fuzz_roll(uint8 actorIdx, uint256 newDuration) external {
        if (address(vault) == address(0)) return;

        address borrower = getActor(actorIdx);

        // Bound duration
        newDuration = newDuration.bound(1 days, 30 days);

        HeapHelpers.prank(borrower);
        try vault.roll(newDuration) {} catch {}
    }

    /**
     * @notice Fuzz target: Add collateral to loan
     * @param actorIdx Actor index
     * @param amount Collateral amount to add
     */
    function fuzz_addCollateral(uint8 actorIdx, uint256 amount) external {
        if (address(vault) == address(0)) return;

        address borrower = getActor(actorIdx);

        // Bound amount
        amount = amount.bound(0.01 ether, 5 ether);

        // Fund borrower
        _fundActorWithTokens(borrower, amount);

        HeapHelpers.startPrank(borrower);
        nomaToken.approve(address(vault), type(uint256).max);

        // Note: addCollateral function needs to be called via external interface
        // try vault.addCollateral(amount) {} catch {}

        HeapHelpers.stopPrank();
    }

    /**
     * @notice Fuzz target: Trigger shift operation
     */
    function fuzz_shift() external {
        if (address(vault) == address(0)) return;

        bool success = false;
        try vault.shift() {
            success = true;
            totalShiftsExecuted++;
        } catch {}

        emit FuzzShift(success);
    }

    /**
     * @notice Fuzz target: Trigger slide operation
     */
    function fuzz_slide() external {
        if (address(vault) == address(0)) return;

        bool success = false;
        try vault.slide() {
            success = true;
            totalSlidesExecuted++;
        } catch {}

        emit FuzzSlide(success);
    }

    /**
     * @notice Fuzz target: Default loans
     * @param start Start index
     * @param limit Number of loans to process
     */
    function fuzz_defaultLoans(uint256 start, uint256 limit) external {
        if (address(vault) == address(0)) return;

        // Bound inputs
        start = start.bound(0, 100);
        limit = limit.bound(1, 50);

        bool success = false;
        try vault.defaultLoans() {
            success = true;
            totalDefaultsExecuted++;
        } catch {}

        emit FuzzDefaultLoans(start, limit, success);
    }

    /**
     * @notice Fuzz target: Warp time forward
     * @param secondsToWarp Seconds to advance
     */
    function fuzz_warpTime(uint256 secondsToWarp) external {
        // Bound to reasonable range (1 second to 400 days)
        secondsToWarp = secondsToWarp.bound(1, 400 days);

        uint256 newTimestamp = block.timestamp + secondsToWarp;
        HeapHelpers.warp(newTimestamp);
        lastWarpTimestamp = newTimestamp;

        emit FuzzTimeWarp(newTimestamp);
    }

    // ==================== INVARIANTS ====================

    /**
     * @notice CRITICAL: Solvency invariant
     * @dev anchorCapacity + floorCapacity >= circulatingSupply
     */
    function echidna_solvency_anchor_floor_capacity() public returns (bool) {
        if (address(vault) == address(0) || address(modelHelper) == address(0)) {
            return true; // Skip if not initialized
        }

        address poolAddr = address(pool);
        address vaultAddr = address(vault);

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(poolAddr, vaultAddr, false);
        if (circulatingSupply == 0) return true;

        uint256 imv = modelHelper.getIntrinsicMinimumValue(vaultAddr);
        if (imv == 0) return true;

        LiquidityPosition[3] memory positions = vault.getPositions();

        uint256 anchorCapacity = modelHelper.getPositionCapacity(
            poolAddr,
            vaultAddr,
            positions[1],
            LiquidityType.Anchor
        );

        (,,, uint256 floorBalance) = modelHelper.getUnderlyingBalances(
            poolAddr,
            vaultAddr,
            LiquidityType.Floor
        );

        uint256 floorCapacity = DecimalMath.divideDecimal(floorBalance, imv);

        bool solvent = (anchorCapacity + floorCapacity) >= circulatingSupply;

        if (!solvent) {
            solvencyViolations++;
            emit InvariantViolation("solvency_anchor_floor_capacity");
        }

        return solvent;
    }

    /**
     * @notice CRITICAL: Collateral in TokenRepo
     * @dev TokenRepo balance >= vault.collateralAmount
     */
    function echidna_collateral_in_repo() public returns (bool) {
        if (address(vault) == address(0) || address(tokenRepo) == address(0)) {
            return true;
        }

        uint256 vaultCollateral = vault.getCollateralAmount();
        uint256 repoBalance = nomaToken.balanceOf(address(tokenRepo));

        bool valid = repoBalance >= vaultCollateral;

        if (!valid) {
            collateralViolations++;
            emit InvariantViolation("collateral_in_repo");
        }

        return valid;
    }

    /**
     * @notice Position validity: All positions have liquidity
     */
    function echidna_positions_have_liquidity() public returns (bool) {
        if (address(vault) == address(0)) return true;

        LiquidityPosition[3] memory positions = vault.getPositions();

        // All positions should have liquidity > 0 after initialization
        bool valid = positions[0].liquidity > 0 &&
                     positions[1].liquidity > 0 &&
                     positions[2].liquidity > 0;

        if (!valid) {
            positionViolations++;
            emit InvariantViolation("positions_have_liquidity");
        }

        return valid;
    }

    /**
     * @notice Position continuity: floor.upperTick == anchor.lowerTick
     */
    function echidna_positions_contiguous() public view returns (bool) {
        if (address(vault) == address(0)) return true;

        LiquidityPosition[3] memory positions = vault.getPositions();

        // Floor upper tick should equal anchor lower tick
        return positions[0].upperTick == positions[1].lowerTick;
    }

    /**
     * @notice Supply cap: totalSupply <= maxTotalSupply
     */
    function echidna_no_token_inflation() public returns (bool) {
        if (address(nomaToken) == address(0)) return true;

        uint256 totalSupply = nomaToken.totalSupply();
        uint256 maxSupply = nomaToken.maxTotalSupply();

        bool valid = totalSupply <= maxSupply;

        if (!valid) {
            supplyCapViolations++;
            emit InvariantViolation("no_token_inflation");
        }

        return valid;
    }

    /**
     * @notice Fee monotonicity: Accumulated fees should not decrease
     */
    function echidna_fee_accumulators_monotonic() public returns (bool) {
        if (address(vault) == address(0)) return true;

        (uint256 fees0, uint256 fees1) = vault.getAccumulatedFees();

        // Fees should only increase or stay the same
        bool valid = fees0 >= feesToken0Previous && fees1 >= feesToken1Previous;

        // Update previous values
        feesToken0Previous = fees0;
        feesToken1Previous = fees1;

        if (!valid) {
            emit InvariantViolation("fee_accumulators_monotonic");
        }

        return valid;
    }

    /**
     * @notice Liquidity ratio bounds: Should stay within 50%-200%
     */
    function echidna_liquidity_ratio_bounded() public view returns (bool) {
        if (address(vault) == address(0) || address(modelHelper) == address(0)) {
            return true;
        }

        uint256 ratio = modelHelper.getLiquidityRatio(address(pool), address(vault));

        // Ratio should be within reasonable bounds (50% to 200%)
        // In 1e18 terms: 0.5e18 to 2e18
        return ratio >= 0.5e18 && ratio <= 2e18;
    }

    /**
     * @notice Staking enabled consistency
     */
    function echidna_staking_enabled_consistency() public view returns (bool) {
        if (address(vault) == address(0)) return true;

        // If staking is enabled, staking contract should be set
        bool stakingEnabled = vault.stakingEnabled();
        address stakingContract = vault.getStakingContract();

        if (stakingEnabled) {
            return stakingContract != address(0);
        }

        return true;
    }

    // ==================== HELPER FUNCTIONS ====================

    /**
     * @notice Estimate collateral needed for a borrow amount
     */
    function _estimateCollateral(uint256 borrowAmount) internal view returns (uint256) {
        if (address(modelHelper) == address(0) || address(vault) == address(0)) {
            return borrowAmount * 2; // Conservative estimate
        }

        uint256 imv = modelHelper.getIntrinsicMinimumValue(address(vault));
        if (imv == 0) return borrowAmount * 2;

        // Collateral = borrowAmount / IMV (with some buffer)
        return DecimalMath.divideDecimal(borrowAmount * 15 / 10, imv);
    }

    /**
     * @notice Get active loan for a borrower
     */
    function _getActiveLoan(address borrower) internal view returns (
        uint256 borrowAmount,
        uint256 collateralAmount,
        uint256 fees,
        uint256 expiry,
        uint256 duration
    ) {
        // This would need to call the lending vault's getActiveLoan function
        // For now, return zeros - implement based on actual interface
        return (0, 0, 0, 0, 0);
    }

    /**
     * @notice Fund actor with tokens
     */
    function _fundActorWithTokens(address actor, uint256 amount) internal {
        // In a forked environment, we might need to:
        // 1. Get tokens from a whale address
        // 2. Use hevm.deal equivalent for ERC20s
        // 3. Or ensure actors have tokens in the fork state

        // For now, try to transfer from this contract if it has tokens
        uint256 balance = nomaToken.balanceOf(address(this));
        if (balance >= amount) {
            nomaToken.transfer(actor, amount);
        }
    }

    /**
     * @notice Fund actor with WETH
     */
    function _fundActorWithWETH(address actor, uint256 amount) internal {
        // Deal ETH and wrap it
        HeapHelpers.deal(address(this), amount);
        weth.deposit{value: amount}();
        weth.transfer(actor, amount);
    }

    // ==================== VIEW HELPERS ====================

    /**
     * @notice Get current vault info
     */
    function getVaultState() external view returns (
        uint256 circulatingSupply,
        uint256 imv,
        uint256 anchorCapacity,
        uint256 floorBalance,
        uint256 liquidityRatio
    ) {
        if (address(vault) == address(0) || address(modelHelper) == address(0)) {
            return (0, 0, 0, 0, 0);
        }

        address poolAddr = address(pool);
        address vaultAddr = address(vault);

        circulatingSupply = modelHelper.getCirculatingSupply(poolAddr, vaultAddr, false);
        imv = modelHelper.getIntrinsicMinimumValue(vaultAddr);

        LiquidityPosition[3] memory positions = vault.getPositions();
        anchorCapacity = modelHelper.getPositionCapacity(
            poolAddr,
            vaultAddr,
            positions[1],
            LiquidityType.Anchor
        );

        (,,, floorBalance) = modelHelper.getUnderlyingBalances(
            poolAddr,
            vaultAddr,
            LiquidityType.Floor
        );

        liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddr);
    }

    /**
     * @notice Get fuzzing statistics
     */
    function getStats() external view returns (
        uint256 borrows,
        uint256 paybacks,
        uint256 shifts,
        uint256 slides,
        uint256 defaults,
        uint256 solvencyViol,
        uint256 collateralViol,
        uint256 positionViol,
        uint256 supplyCapViol
    ) {
        return (
            totalBorrowsExecuted,
            totalPaybacksExecuted,
            totalShiftsExecuted,
            totalSlidesExecuted,
            totalDefaultsExecuted,
            solvencyViolations,
            collateralViolations,
            positionViolations,
            supplyCapViolations
        );
    }
}
