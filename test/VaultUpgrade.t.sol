// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VaultUpgradeSimple} from "./vault_upgrade/init/VaultUpgradeSimple.sol";
import {VaultUpgradeExt} from "./vault_upgrade/init/VaultUpgradeExt.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {ModelHelper} from  "../src/model/Helper.sol";
import {BaseVault} from "../src/vault/BaseVault.sol";

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

contract TestVaultUpgrade is Test {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;

    function setUp() public {
        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);

        string memory networkId = "56";
        // Parse the data for network ID `56`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Model Helper Address:", addresses.ModelHelper);

        // Extract addresses from JSON
        idoManager = payable(addresses.IDOHelper);
        nomaToken = addresses.Proxy;
        modelHelperContract = addresses.ModelHelper;
        
        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");
        
        ModelHelper modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        console.log("Vault address is: ", vaultAddress);        
    }

    function downgrade() public {
        vm.startBroadcast(privateKey);

        VaultUpgradeSimple vaultUpgrade = new VaultUpgradeSimple(deployer);
        console.log("VaultUpgradeSimple deployed to address: ", address(vaultUpgrade));
    
        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");
    
        IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));

        vaultUpgrade.doUpgradeStart(vaultAddress);

        vm.stopBroadcast();
    }

    function upgrade() public {
        vm.startBroadcast(privateKey);

        VaultUpgradeExt vaultUpgrade = new VaultUpgradeExt(deployer);
        console.log("VaultUpgradeExt deployed to address: ", address(vaultUpgrade));
    
        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");
    
        IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));

        vaultUpgrade.doUpgradeStart(vaultAddress);

        vm.stopBroadcast();
    }

    function testDowngradeFunctionality() public {
        downgrade();  
        vm.expectRevert(abi.encodeWithSignature("DisabledFunction()"));
        IVault(vaultAddress).shift();
    }

    function testUpgradeFunctionality() public {
        upgrade();  
        vm.expectRevert(abi.encodeWithSignature("DisabledFunction()"));
        IVault(vaultAddress).extraFunction();
    }

    function testOnlyDeployerCanUpgrade() public {
        // Attempt to upgrade the vault using an unauthorized user
        address unauthorizedUser = address(0x123456);
        vm.startPrank(unauthorizedUser);

        VaultUpgradeExt unauthorizedUpgrade = new VaultUpgradeExt(unauthorizedUser);

        vm.expectRevert(abi.encodeWithSignature("NotDiamondOwner()"));

        // vm.expectRevert("Deployer is not the owner of the vaultAddress");
        IDiamond(vaultAddress).transferOwnership(address(unauthorizedUpgrade));
        vm.stopPrank();

        // Ensure deployer can still upgrade
        vm.startPrank(deployer);

        VaultUpgradeExt validUpgrade = new VaultUpgradeExt(deployer);
        console.log("VaultUpgradeExt deployed to address: ", address(validUpgrade));

        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");

        IDiamond(vaultAddress).transferOwnership(address(validUpgrade));
        validUpgrade.doUpgradeStart(vaultAddress);

        vm.stopPrank();
    }

}