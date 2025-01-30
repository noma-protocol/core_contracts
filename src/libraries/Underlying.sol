// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {LiquidityPosition} from "../types/Types.sol";
import {FullMath} from 'v3-core/libraries/FullMath.sol';
import {TickMath} from 'v3-core/libraries/TickMath.sol';

/**
 * @title Underlying
 * @notice A library for computing fees earned and retrieving underlying balances of liquidity positions in a Uniswap V3 pool.
 */
library Underlying {

    /**
     * @notice Computes the fees earned by a liquidity position.
     * @param position The liquidity position.
     * @param vault The address of the vault holding the position.
     * @param pool The address of the Uniswap V3 pool.
     * @param isToken0 Whether to compute fees for token0 (true) or token1 (false).
     * @param tick The current tick of the pool.
     * @return fee The amount of fees earned by the position.
     */
    function computeFeesEarned(
        LiquidityPosition memory position,
        address vault,
        address pool,
        bool isToken0,
        int24 tick
    ) internal view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
      
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            ,
        ) = IUniswapV3Pool(pool).positions(
            keccak256(
            abi.encodePacked(
                vault, 
                position.lowerTick, 
                position.upperTick
                )
            )            
        );

        if (isToken0) {
            feeGrowthGlobal = IUniswapV3Pool(pool).feeGrowthGlobal0X128();
            (,, feeGrowthOutsideLower,,,,,) = IUniswapV3Pool(pool).ticks(position.lowerTick);
            (,, feeGrowthOutsideUpper,,,,,) = IUniswapV3Pool(pool).ticks(position.upperTick);
        } else {
            feeGrowthGlobal = IUniswapV3Pool(pool).feeGrowthGlobal1X128();
            (,,, feeGrowthOutsideLower,,,,) = IUniswapV3Pool(pool).ticks(position.lowerTick);
            (,,, feeGrowthOutsideUpper,,,,) = IUniswapV3Pool(pool).ticks(position.upperTick);
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (tick >= position.lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (tick < position.upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;
            fee = FullMath.mulDiv(
                liquidity, 
                feeGrowthInside - (isToken0 ? feeGrowthInside0Last : feeGrowthInside1Last), 
                0x100000000000000000000000000000000
            );
        }
    }

    /**
     * @notice Retrieves the underlying balances of a liquidity position.
     * @param pool The address of the Uniswap V3 pool.
     * @param vault The address of the vault holding the position.
     * @param position The liquidity position.
     * @return lowerTick The lower tick of the position.
     * @return upperTick The upper tick of the position.
     * @return amount0Current The current amount of token0 in the position.
     * @return amount1Current The current amount of token1 in the position.
     */
    function getUnderlyingBalances(
        address pool,
        address vault,
        LiquidityPosition memory position
    )
        internal
        view
        returns (
            int24 lowerTick, 
            int24 upperTick, 
            uint256 amount0Current, 
            uint256 amount1Current
        )
    {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        (
            uint128 liquidity,,,,
        ) = IUniswapV3Pool(pool).positions(
            keccak256(
            abi.encodePacked(
                vault, 
                position.lowerTick, 
                position.upperTick
                )
            )            
        );

        if (liquidity > 0) {
            // compute current holdings from liquidity
            (amount0Current, amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(position.lowerTick),
                TickMath.getSqrtRatioAtTick(position.upperTick),
                liquidity
            );

            lowerTick = position.lowerTick;
            upperTick = position.upperTick;
        }  
    }    
}