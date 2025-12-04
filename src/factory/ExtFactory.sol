
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { GonsToken } from "../token/Gons.sol";
import { Staking } from "../staking/Staking.sol";
import { IAddressResolver }  from "../interfaces/IAddressResolver.sol";
import { Utils } from "../libraries/Utils.sol";
import { TokenRepo } from "../TokenRepo.sol";
import { vToken } from "../token/vToken/vToken.sol";
import { VaultDescription, VaultInfo, ExtDeployParams} from "../types/Types.sol";
import { IVault } from "../interfaces/IVault.sol";

interface INomaFactory {
    function getVaultsRepository(address vault) external view returns (VaultDescription memory);
}
 
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
    error OnlyFactoryOrOwner();
    error AlreadyInitialized();

    /// @notice Address resolver used to retrieve contract addresses.
    IAddressResolver public resolver;

    /// @notice Instance of the deployed `Staking` contract.
    Staking public stakingContract;

    /// @notice Instance of the deployed `GonsToken` contract.
    GonsToken public gonsToken;

    /// @notice Instance of the deployed `TokenRepo` contract.
    TokenRepo public tokenRepo;

    /// @notice Instance of the deployed `vToken` contract.
    vToken public vtoken;

    /**
     * @notice Constructs the `ExtFactory` contract.
     * @dev Sets the address resolver for contract address resolution.
     * @param _resolver The address of the `IAddressResolver` contract.
     */
    constructor(address _resolver) {
        resolver = IAddressResolver(_resolver);
    }

    function deployAll(
        ExtDeployParams memory params
    ) external onlyFactoryOrOwner(params.vaultAddress) returns (
        address gonsTokenAddress, 
        address stakingContractAddress, 
        address tokenRepoAddress,
        address vtokenAddress
    ) {
        VaultInfo memory vaultInfo = IVault(params.vaultAddress).getVaultInfo();

        if (vaultInfo.initialized) {
            revert AlreadyInitialized();
        }

        // Deploy GonsToken contract
        gonsToken = new GonsToken(
            string(abi.encodePacked(params.name, " Staked")), 
            string(abi.encodePacked("s", params.symbol)),
            params.totalSupply
        );

        // Deploy Staking contract
        stakingContract = new Staking(params.token0, address(gonsToken), params.vaultAddress);

        // Deploy Token Repo contract
        tokenRepo = new TokenRepo(params.vaultAddress);

        // Deploy vToken contract
        vtoken = new vToken(
            address(resolver),
            params.vaultAddress,
            params.token0,
            string(abi.encodePacked("v", params.symbol)),
            string(abi.encodePacked("v", params.symbol))
        );

        emit DeployerCreated(address(stakingContract));

        // Return addresses of the deployed contracts
        return (address(gonsToken), address(stakingContract), address(tokenRepo), address(vtoken));
    }    

    /**
     * @notice Ensures that only the authorized factory can call certain functions.
     * @dev Uses the Address Resolver to retrieve the factory address.
     *      Reverts with `OnlyFactory()` if the caller is not the registered factory.
     */
    modifier onlyFactoryOrOwner(address vaultAddress) {
        address factory = resolver.requireAndGetAddress(
            Utils.stringToBytes32("NomaFactory"), 
            "no factory"
        );        
        
        VaultDescription memory vaultDesc = 
        INomaFactory(factory).getVaultsRepository(vaultAddress);


        if (msg.sender != factory && msg.sender != vaultDesc.deployer) {
            revert OnlyFactoryOrOwner();
        }
        _;
    }
}
