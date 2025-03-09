// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title pAsset Token
/// @notice An ERC20 token implementation based on Solmate's minimal ERC20.
/// @dev This contract extends Solmate's ERC20, allowing custom name, symbol, and decimals at deployment.
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
}
