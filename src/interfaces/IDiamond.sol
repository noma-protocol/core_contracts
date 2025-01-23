// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IDiamond
 * @notice Interface for a contract that follows the Diamond Standard, allowing for modular upgradeability.
 */
interface IDiamond {
    /**
     * @notice Initializes the diamond contract.
     * @dev This function is typically called to set up initial state or perform necessary configurations.
     */
    function initialize() external;

    /**
     * @notice Transfers ownership of the diamond contract to a new owner.
     * @param _newOwner The address of the new owner.
     * @dev Emits an {OwnershipTransferred} event.
     */
    function transferOwnership(address _newOwner) external;

    /**
     * @notice Returns the address of the current owner.
     * @return The address of the current owner.
     */
    function owner() external view returns (address);
}
