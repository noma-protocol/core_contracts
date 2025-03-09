// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ITokenRepo Interface
/// @notice Interface for a token repository contract that can transfer tokens
interface ITokenRepo {
    /// @notice Transfers a specified amount of a token to a recipient
    /// @param token The address of the ERC20 token contract
    /// @param to The recipient address
    /// @param amount The amount of tokens to transfer
    function transfer(address token, address to, uint256 amount) external;
}

/// @title Token Repository
/// @notice A simple contract that allows the owner to transfer ERC20 tokens from the repository.
/// @dev Only the owner is allowed to initiate transfers.
contract TokenRepo {
    /// @notice The address of the contract owner
    address public owner;

    /// @notice Constructor that sets the contract owner.
    /// @param _owner The address that will be set as the owner.
    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice Transfers a specified amount of an ERC20 token to a recipient.
    /// @dev Can only be called by the owner.
    /// @param token The address of the ERC20 token.
    /// @param to The address of the recipient.
    /// @param amount The amount of tokens to transfer.
    function transfer(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    /// @notice Modifier that restricts function access to only the owner.
    /// @dev Reverts if msg.sender is not the owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
}
