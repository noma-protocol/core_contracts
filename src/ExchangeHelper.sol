// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {Uniswap} from "../src/libraries/Uniswap.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {
    TokenInfo,
    SwapParams
} from "../src/types/Types.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address owner) external returns (uint256);
}

contract ExchangeHelper {

    int24 public constant tickSpacing = 60;

    // TokenInfo state variable
    TokenInfo public tokenInfo;
    address public poolAddress;

    address public WBNB = 0xB3D148caE2d57433e5e2279d3567efA6bA0892c8;

    // Lock state variable to prevent reentrancy
    bool private locked;

    // Modifier to prevent reentrancy
    modifier lock() {
        require(!locked, "ExchangeHelper: Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    constructor() {}

    function buyTokens(
        address pool, 
        uint256 price, 
        uint256 amount, 
        address receiver,
        bool isLimitOrder
    ) public payable lock {
        require(msg.value > 0, "ExchangeHelper: No ETH sent");

        // Set tokenInfo and poolAddress
        tokenInfo = TokenInfo({
            token0: IUniswapV3Pool(pool).token0(),
            token1: IUniswapV3Pool(pool).token1()
        });
        poolAddress = pool;
        uint8 decimals = IERC20Metadata(tokenInfo.token0).decimals();

        // --- Record the initial WBNB balance to avoid refunding extra ---
        uint256 initialWETHBalance = IWETH(WBNB).balanceOf(address(this));

        // Deposit ETH into WBNB (this increases the balance by msg.value)
        IWETH(WBNB).deposit{value: msg.value}();

        // Swap Params
        SwapParams memory swapParams = SwapParams({
            poolAddress: address(pool),
            receiver: receiver,
            token0: tokenInfo.token0,
            token1: tokenInfo.token1,
            basePriceX96: Conversions
            .priceToSqrtPriceX96(
                int256(price), 
                tickSpacing, 
                decimals
            ),
            amountToSwap: msg.value,
            zeroForOne: false,
            isLimitOrder: isLimitOrder
        });
        
        // Perform the swap using the newly deposited WBNB
        (int256 amount0, int256 amount1) = Uniswap
        .swap(
            swapParams
        );


        // Ensure the swap was successful and tokens were received.
        // (amount0 should be negative, meaning token0 was sold)
        require(amount0 < 0, "ExchangeHelper: No token0 received");
        // uint256 tokensReceived = uint256(-amount0);

        uint256 refundAmount = IWETH(WBNB).balanceOf(address(this)) - initialWETHBalance;
        
        if (refundAmount > 0) {
            // Withdraw the excess WBNB into ETH
            IWETH(WBNB).withdraw(refundAmount);
            // Refund the caller with the excess ETH
            payable(receiver).transfer(refundAmount);
        }
    }

    // Requires approval for the token0 token
    function buyTokensWETH(
        address pool, 
        uint256 price, 
        uint256 amount, 
        address receiver,
        bool isLimitOrder
    ) public lock {
        require(amount > 0, "ExchangeHelper: Amount must be greater than 0");
        tokenInfo = TokenInfo({
            token0: IUniswapV3Pool(pool).token0(),
            token1: IUniswapV3Pool(pool).token1()
        });    
        poolAddress = pool;    
        IERC20(tokenInfo.token1).transferFrom(msg.sender, address(this), amount);
        uint8 decimals = IERC20Metadata(tokenInfo.token1).decimals();

        // track balance of WBNB before swap
        uint256 initialWETHBalance = IWETH(WBNB).balanceOf(address(this));

        // Swap Params
        SwapParams memory swapParams = SwapParams({
            poolAddress: address(pool),
            receiver: receiver,
            token0: tokenInfo.token0,
            token1: tokenInfo.token1,
            basePriceX96: Conversions
            .priceToSqrtPriceX96(
                int256(price), 
                tickSpacing, 
                decimals
            ),
            amountToSwap: amount,
            zeroForOne: false,
            isLimitOrder: isLimitOrder
        });
        
        // Perform the swap using the newly deposited WBNB
        (int256 amount0, ) = Uniswap
        .swap(
            swapParams
        );       

        // Ensure the swap was successful and tokens were received.
        require(amount0 < 0, "ExchangeHelper: Invalid swap");

    }
    
    function sellTokens(
        address pool, 
        uint256 price, 
        uint256 amount, 
        address receiver,
        bool isLimitOrder
    ) public lock {
        require(amount > 0, "ExchangeHelper: Amount must be greater than 0");
        tokenInfo = TokenInfo({
            token0: IUniswapV3Pool(pool).token0(),
            token1: IUniswapV3Pool(pool).token1()
        });    
        poolAddress = pool;    
        address token0 = tokenInfo.token0;
        IERC20(tokenInfo.token0).transferFrom(msg.sender, address(this), amount);
        uint8 decimals = IERC20Metadata(tokenInfo.token0).decimals();

        // Swap Params
        SwapParams memory swapParams = SwapParams({
            poolAddress: address(pool),
            receiver: receiver,
            token0: tokenInfo.token0,
            token1: tokenInfo.token1,
            basePriceX96: Conversions
            .priceToSqrtPriceX96(
                int256(price), 
                tickSpacing, 
                decimals
            ),
            amountToSwap: amount,
            zeroForOne: true,
            isLimitOrder: isLimitOrder
        });
            
        // Perform the swap
        (int256 amount0, int256 amount1) = Uniswap.swap(swapParams);
        require(amount1 < 0, "ExchangeHelper: Invalid swap");
        
        uint256 balanceAfterSwap = IERC20Metadata(token0).balanceOf(address(this));

        uint256 refund = balanceAfterSwap > (amount - uint256(amount0)) ?
            amount - uint256(amount0) :
            balanceAfterSwap;  

        if (refund > 0) {
            IERC20(token0).transfer(msg.sender, refund);
        }
    }

    function sellTokensETH(
        address pool, 
        uint256 price, 
        uint256 amount, 
        address receiver,
        bool isLimitOrder
    ) public lock {
        require(amount > 0, "ExchangeHelper: Amount must be greater than 0");
        tokenInfo = TokenInfo({
            token0: IUniswapV3Pool(pool).token0(),
            token1: IUniswapV3Pool(pool).token1()
        });    
        poolAddress = pool;    
        address token0 = tokenInfo.token0;
        IERC20(tokenInfo.token0).transferFrom(msg.sender, address(this), amount);
        uint8 decimals = IERC20Metadata(tokenInfo.token0).decimals();

        // Swap Params
        SwapParams memory swapParams = SwapParams({
            poolAddress: address(pool),
            receiver: address(this),
            token0: tokenInfo.token0,
            token1: tokenInfo.token1,
            basePriceX96: Conversions
            .priceToSqrtPriceX96(
                int256(price), 
                tickSpacing, 
                decimals
            ),
            amountToSwap: amount,
            zeroForOne: true,
            isLimitOrder: isLimitOrder
        });
            
        // Perform the swap
        (int256 amount0, int256 amount1) = Uniswap.swap(swapParams);
        require(amount1 < 0, "ExchangeHelper: Invalid swap");
        
        uint256 bnbReceived = uint256(-amount1);
        IWETH(WBNB).withdraw(bnbReceived);
        payable(receiver).transfer(bnbReceived);

        uint256 balanceAfterSwap = IERC20Metadata(token0).balanceOf(address(this));

        uint256 refund = balanceAfterSwap > (amount - uint256(amount0)) ?
            amount - uint256(amount0) :
            balanceAfterSwap;  

        if (refund > 0) {
            IERC20(token0).transfer(msg.sender, refund);
        }
    }


        /**
         * @notice Uniswap v3 callback function, called back on pool.swap
         */
    function uniswapV3SwapCallback(
        int256 amount0Delta, 
        int256 amount1Delta, 
        bytes calldata data
    ) external {
        require(msg.sender == poolAddress, "ExchangeHelper: Callback caller not pool");

        if (amount0Delta > 0) {
            IERC20(tokenInfo.token0).transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(tokenInfo.token1).transfer(msg.sender, uint256(amount1Delta));
        }

        // Reset token info and pool address
        tokenInfo = TokenInfo({
            token0: address(0),
            token1: address(0)
        });
        poolAddress = address(0);
    }

    receive() external payable {}
}