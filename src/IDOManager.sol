

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
import '@uniswap/v3-core/libraries/TickMath.sol';

import {Conversions} from "./libraries/Conversions.sol";
import {Utils} from "./libraries/Utils.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

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

    uint256 IDOPrice;

    uint24 feeTier = 3000;
    int24 tickSpacing = 60;

    int24 IDOLowerTick;
    int24 IDOUpperTick;

    int24 FloorLowerTick;
    int24 FloorUpperTick;

    struct LiquidityPosition {
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
    }
    
    LiquidityPosition[] public discoveryPositions;
    
    constructor(address _uniswapFactory, address _token1) Owned(msg.sender) { 
        amphorToken = new AmphorToken(address(this), totalSupplyAmphor);
        uniswapFactory = _uniswapFactory;
        token0 = address(amphorToken);
        token1 = _token1;
    }

    function initialize(uint160 _IDOPriceX96, uint256 _IDOPrice) public onlyOwner {
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
                _IDOPriceX96
            );
        } 

        minter = new Minter(address(pool), address(this));

        // transfter WETH to buy IDO
        IWETH(token1).transfer(address(minter), 100 ether);

        IDOPrice = _IDOPrice;
        initialized = true;
    }

    function createIDO() public onlyOwner {
        require(initialized, "not initialized");

        amphorToken.transfer(address(minter), launchSupply);

        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (int24 lowerTick, int24 upperTick) = Conversions.computeSingleTick(IDOPrice, tickSpacing);

        uint256 amount0Max = launchSupply;
        uint256 amount1Max = 0;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        if (liquidity > 0) {
            minter.mint(lowerTick, upperTick, liquidity);
            IDOLowerTick = lowerTick;
            IDOUpperTick = upperTick;
        } else {
            revert("createIDO: liquidity is 0");
        }
    }

    function buyIDO(uint256 price) public {
        minter.swap(
            Conversions.priceToSqrtPriceX96(int256(price), tickSpacing),
            100e18,
            false,
            false
        );        
    }

    function collectWETH() public {

        uint256 balanceBeforeSwap = ERC20(token1).balanceOf(address(this));

        bytes32 IDOPositionId = keccak256(
            abi.encodePacked(
                address(minter), 
                IDOLowerTick, 
                IDOUpperTick
            )
        );

        (uint128 liquidity,,,,) = pool.positions(IDOPositionId);

        if (liquidity > 0) {
            minter.burn(
                IDOLowerTick,
                IDOUpperTick,
                liquidity
            );
        } else {
            revert("collectWETH: liquidity is 0");
        }

        uint256 balanceAfterSwap = ERC20(token1).balanceOf(address(this));
        require(balanceAfterSwap > balanceBeforeSwap, "no tokens exchanged");
    }

    function buildFloor(uint256 floorPrice) public {

        uint256 balanceToken1 = ERC20(token1).balanceOf(address(this));

        IWETH(token1).transfer(address(minter), balanceToken1);
        
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (int24 lowerTick, int24 upperTick) = Conversions.computeSingleTick(floorPrice, tickSpacing);

        uint256 amount0Max = 0;
        uint256 amount1Max = balanceToken1;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        if (liquidity > 0) {
            minter.mint(lowerTick, upperTick, liquidity);
            FloorLowerTick = lowerTick;
            FloorUpperTick = upperTick;
        } else {
            revert(string(abi.encodePacked("buildFloor: liquidity is 0  ", Utils._uint2str(uint256(sqrtRatioX96))))); 
        }

    }

    function sellToFloor(uint256 price, uint256 amount) public {
        ERC20(token0).transfer(address(minter), amount);

        minter.swap(
            Conversions.priceToSqrtPriceX96(int256(price), tickSpacing),
            amount,
            true,
            false
        );        
    }

    function shiftFloor(uint256 newFloorPrice) public onlyOwner {
        int24 newFloorLowerTick = Conversions.priceToTick(int256(newFloorPrice), tickSpacing);

        require(newFloorLowerTick > FloorLowerTick, "invalid floor");

        bytes32 floorPositionId = keccak256(abi.encodePacked(address(minter), FloorLowerTick, FloorUpperTick));
        (uint128 liquidity,,,,) = pool.positions(floorPositionId);

        if (liquidity > 0) {
            minter.burn(
                FloorLowerTick,
                FloorUpperTick,
                liquidity
            );
        } else {
            revert("shiftFloor: liquidity is 0");
        }

        uint256 balanceAfterShiftFloorToken1 = ERC20(token1).balanceOf(address(this));

        IWETH(token1).transfer(address(minter), balanceAfterShiftFloorToken1);
        
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (, int24 newFloorUpperTick) = Conversions.computeSingleTick(newFloorPrice, tickSpacing);

        uint256 amount0Max = 0;
        uint256 amount1Max = balanceAfterShiftFloorToken1;

        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(newFloorLowerTick),
            TickMath.getSqrtRatioAtTick(newFloorUpperTick),
            amount0Max,
            amount1Max
        );

        if (newLiquidity > 0) {
            minter.mint(newFloorLowerTick, newFloorUpperTick, liquidity);
            FloorLowerTick = newFloorLowerTick;
            FloorUpperTick = newFloorUpperTick;
        } else {
            revert(string(abi.encodePacked("shiftFloor: liquidity is 0  ", Utils._uint2str(uint256(sqrtRatioX96))))); 
        }
    }
 
    
    receive() external payable {
        IWETH(token1).deposit{value: msg.value}();
    }

}