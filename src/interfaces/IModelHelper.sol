// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    LiquidityPosition,
    LiquidityType,
    VaultInfo
} from "../Types.sol";

interface IModelHelper{
    function getLiquidityRatio(address pool) external view returns (uint256 liquidityRatio);
    function getPositionCapacity(address pool, address vault, LiquidityPosition memory position) external view returns (uint256 amount0Current);
    function getCirculatingSupply(address pool, address vault) external view returns (uint256 circulatingSupply);
    function getUnderlyingBalances(address pool, address vault, LiquidityType liquidityType) external view returns (int24, int24, uint256, uint256);
    function estimateNewFloorPrice(address pool) external view returns (uint256 newFloor);
    function getVaultInfo(address pool, address vault, VaultInfo memory vaultInfo) external view returns (uint256, uint256, uint256, uint256, uint256, address, address);
    function updatePositions(LiquidityPosition[3] memory _positions) external;
}
