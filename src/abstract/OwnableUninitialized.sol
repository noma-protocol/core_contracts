// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title OwnableUninitialized
 * @dev Provides a basic access control mechanism where an account (manager) is granted exclusive access to specific functions.
 * @notice This contract is designed to be inherited and used as a foundation for access control.
 * @dev The manager account is initially set to the deployer of the contract but can be changed using {transferOwnership}.
 * @dev This contract does not use constructor initialization; instead, initialization must be handled externally.
 * @dev DO NOT ADD STATE VARIABLES - APPEND THEM TO `LibAppStorage`.
 * @dev DO NOT ADD BASE CONTRACTS WITH STATE VARIABLES - APPEND THEM TO `LibAppStorage`.
 */
abstract contract OwnableUninitialized {
    /// @notice The address of the current manager.
    address internal _manager;

    /// @notice Emitted when ownership is transferred from one manager to another.
    /// @param previousManager The address of the previous manager.
    /// @param newManager The address of the new manager.
    event OwnershipTransferred(address indexed previousManager, address indexed newManager);

    /// @dev Error thrown when the provided address is zero.
    error ZeroAddress();

    /// @dev Error thrown when a function is called by an account other than the manager.
    error NotManager();

    /**
     * @notice Initializes the contract and sets the deployer as the initial manager.
     * @dev The constructor is intentionally empty as initialization must be handled elsewhere.
     * @dev Sets `_manager` to the address of the deployer (`msg.sender`).
     */
    constructor() {
        _manager = msg.sender;
    }

    /**
     * @notice Returns the address of the current manager.
     * @return The address of the current manager.
     */
    function manager() public view virtual returns (address) {
        return _manager;
    }

    /**
     * @notice Modifier that restricts access to functions to only the current manager.
     * @dev Reverts with `NotManager` if the caller is not the current manager.
     */
    modifier onlyManager() {
        if (manager() != msg.sender) {
            revert NotManager();
        }
        _;
    }

    /**
     * @notice Renounces ownership of the contract.
     * @dev After calling this function, the contract will no longer have a manager,
     * and `onlyManager` functions cannot be called.
     * @dev Can only be called by the current manager.
     * Emits an {OwnershipTransferred} event with the new manager set to the zero address.
     */
    function renounceOwnership() public virtual onlyManager {
        emit OwnershipTransferred(_manager, address(0));
        _manager = address(0);
    }

    /**
     * @notice Transfers ownership of the contract to a new manager.
     * @dev The new manager address cannot be the zero address.
     * @param newOwner The address of the new manager.
     * @dev Can only be called by the current manager.
     * Emits an {OwnershipTransferred} event.
     */
    function transferOwnership(address newOwner) public virtual onlyManager {
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }
        emit OwnershipTransferred(_manager, newOwner);
        _manager = newOwner;
    }
}
