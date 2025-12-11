// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    LiquidityPosition,
    LiquidityType,
    TokenInfo,
    VaultInfo
} from "../types/Types.sol";

/**
 * @title IModelHelper
 * @notice Interface for retrieving and managing liquidity, vault, and token information in a DeFi protocol.
 */
interface IModelHelper {
    /**
     * @notice Retrieves the liquidity ratio for a given pool and vault.
     * @param pool The address of the Uniswap V3 pool.
     * @param vault The address of the vault.
     * @return liquidityRatio The calculated liquidity ratio.
     */
    function getLiquidityRatio(address pool, address vault) external view returns (uint256 liquidityRatio);

    /**
     * @notice Calculates the current capacity of a liquidity position for a given vault.
     * @param pool The address of the Uniswap V3 pool.
     * @param vault The address of the vault.
     * @param position The liquidity position details.
     * @param liquidityType The type of liquidity being queried.
     * @return amount0Current The current amount of token0 in the position.
     */
    function getPositionCapacity(
        address pool,
        address vault,
        LiquidityPosition memory position,
        LiquidityType liquidityType
    ) external view returns (uint256 amount0Current);

    /**
     * @notice Retrieves the circulating supply of a token in a given vault and pool.
     * @param pool The address of the Uniswap V3 pool.
     * @param vault The address of the vault.
     * @param includeStaked Include staked
     * @return circulatingSupply The calculated circulating supply.
     */
    function getCirculatingSupply(address pool, address vault, bool includeStaked) external view returns (uint256 circulatingSupply);

    /**
     * @notice Retrieves the underlying token balances for a given liquidity type.
     * @param pool The address of the Uniswap V3 pool.
     * @param vault The address of the vault.
     * @param liquidityType The type of liquidity being queried.
     * @return lowerTick The lower tick of the liquidity position.
     * @return upperTick The upper tick of the liquidity position.
     * @return amount0 The current balance of token0.
     * @return amount1 The current balance of token1.
     */
    function getUnderlyingBalances(
        address pool,
        address vault,
        LiquidityType liquidityType
    ) external view returns (int24 lowerTick, int24 upperTick, uint256 amount0, uint256 amount1);

    /**
     * @notice Retrieves detailed information about a vault.
     * @param pool The address of the Uniswap V3 pool.
     * @param vault The address of the vault.
     * @param tokenInfo Information about the tokens associated with the vault.
     * @return vaultInfo The vault's detailed information.
     */
    function getVaultInfo(
        address pool,
        address vault,
        TokenInfo memory tokenInfo
    ) external view returns (VaultInfo memory vaultInfo);

    /**
     * @notice Updates the positions of a vault.
     * @param _positions An array of liquidity positions to update.
     */
    function updatePositions(LiquidityPosition[3] memory _positions) external;

    /**
     * @notice Retrieves the excess reserve balance of a token in a given pool and vault.
     * @param pool The address of the Uniswap V3 pool.
     * @param vault The address of the vault.
     * @param isToken0 A boolean indicating whether to query token0 (true) or token1 (false).
     * @return The excess reserve balance of the specified token.
     */
    function getExcessReserveBalance(
        address pool,
        address vault,
        bool isToken0
    ) external view returns (uint256);

    /**
     * @notice Calculates the intrinsic minimum value of a vault.
     * @param _vault The address of the vault.
     * @return The intrinsic minimum value of the vault.
     */
    function getIntrinsicMinimumValue(address _vault) external view returns (uint256);

    /**
     * @notice Ensures that a vault satisfies the solvency invariant.
     * @param _vault The address of the vault to check.
     * @dev Reverts if the solvency invariant is violated.
     */
    function enforceSolvencyInvariant(address _vault) external view;

    /**
     * @notice Retrieves the total supply of a token in a given pool.
     * @param pool The address of the Uniswap V3 pool.
     * @param isToken0 A boolean indicating whether to query token0 (true) or token1 (false).
     * @return The total supply of the specified token.
     */
    function getTotalSupply(address pool, bool isToken0) external view returns (uint256);
}
