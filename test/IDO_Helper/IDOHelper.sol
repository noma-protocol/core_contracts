

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Conversions} from "../../src/libraries/Conversions.sol";
import { BaseVault } from "../../src/vault/BaseVault.sol";

import {
    LiquidityPosition, 
    LiquidityType, 
    TokenInfo,
    SwapParams
} from "../../src/types/Types.sol";

import {Uniswap} from "../../src/libraries/Uniswap.sol";

contract IDOHelper {

    bool private initialized;

    IUniswapV3Pool public pool;
    BaseVault public vault;
    address public modelHelper;
    TokenInfo private  tokenInfo;

    int24 tickSpacing = 60;

    constructor(
        address _pool, 
        address _vault,
        address _modelHelper,
        address _token0,
        address _token1
    ) { 
        pool = IUniswapV3Pool(_pool);
        vault = BaseVault(_vault);
        modelHelper = _modelHelper;
        tokenInfo = TokenInfo({
            token0: _token0,
            token1: _token1
        });
    }

    // Test function
    function buyTokens(uint256 price, uint256 amount, uint256 minReceived, address receiver) public {
        uint8 decimals = ERC20(tokenInfo.token0).decimals();
        // Swap Params
        SwapParams memory swapParams = SwapParams({
            vaultAddress: address(0),
            poolAddress: address(pool),
            receiver: receiver,
            token0: tokenInfo.token0,
            token1: tokenInfo.token1,
            basePriceX96: Conversions.priceToSqrtPriceX96(
                int256(price), 
                tickSpacing, 
                decimals
            ),
            amountToSwap: amount,
            slippageTolerance: 100,
            zeroForOne: false,
            isLimitOrder: true,
            minAmountOut: minReceived
        });
        
        Uniswap.swap(
            swapParams
        );       
    }
 
    function sellTokens(uint256 price, uint256 amount, address receiver) public {
        uint8 decimals = ERC20(tokenInfo.token0).decimals();
        SwapParams memory swapParams = SwapParams({
            vaultAddress: address(0),
            poolAddress: address(pool),
            receiver: receiver,
            token0: tokenInfo.token0,
            token1: tokenInfo.token1,
            basePriceX96: Conversions.priceToSqrtPriceX96(
                int256(price), 
                tickSpacing, 
                decimals
            ),
            amountToSwap: amount,
            slippageTolerance: 100,
            zeroForOne: true,
            isLimitOrder: true,
            minAmountOut: 0
        });

        Uniswap.swap(
            swapParams
        );
        uint256 balanceAfter = ERC20(tokenInfo.token0).balanceOf(address(this));
        ERC20(tokenInfo.token0).transfer(receiver, balanceAfter);               
    }

    /**
     * @notice Uniswap v3 callback function, called back on pool.swap
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data )
        external
    {
        require(msg.sender == address(pool), "callback caller");

        if (amount0Delta > 0) {
            ERC20(tokenInfo.token0).transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(tokenInfo.token1).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    receive() external payable {

    }

}