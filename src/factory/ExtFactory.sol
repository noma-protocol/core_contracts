// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { GonsToken } from "../staking/Gons.sol";
import { Staking } from "../staking/Staking.sol";

contract ExtFactory {
    event DeployerCreated(address deployerAddress);

    error OnlyOwner();
    error OnlyFactory();
    
    address public owner;
    address public factory;

    Staking public stakingContract;
    GonsToken public gonsToken;
    
    constructor () {
        owner = msg.sender;
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
