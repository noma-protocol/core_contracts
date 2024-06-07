// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    LiquidityPosition,
    AmountsToMint,
    LiquidityType,
    ProtocolAddresses
} from "../Types.sol";

interface IDeployer {
    function deployFloor(uint256 _floorPrice) external;
    function shiftFloor(
        address pool,
        address receiver,
        uint256 currentFloorPrice,
        uint256 newFloorPrice,
        uint256 newFloorBalance,
        uint256 currentFloorBalance,
        LiquidityPosition memory floorPosition
    ) external  returns (LiquidityPosition memory newPosition);
    function deployPosition(
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
    function computeNewFloorPrice(
        address pool,
        uint256 toSkim,
        uint256 floorNewTokenBalance,
        uint256 circulatingSupply,
        uint256 anchorCapacity,
        LiquidityPosition[3] memory positions
    ) external view returns (uint256 newFloorPrice);    
}
