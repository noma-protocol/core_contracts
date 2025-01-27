// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeMathInt} from "../../libraries/SafeMathInt.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {RewardParams} from "../../types/Types.sol";

interface IERC20 { 
    function decimals() external view returns (uint8);
}

interface IVault {
    function pool() external view returns (IUniswapV3Pool);
}

contract RewardsCalculator {
    using FixedPointMathLib for uint256;
    using SafeMathInt for int256;

    function calculateRewards(
        RewardParams memory params,
        uint256 timeElapsed
    ) public pure returns (uint256) {
        require(params.totalSupply > 0, "Total supply must be greater than zero");
        require(params.imv > 0, "IMV must be greater than zero");
        require(timeElapsed > 0, "Time elapsed must be greater than zero");

        uint256 r = _calculateR(params);
        uint256 sigmoid = _calculateSigmoid(r, params.kr);
        uint256 ratio = _calculateRatio(params.spotPrice, params.imv);
        uint256 timeAdjustment = _calculateTimeAdjustment(ratio, timeElapsed);
        uint256 tBacked = _calculateTBacked(params);

        uint256 tMint = tBacked.mulWadDown(sigmoid).mulWadDown(timeAdjustment);
        require(tMint < tBacked, "Mint amount must be less than T_backed");

        return tMint;
    }

    function _calculateR(RewardParams memory params) internal pure returns (uint256) {
        uint256 r = params.circulating.divWadDown(params.totalSupply);
        uint256 maxR = 0.99e18; // Prevent extreme cases
        return r > maxR ? maxR : r;
    }

    function _calculateSigmoid(uint256 r, uint256 kr) internal pure returns (uint256) {
        uint256 half = 0.5e18;
        int256 diff = int256(half) - int256(r);
        int256 krInt = int256(kr);

        int256 exponent = -((krInt * diff) / int256(1e18));
        int256 maxExponent = 135305999368893231589;

        if (exponent > maxExponent) {
            exponent = maxExponent;
        } else if (exponent < -maxExponent) {
            exponent = -maxExponent;
        }

        return uint256(1e18).divWadDown(1e18 + exponent.expWad());
    }

    function _calculateRatio(uint256 spotPrice, uint256 imv) internal pure returns (uint256) {
        uint256 ratio = spotPrice.divWadDown(imv);
        require(ratio >= 1e18, "Spot price must not be lower than IMV");
        return ratio;
    }

    function _calculateTimeAdjustment(uint256 ratio, uint256 timeElapsed) internal pure returns (uint256) {
        uint256 ratioFactor = ratio.divWadDown(1e18); // Normalize ratio to a factor
        uint256 timeFactor = timeElapsed.sqrt();
        return ratioFactor.mulWadDown(timeFactor);
    }

    function _calculateTBacked(RewardParams memory params) internal pure returns (uint256) {
        return params.ethAmount.divWadDown(params.imv);
    }

    // function calculateRewards(RewardParams memory params) public pure returns (uint256) {
    //     require(params.totalSupply > 0, "Total supply must be greater than zero");
    //     require(params.imv > 0, "IMV must be greater than zero");

    //     // Calculate r = circulating / totalSupply
    //     uint256 r = params.circulating.divWadDown(params.totalSupply);

    //     // Clamp r to prevent instability
    //     uint256 maxR = 0.99e18; // Prevent extreme cases
    //     if (r > maxR) {
    //         r = maxR;
    //     }

    //     // Sigmoid adjustment: M_r = 1 / (1 + e^(-k_r * (0.5 - r)))
    //     uint256 half = 0.5e18;
    //     int256 diff = int256(half) - int256(r); // Ensure correct signed difference
    //     int256 krInt = int256(params.kr); // Convert params.kr to int256

    //     // Perform signed multiplication with fixed-point division
    //     int256 exponent = -((krInt * diff) / int256(1e18)); // Scale by 1e18 for fixed-point

    //     if (diff < 0) exponent = -exponent; // Correct the sign

    //     // Cap exponent to prevent overflow
    //     int256 maxExponent = 135305999368893231589; // Limit for e^x in Solmate expWad
    //     if (exponent > maxExponent) {
    //         exponent = maxExponent;
    //     } else if (exponent < -maxExponent) {
    //         exponent = -maxExponent;
    //     }

    //     uint256 sigmoid = uint256(1e18).divWadDown(1e18 + exponent.expWad());

    //     // Volatility adjustment: M_v = e^(-k_v * V)
    //     int256 volExp = -int256(params.kv.mulWadDown(params.volatility));
    //     uint256 volatilityAdjustment = volExp.expWad();

    //     // Base rewards: T_backed = ethAmount / imv
    //     uint256 tBacked = params.ethAmount.divWadDown(params.imv);

    //     // Final minted tokens: T_mint = T_backed * M_r * M_v
    //     uint256 tMint = tBacked.mulWadDown(sigmoid).mulWadDown(volatilityAdjustment);

    //     return tMint;
    // }    
}
