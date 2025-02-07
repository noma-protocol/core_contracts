// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Liquidity Management Structs and Constants
/// @notice This contract defines various structs and constants used in liquidity management operations.


/// @notice Struct for representing token amounts to mint.
/// @param amount0 Amount of token0 to mint.
/// @param amount1 Amount of token1 to mint.
struct AmountsToMint {
    uint256 amount0;
    uint256 amount1;
}

/// @notice Information about the tokens in a pair.
/// @param token0 Address of the first token.
/// @param token1 Address of the second token.
struct TokenInfo {
    address token0;
    address token1;
}
/// @notice Represents a liquidity position within specified tick ranges.
/// @param lowerTick The lower tick of the position.
/// @param upperTick The upper tick of the position.
/// @param liquidity The amount of liquidity provided.
/// @param price The price associated with the position.
struct LiquidityPosition {
    int24 lowerTick;
    int24 upperTick;
    uint128 liquidity;
    uint256 price;
    int24 tickSpacing;
}

/// @notice Enum representing the types of liquidity.
/// @dev This is used to differentiate liquidity roles in the protocol.
enum LiquidityType {
    Floor,
    Anchor,
    Discovery
}

/// @notice Addresses used by the protocol.
/// @param pool Address of the liquidity pool.
/// @param vault Address of the vault contract.
/// @param deployer Address of the deployer.
/// @param modelHelper Address of the model helper.
/// @param adaptiveSupplyController Address of the adaptive supply controller.
struct ProtocolAddresses {
    address pool;
    address vault;
    address deployer;
    address modelHelper;
    address presaleContract;
    address adaptiveSupplyController;
}

/// @notice General information about the vault.
/// @param liquidityRatio Ratio of liquidity in the vault.
/// @param circulatingSupply Total circulating supply of tokens.
/// @param spotPriceX96 Spot price in 96-bit precision.
/// @param anchorCapacity Capacity of the anchor.
/// @param floorCapacity Capacity of the floor.
/// @param token0 Address of token0.
/// @param token1 Address of token1.
/// @param newFloor New floor price.
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

/// @notice Parameters for deploying a vault.
/// @param name Name of the vault token.
/// @param symbol Symbol of the vault token.
/// @param decimals Number of decimals for the token.
/// @param totalSupply Total supply of the token.
/// @param IDOPrice Initial price of the token in the IDO.
/// @param token1 Address of token1.
/// @param feeTier Fee tier for the pool.
struct VaultDeployParams {
    string name;
    string symbol;
    uint8 decimals;
    uint256 totalSupply;
    uint256 IDOPrice;
    uint256 floorPrice;
    address token1;
    uint24 feeTier;
    uint8  presale;
}

struct PresaleUserParams {
    uint256 _softCap;
    uint256 _initialPrice;
    uint256 _deadline;
}

struct PresaleDeployParams {
    address deployer;
    address vaultAddress;
    address pool;
    uint256 softCap;
    uint256 initialPrice;
    uint256 deadline;
    string name;
    string symbol;
    uint8 decimals;
    int24 tickSpacing;
    uint256 floorPercentage;
    uint256 totalSupply;    
}

struct LivePresaleParams {
    uint256 softCap;
    uint256 initialPrice;
    uint256 deadline;
    uint256 launchSupply;
}

struct PresaleProtocolParams {
    uint256 maxSoftCap;
    uint256 minContributionRatio;
    uint256 maxContributionRatio;
    uint256 presalePercentage;
    uint256 minDuration;
    uint256 maxDuration;
}

/// @notice Parameters for deploying liquidity positions.
/// @param bips Basis points for the liquidity.
/// @param bipsBelowSpot Basis points below the spot price.
/// @param tickSpacing Tick spacing for the position.
/// @param lowerTick The lower tick of the position.
/// @param upperTick The upper tick of the position.
struct DeployLiquidityParameters {
    uint256 bips;
    uint256 bipsBelowSpot;
    int24 tickSpacing;
    int24 lowerTick;
    int24 upperTick;
}

/// @notice Description of a vault.
/// @param tokenName Name of the vault token.
/// @param tokenSymbol Symbol of the vault token.
/// @param tokenDecimals Number of decimals for the token.
/// @param token0 Address of token0.
/// @param token1 Address of token1.
/// @param deployer Address of the deployer.
/// @param vault Address of the vault.
struct VaultDescription {
    string tokenName;
    string tokenSymbol;
    uint8 tokenDecimals;
    address token0;
    address token1;
    address deployer;
    address vault;
    address presaleContract;
}

