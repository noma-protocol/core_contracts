

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {LiquidityType} from "../Types.sol";

library Uniswap {

    function mint(
        IUniswapV3Pool pool,
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

       pool.mint(receiver, lowerTick, upperTick, liquidity, data);
    }

    function burn(
        IUniswapV3Pool pool,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity        
    ) internal {

        (uint256 burn0, uint256 burn1) =
            pool.burn(lowerTick, upperTick, liquidity);

        pool.collect(
            address(this), 
            lowerTick, 
            upperTick, 
            type(uint128).max, 
            type(uint128).max
        );
    }

    function swap(
        IUniswapV3Pool pool,
        address token0,
        address token1,
        uint160 basePrice, 
        uint256 amountToSwap, 
        bool zeroForOne, 
        bool isLimitOrder
    ) internal {
        
        uint256 balanceBeforeSwap = ERC20(zeroForOne ? token1 : token0).balanceOf(address(this));
        uint160 slippagePrice = zeroForOne ? basePrice - (basePrice / 25) : basePrice + (basePrice / 25);

        try pool.swap(
            address(this), 
            zeroForOne, 
            int256(amountToSwap), 
            isLimitOrder ? basePrice : slippagePrice,
            ""
        ) {
            uint256 balanceAfterSwap = ERC20(zeroForOne ? token1 : token0).balanceOf(address(this));
            if (balanceBeforeSwap == balanceAfterSwap) {
                revert("no tokens exchanged");
            }
        } catch {
            revert("Error swapping tokens");
        }
    }


}