

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {Minter} from "../src/Minter.sol";
import {AmphorToken} from "../src/token/AmphorToken.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import 'abdk/ABDKMath64x64.sol';

import "../src/libraries/Conversions.sol";


contract IDOManager is Owned {

    bool public initialized;
    
    AmphorToken public amphorToken;
    Minter public minter;
    IUniswapV3Pool public pool;

    uint256 totalSupplyAmphor = 1_000_000e18;
    uint256 launchSupply = (totalSupplyAmphor * 40) / 100;

    address public token0;
    address public token1;
    address public uniswapFactory;

    uint32 IDOPrice;

    uint24 feeTier = 3000;

    constructor(address _uniswapFactory, address _token0) Owned(msg.sender) { 
        amphorToken = new AmphorToken(address(this), totalSupplyAmphor);
        token0 = _token0;
        uniswapFactory = _uniswapFactory;
        token1 = address(amphorToken);
    }

    function init(uint160 _IDOPriceX96, uint32 _IDOPrice) public onlyOwner {
        require(!initialized, "already initialized");

        IUniswapV3Factory factory = IUniswapV3Factory(uniswapFactory);
        pool = IUniswapV3Pool(
            factory.getPool(token0, token1, feeTier)
        );

        if (address(pool) == address(0)) {
            pool = IUniswapV3Pool(
                factory.createPool(token0, token1, feeTier)
            );
            IUniswapV3Pool(pool)
            .initialize(
                // IDO price (1500000 Amphor/WETH) 97034285709077923348982791886170
                _IDOPriceX96
            );
        } 

        IDOPrice = _IDOPrice;
        minter = new Minter(address(pool));

        initialized = true;
    }

    function createIDO() public onlyOwner {
        require(initialized, "not initialized");

        amphorToken.transfer(address(minter), launchSupply);

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        (int24 lowerTick, int24 upperTick) = Conversions.computeSingleTick(750000e18, 60);

        uint256 amount0Max = 0;
        uint256 amount1Max = launchSupply;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        if (liquidity > 0) {
            minter.mint(lowerTick, upperTick, liquidity);
        } 
    }



}