/// @notice Parameters used before a shift operation.
/// @param addresses Protocol-related addresses.
/// @param toSkim Amount to skim from liquidity.
/// @param circulatingSupply Total circulating supply.
/// @param anchorCapacity Capacity allocated to the anchor.
/// @param floorToken1Balance Token1 balance for the floor.
/// @param anchorToken1Balance Token1 balance for the anchor.
/// @param discoveryToken1Balance Token1 balance for discovery.
/// @param discoveryToken0Balance Token0 balance for discovery.
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

/// @notice Parameters for a shift operation.
/// @param pool Address of the liquidity pool.
/// @param deployer Address of the deployer.
/// @param toSkim Amount to skim from liquidity.
/// @param newFloorPrice The new floor price.
/// @param modelHelper Address of the model helper.
/// @param adaptiveSupplyController Address of the adaptive supply controller.
/// @param floorToken1Balance Token1 balance allocated to the floor.
/// @param anchorToken1Balance Token1 balance allocated to the anchor.
/// @param discoveryToken1Balance Token1 balance allocated to discovery.
/// @param discoveryToken0Balance Token0 balance allocated to discovery.
/// @param positions Liquidity positions involved in the operation.
struct ShiftParameters {
    address pool;
    address deployer;
    uint256 toSkim;
    uint256 newFloorPrice;
    address modelHelper;
    address adaptiveSupplyController;
    uint256 floorToken1Balance;
    uint256 anchorToken1Balance;
    uint256 discoveryToken1Balance; 
    uint256 discoveryToken0Balance;   
    LiquidityPosition[3] positions;
}


/// @notice Represents a loan position.
/// @param borrowAmount Amount borrowed.
/// @param collateralAmount Collateral amount provided.
/// @param fees Fees associated with the loan.
/// @param expiry Expiry timestamp of the loan.
/// @param duration Duration of the loan.
struct LoanPosition {
    uint256 borrowAmount;
    uint256 collateralAmount;
    uint256 fees;
    uint256 expiry;
    uint256 duration;
}

/// @notice Parameters for calculating rewards.
/// @param ethAmount Amount of ETH provided.
/// @param imv Token price in ETH.
/// @param spotPrice Spot price in ETH.
/// @param circulating Circulating supply.
/// @param totalSupply Total supply.
/// @param kr Sensitivity for r adjustment.
struct RewardParams {
    uint256 ethAmount;   // Amount of ETH provided 
    uint256 imv;         // Token price in ETH 
    uint256 spotPrice;   // Spot price in ETH 
    uint256 circulating; // Circulating supply
    uint256 totalSupply; // Total supply 
    uint256 kr;          // Sensitivity for r adjustment (e.g., 10e18)
}

/// @notice Parameters for configuring the protocol.
/// @param floorPercentage Percentage allocated to floor liquidity.
/// @param anchorPercentage Percentage allocated to anchor liquidity.
/// @param idoPriceMultiplier Multiplier for the IDO price.
/// @param floorBips Basis points for the floor range.
/// @param shiftRatio Ratio used for liquidity shifting.
/// @param slideRatio Ratio used for liquidity sliding.
/// @param discoveryBips Basis points for the discovery range.
struct ProtocolParameters {
    uint8 floorPercentage;
    uint8 anchorPercentage;
    uint8 idoPriceMultiplier;
    uint16[2] floorBips;
    uint256 shiftRatio;
    uint256 slideRatio;
    int24 discoveryBips;
    int24 shiftAnchorUpperBips;
    int24 slideAnchorUpperBips;
    uint256 lowBalanceThresholdFactor;
    uint256 highBalanceThresholdFactor;
    uint256 inflationFee;
    uint256 loanFee;
    uint256 deployFee;
    uint256 presalePremium;
}

/// @notice Parameters for structuring liquidity.
/// @param floorPercentage Percentage allocated to floor liquidity.
/// @param anchorPercentage Percentage allocated to anchor liquidity.
/// @param idoPriceMultiplier Multiplier for the IDO price.
/// @param floorBips Basis points for the floor range.
/// @param shiftRatio Ratio used for liquidity shifting.
/// @param slideRatio Ratio used for liquidity sliding.
/// @param discoveryBips Basis points for the discovery range.
struct LiquidityInternalPars {
    int24 lowerTick;
    int24 upperTick;
    uint256 amount1ToDeploy;
    LiquidityType liquidityType;
}

struct DeploymentData {
    PresaleUserParams presaleParams;
    VaultDeployParams vaultDeployParams;
    IUniswapV3Pool pool;
    ERC1967Proxy proxy;
    int24 tickSpacing;
    address vaultAddress;
    address vaultUpgrade;
    address sNoma;
    address stakingContract;
    address presaleContract;
}