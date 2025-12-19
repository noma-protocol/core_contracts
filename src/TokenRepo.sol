// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./errors/Errors.sol";

/// @title ITokenRepo Interface
/// @notice Interface for a token repository contract that can transfer tokens
interface ITokenRepo {
    /// @notice Transfers a specified amount of a token to a recipient
    /// @param token The address of the ERC20 token contract
    /// @param to The recipient address
    /// @param amount The amount of tokens to transfer
    function transferToRecipient(address token, address to, uint256 amount) external;
}

/// @title Token Repository
/// @notice A simple contract that allows the owner to transfer ERC20 tokens from the repository.
/// @dev Only the owner is allowed to initiate transfers.
contract TokenRepo {
    using SafeERC20 for IERC20;

    /// @notice The address of the contract owner
    address public owner;

    /// @notice The pending owner for two-step ownership transfer
    address public pendingOwner;

    /// @notice Emitted when ownership transfer is initiated
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);
    /// @notice Emitted when ownership transfer is completed
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Constructor that sets the contract owner.
    /// @param _owner The address that will be set as the owner.
    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
    }

    /// @notice Transfers a specified amount of an ERC20 token to a recipient.
    /// @dev Can only be called by the owner.
    /// @param token The address of the ERC20 token.
    /// @param to The address of the recipient.
    /// @param amount The amount of tokens to transfer.
    function transferToRecipient(address token, address to, uint256 amount) external onlyOwner {
        // [C-02 FIX] Use SafeERC20
        IERC20(token).safeTransfer(to, amount);
    }

    // [H-04 FIX] Add two-step ownership transfer
    /// @notice Initiates ownership transfer to a new address (two-step process)
    /// @param newOwner The address of the proposed new owner
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        if (newOwner == owner) revert InvalidParams();
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }

    /// @notice Accepts pending ownership transfer
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotAuthorized();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /// @notice Modifier that restricts function access to only the owner.
    /// @dev Reverts if msg.sender is not the owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }
}
