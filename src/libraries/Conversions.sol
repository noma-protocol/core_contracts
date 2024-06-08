
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Logarithm} from "./Logarithm.sol";
import {IUniswapV3Pool} from '@uniswap/v3-core/interfaces/IUniswapV3Pool.sol';
import {FullMath} from '@uniswap/v3-core/libraries/FullMath.sol';

import '@uniswap/v3-core/libraries/TickMath.sol';
import 'abdk/ABDKMath64x64.sol';

library Conversions {

    uint256 private constant DECIMALS = 18;
    uint256 private constant ONE = 10 ** DECIMALS;

    int256 private constant LOG2_1E18 = 59794705707972520000;
    int256 private constant LOG2_1P0001 = 144262291094538;

    function computeSingleTick(uint256 price, int24 tickSpacing) 
        internal 
        pure 
        returns 
    (int24 lowerTick, int24 upperTick) {
        lowerTick = priceToTick(int256(price), tickSpacing) ;
        upperTick = (lowerTick / tickSpacing + 1) * tickSpacing;
    }
    
    function computeRangeTicks(uint256 priceLower, uint256 priceUpper, int24 tickSpacing) 
        internal 
        pure 
        returns
    (int24 lowerTick, int24 upperTick) {
        lowerTick = priceToTick(int256(priceLower), tickSpacing);
        upperTick = priceToTick(int256(priceUpper), tickSpacing);
    }

    function tickToSqrtPriceX96(int24 _tick) internal pure returns(uint160) {
        return TickMath.getSqrtRatioAtTick(_tick);
    }

    function priceToTick(int256 price, int24 tickSpacing) internal pure returns(int24) {
        // math.log(10**18,2) * 10**18 = 59794705707972520000
        // math.log(1.0001,2) * 10**18 = 144262291094538
        return round(
            Logarithm.log2(price * 1e18, 1e18, 5e17) - LOG2_1E18, 
            int(LOG2_1P0001) * tickSpacing
        ) * tickSpacing;
    }

    function floor(uint256 number) public pure returns (uint256) {
        return (number / ONE) * ONE;
    }

    function round(int256 _a, int256 _b) internal pure returns(int24) {
        return int24(10000 * _a / _b % 10000 > 10000 / 2 ? _a / _b + 1 : _a / _b);
    }

    function priceToSqrtPriceX96(int256 price, int24 tickSpacing) internal pure returns(uint160) {
        return tickToSqrtPriceX96(priceToTick(price, tickSpacing));
    }

    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96, uint8 decimals) public pure returns (uint256) {
        uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 numerator2 = 10 ** decimals;
        return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

}