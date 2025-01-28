// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {RewardParams} from "../../types/Types.sol";
import {Math} from "openzeppelin/contracts/utils/math/Math.sol";

interface IERC20 { 
    function decimals() external view returns (uint8);
}

contract RewardsCalculator {

    function calculateRewards(
        RewardParams memory params,
        uint256 timeElapsed,
        address token // Token address to determine decimals
    ) public view returns (uint256) {
        require(params.totalSupply > 0, "Total supply must be greater than zero");
        require(params.imv > 0, "IMV must be greater than zero");
        require(timeElapsed > 0, "Time elapsed must be greater than zero");

        uint256 priceRatio = params.spotPrice / params.imv;
        uint256 totalSupplyScaled = params.totalSupply * priceRatio;

        uint256 tMint = totalSupplyScaled / Math.sqrt(timeElapsed);
        return tMint;
    }
}
