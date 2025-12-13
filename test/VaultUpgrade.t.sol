// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {VaultUpgradeSimple} from "./vault_upgrade/init/VaultUpgradeSimple.sol";
import {VaultUpgradeExt} from "./vault_upgrade/init/VaultUpgradeExt.sol";
import {VaultUpgradeAux} from "./vault_upgrade/init/VaultUpgradeAux.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {ModelHelper} from "../src/model/Helper.sol";
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

interface INomaFactory {
    function owner() external view returns (address);
    function setVaultOwnership(address vaultAddress, address newOwner) external;
}

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

contract TestVaultUpgrade is Test {
    using stdJson for string;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;
    address factoryAddress;

    function setUp() public {
        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        // Parse individual fields to avoid struct ordering issues
        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));
        modelHelperContract = vm.parseJsonAddress(json, string.concat(".", networkId, ".ModelHelper"));
        factoryAddress = vm.parseJsonAddress(json, string.concat(".", networkId, ".Factory"));

        // Log parsed addresses for verification
        console2.log("Model Helper Address:", modelHelperContract);
        console2.log("Factory Address:", factoryAddress);

        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        ModelHelper modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        console.log("Vault address is: ", vaultAddress);
        console.log("Current vault owner: ", IDiamond(vaultAddress).owner());
    }

    /// @notice Helper to transfer vault ownership from factory to deployer
    function transferOwnershipToDeployer() internal {
        address currentOwner = IDiamond(vaultAddress).owner();

        if (currentOwner == deployer) {
            // Already owned by deployer
            return;
        }

        if (currentOwner == factoryAddress) {
            // Factory owns the vault, use factory's authority to transfer
            address factoryAuthority = INomaFactory(factoryAddress).owner();
            console.log("Factory authority:", factoryAuthority);

            vm.prank(factoryAuthority);
            INomaFactory(factoryAddress).setVaultOwnership(vaultAddress, deployer);

            require(IDiamond(vaultAddress).owner() == deployer, "Failed to transfer ownership to deployer");
            console.log("Ownership transferred to deployer");
        } else {
            // Someone else owns the vault, try to impersonate them
            vm.prank(currentOwner);
            IDiamond(vaultAddress).transferOwnership(deployer);
        }
    }

    function downgrade() internal {
        // First transfer ownership to deployer if needed
        transferOwnershipToDeployer();

        vm.startPrank(deployer);

        VaultUpgradeSimple vaultUpgrade = new VaultUpgradeSimple(deployer);
        console.log("VaultUpgradeSimple deployed to address: ", address(vaultUpgrade));

        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");

        IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));
        vaultUpgrade.doUpgradeStart(vaultAddress);

        vm.stopPrank();
    }

    function upgrade() internal {
        // First transfer ownership to deployer if needed
        transferOwnershipToDeployer();

        vm.startPrank(deployer);

        VaultUpgradeExt vaultUpgrade = new VaultUpgradeExt(deployer);
        console.log("VaultUpgradeExt deployed to address: ", address(vaultUpgrade));

        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");

        IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));
        vaultUpgrade.doUpgradeStart(vaultAddress);

        vm.stopPrank();
    }

    // ============ OWNERSHIP TRANSFER TESTS ============

    function testFactoryCanTransferVaultOwnership() public {
        address currentOwner = IDiamond(vaultAddress).owner();
        console.log("Current vault owner:", currentOwner);

        if (currentOwner == factoryAddress) {
            // Get factory authority
            address factoryAuthority = INomaFactory(factoryAddress).owner();
            console.log("Factory authority:", factoryAuthority);

            // Transfer ownership via factory
            vm.prank(factoryAuthority);
            INomaFactory(factoryAddress).setVaultOwnership(vaultAddress, deployer);

            // Verify ownership transferred
            assertEq(IDiamond(vaultAddress).owner(), deployer, "Ownership should transfer to deployer");
        } else {
            console.log("Vault not owned by factory, skipping factory transfer test");
        }
    }

    function testUnauthorizedCannotTransferVaultOwnership() public {
        address currentOwner = IDiamond(vaultAddress).owner();

        if (currentOwner == factoryAddress) {
            address unauthorizedUser = address(0x123456);

            vm.prank(unauthorizedUser);
            vm.expectRevert(); // NotAuthorityError
            INomaFactory(factoryAddress).setVaultOwnership(vaultAddress, unauthorizedUser);
        } else {
            // If not factory-owned, test direct transfer rejection
            address unauthorizedUser = address(0x123456);
            vm.prank(unauthorizedUser);
            vm.expectRevert(abi.encodeWithSignature("NotDiamondOwner()"));
            IDiamond(vaultAddress).transferOwnership(unauthorizedUser);
        }
    }

    // ============ UPGRADE TESTS ============

    function testRealUpgrade() public {
        // First transfer ownership to deployer
        transferOwnershipToDeployer();

        vm.startPrank(deployer);
        VaultUpgradeAux vaultUpgrade = new VaultUpgradeAux(deployer);
        console.log("VaultUpgradeAux deployed to address: ", address(vaultUpgrade));

        IDiamond diamondContract = IDiamond(vaultAddress);
        require(diamondContract.owner() == deployer, "Deployer is not the owner of the vaultAddress");

        IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));
        vaultUpgrade.doUpgradeStart(vaultAddress);

        vm.stopPrank();
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

    function testOnlyOwnerCanUpgrade() public {
        // Transfer ownership to deployer first
        transferOwnershipToDeployer();

        // Attempt to upgrade the vault using an unauthorized user
        address unauthorizedUser = address(0x123456);
        vm.startPrank(unauthorizedUser);

        VaultUpgradeExt unauthorizedUpgrade = new VaultUpgradeExt(unauthorizedUser);

        vm.expectRevert(abi.encodeWithSignature("NotDiamondOwner()"));
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

    // ============ FACTORY UPGRADE PATH TESTS ============

    function testUpgradeThroughFactory() public {
        // This tests the upgrade flow where the factory retains ownership
        // and performs upgrades on behalf of the authority
        address currentOwner = IDiamond(vaultAddress).owner();

        if (currentOwner == factoryAddress) {
            address factoryAuthority = INomaFactory(factoryAddress).owner();

            // Factory transfers ownership to upgrade contract, then back
            // This simulates what the factory's doUpgrade function does
            vm.startPrank(factoryAuthority);

            // Transfer ownership to a new address temporarily
            INomaFactory(factoryAddress).setVaultOwnership(vaultAddress, deployer);

            vm.stopPrank();

            // Now deployer owns it, can perform upgrade
            vm.startPrank(deployer);
            VaultUpgradeAux vaultUpgrade = new VaultUpgradeAux(deployer);

            IDiamond(vaultAddress).transferOwnership(address(vaultUpgrade));
            vaultUpgrade.doUpgradeStart(vaultAddress);

            // Transfer ownership back to factory
            IDiamond(vaultAddress).transferOwnership(factoryAddress);

            vm.stopPrank();

            assertEq(IDiamond(vaultAddress).owner(), factoryAddress, "Factory should own vault again");
        } else {
            console.log("Vault not owned by factory, skipping factory upgrade test");
        }
    }
}