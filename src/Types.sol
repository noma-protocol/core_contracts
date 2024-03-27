// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Constants
uint24 constant feeTier = 3000;
int24 constant tickSpacing = 60;

struct LiquidityPosition {
    int24 lowerTick;
    int24 upperTick;
    uint128 liquidity;
    uint256 price;
}

enum LiquidityType {
    Floor,
    Anchor,
    Discovery
}

struct DeployLiquidityParameters {
    uint256 bips;
    uint256 bipsBelowSpot;
    int24 tickSpacing;
    int24 lowerTick;
    int24 upperTick;
}

struct AmountsToMint {
    uint256 amount0;
    uint256 amount1;
}

struct VaultInfo {
    address token0;
    address token1;
}

struct ShiftOpResult {
    uint256 currentLiquidityRatio;
    uint256 newFloorPrice;
}