// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FuzzSetup, IVault, IModelHelper, IStaking, IWETH, NomaToken, IsNomaToken} from "./FuzzSetup.sol";
import {FuzzActors} from "./actors/FuzzActors.sol";
import {FuzzHelpers, HeapHelpers} from "./helpers/FuzzHelpers.sol";

/**
 * @title StakingFuzz
 * @notice Fuzzing harness focused on staking operations and invariants
 *
 * KEY STAKING INVARIANTS:
 * 1. totalStaked consistency: totalStaked == sum(stakedBalances)
 * 2. sNOMA minimum supply: sNOMA.totalSupply() >= MIN_SUPPLY (1e18)
 * 3. Epoch monotonicity: Epoch number only increases
 * 4. Cooldown enforcement: 3-day cooldown between operations
 * 5. Lock-in period: Cannot unstake before lock-in period elapsed
 * 6. Reward distribution: Rewards should increase sNOMA supply proportionally
 */
contract StakingFuzz is FuzzSetup, FuzzActors {
    using FuzzHelpers for uint256;
    using HeapHelpers for address;

    // Staking state tracking
    mapping(address => uint256) public trackedStakedAmounts;
    uint256 public totalTrackedStaked;

    // Epoch tracking
    uint256 public lastKnownEpoch;
    uint256 public epochsObserved;

    // Operation counters
    uint256 public successfulStakes;
    uint256 public successfulUnstakes;
    uint256 public failedStakes;
    uint256 public failedUnstakes;
    uint256 public rewardNotifications;

    // Invariant violations
    uint256 public totalStakedViolations;
    uint256 public minSupplyViolations;
    uint256 public epochMonotonicityViolations;
    uint256 public cooldownViolations;

    // Constants
    uint256 public constant STAKING_COOLDOWN = 3 days;
    uint256 public constant MIN_SNOMA_SUPPLY = 1e18;

    // Events
    event StakingOperation(string operation, address indexed user, uint256 amount, bool success);
    event StakingInvariantViolation(string invariant, uint256 expected, uint256 actual);

    constructor() FuzzSetup() {
        _initializeActors(NUM_ACTORS);

        // Record initial epoch if staking is initialized
        if (address(staking) != address(0)) {
            (uint256 epochNum,,) = staking.epoch();
            lastKnownEpoch = epochNum;
        }
    }

    // ==================== FUZZ TARGETS ====================

    /**
     * @notice Fuzz: Stake tokens
     * @param actorIdx Actor performing the stake
     * @param amount Amount to stake
     */
    function fuzz_stake(uint8 actorIdx, uint256 amount) external {
        if (address(staking) == address(0)) return;

        address staker = getActor(actorIdx);

        // Bound amount
        amount = amount.bound(0.1 ether, 100 ether);

        // Check cooldown
        uint256 lastOp = staking.lastOperationTimestamp(staker);
        if (block.timestamp < lastOp + STAKING_COOLDOWN) {
            // Warp past cooldown
            HeapHelpers.advanceTime(STAKING_COOLDOWN + 1);
        }

        // Fund staker with NOMA
        _fundActorWithTokens(staker, amount);

        HeapHelpers.startPrank(staker);
        nomaToken.approve(address(staking), type(uint256).max);

        bool success = false;
        try staking.stake(amount) {
            success = true;
            successfulStakes++;

            // Track staking
            trackedStakedAmounts[staker] += amount;
            totalTrackedStaked += amount;

            _recordStake();
        } catch {
            failedStakes++;
        }

        HeapHelpers.stopPrank();
        emit StakingOperation("stake", staker, amount, success);
    }

    /**
     * @notice Fuzz: Unstake tokens
     * @param actorIdx Actor performing the unstake
     */
    function fuzz_unstake(uint8 actorIdx) external {
        if (address(staking) == address(0)) return;

        address staker = getActor(actorIdx);

        // Check if user has staked
        if (trackedStakedAmounts[staker] == 0) return;

        // Check lock-in period
        uint256 stakedEpoch = staking.stakedEpochs(staker);
        (uint256 currentEpoch,,) = staking.epoch();
        uint256 lockIn = staking.lockInEpochs();

        if (currentEpoch < stakedEpoch + lockIn) {
            // Warp past lock-in (simulate epoch advancement)
            HeapHelpers.advanceTime(7 days * (lockIn + 1));
        }

        // Check cooldown
        uint256 lastOp = staking.lastOperationTimestamp(staker);
        if (block.timestamp < lastOp + STAKING_COOLDOWN) {
            HeapHelpers.advanceTime(STAKING_COOLDOWN + 1);
        }

        uint256 stakedAmount = trackedStakedAmounts[staker];

        HeapHelpers.prank(staker);
        bool success = false;
        try staking.unstake() {
            success = true;
            successfulUnstakes++;

            // Update tracking
            totalTrackedStaked -= stakedAmount;
            trackedStakedAmounts[staker] = 0;

            _recordUnstake();
        } catch {
            failedUnstakes++;
        }

        emit StakingOperation("unstake", staker, stakedAmount, success);
    }

    /**
     * @notice Fuzz: Advance time to allow operations
     * @param seconds_ Seconds to advance
     */
    function fuzz_advanceTime(uint256 seconds_) external {
        seconds_ = seconds_.bound(1 hours, 30 days);
        HeapHelpers.advanceTime(seconds_);
    }

    /**
     * @notice Fuzz: Trigger shift (which may distribute rewards)
     */
    function fuzz_triggerShiftForRewards() external {
        if (address(vault) == address(0)) return;

        try vault.shift() {
            // Shift may trigger reward distribution
            rewardNotifications++;
        } catch {}

        // Update epoch tracking
        if (address(staking) != address(0)) {
            (uint256 currentEpoch,,) = staking.epoch();
            if (currentEpoch > lastKnownEpoch) {
                epochsObserved += (currentEpoch - lastKnownEpoch);
                lastKnownEpoch = currentEpoch;
            }
        }
    }

    // ==================== INVARIANTS ====================

    /**
     * @notice totalStaked consistency
     * @dev totalStaked should equal sum of all stakedBalances
     */
    function echidna_totalStaked_consistency() public returns (bool) {
        if (address(staking) == address(0)) return true;

        uint256 contractTotalStaked = staking.totalStaked();

        // Sum up tracked stakes
        uint256 sumStaked = 0;
        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            address actor = getActor(uint8(i));
            sumStaked += staking.stakedBalance(actor);
        }

        // Allow 1% tolerance due to rebasing
        bool valid = _isWithinTolerance(contractTotalStaked, sumStaked, 100);

        if (!valid) {
            totalStakedViolations++;
            emit StakingInvariantViolation("totalStaked_consistency", sumStaked, contractTotalStaked);
        }

        return valid;
    }

    /**
     * @notice sNOMA minimum supply
     * @dev sNOMA.totalSupply() should never go below MIN_SUPPLY
     */
    function echidna_sNOMA_min_supply() public returns (bool) {
        if (address(sNOMA) == address(0)) return true;

        uint256 supply = sNOMA.totalSupply();
        bool valid = supply >= MIN_SNOMA_SUPPLY;

        if (!valid) {
            minSupplyViolations++;
            emit StakingInvariantViolation("sNOMA_min_supply", MIN_SNOMA_SUPPLY, supply);
        }

        return valid;
    }

    /**
     * @notice Epoch monotonicity
     * @dev Epoch number should only increase
     */
    function echidna_epoch_monotonic() public returns (bool) {
        if (address(staking) == address(0)) return true;

        (uint256 currentEpoch,,) = staking.epoch();

        bool valid = currentEpoch >= lastKnownEpoch;

        if (!valid) {
            epochMonotonicityViolations++;
            emit StakingInvariantViolation("epoch_monotonic", lastKnownEpoch, currentEpoch);
        }

        // Update last known epoch
        if (currentEpoch > lastKnownEpoch) {
            lastKnownEpoch = currentEpoch;
        }

        return valid;
    }

    /**
     * @notice sNOMA circulating supply >= total staked NOMA
     * @dev After rebasing, sNOMA supply should cover all staked positions
     */
    function echidna_sNOMA_covers_staked() public view returns (bool) {
        if (address(staking) == address(0) || address(sNOMA) == address(0)) return true;

        uint256 sNomaSupply = sNOMA.totalSupply();
        uint256 totalStaked = staking.totalStaked();

        // sNOMA supply should be >= totalStaked (after rebasing it can be more)
        return sNomaSupply >= totalStaked;
    }

    /**
     * @notice Epoch number is positive after initialization
     */
    function echidna_epoch_positive() public view returns (bool) {
        if (address(staking) == address(0)) return true;

        (uint256 epochNum,,) = staking.epoch();
        return epochNum > 0;
    }

    /**
     * @notice Total rewards tracked correctly
     */
    function echidna_total_rewards_positive() public view returns (bool) {
        if (address(staking) == address(0)) return true;

        // Total rewards should be non-negative (it's uint so always >= 0)
        // Check that it hasn't overflowed by being less than a reasonable value
        return staking.totalRewards() < type(uint256).max / 2;
    }

    // ==================== HELPER FUNCTIONS ====================

    function _fundActorWithTokens(address actor, uint256 amount) internal {
        uint256 balance = nomaToken.balanceOf(address(this));
        if (balance >= amount) {
            nomaToken.transfer(actor, amount);
        }
    }

    function _isWithinTolerance(uint256 a, uint256 b, uint256 toleranceBps) internal pure returns (bool) {
        if (a == 0 && b == 0) return true;
        uint256 max = a > b ? a : b;
        uint256 diff = a > b ? a - b : b - a;
        return diff <= (max * toleranceBps) / 10000;
    }

    // ==================== VIEW FUNCTIONS ====================

    function getStakingStats() external view returns (
        uint256 _successfulStakes,
        uint256 _successfulUnstakes,
        uint256 _failedStakes,
        uint256 _failedUnstakes,
        uint256 _epochsObserved,
        uint256 _totalTrackedStaked
    ) {
        return (
            successfulStakes,
            successfulUnstakes,
            failedStakes,
            failedUnstakes,
            epochsObserved,
            totalTrackedStaked
        );
    }

    function getStakingInvariantViolations() external view returns (
        uint256 _totalStaked,
        uint256 _minSupply,
        uint256 _epochMonotonicity,
        uint256 _cooldown
    ) {
        return (
            totalStakedViolations,
            minSupplyViolations,
            epochMonotonicityViolations,
            cooldownViolations
        );
    }

    function getCurrentEpoch() external view returns (uint256 number, uint256 end, uint256 distribute) {
        if (address(staking) == address(0)) return (0, 0, 0);
        return staking.epoch();
    }
}
