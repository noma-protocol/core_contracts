
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Logarithm} from "./Logarithm.sol";

import '@uniswap/v3-core/libraries/TickMath.sol';
import 'abdk/ABDKMath64x64.sol';

library Conversions {

    function computeSingleTick(uint256 price, int24 tickSpacing) 
        internal 
        pure 
        returns 
    (int24 lowerTick, int24 upperTick) {
        lowerTick = nearestUsableTick(priceToTick(int256(price), 60), tickSpacing);
        upperTick = (lowerTick / tickSpacing + 1) * tickSpacing;
    }
    

    function tickToSqrtPriceX96(int24 _tick) internal pure returns(uint160) {
        return TickMath.getSqrtRatioAtTick(_tick);
    }

    function priceToTick(int256 price, int24 tickSpacing) internal pure returns(int24) {
        // math.log(10**18,2) * 10**18 = 59794705707972520000
        // math.log(1.0001,2) * 10**18 = 144262291094538
        return round(
            Logarithm.log2(price * 1e18, 1e18, 5e17) - 59794705707972520000, 
            int(144262291094538) * tickSpacing
        ) * tickSpacing;
    }


    function round(int256 _a, int256 _b) internal pure returns(int24) {
        return int24(10000 * _a / _b % 10000 > 10000 / 2 ? _a / _b + 1 : _a / _b);
    }


    function nearestUsableTick(int24 tick_, int24 tickSpacing)
        internal
        pure
        returns (int24 result)
    {
        result =
            int24(divRound(int128(tick_), int128(int24(tickSpacing)))) *
            int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }
    
    function divRound(int128 x, int128 y)
        internal
        pure
        returns (int128 result)
    {
        int128 quot = ABDKMath64x64.div(x, y);
        result = quot >> 64;

        if (quot % 2**64 >= 0x8000000000000000) {
            result += 1;
        }
    }

    function priceToSqrtPriceX96(
        uint256 price,
        uint8 decimalsToken0
    ) internal pure returns (uint160) {
        uint256 sqrtPrice = sqrt(price);
        uint256 scaledSqrtPrice = sqrtPrice * (1 << 96);
        uint256 divisor = 10 ** (decimalsToken0 / 2);
        
        require(divisor > 0, "Divisor cannot be zero");
        uint256 result = scaledSqrtPrice / divisor;
        
        require(result <= type(uint160).max, "Result exceeds uint160 limits");
        
        return uint160(result);
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