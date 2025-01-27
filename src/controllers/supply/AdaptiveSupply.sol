// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "solmate/utils/FixedPointMathLib.sol";
import "../../libraries/SafeMathInt.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";

interface IERC20 { 
    function decimals() external view returns (uint8);
}

interface IVault{
    function pool() external view returns (IUniswapV3Pool);
}

contract AdaptiveSupply {
    using FixedPointMathLib for uint256;
    using SafeMathInt for int256;

    function calculateVolatilityAdjustment(uint256 volatility) internal pure returns (uint256) {
        uint256 kv = 1e18;
        int256 volExp = -int256(kv.mulWadDown(volatility));
        return uint256(volExp.expWad());
    }

    function calculateMintAmount(
        uint256 deltaSupply,
        uint256 timeElapsed,
        uint256 spotPrice,
        uint256 imv
    ) public view returns (uint256 mintAmount) {
        require(timeElapsed > 0, "Time elapsed must be greater than zero");
        require(deltaSupply > 0, "Delta supply must be greater than zero");
        require(imv > 0, "IMV must be greater than zero");

        uint256 scaleFactor = calculateScaleFactor();
        uint256 sigmoid = calculateSigmoid(deltaSupply, timeElapsed);

        // Calculate ratio = spotPrice / imv
        uint256 ratio = spotPrice.divWadDown(imv);
        require(ratio >= 1e18, "Spot price must not be lower than IMV");

        // Combine ratio and time for adjustment
        uint256 timeAdjustment = calculateTimeAdjustment(ratio, timeElapsed);

        uint256 sqrtTime = timeElapsed.sqrt();
        require(sqrtTime > 0, "Invalid sqrt(timeElapsed)");
        uint256 tBase = deltaSupply.divWadDown(sqrtTime);

        mintAmount = tBase.mulWadDown(sigmoid).mulWadDown(timeAdjustment);
        mintAmount = mintAmount / scaleFactor;
    }

    function calculateScaleFactor() internal view returns (uint256) {
        uint256 tokenDecimals = IERC20(
            IUniswapV3Pool(
                IVault(msg.sender).pool()
            ).token1()
        ).decimals();
        require(tokenDecimals >= 6 && tokenDecimals <= 18, "Invalid token decimals");
        return 10**(18 - tokenDecimals);
    }

    function calculateSigmoid(uint256 deltaSupply, uint256 timeElapsed) internal pure returns (uint256) {
        uint256 denominator = deltaSupply + timeElapsed;
        require(denominator > 0, "Invalid denominator");
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

    function calculateTimeAdjustment(uint256 ratio, uint256 timeElapsed) internal pure returns (uint256) {
        // Combine ratio and timeElapsed to create an adjustment factor
        uint256 ratioFactor = ratio.divWadDown(1e18); // Normalize ratio to a factor
        uint256 timeFactor = timeElapsed.sqrt();
        return ratioFactor.mulWadDown(timeFactor);
    }

}