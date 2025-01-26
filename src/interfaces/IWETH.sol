// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWETH
 * @notice Interface for Wrapped Ether (WETH) token operations.
 * @dev WETH is an ERC20-compliant token that represents Ether (ETH) in the ERC20 standard.
 */
interface IWETH {
    /**
     * @notice Deposit Ether and receive Wrapped Ether (WETH) tokens.
     * @dev Converts the sent Ether to WETH. The amount of WETH minted is equal to the amount of Ether sent.
     * Emits a `Deposit` event with the sender's address and the amount deposited.
     */
    function deposit() external payable;

    /**
     * @notice Withdraw Ether by redeeming Wrapped Ether (WETH) tokens.
     * @param wad The amount of WETH to redeem for Ether.
     * @dev Converts WETH back to Ether and sends it to the caller. The caller must have at least `wad` amount of WETH.
     * Emits a `Withdrawal` event with the receiver's address and the amount withdrawn.
     */
    function withdraw(uint256 wad) external;

    /**
     * @notice Transfer WETH tokens to a specified address.
     * @param to The address to transfer WETH to.
     * @param value The amount of WETH to transfer.
     * @return success A boolean value indicating whether the transfer was successful.
     * @dev Transfers `value` amount of WETH from the caller's account to the `to` address.
     * Emits a `Transfer` event as defined in the ERC20 standard.
     */
    function transfer(address to, uint256 value) external returns (bool success);
}
