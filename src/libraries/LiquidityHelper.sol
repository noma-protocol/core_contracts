

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {FullMath} from '@uniswap/v3-core/libraries/FullMath.sol';
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';
import {ERC20} from "solmate/tokens/ERC20.sol";
import {LiquidityPosition, LiquidityType} from "../Types.sol";
import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {Conversions} from "./Conversions.sol";

interface IVault {
    function updatePosition(LiquidityPosition memory position, LiquidityType liquidityType) external;
}

library LiquidityHelper {

    function shiftFloor(
        address vault,
        IUniswapV3Pool pool,
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

        (uint128 liquidity,,,,) = pool.positions(floorPositionId);

        if (liquidity > 0) {
            Uniswap.burn(
                pool,
                floorPosition.lowerTick,
                floorPosition.upperTick,
                liquidity
            );
        } else {
            revert("shiftFloor: liquidity is 0");
        }

        uint256 balanceAfterShiftFloorToken1 = ERC20(token1).balanceOf(address(this));
        
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (, int24 newFloorUpperTick) = Conversions.computeSingleTick(newFloorPrice, tickSpacing);

        uint256 amount0Max = 0;
        uint256 amount1Max = balanceAfterShiftFloorToken1;

        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(newFloorLowerTick),
            TickMath.getSqrtRatioAtTick(newFloorUpperTick),
            amount0Max,
            amount1Max
        );

        if (newLiquidity > 0) {
            Uniswap.mint(pool, newFloorLowerTick, newFloorUpperTick, liquidity, LiquidityType.Floor, true);
            IVault(vault).updatePosition(
                LiquidityPosition(
                    newFloorLowerTick, 
                    newFloorUpperTick, 
                    newLiquidity, 
                    newFloorPrice,
                    0,
                    0,
                    0
                ), 
                LiquidityType.Floor
            );
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "shiftFloor: liquidity is 0  ", 
                            Utils._uint2str(uint256(sqrtRatioX96)
                        )
                    )
                )
            ); 
        }
    }

    function collect(
        IUniswapV3Pool pool,
        LiquidityPosition memory position
    ) internal {

        bytes32 anchorPositionId = keccak256(
            abi.encodePacked(
                address(this), 
                position.lowerTick, 
                position.upperTick
            )
        );

        (uint128 liquidity,,,,) = pool.positions(anchorPositionId);

        if (liquidity > 0) {
            Uniswap.burn(
                pool,
                position.lowerTick, 
                position.upperTick,
                liquidity
            );
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "collect: liquidity is 0, liquidity: ", 
                            Utils._uint2str(uint256(liquidity)
                        )
                    )
                )                
            );
        }
    }

    function computeFeesEarned(
        IUniswapV3Pool pool,
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
            feeGrowthGlobal = pool.feeGrowthGlobal0X128();
            (,, feeGrowthOutsideLower,,,,,) = pool.ticks(position.lowerTick);
            (,, feeGrowthOutsideUpper,,,,,) = pool.ticks(position.upperTick);
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (,,, feeGrowthOutsideLower,,,,) = pool.ticks(position.lowerTick);
            (,,, feeGrowthOutsideUpper,,,,) = pool.ticks(position.upperTick);
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
        IUniswapV3Pool pool,
        LiquidityPosition memory position
    )
        internal
        view
        returns (uint256 amount0Current, uint256 amount1Current)
    {
        (uint160 sqrtRatioX96, int24 tick,,,,,) = pool.slot0();

        bytes32 positionId = keccak256(
            abi.encodePacked(
                address(this), 
                position.lowerTick, 
                position.upperTick
                )
            );

        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(positionId);

        // compute current holdings from liquidity
        (amount0Current, amount1Current) = LiquidityAmounts
        .getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            liquidity
        );

        // compute current fees earned, 3000 = Manager fee
        uint256 fee0 = computeFeesEarned(
            pool, 
            position, 
            true, 
            feeGrowthInside0Last, 
            tick, 
            liquidity
        ) + uint256(tokensOwed0);

        fee0 = fee0 - (fee0 * (250 + 3000)) / 10000;

        uint256 fee1 = computeFeesEarned(
            pool, 
            position, 
            false, 
            feeGrowthInside1Last, 
            tick, 
            liquidity
        ) + uint256(tokensOwed1);

        fee1 = fee1 - (fee1 * (250 + 3000)) / 10000;

    }

    function getAmount1ForLiquidityInFloor(LiquidityPosition memory floorPosition) internal view returns (uint256) {
        
        bytes32 floorPositionId = keccak256(
            abi.encodePacked(
                address(this), 
                floorPosition.lowerTick, 
                floorPosition.upperTick
                )
            );

        uint256 amount1 = LiquidityAmounts
        .getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(floorPosition.lowerTick),
            TickMath.getSqrtRatioAtTick(floorPosition.upperTick),
            floorPosition.liquidity
        );

        return amount1;
    }

    function getAmount1ForLiquidityInPosition(LiquidityPosition memory position) internal view returns (uint256) {
        
        bytes32 positionId = keccak256(
            abi.encodePacked(
                address(this), 
                position.lowerTick, 
                position.upperTick
                )
            );

        uint256 amount1 = LiquidityAmounts
        .getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            position.liquidity
        );

        return amount1;
    }

    function getFloorCapacity(LiquidityPosition memory floorPosition) internal view returns (uint256) {
    
        uint256 token1InFloor = getAmount1ForLiquidityInFloor(floorPosition);
        uint256 capacity = token1InFloor / floorPosition.price;
        
        return capacity;
    }    
}