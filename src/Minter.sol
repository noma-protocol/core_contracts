// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import '@uniswap/v3-core/libraries/FixedPoint96.sol';
import 'abdk/ABDKMath64x64.sol';

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
            revert(string(abi.encodePacked("insufficient token0 balance, owed: ", _uint2str(amount0Owed))));
        }

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) ERC20(token1).transfer(msg.sender, amount1Owed);
        } else {
            revert(string(abi.encodePacked("insufficient token1 balance, owed: ", _uint2str(amount1Owed))));
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

    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function toHexChar(uint8 byteValue) private pure returns (bytes memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(1);
        result[0] = alphabet[byteValue];
        return result;
    }

    function addressToString(address _address) public pure returns (string memory) {
        bytes32 _bytes = bytes32(uint256(uint160(_address)));
        bytes memory hexString = new bytes(42);
        hexString[0] = "0";
        hexString[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            uint8 byteValue = uint8(_bytes[i]);
            bytes memory stringValue = toHexChar(byteValue / 16);
            hexString[i * 2 + 2] = stringValue[0];
            stringValue = toHexChar(byteValue % 16);
            hexString[i * 2 + 3] = stringValue[0];
        }
        return string(hexString);
    }

}