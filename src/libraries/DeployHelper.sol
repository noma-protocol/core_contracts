// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from 'v3-core/libraries/TickMath.sol';
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Uniswap} from "./Uniswap.sol";
import {Utils} from "./Utils.sol";
import {Conversions} from "./Conversions.sol";

import {
    LiquidityPosition, 
    LiquidityType
} from "../types/Types.sol";

/**
 * @title DeployHelper Library
 * @dev This library provides helper functions for deploying liquidity positions on Uniswap V3.
 *      It facilitates the creation of "Floor" liquidity positions with calculated tick ranges.
 */
library DeployHelper {

    /**
     * @notice Deploys a "Floor" liquidity position in a Uniswap V3 pool.
     * @dev Uses price-to-tick conversion and liquidity calculations to deploy the position.
     *      The liquidity is deployed at a calculated lower and upper tick.
     *      If the calculated liquidity is zero, the function reverts.
     * @param pool The Uniswap V3 pool where liquidity will be provided.
     * @param receiver The address that will receive the liquidity position.
     * @param _floorPrice The price at which the floor liquidity position should be set.
     * @param _amount0 The amount of token0 to be deposited as liquidity.
     * @param tickSpacing The tick spacing of the Uniswap V3 pool.
     * @return newPosition The created liquidity position struct.
     * @return liquidityType The type of liquidity position, which is `LiquidityType.Floor`.
     */
    function deployFloor(
        IUniswapV3Pool pool,
        address receiver, 
        uint256 _floorPrice, 
        uint256 _amount0,
        int24 tickSpacing
    ) 
        internal 
        returns (
            LiquidityPosition memory newPosition,
            LiquidityType liquidityType
        ) 
    {
        // Get the current square root price ratio from the pool
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();   

        // Retrieve the number of decimals for token0
        uint8 decimals = IERC20Metadata(address(pool.token0())).decimals();

        // Convert price to tick and determine lower tick
        int24 lowerTick = TickMath.getTickAtSqrtRatio(
            Conversions.priceToSqrtPriceX96(
                int256(_floorPrice), 
                tickSpacing,
                decimals
            )
        );

        // Sets the upper tick value to lower tick + minimum tick spacing value
        int24 upperTick = lowerTick + tickSpacing;

        // Compute the liquidity amount based on the provided token0 amount
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            _amount0,
            0 // No token1 contribution for floor liquidity
        );

        // Ensure that the computed liquidity is non-zero before minting
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
                        Utils._uint2str(uint256(
                            Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, decimals)
                        ))
                    )
                )
            );             
        }

        // Store the new liquidity position
        newPosition = LiquidityPosition({
            lowerTick: lowerTick, 
            upperTick: upperTick, 
            liquidity: liquidity, 
            price: _floorPrice,
            tickSpacing: tickSpacing
        });

        return (
            newPosition, 
            LiquidityType.Floor
        );
    }
}
