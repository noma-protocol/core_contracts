// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./abstract/OwnableUninitialized.sol";
import "./libraries/LibAppStorage.sol";

contract Resolver is OwnableUninitialized {
    IAddressResolver resolver;

    mapping(bytes32 => address) private addressCache;
    mapping(bytes32 => address) private repository;
    mapping(bytes32 => uint256) private uintSettings;
    mapping(address => bool) private deployerACL;

    error InvalidAddress();
    error InputLengthsMismatch();
    error NotAllowed();
    error AddressNotFound(string reason);
    error OnlyFactoryOrManagerAllowed();

    constructor() {
        _manager = msg.sender;
    }

    function initFactory(address _factory) external onlyManager {
        if (_factory == address(0)) revert InvalidAddress();
        repository["NomaFactory"] = _factory;
    }

    function importAddresses(bytes32[] calldata names, address[] calldata destinations) external onlyManager {
        if (names.length != destinations.length) revert InputLengthsMismatch();

        for (uint256 i = 0; i < names.length; i++) {
            bytes32 name = names[i];
            address destination = destinations[i];
            repository[name] = destination;
            emit AddressImported(name, destination);
        }
    }

    function configureDeployerACL(address _vault) external onlyFactoryOrManager {
        deployerACL[_vault] = true;
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

    function requireDeployerACL(address _vault) external view {
        if (!deployerACL[_vault]) revert NotAllowed();
    }

    function requireAndGetAddress(bytes32 name, string calldata reason) external view returns (address) {
        address _foundAddress = repository[name];
        if (_foundAddress == address(0)) revert AddressNotFound(reason);
        return _foundAddress;
    }

    modifier onlyFactoryOrManager() {
        if (msg.sender != repository["NomaFactory"] && msg.sender != _manager) {
            revert OnlyFactoryOrManagerAllowed();
        }
        _;
    }

    /* ========== EVENTS ========== */

    event AddressImported(bytes32 name, address destination);
}
