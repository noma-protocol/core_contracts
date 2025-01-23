// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { GonsToken } from "../staking/Gons.sol";
import { Staking } from "../staking/Staking.sol";
import { IAddressResolver }  from "../interfaces/IAddressResolver.sol";
import "../libraries/Utils.sol";

contract ExtFactory {
    event DeployerCreated(address deployerAddress);

    error OnlyFactory();
    
    IAddressResolver public resolver;
    Staking public stakingContract;
    GonsToken public gonsToken;

    constructor (address _resolver) {
        resolver = IAddressResolver(_resolver);
    }

    function deployAll(
        address deployerAddress,
        address vaultAddress,
        address token0
    ) public onlyFactory returns (address, address) {

        // Deploy GonsToken contract
        gonsToken = new GonsToken(deployerAddress);

        // Deploy Staking contract
        stakingContract = new Staking(token0, address(gonsToken), vaultAddress);

        emit DeployerCreated(address(stakingContract));

        // Return addresses
        return (address(gonsToken), address(stakingContract));
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
