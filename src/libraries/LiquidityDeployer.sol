// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";

import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Conversions} from "./Conversions.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    AmountsToMint,
    DeployLiquidityParams
} from "../types/Types.sol";

// Custom errors
error InvalidTicksFloor();
error InvalidTicksAnchor();
error InvalidTicksDiscovery();
error InvalidFloor();
error NoLiquidity();

/**
 * @title LiquidityManager
 * @notice A library for deploying and managing liquidity positions in a Uniswap V3 pool.
 */
library LiquidityDeployer {

    function deployFloor(
        address pool,
        address receiver,
        uint256 floorPrice,
        uint256 amount0ToDeploy,
        uint256 amount1ToDeploy,
        int24 tickSpacing
        // LiquidityPosition[3] memory positions
    ) internal returns (LiquidityPosition memory newPosition) {

        uint8 decimals = IERC20Metadata(IUniswapV3Pool(pool).token0()).decimals();
        (int24 lowerTick, int24 upperTick) = Conversions.computeSingleTick(floorPrice, tickSpacing, decimals);

        // Ensuring valid tick range
        if (upperTick <= lowerTick) {
            revert InvalidTicksFloor();
        }

        // Deploying the new liquidity position
        newPosition = deployPosition(
            DeployLiquidityParams({
                pool: pool,
                receiver: receiver,
                bips: 0,
                lowerTick: lowerTick,
                upperTick: upperTick,
                tickSpacing: tickSpacing,
                liquidityType: LiquidityType.Floor,
                amounts: AmountsToMint({
                    amount0: amount0ToDeploy,
                    amount1: amount1ToDeploy
                })
            })            
        );           
    }

    // Deploys anchor Position during initial provisioning 
    function deployAnchor(
        LiquidityPosition memory floorPosition,
        DeployLiquidityParams memory deployParams
    )
        internal
        returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        )
    {
        uint8 decimals = IERC20Metadata(IUniswapV3Pool(deployParams.pool).token0()).decimals();

        uint256 floorUpperPrice = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(floorPosition.upperTick),
            decimals
        );

        (int24 lowerTick, int24 upperTick) = Conversions.computeRangeTicks(
            floorUpperPrice,
            Utils.addBips(floorUpperPrice, int256(deployParams.bips)),
            deployParams.tickSpacing,
            decimals
        );

        if (upperTick <= lowerTick) {
            revert InvalidTicksAnchor();
        }

        (newPosition) = deployPosition(
            DeployLiquidityParams({
                pool: deployParams.pool,
                receiver: deployParams.receiver,
                bips: 0,
                lowerTick: lowerTick,
                upperTick: upperTick,
                tickSpacing: deployParams.tickSpacing,
                liquidityType: LiquidityType.Anchor,
                amounts: AmountsToMint({
                    amount0: deployParams.amounts.amount0,
                    amount1: deployParams.amounts.amount1
                })
            })
        );
        
        return (newPosition, LiquidityType.Anchor);
    }

    function deployDiscovery(
        uint256 upperDiscoveryPrice,
        LiquidityPosition memory anchorPosition,
        DeployLiquidityParams memory deployParams
    )
        internal
        returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        )
    {
        uint8 decimals = IERC20Metadata(address(IUniswapV3Pool(deployParams.pool).token0())).decimals();

        uint256 lowerDiscoveryPrice = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(anchorPosition.upperTick),
            decimals
        );

        lowerDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, 50);

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeRangeTicks(
            lowerDiscoveryPrice,
            upperDiscoveryPrice,
            anchorPosition.tickSpacing,
            decimals
        );

        if (lowerTick <= anchorPosition.upperTick) {
            revert InvalidTicksDiscovery();
        }

        uint256 balanceToken0 = IERC20Metadata(IUniswapV3Pool(deployParams.pool).token0()).balanceOf(address(this));

        newPosition = deployPosition(
            DeployLiquidityParams({
                pool: deployParams.pool,
                receiver: deployParams.receiver,
                bips: 0,
                lowerTick: lowerTick,
                upperTick: upperTick,
                tickSpacing: deployParams.tickSpacing,
                liquidityType: LiquidityType.Discovery,
                amounts: AmountsToMint({
                    amount0: balanceToken0,
                    amount1: 0
                })
            })            
        );

        newPosition.price = upperDiscoveryPrice;

        return (newPosition, LiquidityType.Discovery);
    }

    function shiftFloor(
        address pool,
        address receiver,
        uint256 newFloorPrice,
        uint256 newFloorBalance,
        LiquidityPosition memory floorPosition
    ) internal returns (LiquidityPosition memory newPosition) {
        
        (uint160 sqrtRatioX96,,,,,, ) = IUniswapV3Pool(pool).slot0();
        uint8 decimals = IERC20Metadata(address(IUniswapV3Pool(pool).token0())).decimals();

        (int24 lowerTick, int24 upperTick) = 
        Conversions.computeSingleTick(
            newFloorPrice,
            floorPosition.tickSpacing,
            decimals
        );

        if (lowerTick < floorPosition.lowerTick) revert InvalidFloor();

        uint128 liquidity = LiquidityAmounts
        .getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            0,
            newFloorBalance
        );

        if (liquidity > 0) {

            Uniswap.mint(
                pool,
                receiver,
                lowerTick,
                upperTick,
                liquidity,
                LiquidityType.Floor,
                false
            );

            newPosition.liquidity = liquidity;
            newPosition.upperTick = upperTick;
            newPosition.lowerTick = lowerTick;
            newPosition.tickSpacing = floorPosition.tickSpacing;
            newPosition.liquidityType = LiquidityType.Floor;
            
        } else {

            revert(
                string(
                    abi.encodePacked(
                        "shiftFloor: liquidity is 0 : ", 
                        Utils._uint2str(uint256(newFloorPrice))
                    )
                )
            );

        }

        return newPosition;
    }

    function deployPosition(
      DeployLiquidityParams memory params
    ) internal returns (LiquidityPosition memory newPosition) {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(params.pool).slot0();

        uint128 liquidity = LiquidityAmounts
        .getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(params.lowerTick),
            TickMath.getSqrtRatioAtTick(params.upperTick),
            params.amounts.amount0, 
            params.amounts.amount1
        );

        if (liquidity > 0) {
            Uniswap.mint(
                params.pool, 
                params.receiver, 
                params.lowerTick, 
                params.upperTick, 
                liquidity, 
                params.liquidityType, 
                false
            );
        } else {
            revert NoLiquidity();
        }   

        newPosition = LiquidityPosition({
            lowerTick: params.lowerTick, 
            upperTick: params.upperTick, 
            liquidity: liquidity, 
            price: 0,
            tickSpacing: params.tickSpacing,
            liquidityType: params.liquidityType
        });          
    }


    function computeAmount0ForAmount1(
        LiquidityPosition memory position,
        uint256 amount1
    ) public view returns (uint256 amount0) {
        
        // Get Liquidity for amount1 
        uint128 liquidity = LiquidityAmounts
        .getLiquidityForAmount1(
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            amount1
        );

        // Compute token0 for liquidity 
        amount0 = LiquidityAmounts
        .getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick),
            liquidity
        );
    }
}