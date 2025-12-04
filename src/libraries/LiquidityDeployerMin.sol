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

/**
 * @title LiquidityManager
 * @notice A library for deploying and managing liquidity positions in a Uniswap V3 pool.
 */
library LiquidityDeployerMin {

    function reDeployFloor(
        address pool,
        address receiver,
        uint256 amount0ToDeploy,
        uint256 amount1ToDeploy,
        LiquidityPosition[3] memory positions
    ) internal returns (LiquidityPosition memory newPosition) {
        // Ensuring valid tick range
        if (positions[0].upperTick <= positions[0].lowerTick) {
            revert InvalidTicksFloor();
        }

        // Deploying the new liquidity position
        newPosition = deployPosition(
            DeployLiquidityParams({
                pool: pool,
                receiver: receiver,
                bips: 0,
                lowerTick: positions[0].lowerTick,
                upperTick: positions[0].upperTick,
                tickSpacing: positions[0].tickSpacing,
                liquidityType: LiquidityType.Floor,
                amounts: AmountsToMint({
                    amount0: amount0ToDeploy,
                    amount1: amount1ToDeploy
                })
            })              
        );

        LiquidityPosition[3] memory newPositions = [
            newPosition, 
            positions[1], 
            positions[2]
        ];

        IVault(receiver)
        .updatePositions(
            newPositions
        );            
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
            
            revert(
                string(
                    abi.encodePacked(
                        "deployPosition params.amounts.amount0: ", 
                        Utils._uint2str(uint256(params.amounts.amount0))
                    )
                )
            );                
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
}