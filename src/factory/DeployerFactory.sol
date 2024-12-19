// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Deployer } from "../Deployer.sol";

contract DeployerFactory {
    
    event DeployerCreated(address deployerAddress);

    /**
     * @notice Deploys a new instance of the Deployer contract
     * @param owner The owner address for the Deployer contract
     * @return The address of the newly deployed Deployer contract
     */
    function deployDeployer(address owner) public returns (address) {
        Deployer deployer = new Deployer(owner);
        address deployerAddress = address(deployer);

        emit DeployerCreated(deployerAddress);

        return deployerAddress;
    }

}
