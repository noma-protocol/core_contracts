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

struct TokenInfo {
    address token0;
    address token1;
}

struct ShiftOpResult {
    uint256 currentLiquidityRatio;
    uint256 newFloorPrice;
}

struct ProtocolAddresses {
    address pool;
    address vault;
    address deployer;
    address modelHelper;
}

struct ShiftParameters {
    address pool;
    address deployer;
    uint256 toSkim;
    uint256 newFloorPrice;
    address modelHelper;
    uint256 floorToken1Balance;
    uint256 anchorToken1Balance;
    uint256 discoveryToken1Balance; 
    uint256 discoveryToken0Balance;   
    LiquidityPosition[3] positions;
}

struct VaultData {
    uint256 anchorToken1Balance;
    uint256 discoveryToken1Balance;
    uint256 circulatingSupply;
}

struct VaultInfo {
    uint256 liquidityRatio;
    uint256 circulatingSupply; 
    uint256 spotPriceX96;
    uint256 anchorCapacity; 
    uint256 floorCapacity;
    address token0;
    address token1;
    uint256 newFloor;
}

struct VaultDeployParameters {
    bytes32 _name;
    bytes32 _symbol;
    uint8 _decimals;
    uint256 _totalSupply;
    uint16 _percentageForSale;
    uint256 _IDOPrice;
    address token1;
}

struct VaultDescription {
    bytes32 tokenName;
    bytes32 tokenSymbol;
    uint8 tokenDecimals;
    address token0;
    address token1;
    address deployer;
    address vault;
}

struct PreShiftParameters {
    ProtocolAddresses addresses;
    uint256 toSkim;
    uint256 circulatingSupply;
    uint256 anchorCapacity;
    uint256 floorToken1Balance;
    uint256 anchorToken1Balance;
    uint256 discoveryToken1Balance;
    uint256 discoveryToken0Balance;
}

struct LoanPosition {
    uint256 borrowAmount;
    uint256 collateralAmount;
    uint256 fees;
    uint256 expiry;
    uint256 duration;
}