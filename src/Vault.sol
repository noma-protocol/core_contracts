// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {Utils} from "./libraries/Utils.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {LiquidityHelper} from "./libraries/LiquidityHelper.sol";
import {Underlying} from "./libraries/Underlying.sol";

import {
    feeTier, 
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters
} from "./Types.sol";

contract Vault is Owned {

    LiquidityPosition public floorPosition;
    LiquidityPosition public anchorPosition;
    LiquidityPosition public discoveryPosition;

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
        require(_deployerContract != address(0), "invalid address");
        require(_deployerContract != address(this), "invalid address");
        require(_deployerContract != owner, "invalid address");

        deployerContract = _deployerContract;
    }

    /**
     * @notice Uniswap V3 callback function, called back on pool.mint
     */
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data)
        external
    {
        require(msg.sender == address(pool), "cc");

        uint256 token0Balance = ERC20(token0).balanceOf(address(this));
        uint256 token1Balance = ERC20(token1).balanceOf(address(this));

        (uint256 code, string memory message) = abi.decode(data, (uint256, string));

        if (token0Balance >= amount0Owed) {

            if (amount0Owed > 0) ERC20(token0).transfer(msg.sender, amount0Owed);
            
            if (code == 0 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                floorPosition.amount0LowerBound = amount0Owed;
            } else if (code == 1 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                anchorPosition.amount0LowerBound = amount0Owed;
            } else if (code == 2 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                discoveryPosition.amount0LowerBound = amount0Owed;
            }
        
        } 

        if (token1Balance >= amount1Owed) {

            if (amount1Owed > 0) ERC20(token1).transfer(msg.sender, amount1Owed);

            if (code == 0 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                floorPosition.amount1UpperBound = amount1Owed;
            } else if (code == 1 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                anchorPosition.amount1UpperBound = amount1Owed;
            } else if (code == 2 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                discoveryPosition.amount1UpperBound = amount1Owed;
            }      

        } 
    }

    function _shiftFloor(uint256 bips) internal {
        // require(initialized, "not initialized");

        LiquidityHelper
        .shiftFloor(
            pool, 
            address(this),
            floorPosition,
            token1, 
            bips, 
            tickSpacing
        );
    }

    function shift() public {
        // require(initialized, "not initialized");

        lastLiquidityRatio = LiquidityHelper
        .shift(
            pool,
            anchorPosition,
            lastLiquidityRatio
        );


    }    

    function collect(LiquidityType liquidityType) public {
        // require(initialized, "not initialized");
        LiquidityPosition memory position;

        if (liquidityType == LiquidityType.Floor) {
            position = floorPosition;
        } else if (liquidityType == LiquidityType.Anchor) {
            position = anchorPosition;
        } else if (liquidityType == LiquidityType.Discovery) {
            position = discoveryPosition;
        }
    
        LiquidityHelper.collect(
            pool, 
            address(this),
            position
        );
    }

    function getUnderlyingBalances(LiquidityType liquidityType) public 
    view 
    returns (uint256, uint256) {
        
        LiquidityPosition memory position;

        if (liquidityType == LiquidityType.Floor) {
            position = floorPosition;
        } else if (liquidityType == LiquidityType.Anchor) {
            position = anchorPosition;
        } else if (liquidityType == LiquidityType.Discovery) {
            position = discoveryPosition;
        }

        return Underlying.getUnderlyingBalances(pool, position);
    }

    function getLiquidityRatio() public view returns (uint256) {
        return LiquidityHelper.getLiquidityRatio(pool, anchorPosition);
    }

    function getToken0Balance() public view returns (uint256) {
        return ERC20(token0).balanceOf(address(this));
    }

    function getToken1Balance() public view returns (uint256) {
        return ERC20(token1).balanceOf(address(this));
    }
    
    function getFloorPrice() public view returns (uint256) {
        return floorPosition.price;
    }

}