// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {Utils} from "./libraries/Utils.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {LiquidityHelper} from "./libraries/LiquidityHelper.sol";

import {
    feeTier, 
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType, 
    DeployLiquidityParameters
} from "./Types.sol";

contract Deployer is Owned {

    LiquidityPosition public floorPosition;
    LiquidityPosition public anchorPosition;
    LiquidityPosition public discoveryPosition;

    address public token0;
    address public token1;
    IUniswapV3Pool public pool;

    bool initialized; 
    address vault;

    constructor(
        address _vault, 
        address _pool
    ) Owned(msg.sender) {
        pool = IUniswapV3Pool(_pool);
        token0 = pool.token0();
        token1 = pool.token1();
        vault = _vault;
        initialized = false;
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
        
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "insufficient token0 balance, owed: ", 
                        Utils._uint2str(amount0Owed)
                        )
                    )
                );
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

        } else {
            revert(
                string(
                    abi.encodePacked("insufficient token1 balance, owed: ", 
                    Utils._uint2str(amount1Owed)
                    )
                )
            );
        }
    }

    function deployFloor(uint256 _floorPrice) public /*onlyOwner*/ {
        // require(!initialized, "already initialized");  
        
        (LiquidityPosition memory newPosition,) = 
        LiquidityHelper.deployFloor(
            pool, 
            vault, 
            _floorPrice, 
            tickSpacing
        );

        floorPosition = newPosition;
    }

    function deployAnchor(uint256 bips, uint256 bipsBelowSpot) public /*onlyOwner*/ {
        // require(initialized, "not initialized");

        (LiquidityPosition memory newPosition,) = LiquidityHelper
        .deployAnchor(
            pool,
            vault,
            floorPosition,
            DeployLiquidityParameters({
                bips: bips,
                bipsBelowSpot: bipsBelowSpot,
                tickSpacing: tickSpacing
            })
        );

        anchorPosition = newPosition;

    }

    function deployDiscovery(uint256 bips) public /*onlyOwner*/{
        // require(initialized, "not initialized");

        (LiquidityPosition memory newPosition,) = LiquidityHelper
        .deployDiscovery(
            pool, 
            vault,
            floorPosition, 
            bips, 
            tickSpacing
        );

        discoveryPosition = newPosition;
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
            position
        );
    }


}