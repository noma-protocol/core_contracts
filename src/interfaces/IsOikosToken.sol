// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IsOikosToken
 * @notice Interface for the sOikosToken, extending the standard ERC20 interface with additional functionalities.
 */
interface IsOikosToken is IERC20 {

    function initialize(address _stakingContract) external;
    
    /**
     * @notice Adjusts the total supply of the token by a specified amount.
    * @param supplyDelta The number of new fragment tokens to add into circulation via expansion.
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
     * @notice Burns a specified amount of tokens from a sender address.
     * @param amount The amount of tokens to burn.
     * @param from The address from which to burn tokens.
     * @dev This function allows for the destruction of tokens, decreasing the total supply.
     */
    function burn(uint256 amount, address from) external;
}
