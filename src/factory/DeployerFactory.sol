// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Deployer } from "../Deployer.sol";

contract DeployerFactory {
    
    event DeployerCreated(address deployerAddress);
    error OnlyOwner();
    error OnlyFactory();
    
    address public owner;
    address public factory;

    Deployer public deployerContract;
    
    constructor () {
        owner = msg.sender;
    }

    /**
     * @notice Deploys a new instance of the Deployer contract
     * @param _owner The owner address for the Deployer contract
     * @return The address of the newly deployed Deployer contract
     */
    function deployDeployer(address _owner, address _resolver) public onlyFactory returns (address) {
        deployer = new Deployer(_owner, _resolver);
        address deployerAddress = address(deployer);

        emit DeployerCreated(deployerAddress);

        return deployerAddress;
    }

    function setFactory(address _factory) public onlyOwner {
        factory = _factory;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert OnlyOwner();
        }
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) {
            revert OnlyFactory();
        }
        _;
    }

}
