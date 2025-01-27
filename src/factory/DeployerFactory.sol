// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Deployer } from "../Deployer.sol";
import { IAddressResolver }  from "../interfaces/IAddressResolver.sol";
import "../libraries/Utils.sol";

contract DeployerFactory {
    
    event DeployerCreated(address deployerAddress);
    error OnlyOwner();
    error OnlyFactory();
    
    Deployer public deployer;
    IAddressResolver public resolver;

    constructor (address _resolver) {
        resolver = IAddressResolver(_resolver);
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


    modifier onlyFactory() {
        address factory = resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("NomaFactory"), 
                    "no factory"
                );        
        if (msg.sender != factory) {
            revert OnlyFactory();
        }
        _;
    }

}
