// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../errors/Errors.sol";

/// @title pAsset Token
/// @notice A non-transferable ERC20 token for presale participation.
/// @dev Only mint (from=address(0)) and burn (to=address(0)) are allowed.
///      Direct transfers between addresses are blocked.
contract pAsset is ERC20 {

    /// @notice Creates a new pAsset token.
    /// @param name The name of the token.
    /// @param symbol The token symbol.
    /// @param decimals The number of decimals the token uses.
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol) {}

    /// @notice Override _update to block transfers between addresses.
    /// @dev Only mint (from=address(0)) and burn (to=address(0)) are allowed.
    /// @param from Source address (address(0) for mint)
    /// @param to Destination address (address(0) for burn)
    /// @param value Amount to transfer
    function _update(address from, address to, uint256 value) internal override {
        // Allow mint (from=0) and burn (to=0), block transfers
        if (from != address(0) && to != address(0)) revert NonTransferrable();
        super._update(from, to, value);
    }
}
