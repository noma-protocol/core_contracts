// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAddressResolver Interface
/// @notice Interface for the Address Resolver contract in a smart contract system.
/// This interface manages the retrieval and verification of addresses identified by unique bytes32 names.
interface IAddressResolver {
    /// @notice Retrieves the address associated with a given name.
    /// @dev This function does not revert but returns a zero address if the name is not found.
    /// @param name The bytes32 name identifier for the address.
    /// @return address The contract address associated with the name identifier.
    function getAddress(bytes32 name) external view returns (address);

    /// @notice Retrieves the address associated with a given name and reverts if not found.
    /// @dev This function reverts with the provided reason if the name is not associated with an address.
    /// @param name The bytes32 name identifier for the address.
    /// @param reason The revert reason to be thrown if the address is not found.
    /// @return address The contract address associated with the name identifier.
    function requireAndGetAddress(bytes32 name, string calldata reason) external view returns (address);

    function requireDeployerACL(address _vault) external view;

    /// @notice Imports multiple addresses and associates them with their corresponding names.
    /// @dev This function allows batch updating of name-address pairs.
    /// Typically called by an admin or owner of the contract to update the resolver's records.
    /// @param names An array of bytes32 identifiers.
    /// @param destinations An array of contract addresses, each corresponding to the name at the same index in the names array.
    function importAddresses(bytes32[] calldata names, address[] calldata destinations) external;


    function configureDeployerACL(address _vault) external;

    /// @notice Checks if the provided name-address pairs are correctly imported in the resolver.
    /// @dev This function can be used for verification after executing importAddresses.
    /// @param names An array of bytes32 identifiers to check.
    /// @param destinations An array of addresses to check against the corresponding names.
    /// @return bool True if all provided names are correctly mapped to the given addresses, false otherwise.
    function areAddressesImported(bytes32[] calldata names, address[] calldata destinations)
        external
        view
        returns (bool);
    
    /// @notice Retrieves the address associated with a given name in a specific vault.
    /// @dev This function does not revert but returns a zero address if the name is not found.
    /// @param _vault The address of the vault to query.
    /// @param name The bytes32 name identifier for the address.
    /// @return address The contract address associated with the name identifier.
    function getVaultAddress(address _vault, bytes32 name) external view returns (address);

    /// @notice Retrieves the address associated with a given name in a specific vault and reverts if not found.
    /// @dev This function reverts with the provided reason if the name is not associated with an address.
    /// @param _vault The address of the vault to query.
    /// @param name The bytes32 name identifier for the address.
    /// @param reason The revert reason to be thrown if the address is not found.
    /// @return address The contract address associated with the name identifier.
    function requireAndGetVaultAddress(address _vault, bytes32 name, string calldata reason) external view returns (address);

    /// @notice Imports multiple addresses and associates them with their corresponding names in a specific vault.
    /// @dev This function allows batch updating of name-address pairs in a specific vault.
    /// Typically called by an admin or owner of the contract to update the resolver's records.
    /// @param _vault The address of the vault to update.
    /// @param names An array of bytes32 identifiers.
    /// @param destinations An array of contract addresses, each corresponding to the name at the same index in the names array.
    function importVaultAddress(address _vault, bytes32[] calldata names, address[] calldata destinations) external;

}
