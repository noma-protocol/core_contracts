// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {
    tickSpacing, 
    LiquidityPosition, 
    LiquidityType,
    VaultInfo,
    ProtocolAddresses
} from "./Types.sol";

import {Owned} from "solmate/auth/Owned.sol";

contract VaultController is Owned {

    IUniswapV3Pool public pool;
    
    constructor(address _pool, address _modelHelper) Owned(msg.sender) {
        pool = IUniswapV3Pool(_pool);
    }
    
    function shift(ProtocolAddresses parameters, address vault) public {
        require(initialized, "not initialized");
        
        LiquidityPosition[3] memory positions = _getPositions();
      
        (
            uint256 currentLiquidityRatio,
            LiquidityPosition[3] memory newPositions
        ) = LiquidityOps
        .shift(
            ProtocolAddresses({
                pool: address(pool),
                vault: vault,
                deployer: deployerContract,
                modelHelper: modelHelper
            }),
            positions
        );

        floorPosition = newPositions[0];

        // Emit event
        emit FloorUpdated(
            0, 
            IModelHelper(modelHelper)
            .getPositionCapacity(
                address(pool), 
                vault,
                floorPosition
            )
        );
    }    

    function slide() external  {
        require(initialized, "not initialized");

        LiquidityPosition[3] memory positions = _getPositions();

        (
            LiquidityPosition[3] memory newPositions
        ) = LiquidityOps
        .slide(
            ProtocolAddresses({
                pool: address(pool),
                vault: address(this),
                deployer: deployerContract,
                modelHelper: modelHelper
            }),
            positions
        );

        // Emit event
    }
}