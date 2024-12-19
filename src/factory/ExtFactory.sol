// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { GonsToken } from "../staking/Gons.sol";
import { Staking } from "../staking/Staking.sol";

contract ExtFactory {
    
    function deployAll(
        address deployerAddress,
        address vaultAddress,
        address token0
    ) external returns (address, address) {

        // Deploy GonsToken contract
        GonsToken gonsToken = new GonsToken(deployerAddress);

        // Deploy Staking contract
        Staking stakingContract = new Staking(token0, address(gonsToken), vaultAddress);

        // Return addresses
        return (address(gonsToken), address(stakingContract));
    }    
}
