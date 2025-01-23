// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {
    VaultInfo,
    LiquidityPosition,
    ProtocolAddresses,
    LiquidityStructureParameters
} from "../types/Types.sol";

/**
 * @title IVault
 * @notice Interface for managing a vault's liquidity, borrowing, and protocol parameters.
 */
interface IVault {
    /**
     * @notice Retrieves the current liquidity positions of the vault.
     * @return An array of three `LiquidityPosition` objects representing the current liquidity positions.
     */
    function getPositions() external view returns (LiquidityPosition[3] memory);

    /**
     * @notice Executes a liquidity shift operation for the vault.
     * @dev Adjusts the floor, anchor, and discovery positions based on vault conditions.
     */
    function shift() external;

    /**
     * @notice Executes a liquidity slide operation for the vault.
     * @dev Adjusts the positions to rebalance liquidity based on vault requirements.
     */
    function slide() external;

    /**
     * @notice Allows a user to borrow from the vault.
     * @param who The address of the borrower.
     * @param borrowAmount The amount to borrow.
     * @param duration The duration of the loan.
     * @dev Implements borrowing logic while ensuring collateralization and solvency constraints.
     */
    function borrow(address who, uint256 borrowAmount, uint256 duration) external;

    /**
     * @notice Retrieves the address of the Uniswap V3 pool associated with the vault.
     * @return The address of the Uniswap V3 pool.
     */
    function pool() external view returns (IUniswapV3Pool);

    /**
     * @notice Allows a borrower to repay their loan.
     * @param who The address of the borrower repaying the loan.
     * @dev Updates the vault state to reflect the repayment.
     */
    function payback(address who) external;

    /**
     * @notice Allows a borrower to roll their loan.
     * @param who The address of the borrower rolling their loan.
     * @dev Rolls the loan to a new term with updated parameters.
     */
    function roll(address who) external;

    /**
     * @notice Updates the vault's liquidity positions.
     * @param newPositions An array of three new `LiquidityPosition` objects.
     * @dev Replaces the vault's existing positions with the new positions.
     */
    function updatePositions(LiquidityPosition[3] memory newPositions) external;

    /**
     * @notice Retrieves detailed information about the vault.
     * @return A `VaultInfo` object containing detailed vault information.
     */
    function getVaultInfo() external view returns (VaultInfo memory);

    /**
     * @notice Retrieves the excess reserve of token1 in the vault.
     * @return The amount of excess token1 reserves.
     */
    function getExcessReserveToken1() external view returns (uint256);

    /**
     * @notice Retrieves the total collateral amount in the vault.
     * @return The total collateral amount.
     */
    function getCollateralAmount() external view returns (uint256);

    /**
     * @notice Retrieves the accumulated fees for token0 and token1.
     * @return The accumulated fees for token0 and token1 as a tuple.
     */
    function getAccumulatedFees() external view returns (uint256, uint256);

    /**
     * @notice Retrieves the protocol addresses associated with the vault.
     * @return A `ProtocolAddresses` object containing the associated protocol addresses.
     */
    function getProtocolAddresses() external view returns (ProtocolAddresses memory);

    /**
     * @notice Retrieves the liquidity structure parameters of the vault.
     * @return A `LiquidityStructureParameters` object containing the vault's liquidity parameters.
     */
    function getLiquidityStructureParameters() external view returns (LiquidityStructureParameters memory);

    /**
     * @notice Retrieves the address of the staking contract associated with the vault.
     * @return The address of the staking contract.
     */
    function getStakingContract() external view returns (address);
}
