
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {LiquidityPosition} from "../Types.sol";
import {FullMath} from '@uniswap/v3-core/libraries/FullMath.sol';
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';

library Underlying {

    function computeFeesEarned(
        address pool,
        LiquidityPosition memory position,
        bool isToken0,
        uint256 feeGrowthInsideLast,
        int24 tick,
        uint128 liquidity
    ) private view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
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
            fee = FullMath.mulDiv(liquidity, feeGrowthInside - feeGrowthInsideLast, 0x100000000000000000000000000000000);
        }
    }

    function getUnderlyingBalances(
        address pool,
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
        require(position.liquidity > 0, "0 liquidity position");

        (uint160 sqrtRatioX96, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();

        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = IUniswapV3Pool(pool).positions(
            keccak256(
            abi.encodePacked(
                address(this), 
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

            // compute current fees earned, 3000 = Manager fee
            // uint256 fee0 = computeFeesEarned(
            //     pool, 
            //     position, 
            //     true, 
            //     feeGrowthInside0Last, 
            //     tick, 
            //     liquidity
            // ) + uint256(tokensOwed0);

            // fee0 = fee0 - (fee0 * (250 + 3000)) / 10000;

            // uint256 fee1 = computeFeesEarned(
            //     pool, 
            //     position, 
            //     false, 
            //     feeGrowthInside1Last, 
            //     tick, 
            //     liquidity
            // ) + uint256(tokensOwed1);

            // fee1 = fee1 - (fee1 * (250 + 3000)) / 10000;
        } else {
            revert("0 liquidity");
        }
    }    
}