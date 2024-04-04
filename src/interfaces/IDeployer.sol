// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    LiquidityPosition,
    AmountsToMint,
    LiquidityType
} from "../Types.sol";

interface IDeployer {
    function deployFloor(uint256 _floorPrice) external;
    function shiftFloor(
        address pool,
        address receiver,
        uint256 currentFloorPrice,
        uint256 newFloorPrice,
        LiquidityPosition memory floorPosition
    ) external  returns (LiquidityPosition memory newPosition);
    function doDeployPosition(
        address pool,
        address receiver,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType,
        AmountsToMint memory amounts
    ) external returns (LiquidityPosition memory newPosition);
    function reDeploy(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        LiquidityType liquidityType
    ) external returns (LiquidityPosition memory newPosition);    
}
