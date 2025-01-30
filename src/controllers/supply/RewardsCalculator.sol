// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {RewardParams} from "../../types/Types.sol";
import {Math} from "openzeppelin/contracts/utils/math/Math.sol";

/// @title RewardsCalculator
/// @notice A contract to calculate rewards based on supply, time, and price factors.
contract RewardsCalculator {

    /// @notice Calculates the rewards based on reward parameters, time elapsed, and token decimals.
    /// @dev This function computes rewards using the formula: (totalSupply * (spotPrice / IMV)) / sqrt(timeElapsed).
    /// @param params The reward parameters including total supply, spot price, and IMV.
    /// @param timeElapsed The time elapsed since the last reward calculation.
    /// @param token The token address to determine decimals (currently unused in the function).
    /// @return The calculated reward amount.
    /// @custom:require totalSupply > 0, "Total supply must be greater than zero"
    /// @custom:require imv > 0, "IMV must be greater than zero"
    /// @custom:require timeElapsed > 0, "Time elapsed must be greater than zero"
    function calculateRewards(
        RewardParams memory params,
        uint256 timeElapsed,
        address token // Token address to determine decimals
    ) public pure returns (uint256) {
        require(params.totalSupply > 0, "Total supply must be greater than zero");
        require(params.imv > 0, "IMV must be greater than zero");
        require(timeElapsed > 0, "Time elapsed must be greater than zero");

        // Calculate the ratio of spot price to IMV
        uint256 priceRatio = params.spotPrice / params.imv;

        // Scale the total supply by the price ratio
        uint256 totalSupplyScaled = params.totalSupply * priceRatio;

        // Compute the reward amount using the scaled total supply and square root of time elapsed
        uint256 tMint = totalSupplyScaled / Math.sqrt(timeElapsed);
        return tMint;
    }
}