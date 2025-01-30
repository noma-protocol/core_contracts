// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Logarithm} from "./Logarithm.sol";
import {FullMath} from 'v3-core/libraries/FullMath.sol';
import {TickMath} from 'v3-core/libraries/TickMath.sol';

/**
 * @title Conversions Library
 * @dev Provides functions for converting prices to Uniswap V3 tick values and vice versa.
 *      Also includes utilities for handling price calculations and rounding.
 */
library Conversions {

    /// @notice Log base-2 of 1e18, used for logarithmic calculations.
    int256 private constant LOG2_1E18 = 59794705707972520000;

    /// @notice Log base-2 of 1.0001, used for tick calculations.
    int256 private constant LOG2_1P0001 = 144262291094538;

    /// @notice Error thrown when the provided token decimals are outside the valid range.
    error InvalidDecimals();
    
    /**
     * @notice Computes the single tick range for a given price.
     * @param price The price value.
     * @param tickSpacing The tick spacing of the Uniswap V3 pool.
     * @param decimals The number of decimals for the token.
     * @return lowerTick The lower tick corresponding to the price.
     * @return upperTick The upper tick corresponding to the price.
     */
    function computeSingleTick(
        uint256 price, 
        int24 tickSpacing, 
        uint8 decimals
    ) 
        internal 
        pure 
        returns (int24 lowerTick, int24 upperTick) 
    {
        lowerTick = priceToTick(int256(price), tickSpacing, decimals);
        upperTick = (lowerTick / tickSpacing + 1) * tickSpacing;
    }
    
    /**
     * @notice Computes the lower and upper ticks for a given price range.
     * @param priceLower The lower price value.
     * @param priceUpper The upper price value.
     * @param tickSpacing The tick spacing of the Uniswap V3 pool.
     * @param decimals The number of decimals for the token.
     * @return lowerTick The tick corresponding to priceLower.
     * @return upperTick The tick corresponding to priceUpper.
     */
    function computeRangeTicks(
        uint256 priceLower, 
        uint256 priceUpper, 
        int24 tickSpacing, 
        uint8 decimals
    ) 
        internal 
        pure 
        returns (int24 lowerTick, int24 upperTick) 
    {
        lowerTick = priceToTick(int256(priceLower), tickSpacing, decimals);
        upperTick = priceToTick(int256(priceUpper), tickSpacing, decimals);
    }

    /**
     * @notice Converts a tick value to its corresponding square root price in Uniswap V3.
     * @param _tick The tick value to be converted.
     * @return The square root price as a Q96.32 fixed-point number.
     */
    function tickToSqrtPriceX96(int24 _tick) internal pure returns(uint160) {
        return TickMath.getSqrtRatioAtTick(_tick);
    }

    /**
     * @notice Converts a price value to its corresponding tick in Uniswap V3.
     * @dev Adjusts price to 18 decimals for consistency.
     * @param price The price value to convert.
     * @param tickSpacing The tick spacing of the Uniswap V3 pool.
     * @param tokenDecimals The number of decimals in the token's representation.
     * @return The corresponding tick value.
     */
    function priceToTick(
        int256 price, 
        int24 tickSpacing, 
        uint8 tokenDecimals
    ) 
        internal 
        pure 
        returns (int24) 
    {
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

    /**
     * @notice Rounds a division operation to the nearest integer value.
     * @param _a The numerator.
     * @param _b The denominator.
     * @return The rounded result as an int24.
     */
    function round(int256 _a, int256 _b) internal pure returns(int24) {
        return int24(10000 * _a / _b % 10000 > 10000 / 2 ? _a / _b + 1 : _a / _b);
    }

    /**
     * @notice Converts a price value to a Uniswap V3 square root price in Q96.32 format.
     * @param price The price value to convert.
     * @param tickSpacing The tick spacing of the Uniswap V3 pool.
     * @param decimals The number of decimals for the token.
     * @return The corresponding square root price in Q96.32 format.
     */
    function priceToSqrtPriceX96(
        int256 price, 
        int24 tickSpacing, 
        uint8 decimals
    ) 
        internal 
        pure 
        returns(uint160) 
    {
        return tickToSqrtPriceX96(priceToTick(price, tickSpacing, decimals));
    }

    /**
     * @notice Converts a square root price (Q96.32 format) to a token price with a specified number of decimals.
     * @param sqrtPriceX96 The square root price value in Q96.32 format.
     * @param decimals The number of decimals to use for the resulting price.
     * @return The corresponding token price.
     */
    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96, uint8 decimals) 
        public 
        pure 
        returns (uint256) 
    {
        uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 numerator2 = 10 ** decimals;
        return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }
}
