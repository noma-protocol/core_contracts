// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import '@uniswap/v3-core/libraries/FixedPoint96.sol';
import 'abdk/ABDKMath64x64.sol';

import {Utils} from "./libraries/Utils.sol";

contract Minter is Owned {

    bool public initialized;

    address public pool;
    address public minter;

    address public token0 = address(0);
    address public token1 = address(0);

    uint160 public sqrtPriceX96;

    constructor(address _pool, address _minter) Owned(msg.sender) {
        pool = _pool;
        minter = _minter;
        token0 = IUniswapV3Pool(_pool).token0();
        token1 = IUniswapV3Pool(_pool).token1();
    }

    /**
     * @notice Uniswap V3 callback function, called back on pool.mint
     */
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata _data)
        external
    {
        require(msg.sender == pool, "callback caller");

        uint256 token0Balance = ERC20(token0).balanceOf(address(this));
        uint256 token1Balance = ERC20(token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) ERC20(token0).transfer(msg.sender, amount0Owed);
        } else {
            revert(string(abi.encodePacked("insufficient token0 balance, owed: ", Utils._uint2str(amount0Owed))));
        }

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) ERC20(token1).transfer(msg.sender, amount1Owed);
        } else {
            revert(string(abi.encodePacked("insufficient token1 balance, owed: ", Utils._uint2str(amount1Owed))));
        }
    }

    /**
     * @notice Uniswap v3 callback function, called back on pool.swap
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data )
        external
    {
        require(msg.sender == pool, "callback caller");

        if (amount0Delta > 0) {
           ERC20(token0).transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(token1).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    function mint(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    )
        public
    {
        IUniswapV3Pool(pool).mint(address(this), lowerTick, upperTick, liquidity, "");
    }

    function burn(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity        
    ) public {
        uint256 preBalance0 = ERC20(token0).balanceOf(address(this));
        uint256 preBalance1 = ERC20(token1).balanceOf(address(this));

        (uint256 burn0, uint256 burn1) =
            IUniswapV3Pool(pool).burn(lowerTick, upperTick, liquidity);

        IUniswapV3Pool(pool).collect(
            address(this), 
            lowerTick, 
            upperTick, 
            type(uint128).max, 
            type(uint128).max
        );

        uint256 fee0 = ERC20(token0).balanceOf(address(this)) - preBalance0 - burn0;
        uint256 fee1 = ERC20(token1).balanceOf(address(this)) - preBalance1 - burn1;    

        ERC20(token0).transfer(minter, ERC20(token0).balanceOf(address(this)));
        ERC20(token1).transfer(minter, ERC20(token1).balanceOf(address(this)));    
    }


    function swap(uint160 basePrice, uint256 amountToSwap, bool zeroForOne, bool isLimitOrder) public {
        
        uint256 balanceBeforeSwap = ERC20(zeroForOne ? token1 : token0).balanceOf(address(this));
        uint160 slippagePrice = zeroForOne ? basePrice - (basePrice / 25) : basePrice + (basePrice / 25);

        try IUniswapV3Pool(pool).swap(
            address(this), 
            zeroForOne, 
            int256(amountToSwap), 
            isLimitOrder ? basePrice : slippagePrice,
            ""
        ) {
            uint256 balanceAfterSwap = ERC20(zeroForOne ? token1 : token0).balanceOf(address(this));
            if (balanceBeforeSwap == balanceAfterSwap) {
                revert("no tokens exchanged");
            } else {
                // revert("tokens exchanged");
            }
        } catch {
            revert("Error swapping tokens");
        }

        ERC20(zeroForOne ? token0 : token1).transfer(minter, ERC20(zeroForOne ? token0 : token1).balanceOf(address(this)));
    }

 
}