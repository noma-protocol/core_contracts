// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ███╗   ██╗ ██████╗ ███╗   ███╗ █████╗                               
// ████╗  ██║██╔═══██╗████╗ ████║██╔══██╗                              
// ██╔██╗ ██║██║   ██║██╔████╔██║███████║                              
// ██║╚██╗██║██║   ██║██║╚██╔╝██║██╔══██║                              
// ██║ ╚████║╚██████╔╝██║ ╚═╝ ██║██║  ██║                              
// ╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝                              
                                                                    
// ██████╗ ██████╗  ██████╗ ████████╗ ██████╗  ██████╗ ██████╗ ██╗     
// ██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝██╔═══██╗██╔════╝██╔═══██╗██║     
// ██████╔╝██████╔╝██║   ██║   ██║   ██║   ██║██║     ██║   ██║██║     
// ██╔═══╝ ██╔══██╗██║   ██║   ██║   ██║   ██║██║     ██║   ██║██║     
// ██║     ██║  ██║╚██████╔╝   ██║   ╚██████╔╝╚██████╗╚██████╔╝███████╗
// ╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝  ╚═════╝ ╚═════╝ ╚══════╝
//
// Contract: Resolver.sol
// Author:  
// Copyright  

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Resolver Contract
/// @notice Manages a repository of addresses, configurations, and access control for deployers.
/// @dev This contract is Ownable and integrates deployer ACL mechanisms for address resolution.
contract Resolver is Ownable {
    
    /// @dev Maps a name (as bytes32) to its corresponding address.
    mapping(bytes32 => address) private addressCache;

    /// @dev Repository mapping for storing key-value pairs of addresses.
    mapping(bytes32 => address) private repository;
    
    mapping(address => mapping(bytes32 => address)) private vaultAddressCache;

    /// @dev Maps configuration names (as bytes32) to their uint256 settings.
    mapping(bytes32 => uint256) private uintSettings;

    /// @dev Tracks allowed deployers for specific actions.
    mapping(address => bool) private deployerACL;

    /// @dev Error triggered when an invalid address (e.g., `address(0)`) is provided.
    error InvalidAddress();

    /// @dev Error triggered when input array lengths do not match.
    error InputLengthsMismatch();

    /// @dev Error triggered when an unauthorized action is attempted.
    error NotAllowed();

    /// @dev Error triggered when an address is not found for a specified name.
    error AddressNotFound(string reason);

    /// @dev Error triggered when a function is called by an unauthorized address.
    error OnlyFactoryOrManagerAllowed();

    /// @notice Constructor for the Resolver contract.
    /// @param _deployer Address of the deployer or initial owner of the contract.
    constructor(address _deployer) Ownable(_deployer) {}

    /// @notice Initializes the factory address in the repository.
    /// @dev This function can only be called by the owner.
    /// @param _factory Address of the factory contract to initialize.
    function initFactory(address _factory) external onlyOwner {
        if (_factory == address(0)) revert InvalidAddress();
        repository["NomaFactory"] = _factory;
    }

    /// @notice Imports multiple addresses into the repository.
    /// @dev Updates the repository mapping with names and corresponding addresses.
    /// @param names Array of names (as bytes32) to associate with the addresses.
    /// @param destinations Array of addresses to associate with the names.
    function importAddresses(bytes32[] calldata names, address[] calldata destinations) external onlyOwner {
        if (names.length != destinations.length) revert InputLengthsMismatch();

        for (uint256 i = 0; i < names.length; i++) {
            bytes32 name = names[i];
            address destination = destinations[i];
            repository[name] = destination;
            emit AddressImported(name, destination);
        }
    }

    function importVaultAddress(
        address _vault, 
        bytes32[] calldata names, 
        address[] calldata destinations
    ) external onlyFactoryOrOwner {
        if (names.length != destinations.length) revert InputLengthsMismatch();

        for (uint256 i = 0; i < names.length; i++) {
            bytes32 name = names[i];
            address destination = destinations[i];
            vaultAddressCache[_vault][name] = destination;
            emit AddressImported(name, destination);
        }
    }

    /// @notice Configures the deployer ACL for a specific vault address.
    /// @dev Grants deployer permissions for a given address.
    /// @param _vault Address of the vault to grant ACL permissions.
    function configureDeployerACL(address _vault) external onlyFactoryOrOwner {
        deployerACL[_vault] = true;
    }

    /* ========== VIEWS ========== */

    /// @notice Checks if a set of names and addresses are already imported.
    /// @dev Compares the repository values with the provided destinations for the given names.
    /// @param names Array of names to check in the repository.
    /// @param destinations Array of addresses to compare with repository values.
    /// @return True if all names and destinations match the repository, otherwise false.
    function areAddressesImported(bytes32[] calldata names, address[] calldata destinations)
        external
        view
        returns (bool)
    {
        for (uint256 i = 0; i < names.length; i++) {
            if (repository[names[i]] != destinations[i]) {
                return false;
            }
        }
        return true;
    }

    function getVaultAddress(address _vault, bytes32 name) external view returns (address) {
        return vaultAddressCache[_vault][name];
    }

    /// @notice Verifies that the provided vault address has deployer ACL permissions.
    /// @dev Reverts with `NotAllowed()` if the vault does not have ACL permissions.
    /// @param _vault Address of the vault to verify.
    function requireDeployerACL(address _vault) external view {
        if (!deployerACL[_vault]) revert NotAllowed();
    }

    /// @notice Retrieves an address associated with a given name and ensures it is valid.
    /// @dev Reverts with `AddressNotFound(reason)` if the address is `address(0)`.
    /// @param name The name (as bytes32) to query in the repository.
    /// @param reason The reason for the address lookup (used in the revert message).
    /// @return The address associated with the provided name.
    function requireAndGetAddress(bytes32 name, string calldata reason) external view returns (address) {
        // Check first if the vault has a specific address
        address vaultAddress = vaultAddressCache[msg.sender][name];
        if (vaultAddress != address(0)) {
            return vaultAddress;
        } else  {
            address _foundAddress = repository[name];
            if (_foundAddress == address(0)) revert AddressNotFound(reason);
            return _foundAddress;
        }
    }

    function getAddress(bytes32 name) external view returns (address) {
        // Check first if the vault has a specific address
        address vaultAddress = vaultAddressCache[msg.sender][name];
        if (vaultAddress != address(0)) {
            return vaultAddress;
        } else  {
            address _foundAddress = repository[name];
            return _foundAddress;
        }
    }

    /* ========== MODIFIERS ========== */

    /// @dev Ensures that the caller is either the factory or the owner of the contract.
    modifier onlyFactoryOrOwner() {
        if (msg.sender != repository["NomaFactory"] && msg.sender != owner()) {
            revert OnlyFactoryOrManagerAllowed();
        }
        _;
    }

    /* ========== EVENTS ========== */

    /// @notice Emitted when an address is successfully imported into the repository.
    /// @param name The name (as bytes32) associated with the imported address.
    /// @param destination The address that was imported into the repository.
    event AddressImported(bytes32 name, address destination);
}
