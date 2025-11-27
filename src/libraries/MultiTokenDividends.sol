// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title MultiTokenDividends
/// @notice Library for index-based multi-token dividend accounting.
/// @dev Pattern similar to Compound's reward index: for each reward token:
///      - global index tracks cumulative rewards per 1 share
///      - each user tracks a personal index snapshot
///      - accrued[user] stores unclaimed rewards
library MultiTokenDividends {
    uint256 internal constant PRECISION = 1e18;

    struct RewardData {
        uint256 index;                         // global index for this reward token
        mapping(address => uint256) userIndex; // user -> last index
        mapping(address => uint256) accrued;   // user -> unclaimed amount
    }

    struct State {
        // rewardToken => RewardData
        mapping(address => RewardData) rewards;
    }

    /// @notice Distribute `amount` of `rewardToken` among `totalShares` pro-rata.
    /// @dev Caller must have already transferred `amount` of rewardToken into the contract.
    function distribute(
        State storage self,
        address rewardToken,
        uint256 amount,
        uint256 totalShares
    ) internal {
        if (amount == 0 || totalShares == 0) return;

        RewardData storage rd = self.rewards[rewardToken];
        // Increase global index: amount per 1 share
        rd.index += (amount * PRECISION) / totalShares;
    }

    /// @notice Accrue rewards for `user` in `rewardToken` using current `userShares`.
    /// @dev Must be called BEFORE changing userShares to capture rewards earned up to now.
    function accrueForUser(
        State storage self,
        address rewardToken,
        address user,
        uint256 userShares
    ) internal {
        RewardData storage rd = self.rewards[rewardToken];
        uint256 globalIdx = rd.index;
        uint256 userIdx = rd.userIndex[user];

        if (userIdx == 0) {
            // First time we see this user for this token: just set index baseline
            rd.userIndex[user] = globalIdx;
            return;
        }

        uint256 delta = globalIdx - userIdx;
        if (delta == 0) return;

        uint256 earned = (userShares * delta) / PRECISION;
        rd.accrued[user] += earned;
        rd.userIndex[user] = globalIdx;
    }

    /// @notice View how much `rewardToken` is currently accrued for `user`.
    function claimable(
        State storage self,
        address rewardToken,
        address user
    ) internal view returns (uint256) {
        return self.rewards[rewardToken].accrued[user];
    }

    /// @notice Reset accrued balance for `user` and return the amount (for actual transfer).
    function takeAccrued(
        State storage self,
        address rewardToken,
        address user
    ) internal returns (uint256 amount) {
        RewardData storage rd = self.rewards[rewardToken];
        amount = rd.accrued[user];
        if (amount > 0) {
            rd.accrued[user] = 0;
        }
    }

    function getPrecision() internal pure returns (uint256) {
        return PRECISION;
    }
}
