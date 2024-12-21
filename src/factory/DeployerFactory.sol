// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Deployer } from "../Deployer.sol";

contract DeployerFactory {
    
    event DeployerCreated(address deployerAddress);

    /**
     * @notice Deploys a new instance of the Deployer contract
     * @param _owner The owner address for the Deployer contract
     * @return The address of the newly deployed Deployer contract
     */
    function deployDeployer(address _owner, address _resolver) public returns (address) {
        Deployer deployer = new Deployer(_owner, _resolver);
        address deployerAddress = address(deployer);

        emit DeployerCreated(deployerAddress);

        return deployerAddress;
    }

}
