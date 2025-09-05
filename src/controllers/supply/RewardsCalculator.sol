// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {RewardParams} from "../../types/Types.sol";
import {Math} from "openzeppelin/contracts/utils/math/Math.sol";

/// @title RewardsCalculator
/// @notice A contract to calculate rewards based on the ratio of total staked to circulating supply.
contract RewardsCalculator {

    /**
     * @dev Calculates how much ETH from `excessEth` should be used
     *      based on the ratio of total staked to circulating supply,
     *      with a tolerance band around 50%, and the final fraction
     *      clamped to [20%, 80%].
     */
    function calculateRewards(
        RewardParams memory params
    ) public pure returns (uint256) {
        require(params.circulating > 0, "Circulating supply cannot be zero");

        // stakedRatio = (totalStaked / circulatingSupply), scaled by 1e18
        uint256 stakedRatio = (params.totalStaked * 1e18) / params.circulating;

        // Constants in 1e18 scaling
        // 50%: 0.50 -> 5e17
        // tolerance: 0.02 -> 2e16
        uint256 half = 5e17;       // 0.50
        uint256 tolerance = 2e16;  // 0.02

        // We'll clamp the final fraction p(R) to [0.20, 0.80]
        // 20% -> 2e17
        // 80% -> 8e17
        uint256 minFraction = 2e17; // 0.20
        uint256 maxFraction = 8e17; // 0.80

        // Lower bound = 0.48 -> 4.8e17
        // Upper bound = 0.52 -> 5.2e17
        uint256 lowerBound = half - tolerance; // 4.8e17
        uint256 upperBound = half + tolerance; // 5.2e17

        // fraction is in 1e18 scaling
        uint256 fraction;

        if (stakedRatio < lowerBound) {
            // fraction = 0.50 + ((0.48) - stakedRatio)
            fraction = half + (lowerBound - stakedRatio);
        } else if (stakedRatio > upperBound) {
            // fraction = 0.50 - (stakedRatio - 0.52)
            fraction = half - (stakedRatio - upperBound);
        } else {
            // If in [0.48, 0.52], fraction = 0.50
            fraction = half;
        }

        // --- Clamp fraction to [0.20, 0.80] ---
        if (fraction < minFraction) {
            fraction = minFraction;
        } else if (fraction > maxFraction) {
            fraction = maxFraction;
        }

        // Convert fraction (1e18 scale) to actual ETH used
        uint256 usedEth = (params.ethAmount * fraction) / 1e18;

        return usedEth;
    }
}


