// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {MathInt} from "../../libraries/MathInt.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

interface IERC20 { 
    function decimals() external view returns (uint8);
}

interface IVault {
    function pool() external view returns (IUniswapV3Pool);
}

contract AdaptiveSupply {
    using FixedPointMathLib for uint256;
    using MathInt for int256;

    // Custom errors
    error TimeElapsedZero();
    error DeltaSupplyZero();
    error IMVZero();
    error SpotPriceLowerThanIMV();
    error InvalidTokenDecimals();
    error InvalidDenominator();
    error InvalidSqrtTimeElapsed();

    function computeMintAmount(
        uint256 deltaSupply,
        uint256 timeElapsed,
        uint256 spotPrice,
        uint256 imv
    ) public view returns (uint256 mintAmount) {
        if (timeElapsed == 0) revert TimeElapsedZero();
        if (deltaSupply == 0) revert DeltaSupplyZero();
        if (imv == 0) revert IMVZero();

        uint256 scaleFactor = computeScaleFactor();
        uint256 sigmoid = computeSigmoid(deltaSupply, timeElapsed);

        // compute ratio = spotPrice / imv
        uint256 ratio = spotPrice.divWadDown(imv);
        if (ratio < 1e18) revert SpotPriceLowerThanIMV();

        // Combine ratio and time for adjustment
        uint256 timeAdjustment = computeTimeAdjustment(ratio, timeElapsed);

        uint256 sqrtTime = timeElapsed.sqrt();
        if (sqrtTime == 0) revert InvalidSqrtTimeElapsed();
        uint256 tBase = deltaSupply.divWadDown(sqrtTime);

        mintAmount = tBase.mulWadDown(sigmoid).mulWadDown(timeAdjustment);
        mintAmount = mintAmount / scaleFactor;
    }

    function computeScaleFactor() internal view returns (uint256) {
        uint256 tokenDecimals = IERC20(
            IUniswapV3Pool(
                IVault(msg.sender).pool()
            ).token1()
        ).decimals();
        if (tokenDecimals < 6 || tokenDecimals > 18) revert InvalidTokenDecimals();
        return 10**(18 - tokenDecimals);
    }

    function computeSigmoid(uint256 deltaSupply, uint256 timeElapsed) internal pure returns (uint256) {
        uint256 denominator = deltaSupply + timeElapsed;
        if (denominator == 0) revert InvalidDenominator();
        uint256 r = deltaSupply.divWadDown(denominator);

        uint256 maxR = 0.99e18;
        if (r > maxR) {
            r = maxR;
        }

        uint256 half = 0.5e18;
        int256 diff = int256(half) - int256(r);
        int256 kr = int256(5e18);
        int256 exponent = -((kr * diff) / int256(1e18));

        int256 maxExponent = 135305999368893231589;
        if (exponent > maxExponent) {
            exponent = maxExponent;
        } else if (exponent < -maxExponent) {
            exponent = -maxExponent;
        }

        return uint256(1e18).divWadDown(1e18 + exponent.expWad());
    }

    function computeTimeAdjustment(uint256 ratio, uint256 timeElapsed) internal pure returns (uint256) {
        // Combine ratio and timeElapsed to create an adjustment factor
        uint256 ratioFactor = ratio.divWadDown(1e18); // Normalize ratio to a factor
        uint256 timeFactor = timeElapsed.sqrt();
        return ratioFactor.mulWadDown(timeFactor);
    }
}
