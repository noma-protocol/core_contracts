// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { GonsToken } from "../token/Gons.sol";
import { Staking } from "../staking/Staking.sol";
import { IAddressResolver }  from "../interfaces/IAddressResolver.sol";
import { Utils } from "../libraries/Utils.sol";
import { TokenRepo } from "../TokenRepo.sol";

/**
 * @title ExtFactory
 * @dev This contract is responsible for deploying both `GonsToken` and `Staking` contracts.
 *      It ensures that only an authorized factory (retrieved from the Address Resolver)
 *      can call the deployment function.
 */
contract ExtFactory {
    
    /// @notice Emitted when a new `Staking` contract is created.
    /// @param deployerAddress The address of the newly deployed `Staking` contract.
    event DeployerCreated(address deployerAddress);

    /// @notice Error thrown when the caller is not the authorized factory.
    error OnlyFactory();
    
    /// @notice Address resolver used to retrieve contract addresses.
    IAddressResolver public resolver;

    /// @notice Instance of the deployed `Staking` contract.
    Staking public stakingContract;

    /// @notice Instance of the deployed `GonsToken` contract.
    GonsToken public gonsToken;

    /// @notice Instance of the deployed `TokenRepo` contract.
    TokenRepo public tokenRepo;

    /**
     * @notice Constructs the `ExtFactory` contract.
     * @dev Sets the address resolver for contract address resolution.
     * @param _resolver The address of the `IAddressResolver` contract.
     */
    constructor(address _resolver) {
        resolver = IAddressResolver(_resolver);
    }

    /**
     * @notice Deploys both `GonsToken` and `Staking` contracts.
     * @dev This function can only be called by the factory contract registered in the resolver.
     * @param deployerAddress The address that will be assigned as the owner of `GonsToken`.
     * @param vaultAddress The vault address for `Staking` contract.
     * @param token0 The address of the token that will be staked.
     * @return gonsTokenAddress The address of the newly deployed `GonsToken` contract.
     * @return stakingContractAddress The address of the newly deployed `Staking` contract.
     * @custom:require Only callable by the factory contract.
     */
    function deployAll(
        address deployerAddress,
        address vaultAddress,
        address token0
    ) external onlyFactory returns (
        address gonsTokenAddress, 
        address stakingContractAddress, 
        address tokenRepoAddress
    ) {

        // Deploy GonsToken contract
        gonsToken = new GonsToken(address(this));

        // Deploy Staking contract
        stakingContract = new Staking(token0, address(gonsToken), vaultAddress);

        // Deploy Token Repo contract
        tokenRepo = new TokenRepo(vaultAddress);

        emit DeployerCreated(address(stakingContract));

        // Return addresses of the deployed contracts
        return (address(gonsToken), address(stakingContract), address(tokenRepo));
    }    

    /**
     * @notice Ensures that only the authorized factory can call certain functions.
     * @dev Uses the Address Resolver to retrieve the factory address.
     *      Reverts with `OnlyFactory()` if the caller is not the registered factory.
     */
    modifier onlyFactory() {
        address factory = resolver.requireAndGetAddress(
            Utils.stringToBytes32("NomaFactory"), 
            "no factory"
        );        
        if (msg.sender != factory) {
            revert OnlyFactory();
        }
        _;
    }
}
