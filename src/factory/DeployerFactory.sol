// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Deployer} from "../Deployer.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import {Utils} from "../libraries/Utils.sol";

/**
 * @title DeployerFactory
 * @dev This contract is responsible for deploying instances of the `Deployer` contract.
 *      It ensures that only an authorized factory (retrieved from the Address Resolver)
 *      can call the deployment function.
 */
contract DeployerFactory {
    
    /// @notice Emitted when a new `Deployer` contract is created.
    /// @param deployerAddress The address of the newly deployed Deployer contract.
    event DeployerCreated(address deployerAddress);

    /// @notice Error thrown when the caller is not the contract owner.
    error OnlyOwner();

    /// @notice Error thrown when the caller is not the authorized factory.
    error OnlyFactory();
    
    /// @notice Holds the latest deployed Deployer contract instance.
    Deployer public deployer;

    /// @notice Address resolver used to retrieve contract addresses.
    IAddressResolver public resolver;

    /**
     * @notice Constructs the DeployerFactory contract.
     * @dev Sets the address resolver for contract address resolution.
     * @param _resolver The address of the Address Resolver contract.
     */
    constructor(address _resolver) {
        resolver = IAddressResolver(_resolver);
    }

    /**
     * @notice Deploys a new instance of the `Deployer` contract.
     * @dev This function can only be called by the factory contract registered in the resolver.
     * @param _owner The owner address of the new Deployer contract.
     * @param _resolver The address resolver to be used by the Deployer contract.
     * @return deployerAddress The address of the newly deployed `Deployer` contract.
     * @custom:require Only callable by the factory contract.
     */
    function deployDeployer(address _owner, address _resolver) external onlyFactory returns (address deployerAddress) {
        deployer = new Deployer(_owner, _resolver);
        deployerAddress = address(deployer);

        emit DeployerCreated(deployerAddress);
    }

    /**
     * @notice Ensures that only the authorized factory can call certain functions.
     * @dev Uses the Address Resolver to retrieve the factory address.
     *      Reverts with `OnlyFactory()` if the caller is not the registered factory.
     */
    modifier onlyFactory() {
        address factory = resolver.requireAndGetAddress(
            Utils.stringToBytes32("OikosFactory"), 
            "no factory"
        );        
        if (msg.sender != factory) {
            revert OnlyFactory();
        }
        _;
    }
}
