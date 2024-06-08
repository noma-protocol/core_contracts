// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    LiquidityPosition,
    LiquidityType,
    TokenInfo,
    VaultInfo
} from "../Types.sol";

interface IModelHelper{
    function getLiquidityRatio(address pool, address vault) external view returns (uint256 liquidityRatio);
    function getPositionCapacity(address pool, address vault, LiquidityPosition memory position) external view returns (uint256 amount0Current);
    function getCirculatingSupply(address pool, address vault) external view returns (uint256 circulatingSupply);
    function getUnderlyingBalances(address pool, address vault, LiquidityType liquidityType) external view returns (int24, int24, uint256, uint256);
    function getVaultInfo(address pool, address vault, TokenInfo memory tokenInfo) external view returns (VaultInfo memory vaultInfo);
    function updatePositions(LiquidityPosition[3] memory _positions) external;
}
