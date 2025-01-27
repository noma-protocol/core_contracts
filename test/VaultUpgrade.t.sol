// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VaultUpgradeSimple} from "./vault_upgrade/init/VaultUpgradeSimple.sol";
import {VaultUpgradeExt} from "./vault_upgrade/init/VaultUpgradeExt.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";

interface IVault {
    function shift() external;
    function extraFunction() external;
}

contract TestVaultUpgrade is Test {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    address diamond = 0x1b26D84372D1F8699a3a71801B4CA757B95C9929;
    
    function setUp() public {
        // setup code
    }

    function downgrade() public {
        vm.startBroadcast(privateKey);

        VaultUpgradeSimple vaultUpgrade = new VaultUpgradeSimple(deployer);
        console.log("VaultUpgradeSimple deployed to address: ", address(vaultUpgrade));
    
        IDiamond diamondContract = IDiamond(diamond);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the diamond");
    
        IDiamond(diamond).transferOwnership(address(vaultUpgrade));

        vaultUpgrade.doUpgradeStart(diamond);

        vm.stopBroadcast();
    }

    function upgrade() public {
        vm.startBroadcast(privateKey);

        VaultUpgradeExt vaultUpgrade = new VaultUpgradeExt(deployer);
        console.log("VaultUpgradeExt deployed to address: ", address(vaultUpgrade));
    
        IDiamond diamondContract = IDiamond(diamond);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the diamond");
    
        IDiamond(diamond).transferOwnership(address(vaultUpgrade));

        vaultUpgrade.doUpgradeStart(diamond);

        vm.stopBroadcast();
    }

    function testDowngradeFunctionality() public {
        downgrade();  
        vm.expectRevert(abi.encodeWithSignature("DisabledFunction()"));
        IVault(diamond).shift();
    }

    function testUpgradeFunctionality() public {
        upgrade();  
        vm.expectRevert(abi.encodeWithSignature("DisabledFunction()"));
        IVault(diamond).extraFunction();
    }

    function testOnlyDeployerCanUpgrade() public {
        // Attempt to upgrade the vault using an unauthorized user
        address unauthorizedUser = address(0x123456);
        vm.startPrank(unauthorizedUser);

        VaultUpgradeExt unauthorizedUpgrade = new VaultUpgradeExt(unauthorizedUser);

        vm.expectRevert(abi.encodeWithSignature("NotDiamondOwner()"));

        // vm.expectRevert("Deployer is not the owner of the diamond");
        IDiamond(diamond).transferOwnership(address(unauthorizedUpgrade));
        vm.stopPrank();

        // Ensure deployer can still upgrade
        vm.startPrank(deployer);

        VaultUpgradeExt validUpgrade = new VaultUpgradeExt(deployer);
        console.log("VaultUpgradeExt deployed to address: ", address(validUpgrade));

        IDiamond diamondContract = IDiamond(diamond);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the diamond");

        IDiamond(diamond).transferOwnership(address(validUpgrade));
        validUpgrade.doUpgradeStart(diamond);

        vm.stopPrank();
    }

}