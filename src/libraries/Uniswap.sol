// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LiquidityType, LiquidityPosition, SwapParams} from "../types/Types.sol";
import {Conversions} from "./Conversions.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import { IVault } from "../interfaces/IVault.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";

// Custom errors
error ZeroLiquidty();
error NoTokensExchanged();
error InvalidSwap();
error SlippageExceeded();
error PriceImpactTooHigh();

/**
 * @title Uniswap
 * @notice A library for interacting with Uniswap V3 pools, including minting, burning, collecting, and swapping liquidity positions.
 */
library Uniswap {

    /**
     * @notice Mints a new liquidity position in a Uniswap V3 pool.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the liquidity position.
     * @param lowerTick The lower tick of the position.
     * @param upperTick The upper tick of the position.
     * @param liquidity The amount of liquidity to mint.
     * @param liquidityType The type of liquidity position (Floor, Anchor, Discovery).
     * @param isShift Whether the operation is part of a shift (true) or not (false).
     */
    function mint(
        address pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity,
        LiquidityType liquidityType,
        bool isShift
    )
        internal
    {
        bytes memory data;
        string memory op = "mint";

        if (isShift) {
           op = "shift";
           data = abi.encode(0, op);
        } else {
            if (liquidityType == LiquidityType.Floor) {
                data = abi.encode(0, op);
            } else if (liquidityType == LiquidityType.Anchor) {
                data = abi.encode(1, op);
            } else if (liquidityType == LiquidityType.Discovery) {
                data = abi.encode(2, op);
            }
        }

       IUniswapV3Pool(pool).mint(receiver, lowerTick, upperTick, liquidity, data);
    }

    /**
     * @notice Burns a liquidity position and collects the fees.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the collected fees.
     * @param lowerTick The lower tick of the position.
     * @param upperTick The upper tick of the position.
     * @param liquidity The amount of liquidity to burn.
     */
    function _burn(
        address pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity        
    ) internal {

        IUniswapV3Pool(pool).burn(lowerTick, upperTick, liquidity);

        IUniswapV3Pool(pool).collect(
            receiver, 
            lowerTick, 
            upperTick, 
            type(uint128).max, 
            type(uint128).max
        );
    }

    /**
     * @notice Collects fees from a liquidity position and burns it if it has liquidity.
     * @param pool The address of the Uniswap V3 pool.
     * @param receiver The address that will receive the collected fees.
     * @param lowerTick The lower tick of the position.
     * @param upperTick The upper tick of the position.
     */
    function collect(
        address pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick
    ) internal {

        bytes32 positionId = keccak256(
            abi.encodePacked(
                address(this), 
                lowerTick, 
                upperTick
            )
        );

        (uint128 liquidity,,,,) = IUniswapV3Pool(pool).positions(positionId);

        if (liquidity > 0) {
            _burn(
                pool,
                receiver,
                lowerTick, 
                upperTick,
                liquidity
            );
        }
    }

    /**
    * @notice Executes an exact-input swap in a Uniswap V3 pool.
    * Uses a wide price limit (unless isLimitOrder) so full input can be consumed,
    * then enforces slippage via a post-swap minAmountOut check and a max-tick guard.
    */
    function swap(
        SwapParams memory params
    ) internal returns (int256 amount0, int256 amount1) {
        if (params.amountToSwap == 0) revert InvalidSwap();
        if (params.receiver == address(0)) revert InvalidSwap();

        // It's okay if minAmountOut is 0 for pure limit orders; otherwise recommend >0.
        if (!params.isLimitOrder && params.minAmountOut == 0) {
            revert SlippageExceeded();
        }

        uint160 priceLimit = 
            params.zeroForOne
            ? (TickMath.MIN_SQRT_RATIO + 1)
            : (TickMath.MAX_SQRT_RATIO - 1);

        // Wide price limit avoids early stop unless this is a true limit order.
        uint160 sqrtPriceLimitX96 = params.isLimitOrder
            ? (params.basePriceX96 > 0 ? params.basePriceX96 :  priceLimit)
            : priceLimit;

        try IUniswapV3Pool(params.poolAddress)
        .swap(
            params.receiver,
            params.zeroForOne,
            int256(params.amountToSwap), // exact input = positive
            sqrtPriceLimitX96,
            ""
        ) returns (int256 a0, int256 a1) {
            amount0 = a0;
            amount1 = a1;

            // Compute actual amountOut from pool deltas.
            uint256 amountOut;
            if (params.zeroForOne) {
                // pool sent token1 => a1 < 0, out = -a1
                if (a1 >= 0) revert NoTokensExchanged();
                amountOut = uint256(-a1);
            } else {
                // pool sent token0 => a0 < 0, out = -a0
                if (a0 >= 0) revert NoTokensExchanged();
                amountOut = uint256(-a0);
            }

            // Enforce slippage for market-style swaps
            if (!params.isLimitOrder && amountOut < params.minAmountOut) {
                revert SlippageExceeded();
            }

        } catch {
            revert InvalidSwap();
        }
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