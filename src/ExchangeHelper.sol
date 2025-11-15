// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
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

interface INomaFactory {
    function getVaultFromPool(address pool) external view returns (address);
}

interface IVault {
    function setReferralEntity(bytes8 code, uint256 amount) external;
}

contract ExchangeHelper {

    event BoughtTokensETH(address who, uint256 amount);
    event BoughtTokensWETH(address who, uint256 amount);
    event SoldTokensETH(address who, uint256 amount);
    event SoldTokensWETH(address who, uint256 amount);

    error NoETHSent();
    error NoToken0Received();
    error InvalidAmount();
    error InvalidSwap();

    // TokenInfo state variable
    TokenInfo public tokenInfo;

    address public WMON = address(0);
    address public nomaFactory = address(0);

    // Lock state variable to prevent reentrancy
    bool private locked;

    constructor(
        address nomaFactoryAddress, 
        address wrappedMonAddress
    ) {
        nomaFactory = nomaFactoryAddress;
        WMON = wrappedMonAddress;
    }

    function buyTokens(
        address vaultAddress,
        address pool, 
        uint256 price, 
        uint256 minAmount,
        address receiver,
        bool isLimitOrder,
        uint256 slippageTolerance,
        bytes8 referralCode
    ) public payable lock {

        if (msg.value <= 0) {
            revert NoETHSent();
        }

        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();

        // Set tokenInfo and poolAddress
        tokenInfo = TokenInfo({
            token0: IUniswapV3Pool(pool).token0(),
            token1: IUniswapV3Pool(pool).token1()
        });
        uint8 decimals = IERC20Metadata(tokenInfo.token0).decimals();

        // --- Record the initial WMON balance to avoid refunding extra ---
        uint256 initialWETHBalance = IWETH(WMON).balanceOf(address(this));

        // Deposit MON into WMON (this increases the balance by msg.value)
        IWETH(WMON).deposit{value: msg.value}();

        // Swap Params
        SwapParams memory swapParams = SwapParams({
            vaultAddress: vaultAddress,
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
            slippageTolerance: slippageTolerance,
            zeroForOne: false,
            isLimitOrder: isLimitOrder,
            minAmountOut: minAmount
        });
        
        // Perform the swap using the newly deposited WMON
        (int256 amount0, int256 amount1) = Uniswap
        .swap(
            swapParams
        );

        // Ensure the swap was successful and tokens were received.
        if (amount0 >= 0) {
            revert NoToken0Received();
        }

        uint256 refundAmount = IWETH(WMON).balanceOf(address(this)) - initialWETHBalance;
        
        if (refundAmount > 0) {
            // Withdraw the excess WMON into MON
            IWETH(WMON).withdraw(refundAmount);
            // Refund the caller with the excess MON
            payable(receiver).transfer(refundAmount);
        }

        // track referrals if a code is provided
        if (referralCode != bytes8(0)) {
            _trackReferralVolume(pool, referralCode, amount1);
        }

        emit BoughtTokensETH(receiver, SignedMath.abs(amount0));
    }

    // Requires approval for the token0 token
    function buyTokensWETH(
        address vaultAddress,
        address pool, 
        uint256 price, 
        uint256 amount, 
        uint256 minAmount,
        address receiver,
        bool isLimitOrder,
        uint256 slippageTolerance,
        bytes8 referralCode
    ) public lock {
        if (amount <= 0) {
            revert InvalidAmount();
        }

        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();

        tokenInfo = TokenInfo({
            token0: IUniswapV3Pool(pool).token0(),
            token1: IUniswapV3Pool(pool).token1()
        });    
        IERC20(tokenInfo.token1).transferFrom(msg.sender, address(this), amount);
        uint8 decimals = IERC20Metadata(tokenInfo.token1).decimals();

        // Swap Params
        SwapParams memory swapParams = SwapParams({
            vaultAddress: vaultAddress,
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
            slippageTolerance: slippageTolerance,
            zeroForOne: false,
            isLimitOrder: isLimitOrder,
            minAmountOut: minAmount
        });
        
        // Perform the swap using the newly deposited WMON
        (int256 amount0, int256 amount1) = Uniswap
        .swap(
            swapParams
        );       

        // Ensure the swap was successful and tokens were received.
        if (amount0 >= 0) {
            revert InvalidSwap();
        }
        
        // track referrals if a code is provided
        if (referralCode != bytes8(0)) {
            _trackReferralVolume(pool, referralCode, amount1);
        }

        emit  BoughtTokensWETH(receiver, SignedMath.abs(amount0));
    }
    
    function sellTokens(
        address vaultAddress,
        address pool, 
        uint256 price, 
        uint256 amount, 
        uint256 minAmount,
        address receiver,
        bool isLimitOrder,
        uint256 slippageTolerance,
        bytes8 referralCode
    ) public lock {
        if (amount <= 0) {
            revert InvalidAmount();
        }

        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();

        tokenInfo = TokenInfo({
            token0: IUniswapV3Pool(pool).token0(),
            token1: IUniswapV3Pool(pool).token1()
        });    
        address token0 = tokenInfo.token0;
        IERC20(tokenInfo.token0).transferFrom(msg.sender, address(this), amount);

        // Swap Params
        SwapParams memory swapParams = SwapParams({
            vaultAddress: vaultAddress,
            poolAddress: address(pool),
            receiver: receiver,
            token0: tokenInfo.token0,
            token1: tokenInfo.token1,
            basePriceX96: Conversions
            .priceToSqrtPriceX96(
                int256(price), 
                tickSpacing, 
                IERC20Metadata(tokenInfo.token0).decimals()
            ),
            amountToSwap: amount,
            slippageTolerance: slippageTolerance,
            zeroForOne: true,
            isLimitOrder: isLimitOrder,
            minAmountOut: minAmount
        });
            
        // Perform the swap
        (int256 amount0, int256 amount1) = Uniswap.swap(swapParams);
        if (amount1 >= 0) {
            revert InvalidSwap();
        }
        

        uint256 refund = IERC20Metadata(token0).balanceOf(address(this)) > (amount - uint256(amount0)) ?
            amount - uint256(amount0) :
            IERC20Metadata(token0).balanceOf(address(this));  

        if (refund > 0) {
            IERC20(token0).transfer(msg.sender, refund);
        }

        // track referrals if a code is provided
        if (referralCode != bytes8(0)) {
            _trackReferralVolume(pool, referralCode, amount1);
        }

        emit SoldTokensETH(receiver, SignedMath.abs(amount1));
    }

    function sellTokensETH(
        address vaultAddress,
        address pool, 
        uint256 price, 
        uint256 amount, 
        uint256 minAmount,
        address receiver,
        bool isLimitOrder,
        uint256 slippageTolerance,
        bytes8 referralCode
    ) public lock {
        require(amount > 0, "ExchangeHelper: Amount must be greater than 0");
        
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();

        tokenInfo = TokenInfo({
            token0: IUniswapV3Pool(pool).token0(),
            token1: IUniswapV3Pool(pool).token1()
        });    
        IERC20(tokenInfo.token0).transferFrom(msg.sender, address(this), amount);

        // Swap Params
        SwapParams memory swapParams = SwapParams({
            vaultAddress: vaultAddress,
            poolAddress: address(pool),
            receiver: address(this),
            token0: tokenInfo.token0,
            token1: tokenInfo.token1,
            basePriceX96: Conversions
            .priceToSqrtPriceX96(
                int256(price), 
                tickSpacing, 
                IERC20Metadata(tokenInfo.token0).decimals()
            ),
            amountToSwap: amount,
            slippageTolerance: slippageTolerance,
            zeroForOne: true,
            isLimitOrder: isLimitOrder,
            minAmountOut: minAmount
        });
            
        // Perform the swap
        (int256 amount0, int256 amount1) = Uniswap.swap(swapParams);
        require(amount1 < 0, "ExchangeHelper: Invalid swap");
        
        uint256 ethReceived = uint256(-amount1);
        IWETH(WMON).withdraw(ethReceived);
        payable(receiver).transfer(ethReceived);

        // uint256 refund = IERC20Metadata(tokenInfo.token0).balanceOf(address(this)) > (amount - uint256(amount0)) ?
        //     amount - uint256(amount0) :
        //     IERC20Metadata(tokenInfo.token0).balanceOf(address(this));  

        // if (refund > 0) {
        //     IERC20(tokenInfo.token0).transfer(msg.sender, refund);
        // }

        // track referrals if a code is provided
        if (referralCode != bytes8(0)) {
            _trackReferralVolume(pool, referralCode, amount1);
        }

        emit SoldTokensETH(receiver, SignedMath.abs(amount1));
    }

    // Function to record referral usage
    function _trackReferralVolume(address poolAddress, bytes8 code, int256 amount) internal {
        address vault = INomaFactory(nomaFactory).getVaultFromPool(poolAddress);
        if (vault != address(0)) {
            IVault(vault).setReferralEntity(code, uint256(SignedMath.abs(amount)));
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
        address vault = INomaFactory(nomaFactory).getVaultFromPool(msg.sender);
        if (vault == address(0)) {
            revert InvalidSwap();
        }

        if (amount0Delta > 0) {
            IERC20(tokenInfo.token0).transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(tokenInfo.token1).transfer(msg.sender, uint256(amount1Delta));
        }

        // Reset token info 
        tokenInfo = TokenInfo({
            token0: address(0),
            token1: address(0)
        });
    }

    /**
    * @notice PancakeSwap v3 callback function, called back on pool.swap
    */
    function pancakeV3SwapCallback(
        int256 amount0Delta, 
        int256 amount1Delta, 
        bytes calldata data
    ) external {
        address vault = INomaFactory(nomaFactory).getVaultFromPool(msg.sender);
        if (vault == address(0)) {
            revert InvalidSwap();
        }

        if (amount0Delta > 0) {
            IERC20(tokenInfo.token0).transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(tokenInfo.token1).transfer(msg.sender, uint256(amount1Delta));
        }

        // Reset token info 
        tokenInfo = TokenInfo({
            token0: address(0),
            token1: address(0)
        });
    }

    // Modifier to prevent reentrancy
    modifier lock() {
        require(!locked, "ExchangeHelper: Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    receive() external payable {}
}