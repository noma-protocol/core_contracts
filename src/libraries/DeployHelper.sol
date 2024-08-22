

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
} from "../types/Types.sol";


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
            
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();        
        int24 lowerTick = TickMath.getTickAtSqrtRatio(Conversions.priceToSqrtPriceX96(int256(_floorPrice), tickSpacing));
        int24 upperTick = lowerTick + tickSpacing;
        
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            8_750_000e18,
            0 
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