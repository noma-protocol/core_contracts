// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IsNomaToken
 * @notice Interface for the sNomaToken, extending the standard ERC20 interface with additional functionalities.
 */
interface IsNomaToken is IERC20 {
    /**
     * @notice Adjusts the total supply of the token by a specified amount.
     * @param supplyDelta The amount by which to adjust the total supply. Positive values increase the supply, negative values decrease it.
     * @dev This function is intended to be called to perform a rebase operation, modifying the total token supply.
     */
    function rebase(uint256 supplyDelta) external;

    /**
     * @notice Retrieves the current circulating supply of the token.
     * @return The total amount of tokens currently in circulation.
     * @dev This function provides the circulating supply, which may differ from the total supply due to tokens held in reserves or burned.
     */
    function circulatingSupply() external view returns (uint256);

    /**
     * @notice Mints a specified amount of tokens to a recipient address.
     * @param _recipient The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint.
     * @dev This function allows for the creation of new tokens, increasing the total supply.
     */
    function mint(address _recipient, uint256 _amount) external;

    /**
     * @notice Burns a specified amount of tokens from a given address.
     * @param from The address from which the tokens will be burned.
     * @param value The amount of tokens to burn.
     * @return A boolean value indicating whether the operation succeeded.
     * @dev This function reduces the total supply by permanently destroying the specified amount of tokens from the specified address.
     */
    function burnFor(address from, uint256 value) external returns (bool);
}
