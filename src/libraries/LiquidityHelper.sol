

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {Conversions} from "./Conversions.sol";
import {DecimalMath} from "./DecimalMath.sol";

import {Underlying} from "./Underlying.sol";
import {ModelHelper} from "./ModelHelper.sol";

import {
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters,
    AmountsToMint
} from "../Types.sol";

library LiquidityHelper {

    function shift(
        address pool,
        LiquidityPosition[] memory positions,
        LiquidityType liquidityType
    ) internal returns (
        uint256 currentLiquidityRatio, 
        LiquidityPosition memory newPosition
    ) {
        // Ratio of the anchor's price to market price
        currentLiquidityRatio = ModelHelper.getLiquidityRatio(pool, positions[1]);
        (,,, uint256 balanceToken1BeforeCollect) = Underlying.getUnderlyingBalances(pool, positions[1]);
        
        Uniswap.collect(pool, address(this), positions[1].lowerTick, positions[1].upperTick);
        Uniswap.collect(pool, address(this), positions[2].lowerTick, positions[2].upperTick);

        if (currentLiquidityRatio < 1e18) {
            
            // Shift --> ETH after skim at floor = ETH before skim at anchor - (liquidity ratio * ETH before skim at anchor)
            uint256 toSkim = balanceToken1BeforeCollect - (
                DecimalMath.multiplyDecimal(currentLiquidityRatio, balanceToken1BeforeCollect)
            );

            if (toSkim > 0) {
                addToFloor(pool, positions[0], toSkim);

                (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

                uint256 priceLower = Utils.addBips(Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18), -250);

                int24 tickLower = Conversions.priceToTick(int256(priceLower), 60);
                int24 tickUpper = Conversions.priceToTick(int256(Utils.addBips(priceLower, 500)), 60);

                newPosition = reDeploy(pool, sqrtRatioX96, tickLower, tickUpper, LiquidityType.Anchor);

            } else {
                revert("Nothing to skim");
            }

        }  else {
            revert("liqRatio >= 1");
        }
    }

    function reDeploy(
        address pool,
        uint160 sqrtRatioX96,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType
    ) internal returns (LiquidityPosition memory newPosition) {
        require(upperTick > lowerTick, "invalid ticks");
        
        newPosition = doDeployPosition(
            pool, 
            address(this), 
            sqrtRatioX96, 
            lowerTick,
            upperTick,
            liquidityType, 
            AmountsToMint({
                amount0: ERC20(IUniswapV3Pool(pool).token0()).balanceOf(address(this)),
                amount1: liquidityType == LiquidityType.Anchor ? 
                ERC20(IUniswapV3Pool(pool).token1()).balanceOf(address(this)) : 0
            })
        );     
    }
        

    function doDeployPosition(
        address pool,
        address receiver,
        uint160 sqrtRatioX96,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType,
        AmountsToMint memory amounts
    ) internal returns (LiquidityPosition memory newPosition) {
 
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amounts.amount0, 
            amounts.amount1
        );

        if (liquidity > 0) {
            Uniswap.mint(
                pool, 
                receiver, 
                lowerTick, 
                upperTick, 
                liquidity, 
                liquidityType, 
                false
            );
        } else {
            revert("doDeployPosition: liquidity is 0");
        }  

        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: 0,
            amount0LowerBound: 0,
            amount1UpperBound: 0,
            amount1UpperBoundVirtual: 0
        });    
    }

    function addToFloor(
        address pool,
        LiquidityPosition memory floorPosition,
        uint256 amountToken1
    ) internal {

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        if (floorPosition.liquidity > 0) {
            
            uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(floorPosition.lowerTick),
                TickMath.getSqrtRatioAtTick(floorPosition.upperTick),
                0,
                amountToken1
            );

            if (newLiquidity > 0) {
                Uniswap.mint(
                    pool, 
                    address(this), 
                    floorPosition.lowerTick, 
                    floorPosition.upperTick, 
                    newLiquidity, 
                    LiquidityType.Floor, 
                    false
                );
            }

        }        
    }
    
}