// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {
    VaultInfo,
    LiquidityPosition,
    ProtocolAddresses,
    ProtocolParameters,
    LiquidityType
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
     * @param borrowAmount The amount to borrow.
     * @param duration The duration of the loan.
     * @dev Implements borrowing logic while ensuring collateralization and solvency constraints.
     */
    function borrow(uint256 borrowAmount, uint256 duration) external;

    /**
     * @notice Retrieves the address of the Uniswap V3 pool associated with the vault.
     * @return The address of the Uniswap V3 pool.
     */
    function pool() external view returns (IUniswapV3Pool);

    /**
     * @notice Allows a borrower to repay their loan.
     * @dev Updates the vault state to reflect the repayment.
     * @param amount The amount to repay.
     */
    function payback(uint256 amount) external;

    /**
     * @notice Allows a borrower to roll their loan.
     * @param newDuration The new duration of the loan.
     * @dev Rolls the loan to a new term with updated parameters.
     */
    function roll(uint256 newDuration) external;

    /**
     * @notice Updates the vault's liquidity positions.
     * @param newPositions An array of three new `LiquidityPosition` objects.
     * @dev Replaces the vault's existing positions with the new positions.
     */
    function updatePositions(LiquidityPosition[3] memory newPositions) external;

    function bumpRewards(uint256 bnbAmount) external;
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
     * @return A `ProtocolParameters` object containing the vault's liquidity parameters.
     */
    function getProtocolParameters() external view returns (ProtocolParameters memory);

    /**
    * @notice Bumps the floor liquidity of the vault.
    * @param reserveAmount The amount of reserve to bump the floor with.
    * @dev Adjusts the floor position based on the provided reserve amount.
    */
    function bumpFloor(uint256 reserveAmount) external; 
        
    /**
    * @notice Defaults outstanding unpaid loans.
    * @dev Marks overdue loans as defaulted and burns associated tokens per vault policy.
    */
    function defaultLoans() external;
        
    /**
    * @notice Retrieves the address of the staking contract associated with the vault.
    * @return The address of the staking contract.
    */
    function getStakingContract() external view returns (address);

    /**
    * @notice Returns whether staking is currently enabled for this vault.
    * @dev Useful for front-ends and integrations to gate staking-related actions.
    * @return enabled True if staking is enabled, false otherwise.
    */
    function stakingEnabled() external view returns (bool);

    /**
    * @notice Mints vault tokens to a recipient.
    * @dev MAY be restricted to vault/manager roles. Implementations SHOULD emit a Transfer event.
    * @param to The recipient address that will receive the newly minted tokens.
    * @param amount The amount of tokens to mint.
    * @return success True if minting succeeded.
    */
    function mintTokens(address to, uint256 amount) external returns (bool);

    /**
    * @notice Burns vault tokens from the caller.
    * @dev Caller MUST have at least `amount` balance. Implementations SHOULD emit a Transfer event to address(0).
    * @param amount The amount of tokens to burn.
    */
    function burnTokens(uint256 amount) external;

    /**
    * @notice Sets the accumulated fee amounts for the vault’s accounting.
    * @dev Typically callable by the vault/fee collector after harvesting. Values are denominated in token0/token1 units.
    * @param _feesAccumulatedToken0 The total accumulated fees for token0.
    * @param _feesAccumulatedToken1 The total accumulated fees for token1.
    */
    function setFees(uint256 _feesAccumulatedToken0, uint256 _feesAccumulatedToken1) external;

    /**
    * @notice Returns the number of seconds elapsed since the last token mint operation.
    * @dev Implementations SHOULD return 0 if no mint has occurred yet.
    * @return secondsElapsed Seconds since the last mint.
    */
    function getTimeSinceLastMint() external view returns (uint256);

    /**
    * @notice Returns the address of the team-controlled multisig for administrative actions.
    * @dev This address MAY be used for restricted operations such as parameter updates.
    * @return multisig The team multisig address.
    */
    function teamMultiSig() external view returns (address);

    function getUnderlyingBalances(LiquidityType liquidityType) external view  returns (int24, int24, uint256, uint256);

    function setReferralEntity(bytes8 code, uint256 amount) external;

    function fixInbalance(address pool,uint160 sqrtPriceX96, uint256 amount) external;
}
