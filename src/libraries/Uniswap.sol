// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LiquidityType, SwapParams} from "../types/Types.sol";
import {Conversions} from "./Conversions.sol";

// Custom errors
error ZeroLiquidty();
error NoTokensExchanged();
error InvalidSwap();

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
        else {
            revert ZeroLiquidty();
        }
    }

    /**
     * @notice Executes a swap in a Uniswap V3 pool.
     */
    function swap(
        SwapParams memory params
    ) internal returns (int256 amount0, int256 amount1) {
        uint256 balanceBeforeSwap = IERC20Metadata(params.zeroForOne ? params.token1 : params.token0).balanceOf(params.receiver);
        // immutables
        int24  tickSpacing   = IUniswapV3Pool(params.poolAddress).tickSpacing(); 
        // Convert basePriceX96 before slippage calculation
        uint256 basePrice = Conversions.sqrtPriceX96ToPrice(params.basePriceX96, IERC20Metadata(params.zeroForOne ? params.token1 : params.token0).decimals());
        uint160 slippagePrice = Conversions.priceToSqrtPriceX96(
            int256(params.zeroForOne ? basePrice - (basePrice * 5 / 100) : basePrice + (basePrice * 5 / 100)), 
            tickSpacing, 
            IERC20Metadata(params.zeroForOne ? params.token1 : params.token0).decimals()
        );

        try IUniswapV3Pool(params.poolAddress).swap(
            params.receiver, 
            params.zeroForOne, 
            int256(params.amountToSwap), 
            params.isLimitOrder ? params.basePriceX96 : slippagePrice,
            ""
        ) returns (int256 _amount0, int256 _amount1) {
            // Capture the return values
            amount0 = _amount0;
            amount1 = _amount1;

            // Check if tokens were exchanged
            uint256 balanceAfterSwap = IERC20Metadata(params.zeroForOne ? params.token1 : params.token0).balanceOf(params.receiver);
            if (balanceBeforeSwap == balanceAfterSwap) {
                revert NoTokensExchanged();
            }
        } catch {
            revert InvalidSwap();
        }
    }
}