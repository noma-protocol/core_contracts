// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Liquidity Management Structs and Constants
/// @notice This contract defines various structs and constants used in liquidity management operations.

/// @dev Fee tier used in the protocol, specified in basis points (bps).
uint24 constant feeTier = 3000;

/// @dev Tick spacing used for Uniswap pools.
int24 constant tickSpacing = 60;

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
}

/// @notice Enum representing the types of liquidity.
/// @dev This is used to differentiate liquidity roles in the protocol.
enum LiquidityType {
    Floor,
    Anchor,
    Discovery
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

/// @notice Results of a shift operation.
/// @param currentLiquidityRatio The current liquidity ratio.
/// @param newFloorPrice The new floor price after the shift.
struct ShiftOpResult {
    uint256 currentLiquidityRatio;
    uint256 newFloorPrice;
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
    address adaptiveSupplyController;
}

/// @notice Parameters for structuring liquidity.
/// @param floorPercentage Percentage allocated to floor liquidity.
/// @param anchorPercentage Percentage allocated to anchor liquidity.
/// @param idoPriceMultiplier Multiplier for the IDO price.
/// @param floorBips Basis points for the floor range.
/// @param shiftRatio Ratio used for liquidity shifting.
/// @param slideRatio Ratio used for liquidity sliding.
/// @param discoveryBips Basis points for the discovery range.
struct LiquidityStructureParameters {
    uint8 floorPercentage;
    uint8 anchorPercentage;
    uint8 idoPriceMultiplier;
    uint16[2] floorBips;
    uint256 shiftRatio;
    uint256 slideRatio;
    int24 discoveryBips;
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

/// @notice Vault data used in the protocol.
/// @param anchorToken1Balance Token1 balance allocated to the anchor.
/// @param discoveryToken1Balance Token1 balance allocated to discovery.
/// @param circulatingSupply Total circulating supply of the vault's tokens.
struct VaultData {
    uint256 anchorToken1Balance;
    uint256 discoveryToken1Balance;
    uint256 circulatingSupply;
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
/// @param _name Name of the vault token.
/// @param _symbol Symbol of the vault token.
/// @param _decimals Number of decimals for the token.
/// @param _totalSupply Total supply of the token.
/// @param _percentageForSale Percentage of tokens allocated for sale.
/// @param _IDOPrice Initial price of the token in the IDO.
/// @param token1 Address of token1.
struct VaultDeployParams {
    string _name;
    string _symbol;
    uint8 _decimals;
    uint256 _totalSupply;
    uint16 _percentageForSale;
    uint256 _IDOPrice;
    address token1;
}

/// @notice Parameters for initializing a vault.
/// @param _deployer Address of the deployer.
/// @param _pool Address of the liquidity pool.
/// @param _modelHelper Address of the model helper.
/// @param _stakingContract Address of the staking contract.
/// @param _proxyAddress Address of the proxy contract.
/// @param _escrowContract Address of the escrow contract.
struct VaultInitParams {
    address _deployer;
    address _pool;
    address _modelHelper;
    address _stakingContract;
    address _proxyAddress;
    address _escrowContract;
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
