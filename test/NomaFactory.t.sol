// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { NomaFactory } from "../src/factory/NomaFactory.sol";
import { TestResolver } from "./resolver/Resolver.sol";
import { DeployerFactory } from "../src/factory/DeployerFactory.sol";
import { ExtFactory } from "../src/factory/ExtFactory.sol";
import { EtchVault } from "../src/vault/deploy/EtchVault.sol";

import { 
    VaultUpgrade, 
    VaultUpgradeStep1, 
    VaultUpgradeStep2
} from "../src/vault/init/VaultUpgrade.sol";

import { VaultFinalize } from "../src/vault/init/VaultFinalize.sol";

import { 
    VaultDeployParams, 
    VaultDescription, 
    LiquidityStructureParameters 
} from "../src/types/Types.sol";

import "../src/libraries/Utils.sol";
import { ModelHelper } from "../src/model/Helper.sol";
import { AdaptiveSupply } from "../src/controllers/supply/AdaptiveSupply.sol";

struct ContractInfo {
    string name;
    address addr;
}

contract NomaFactoryTest is Test {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    address user = address(2);

    NomaFactory nomaFactory;
    TestResolver resolver;
    EtchVault etchVault;
    VaultUpgrade vaultUpgrade;
    ModelHelper modelHelper;
    AdaptiveSupply adaptiveSupply;
    
    // Constants
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    ContractInfo[] private expectedAddressesInResolver;

    uint256[4] thresholds = [
        uint256(5e17),
        uint256(9e17),
        uint256(1e18),
        uint256(2e18)
    ];

    function setUp() public {
        vm.prank(deployer);

        // Model Helper
        modelHelper = new ModelHelper();
        
        expectedAddressesInResolver.push(
            ContractInfo("ModelHelper", address(modelHelper))
        );

        // Resolver
        resolver = new TestResolver();

        expectedAddressesInResolver.push(
            ContractInfo("Resolver", address(resolver))
        );  

        adaptiveSupply = new AdaptiveSupply(
            address(modelHelper),
            thresholds // Low, Medium, High, Extreme thresholds
        );

        expectedAddressesInResolver.push(
            ContractInfo("AdaptiveSupply", address(adaptiveSupply))
        );

        configureResolver();

        // Deployer contracts factory
        DeployerFactory deploymentFactory = new DeployerFactory();
        // External contracts factory
        ExtFactory extFactory = new ExtFactory();

        vm.prank(deployer);
        // Noma Factory
        nomaFactory = new NomaFactory(
            uniswapFactory,
            address(resolver),
            address(deploymentFactory),
            address(extFactory),
            false
        );
        
        vm.prank(deployer);
        etchVault = new EtchVault(address(nomaFactory), address(resolver));
        vaultUpgrade = new VaultUpgrade(deployer, address(nomaFactory));
        VaultUpgradeStep1 vaultUpgradeStep1 = new VaultUpgradeStep1(deployer);
        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer);        
        VaultFinalize vaultFinalize = new VaultFinalize(deployer);
       
        vm.prank(deployer);
        vaultUpgrade.init(address(0), address(vaultUpgradeStep1));
        vm.prank(deployer);
        vaultUpgradeStep1.init(address(vaultUpgradeStep2), address(vaultUpgrade));
        vm.prank(deployer);
        vaultUpgradeStep2.init(address(vaultFinalize), address(vaultUpgradeStep1));
        vm.prank(deployer);
        vaultFinalize.init(deployer, address(vaultUpgradeStep2));

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgrade", address(vaultUpgrade))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeFinalize", address(vaultFinalize))
        );

        expectedAddressesInResolver.push(
            ContractInfo("EtchVault", address(etchVault))
        );

        LiquidityStructureParameters memory _params =
        LiquidityStructureParameters(
            10, // Floor percentage of total supply
            5, // Anchor percentage of total supply
            3, // IDO price multiplier
            [200, 500], // Floor bips
            90e16, // Shift liquidity ratio
            120e16 // Slide liquidity ratio
        );

        vm.prank(deployer);
        nomaFactory.setLiquidityStructureParameters(_params);
    }

    function testCreateVaultShouldRevert() public {
        VaultDeployParams memory vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        // 1. Expect revert using custom error signature
        vm.expectRevert(abi.encodeWithSignature("AddressNotFound(string)", "not a reserve token"));
        
        vm.prank(deployer);
        // 2. Call the function
        nomaFactory.deployVault(vaultDeployParams);
    }

    function testCreateVaultShouldSucceed() public {

        expectedAddressesInResolver.push(
            ContractInfo("WETH", WETH)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(vaultDeployParams);

    }

    function testCreateDuplicateVault() public {

        expectedAddressesInResolver.push(
            ContractInfo("WETH", WETH)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(vaultDeployParams);
        
        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(true);

        vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        vm.expectRevert(abi.encodeWithSignature("TokenAlreadyExistsError()"));

        // 1. Call the function
        vm.prank(user);
        nomaFactory.deployVault(vaultDeployParams);

    }

    function testLiquidityStructureMatches() public {
        LiquidityStructureParameters memory _params =
        LiquidityStructureParameters(
            10, // Floor percentage of total supply
            5, // Anchor percentage of total supply
            3, // IDO price multiplier
            [200, 500], // Floor bips
            90e16, // Shift liquidity ratio
            120e16 // Slide liquidity ratio
        );

        vm.prank(deployer);
        nomaFactory.setLiquidityStructureParameters(_params);

        LiquidityStructureParameters memory _params2 = nomaFactory.getLiquidityStructureParameters();

        assertEq(_params.floorPercentage, _params2.floorPercentage);
        assertEq(_params.anchorPercentage, _params2.anchorPercentage);
        assertEq(_params.idoPriceMultiplier, _params2.idoPriceMultiplier);
        assertEq(_params.floorBips[0], _params2.floorBips[0]);
        assertEq(_params.floorBips[1], _params2.floorBips[1]);
        assertEq(_params.shiftRatio, _params2.shiftRatio);
        assertEq(_params.slideRatio, _params2.slideRatio);
    }

    function testPermissionlessDeployNotEnabled() public {

        expectedAddressesInResolver.push(
            ContractInfo("WETH", WETH)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        vm.expectRevert(abi.encodeWithSignature("NotAuthorityError()"));

        // 1. Call the function
        nomaFactory.deployVault(vaultDeployParams);
    }

    function testPermissionlessDeployEnabled() public {

        expectedAddressesInResolver.push(
            ContractInfo("WETH", WETH)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(true);

        // 1. Call the function
        nomaFactory.deployVault(vaultDeployParams);
    }

    function testEnumerateVaults() public {
        expectedAddressesInResolver.push(
            ContractInfo("WETH", WETH)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(true);

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(vaultDeployParams);

        // Check deployers
        address[] memory deployersList = nomaFactory.getDeployers();

        // Check vaults
        VaultDescription memory vaultDesc = nomaFactory.getVaultDescription(deployer);     

        assertEq(deployersList.length, 1);
        assertEq(vaultDesc.deployer, deployersList[0]);
        assertEq(deployersList[0], deployer);
        assertEq(vaultDesc.token1, WETH);

        vaultDeployParams = 
            VaultDeployParams(
                "Test Token", // Name
                "TEST",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        // 1. Call the function
        vm.prank(user);
        nomaFactory.deployVault(vaultDeployParams);

        // Check deployers
        deployersList = nomaFactory.getDeployers();

        for (uint256 i = 0; i < deployersList.length; i++) {
            console.log("Deployer %d: %s", i, deployersList[i]);
        }

        // Check vaults
        vaultDesc = nomaFactory.getVaultDescription(user);     

        assertEq(deployersList.length, 2);
        assertEq(vaultDesc.deployer, deployersList[1]);
        assertEq(deployersList[1], user);
        assertEq(vaultDesc.token1, WETH);
    }

    function testOnlyOneVaultPerDeployer() public {
        expectedAddressesInResolver.push(
            ContractInfo("WETH", WETH)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(true);

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(vaultDeployParams);

        // Check deployers
        address[] memory deployersList = nomaFactory.getDeployers();

        // Check vaults
        VaultDescription memory vaultDesc = nomaFactory.getVaultDescription(deployer);     

        assertEq(deployersList.length, 1);
        assertEq(vaultDesc.deployer, deployersList[0]);
        assertEq(deployersList[0], deployer);
        assertEq(vaultDesc.token1, WETH);

        vaultDeployParams = 
            VaultDeployParams(
                "Test Token", // Name
                "TEST",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                10,           // Percentage for sale
                1e18,         // IDO Price
                WETH          // Token1 address
            );

        // 1. Call the function
        vm.expectRevert(abi.encodeWithSignature("OnlyOneVaultError()"));

        vm.prank(deployer);
        nomaFactory.deployVault(vaultDeployParams);
    }

    function configureResolver() internal {
        bytes32[] memory names = new bytes32[](expectedAddressesInResolver.length);
        address[] memory addresses = new address[](expectedAddressesInResolver.length);

        for (uint256 i = 0; i < expectedAddressesInResolver.length; i++) {
            names[i] = Utils.stringToBytes32(expectedAddressesInResolver[i].name);
            addresses[i] = expectedAddressesInResolver[i].addr;
        }

        bool areAddressesInResolver = resolver.areAddressesImported(names, addresses);

        if (!areAddressesInResolver) {
            resolver.importAddresses(names, addresses);
        }

        areAddressesInResolver = resolver.areAddressesImported(names, addresses);
        console.log("Addresses are imported in resolver: %s", areAddressesInResolver);
    }
}