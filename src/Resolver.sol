// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./abstract/OwnableUninitialized.sol";
import "./libraries/LibAppStorage.sol";

contract Resolver is OwnableUninitialized {
    
    IAddressResolver resolver;

    mapping(bytes32 => address) private addressCache;
    mapping(bytes32 => address) private repository;
    mapping(bytes32 => uint256) private uintSettings;

    constructor()  {
        _manager = msg.sender;
    }

    function importAddresses(bytes32[] calldata names, address[] calldata destinations) external onlyManager {
        require(names.length == destinations.length, "Input lengths must match");

        for (uint256 i = 0; i < names.length; i++) {
            bytes32 name = names[i];
            address destination = destinations[i];
            repository[name] = destination;
            emit AddressImported(name, destination);
        }
    }

    /* ========== VIEWS ========== */

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

    function getAddress(bytes32 name) external view returns (address) {
        return repository[name];
    }

    function requireAndGetAddress(bytes32 name, string calldata reason) external view returns (address) {
        address _foundAddress = repository[name];
        require(_foundAddress != address(0), reason);
        return _foundAddress;
    }

    /* ========== EVENTS ========== */

    function getFunctionSelectors() external pure virtual returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = bytes4(keccak256(bytes("requireAndGetAddress(bytes32,string)")));
        selectors[1] = bytes4(keccak256(bytes("getAddress(bytes32)")));
        selectors[2] = bytes4(keccak256(bytes("areAddressesImported(bytes32[],address[])")));
        selectors[3] = bytes4(keccak256(bytes("importAddresses(bytes32[],address[])")));
        selectors[4] = bytes4(keccak256(bytes("initialize(address)")));
        return selectors;
    }

    event AddressImported(bytes32 name, address destination);
}
