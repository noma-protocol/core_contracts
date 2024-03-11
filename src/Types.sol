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
    uint256 amount0LowerBound;
    uint256 amount1UpperBound;
    uint256 amount1UpperBoundVirtual;
}

enum LiquidityType {
    Floor,
    Anchor,
    Discovery
}