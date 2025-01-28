

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LiquidityType} from "../types/Types.sol";

error ZeroLiquidty();
error NoTokensExchanged();
error InvalidSwap();

library Uniswap {

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
        } else {
            revert ZeroLiquidty();
        }
    }

    function swap(
        address pool,
        address receiver,
        address token0,
        address token1,
        uint160 basePrice, 
        uint256 amountToSwap, 
        bool zeroForOne, 
        bool isLimitOrder
    ) internal {
        
        uint256 balanceBeforeSwap = IERC20Metadata(zeroForOne ? token1 : token0).balanceOf(receiver);
        uint160 slippagePrice = zeroForOne ? basePrice - (basePrice / 25) : basePrice + (basePrice / 25);

        try IUniswapV3Pool(pool).swap(
            receiver, 
            zeroForOne, 
            int256(amountToSwap), 
            isLimitOrder ? basePrice : slippagePrice,
            ""
        ) {
            uint256 balanceAfterSwap = IERC20Metadata(zeroForOne ? token1 : token0).balanceOf(receiver);
            if (balanceBeforeSwap == balanceAfterSwap) {
                revert NoTokensExchanged();
            }
        } catch {
            revert InvalidSwap();
        }
    }


}