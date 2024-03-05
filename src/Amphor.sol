// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Owned} from "solmate/auth/Owned.sol";

contract Positions is Owned {

    IUniswapV3Pool public pool;
    address public token0;

    bool public initialized;
    uint24 private poolFee = 10_000;

    // base
    address public weth = 0x4200000000000000000000000000000000000006;
    // base
    address public positionManager = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    // base
    address public factoryAddress = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    constructor() Owned(msg.sender) {

    }

    function initialize(address amphorToken) external  {

        // Creates a new pool if it doesn't exist and initializes contract variables
        if (!initialized && address(pool) == address(0)) {
            IUniswapV3Factory factory = IUniswapV3Factory(factoryAddress);
            pool = IUniswapV3Pool(factory.getPool(weth, amphorToken, poolFee));
            ERC20(amphorToken).approve(address(pool), type(uint256).max);
            WETH(payable(weth)).approve(address(pool), type(uint256).max);
            require(address(pool) != address(0));
            token0 = pool.token0();
            initialized = true;
        }
    }


    modifier onlyInitialized() {
        require(initialized, "Positions: not initialized");
        _;
    }

}