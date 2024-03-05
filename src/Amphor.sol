// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Owned} from "solmate/auth/Owned.sol";

contract Amphor is Owned {

    // Protocol liquidity position
    struct LiquidityPosition {
        uint tokenId;
        address pool;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
        // uint32 secondsInsideSince;
        bool burned;
    }

    enum PositionType {
        FLOOR,
        ANCHOR,
        DISCOVERY
    }

    IUniswapV3Pool public pool;
    address public token0;

    bool public initialized;
    uint24 private poolFee;

    // base
    address public weth = 0x4200000000000000000000000000000000000006;
    // base
    address public positionManager = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    // base
    address public factoryAddress = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    mapping(PositionType => LiquidityPosition) public positions;

    /**
     * @dev Initializes the contract
     * @param _poolFee The fee of the pool (e.g. 10_000)
     */
    constructor(uint24 _poolFee) Owned(msg.sender) {
        poolFee = _poolFee;
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


    function initialLaunch(uint24 _lowerTick, uint24 _upperTick) external onlyOwner onlyInitialized {

        // Create a new position
        positions[PositionType.FLOOR] = LiquidityPosition({
            tokenId: 0,
            pool: address(pool),
            liquidity: 0,
            lowerTick: -887220,
            upperTick: -887200,
            // secondsInsideSince: 0,
            burned: false
        });

        // Create a new position
        positions[PositionType.ANCHOR] = LiquidityPosition({
            tokenId: 0,
            pool: address(pool),
            liquidity: 0,
            lowerTick: -887200,
            upperTick: -887180,
            // secondsInsideSince: 0,
            burned: false
        });

        // Create a new position
        positions[PositionType.DISCOVERY] = LiquidityPosition({
            tokenId: 0,
            pool: address(pool),
            liquidity: 0,
            lowerTick: -887180,
            upperTick: -887160,
            // secondsInsideSince: 0,
            burned: false
        });


    }


    modifier onlyInitialized() {
        require(initialized, "Positions: not initialized");
        _;
    }

}