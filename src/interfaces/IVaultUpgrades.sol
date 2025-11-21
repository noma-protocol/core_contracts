// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IVaultUpgrade
 * @notice Interface for initiating and finalizing vault upgrades.
 */
interface IVaultUpgrade {
    /**
     * @notice Initiates the upgrade process for a vault.
     * @param diamond The address of the diamond contract to be upgraded.
     * @param _vaultUpgradeFinalize The address of the contract responsible for finalizing the upgrade.
     */
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;

    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize, bool isExtended) external;
    function doUpgradeStart(address diamond) external;

    /**
     * @notice Finalizes the upgrade process for a vault.
     * @param diamond The address of the diamond contract that has been upgraded.
     */
    function doUpgradeFinalize(address diamond) external;
}

/**
 * @title IEtchVault
 * @notice Interface for pre-deploying a vault.
 */
interface IEtchVault {
    /**
     * @notice Pre-deploys a vault using the provided resolver.
     * @param _resolver The address of the resolver contract.
     * @return vaultAddress The address of the pre-deployed vault.
     * @return vaultUpgrade The address of the associated vault upgrade contract.
     */
    function preDeployVault(address _resolver) external returns (address vaultAddress, address vaultUpgrade);
}

/**
 * @title IExtFactory
 * @notice Interface for deploying auxiliary contracts related to a vault.
 */
interface IExtFactory {
    /**
     * @notice Deploys all necessary auxiliary contracts for a vault.
     * @param name The name of the token to be created.
     * @param symbol The symbol of the token to be created.
     * @param deployerAddress The address of the deployer initiating the process.
     * @param vaultAddress The address of the vault for which auxiliary contracts are being deployed.
     * @param token0 The address of the primary token associated with the vault.
     * @return auxiliaryContract1 The address of the first auxiliary contract deployed.
     * @return auxiliaryContract2 The address of the second auxiliary contract deployed.
     */
    function deployAll(
        string memory name,
        string memory symbol,
        address deployerAddress,
        address vaultAddress,
        address token0
    ) external returns (
        address auxiliaryContract1, 
        address auxiliaryContract2, 
        address auxiliaryContract3,
        address auxiliaryContract4
    );
}

/**
 * @title IDeployerFactory
 * @notice Interface for deploying a Deployer contract.
 */
interface IDeployerFactory {
    /**
     * @notice Deploys a new Deployer contract.
     * @param owner The address designated as the owner of the new Deployer contract.
     * @param resolver The address of the resolver contract to be associated with the Deployer.
     * @return deployer The address of the newly deployed Deployer contract.
     */
    function deployDeployer(address owner, address resolver) external returns (address deployer);
}
