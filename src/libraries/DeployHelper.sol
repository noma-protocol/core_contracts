

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
 
import {
    LiquidityPosition, 
    LiquidityType 
} from "../Types.sol";


library DeployHelper {

    function deployFloor(
        IUniswapV3Pool pool,
        address receiver, 
        uint256 _floorPrice, 
        int24 tickSpacing
        ) internal returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        ) {
    
        uint256 balanceToken0 = ERC20(pool.token0()).balanceOf(address(this));
        uint256 balanceToken1 = ERC20(pool.token1()).balanceOf(address(this));
        
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        // (int24 lowerTick, int24 upperTick) = Conversions.computeSingleTick(_floorPrice, tickSpacing);
        int24 lowerTick = TickMath.getTickAtSqrtRatio(Conversions.priceToSqrtPriceX96(int256(_floorPrice), tickSpacing));
        int24 upperTick = TickMath.getTickAtSqrtRatio(Conversions.priceToSqrtPriceX96(int256(1.0202003198939318e18), tickSpacing));
        
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            10000 ether,
            0 //(balanceToken1 * 66) / 100 // % of WETH
        );

        if (liquidity > 0) {
            Uniswap.mint(
                address(pool), 
                receiver,
                lowerTick, 
                upperTick, 
                liquidity, 
                LiquidityType.Floor, 
                false
            );
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "deployFloor: liquidity is 0, spot price: ", 
                            Utils._uint2str(uint256(sqrtRatioX96)
                        )
                    )
                )
            );             
        }

        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: _floorPrice
        });

        return (
            newPosition, 
            LiquidityType.Floor
        );
    }

}