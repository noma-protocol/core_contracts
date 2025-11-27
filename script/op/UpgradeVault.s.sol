// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {VaultUpgradeLendingOpsExec} from "./upgrade/VaultUpgradeLendingOps.sol";
import {VaultUpgradeExt} from "./upgrade/VaultUpgradeExt.sol";
import {VaultUpgradeLending} from "./upgrade/VaultUpgradeLending.sol";
import {VaultUpgradeStaking} from "./upgrade/VaultUpgradeStaking.sol";
import {AuxVault} from "../../src/vault/AuxVault.sol";
import {IDiamond} from "../../src/interfaces/IDiamond.sol";
import {ModelHelper} from  "../../src/model/Helper.sol";
import {BaseVault} from "../../src/vault/BaseVault.sol";

interface IDOManager {
    function vault() external view returns (BaseVault);
    function buyTokens(uint256 price, uint256 amount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
    function modelHelper() external view returns (address);
}

interface IVault {
    function shift() external;
    function extraFunction() external;
}

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

interface IFactory {
    function setVaultOwnership(address vaultAddress, address newOwner) external;
}

interface IVault2 {
    function owner() external returns (address);
}

contract TestVaultUpgrade is Script {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;
    address factory;
    address vaultUpgrade;

    function run() public {
         vm.startBroadcast(privateKey);
        //IDOManager managerContract = IDOManager(0xB7B9f5a5Cce8Ef8cCBbEefd3eE5daE64d48CDC40);
        vaultAddress = 0xeC526f0718Fe1110763C53bF5b94857611371134; //address(managerContract.vault());
        factory = 0x94B47BbcFc5240C088bD4D1DF8b615b163eb6218;
        vaultUpgrade = 0x01D02757A8738869eec5967b777E01780e940f12;

        //transferOwnership();
        doUpgradeAux();
        // doUpgradeExt();
        // doUpgradeLending();
        // doUpgradeStaking();
    }

    function transferOwnership() public {
        VaultUpgradeLendingOpsExec vaultUpgradeContract = VaultUpgradeLendingOpsExec(vaultUpgrade);
        IFactory(factory).setVaultOwnership(vaultAddress, deployer);
        IDiamond(vaultAddress).transferOwnership(address(vaultUpgradeContract));
    }

    function doUpgradeAux() public {
        // vm.startBroadcast(privateKey);
        // VaultUpgradeLendingOpsExec vaultUpgrade = new VaultUpgradeLendingOpsExec(deployer, factory);
        // console.log("VaultUpgradeLendingOpsExec deployed to address: ", address(vaultUpgrade));
        // IFactory(factory).setVaultOwnership(vaultAddress, deployer);
        address currentOwner = IVault2(vaultAddress).owner();
        console.log("Current owner is ", currentOwner);

        VaultUpgradeLendingOpsExec vaultUpgradeContract = VaultUpgradeLendingOpsExec(vaultUpgrade);

        IDiamond diamondContract = IDiamond(vaultAddress);
        // require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");
        
        // IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));

        vaultUpgradeContract.doUpgradeStart(vaultAddress);
       

        // ModelHelper modelHelper =  new ModelHelper();
        // AuxVault auxVault = AuxVault(vaultAddress);
        // auxVault.setModelHelper(address(modelHelper));
        
        vm.stopBroadcast();

        // console.log("ModelHelper set in AuxVault at address: ", address(modelHelper));
    }

    function doUpgradeExt() public {
        vm.startBroadcast(privateKey);
        VaultUpgradeExt vaultUpgrade = new VaultUpgradeExt(deployer);
        console.log("VaultUpgradeExt deployed to address: ", address(vaultUpgrade));

        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");
        
        IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));

        vaultUpgrade.doUpgradeStart(vaultAddress);
        vm.stopBroadcast();
    }

    function doUpgradeLending() public {
        vm.startBroadcast(privateKey);
        VaultUpgradeLending vaultUpgrade = new VaultUpgradeLending(deployer);
        console.log("VaultUpgradeLending deployed to address: ", address(vaultUpgrade));

        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");
        
        IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));

        vaultUpgrade.doUpgradeStart(vaultAddress);
        vm.stopBroadcast();
    }

    function doUpgradeStaking() public {
        vm.startBroadcast(privateKey);
        VaultUpgradeStaking vaultUpgrade = new VaultUpgradeStaking(deployer);
        console.log("VaultUpgradeStaking deployed to address: ", address(vaultUpgrade));

        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");
        
        IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));

        vaultUpgrade.doUpgradeStart(vaultAddress);
        vm.stopBroadcast();
    }


}