
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Logarithm} from "./Logarithm.sol";
import {IUniswapV3Pool} from '@uniswap/v3-core/interfaces/IUniswapV3Pool.sol';
import {FullMath} from '@uniswap/v3-core/libraries/FullMath.sol';
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library Conversions {

    int256 private constant LOG2_1E18 = 59794705707972520000;
    int256 private constant LOG2_1P0001 = 144262291094538;

    error InvalidDecimals();
    
    function computeSingleTick(uint256 price, int24 tickSpacing, uint8 decimals) 
        internal 
        pure 
        returns 
    (int24 lowerTick, int24 upperTick) {
        lowerTick = priceToTick(int256(price), tickSpacing, decimals);
        upperTick = (lowerTick / tickSpacing + 1) * tickSpacing;
    }
    
    function computeRangeTicks(uint256 priceLower, uint256 priceUpper, int24 tickSpacing, uint8 decimals) 
        internal 
        pure 
        returns
    (int24 lowerTick, int24 upperTick) {
        lowerTick = priceToTick(int256(priceLower), tickSpacing, decimals);
        upperTick = priceToTick(int256(priceUpper), tickSpacing, decimals);
    }

    function tickToSqrtPriceX96(int24 _tick) internal pure returns(uint160) {
        return TickMath.getSqrtRatioAtTick(_tick);
    }

    function priceToTick(int256 price, int24 tickSpacing, uint8 tokenDecimals) internal pure returns (int24) {
        if (!(tokenDecimals >= 6 && tokenDecimals <= 18)) {
            revert InvalidDecimals();
        }
        // Adjust price to 18 decimals
        int256 scaleFactor = int256(10**(18 - tokenDecimals));
        price = price * scaleFactor;

        return round(
            Logarithm.log2(price * 1e18, 1e18, 5e17) - LOG2_1E18, 
            int256(LOG2_1P0001) * tickSpacing
        ) * tickSpacing;
    }

    function round(int256 _a, int256 _b) internal pure returns(int24) {
        return int24(10000 * _a / _b % 10000 > 10000 / 2 ? _a / _b + 1 : _a / _b);
    }

    function priceToSqrtPriceX96(int256 price, int24 tickSpacing, uint8 decimals) internal pure returns(uint160) {
        return tickToSqrtPriceX96(priceToTick(price, tickSpacing, decimals));
    }

    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96, uint8 decimals) public pure returns (uint256) {
        uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 numerator2 = 10 ** decimals;
        return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }


}