
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Uniswap} from "./Uniswap.sol";
import {Conversions} from "./Conversions.sol";
import {DecimalMath} from "./DecimalMath.sol";

import {Underlying} from "./Underlying.sol";
import {Utils} from "./Utils.sol";

import {
    LiquidityPosition
} from "../Types.sol";

library ModelHelper {

    function getLiquidityRatio(
        address pool,
        LiquidityPosition memory anchorPosition
    ) internal view returns (uint256 liquidityRatio) {
            
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        uint256 anchorLowerPrice = Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(anchorPosition.lowerTick),
            18);

        uint256 anchorUpperPrice = Conversions.sqrtPriceX96ToPrice(
                Conversions.tickToSqrtPriceX96(anchorPosition.upperTick),
            18);
            
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
        liquidityRatio = DecimalMath.divideDecimal(anchorLowerPrice, spotPrice);
    }

    function getPositionCapacity(
        address pool,
        LiquidityPosition memory position
    ) internal view returns (uint256 amount0Current) {
    
        // require(position.liquidity > 0, "0 liquidity floorPosition");

        (
            uint128 liquidity,,,,
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
            (amount0Current,) = LiquidityAmounts
            .getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(position.lowerTick),
                TickMath.getSqrtRatioAtTick(position.lowerTick),
                TickMath.getSqrtRatioAtTick(position.upperTick),
                liquidity
            );      
        }
    } 

    function getCirculatingSupply(
        address pool,
        LiquidityPosition memory anchorPosition,
        LiquidityPosition memory discoveryPosition
    ) internal view returns (uint256) {
        uint256 totalSupply = ERC20(address(IUniswapV3Pool(pool).token0())).totalSupply();
        uint256 protocolLockedBalanceToken0 = ERC20(address(IUniswapV3Pool(pool).token0())).balanceOf(address(this));

        (   
            ,, uint256 amount0CurrentAnchor, 
        ) = Underlying.getUnderlyingBalances(pool, anchorPosition);
        
        (
            ,, uint256 amount0CurrentDiscovery,             
        ) = Underlying.getUnderlyingBalances(pool, discoveryPosition);
    
        return totalSupply - (amount0CurrentAnchor + amount0CurrentDiscovery) - protocolLockedBalanceToken0;
    } 
   
}