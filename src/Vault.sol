// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {Utils} from "./libraries/Utils.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {LiquidityHelper} from "./libraries/LiquidityHelper.sol";
import {Underlying} from "./libraries/Underlying.sol";

import {Conversions} from "./libraries/Conversions.sol";
import {ModelHelper} from "./libraries/ModelHelper.sol";

import {
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType
} from "./Types.sol";

contract Vault is Owned {

    LiquidityPosition private floorPosition;
    LiquidityPosition private anchorPosition;
    LiquidityPosition private discoveryPosition;

    address public token0;
    address public token1;
    address public deployerContract;

    IUniswapV3Pool public pool;

    bool initialized; 
    uint256 lastLiquidityRatio;

    constructor(address _pool) Owned(msg.sender) {
        pool = IUniswapV3Pool(_pool);
        token0 = pool.token0();
        token1 = pool.token1();
        initialized = false;
        lastLiquidityRatio = 0;
    }

    function initialize(
        LiquidityPosition memory _floorPosition,
        LiquidityPosition memory _anchorPosition,
        LiquidityPosition memory _discoveryPosition
    ) public {
        require(!initialized, "already initialized");
        require(msg.sender == deployerContract, "invalid caller");

        floorPosition = _floorPosition;
        anchorPosition = _anchorPosition;
        discoveryPosition = _discoveryPosition;

        initialized = true;
    }

    function setDeployer(address _deployerContract) public /*onlyOwner*/ {
        require(!initialized, "already initialized");

        deployerContract = _deployerContract;
    }

    /**
     * @notice Uniswap V3 callback function, called back on pool.mint
     */
    function uniswapV3MintCallback(
        uint256 amount0Owed, 
        uint256 amount1Owed, 
        bytes calldata data
    )
        external
    {
        require(msg.sender == address(pool), "cc");

        uint256 token0Balance = ERC20(token0).balanceOf(address(this));
        uint256 token1Balance = ERC20(token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) ERC20(token0).transfer(msg.sender, amount0Owed);
        } 

        if (token1Balance >= amount1Owed) {
            if (amount1Owed > 0) ERC20(token1).transfer(msg.sender, amount1Owed); 
        } 
    }

    function shift() public {
        // require(initialized, "not initialized");
        
        LiquidityPosition[] memory positions = new LiquidityPosition[](3);
        positions[0] = floorPosition;
        positions[1] = anchorPosition;
        positions[2] = discoveryPosition;

        (
            uint256 currentLiquidityRatio, 
            LiquidityPosition memory newPosition
        ) = LiquidityHelper
        .shift(
            address(pool),
            positions,
            LiquidityType.Anchor
        );

        lastLiquidityRatio = currentLiquidityRatio;
        anchorPosition = newPosition;

        // Emit event
    }    

    function getUnderlyingBalances(LiquidityType liquidityType) public 
    view 
    returns (int24, int24, uint256, uint256) {

        LiquidityPosition memory position;

        if (liquidityType == LiquidityType.Floor) {
            position = floorPosition;
        } else if (liquidityType == LiquidityType.Anchor) {
            position = anchorPosition;
        } else if (liquidityType == LiquidityType.Discovery) {
            position = discoveryPosition;
        }

        return Underlying.getUnderlyingBalances(address(pool), position);
    }

    function getVaultInfo() public view returns (uint256, uint256, uint256, uint256, uint256) {
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();

        return (
            ModelHelper.getLiquidityRatio(address(pool), anchorPosition),
            ModelHelper.getCirculatingSupply(address(pool), anchorPosition, discoveryPosition),
            Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18),
            ModelHelper.getPositionCapacity(address(pool), anchorPosition),
            ModelHelper.getPositionCapacity(address(pool), floorPosition)
        );
    }
    
}