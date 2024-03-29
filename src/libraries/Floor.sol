

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {Conversions} from "./Conversions.sol";


import {
    LiquidityPosition, 
    LiquidityType
} from "../Types.sol";

library Floor {

    function shiftFloor(
        address pool,
        address receiver,
        LiquidityPosition memory floorPosition,
        address token1,
        uint256 bips,
        int24 tickSpacing
    ) internal {
        require(bips < 10_000, "invalid bips");

        uint256 newFloorPrice = Utils.addBips(floorPosition.price, int256(bips));
        int24 newFloorLowerTick = Conversions.priceToTick(int256(newFloorPrice), tickSpacing);

        require(newFloorLowerTick > floorPosition.lowerTick, "invalid floor");

        bytes32 floorPositionId = keccak256(
            abi.encodePacked(
                    address(this), 
                    floorPosition.lowerTick, 
                    floorPosition.upperTick
                )
            );

        (uint128 liquidity,,,,) = IUniswapV3Pool(pool).positions(floorPositionId);

        if (liquidity > 0) {
            Uniswap.burn(
                pool,
                receiver,
                floorPosition.lowerTick,
                floorPosition.upperTick,
                liquidity
            );
        } else {
            revert("shiftFloor: liquidity is 0");
        }

        uint256 balanceAfterShiftFloorToken1 = ERC20(token1).balanceOf(address(this));
        
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        (, int24 newFloorUpperTick) = Conversions.computeSingleTick(newFloorPrice, tickSpacing);

        uint256 amount0Max = 0;
        uint256 amount1Max = balanceAfterShiftFloorToken1;

        uint128 newLiquidity = LiquidityAmounts
        .getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(newFloorLowerTick),
            TickMath.getSqrtRatioAtTick(newFloorUpperTick),
            amount0Max,
            amount1Max
        );

        if (newLiquidity > 0) {
            Uniswap.mint(
                pool, 
                receiver,
                newFloorLowerTick, 
                newFloorUpperTick, 
                liquidity, 
                LiquidityType.Floor, 
                true
            );
        }
    }

    
}