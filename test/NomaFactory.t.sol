// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { NomaFactory } from "../src/factory/NomaFactory.sol";
import { TestResolver } from "./resolver/Resolver.sol";
import { DeployerFactory } from "../src/factory/DeployerFactory.sol";
import { ExtFactory } from "../src/factory/ExtFactory.sol";
import { EtchVault } from "../src/vault/deploy/EtchVault.sol";
import { TokenFactory } from "../src/factory/TokenFactory.sol";

import { 
    VaultUpgrade, 
    VaultUpgradeStep1, 
    VaultUpgradeStep2
} from "../src/vault/init/VaultUpgrade.sol";

import { VaultFinalize } from "../src/vault/init/VaultFinalize.sol";

import { 
    VaultDeployParams,
    PresaleUserParams, 
    VaultDescription, 
    ProtocolParameters 
} from "../src/types/Types.sol";

import "../src/libraries/Utils.sol";
import { ModelHelper } from "../src/model/Helper.sol";
import { AdaptiveSupply } from "../src/controllers/supply/AdaptiveSupply.sol";
import { PresaleFactory } from "../src/factory/PresaleFactory.sol";

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
    TokenFactory tokenFactory;

    // Constants
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    ContractInfo[] private expectedAddressesInResolver;

    function setUp() public {
        vm.prank(deployer);

        // Model Helper
        modelHelper = new ModelHelper();
        
        expectedAddressesInResolver.push(
            ContractInfo("ModelHelper", address(modelHelper))
        );

        // Resolver
        resolver = new TestResolver(deployer);

        expectedAddressesInResolver.push(
            ContractInfo("Resolver", address(resolver))
        );  

        // Presale Factory
        PresaleFactory presaleFactory = new PresaleFactory(address(resolver));

        expectedAddressesInResolver.push(
            ContractInfo("PresaleFactory", address(presaleFactory))
        );

        // Adaptive Supply
        adaptiveSupply = new AdaptiveSupply();

        expectedAddressesInResolver.push(
            ContractInfo("AdaptiveSupply", address(adaptiveSupply))
        );

        // Token Factory
        tokenFactory = new TokenFactory(address(resolver));

        expectedAddressesInResolver.push(
            ContractInfo("TokenFactory", address(tokenFactory))
        );
        
        // Deployer contracts factory
        DeployerFactory deploymentFactory = new DeployerFactory(address(resolver));
        // External contracts factory
        ExtFactory extFactory = new ExtFactory(address(resolver));

        vm.prank(deployer);
        // Noma Factory
        nomaFactory = new NomaFactory(
            uniswapFactory,
            address(resolver),
            address(deploymentFactory),
            address(extFactory),
            address(presaleFactory)
        );

        expectedAddressesInResolver.push(
            ContractInfo("NomaFactory", address(nomaFactory))
        );
        
        vm.prank(deployer);
        etchVault = new EtchVault(address(nomaFactory), address(resolver));
        vaultUpgrade = new VaultUpgrade(deployer, address(nomaFactory));
        VaultUpgradeStep1 vaultUpgradeStep1 = new VaultUpgradeStep1(deployer);
        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer);        
        VaultFinalize vaultFinalize = new VaultFinalize(deployer);
       
        vm.prank(deployer);
        vaultUpgrade.init(address(vaultUpgradeStep1));
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

        vm.prank(deployer);
        configureResolver();

        ProtocolParameters memory _params =
        ProtocolParameters(
            10,         // Floor percentage of total supply
            5,          // Anchor percentage of total supply
            3,          // IDO price multiplier
            [200, 500], // Floor bips
            90e16,      // Shift liquidity ratio
            120e16,     // Slide liquidity ratio
            25000,      // Discovery deploy bips
            10,         // shiftAnchorUpperBips
            300,        // slideAnchorUpperBips
            100,        // lowBalanceThresholdFactor
            100,        // highBalanceThresholdFactor
            5e15,       // inflationFee
            27,         // loanFee
            0.01e18,    // deployFee (ETH)
            25e16       // presalePremium (25%)
        );

        vm.prank(deployer);
        nomaFactory.setProtocolParameters(_params);
    }

    function testCreateVaultShouldRevert() public {
        VaultDeployParams memory vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                1e18,         // IDO Price
                0,
                WETH,         // Token1 address
                3000,         // Uniswap V3 Fee tier
                0             // Presale
            );

        // 1. Expect revert using custom error signature
        vm.expectRevert(abi.encodeWithSignature("AddressNotFound(string)", "not a reserve token"));
        
        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams
        );
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
                1e18,         // IDO Price
                0,
                WETH,         // Token1 address
                3000,         // Uniswap V3 Fee tier
                0             // Presale
            );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams
        );

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
                1e18,         // IDO Price
                0,
                WETH,         // Token1 address
                3000,         // Uniswap V3 Fee tier
                0             // Presale
            );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams
        );

        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(true);

        vaultDeployParams = 
            VaultDeployParams(
                "Noma Token", // Name
                "NOMA",       // Symbol
                18,           // Decimals
                100e18,       // Total supply
                1e18,         // IDO Price
                0,
                WETH,         // Token1 address
                3000,         // Uniswap V3 Fee tier
                0             // Presale
            );

        vm.expectRevert(abi.encodeWithSignature("TokenAlreadyExistsError()"));

        // 1. Call the function
        vm.prank(user);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams
        );

    }

    function testLiquidityStructureMatches() public {
        ProtocolParameters memory _params =
        ProtocolParameters(
            10,         // Floor percentage of total supply
            5,          // Anchor percentage of total supply
            3,          // IDO price multiplier
            [200, 500], // Floor bips
            90e16,      // Shift liquidity ratio
            120e16,     // Slide liquidity ratio
            25000,      // Discovery deploy bips
            10,         // shiftAnchorUpperBips
            300,        // slideAnchorUpperBips
            100,        // lowBalanceThresholdFactor
            100,        // highBalanceThresholdFactor
            5e15,       // inflationFee
            27,         // loanFee
            0.01e18,    // deployFee (ETH)
            25e16       // presalePremium (25%)
        );

        vm.prank(deployer);
        nomaFactory.setProtocolParameters(_params);

        ProtocolParameters memory _params2 = nomaFactory.getProtocolParameters();

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
                1e18,         // IDO Price
                0,
                WETH,         // Token1 address
                3000,         // Uniswap V3 Fee tier
                0             // Presale
            );

        vm.expectRevert(abi.encodeWithSignature("NotAuthorityError()"));

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams
        );
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
                1e18,         // IDO Price
                0,
                WETH,         // Token1 address
                3000,         // Uniswap V3 Fee tier
                0             // Presale
            );

        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(true);

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams
        );
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
                1e18,         // IDO Price
                0,
                WETH,         // Token1 address
                3000,         // Uniswap V3 Fee tier
                0             // Presale
            );

        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(true);

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams
        );
        // Check deployers
        address[] memory deployersList = nomaFactory.getDeployers();

        // Get Vaults
        address[] memory vaults = nomaFactory.getVaults(deployer);

        // Check vaults
        VaultDescription memory vaultDesc = nomaFactory.getVaultDescription(vaults[0]);     

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
                1e18,         // IDO Price
                0,
                WETH,         // Token1 address
                3000,         // Uniswap V3 Fee tier
                0             // Presale
            );

        // 1. Call the function
        vm.prank(user);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams
        );

        // Check deployers
        deployersList = nomaFactory.getDeployers();

        // Get Vaults
        vaults = nomaFactory.getVaults(user);

        // Check vaults
        vaultDesc = nomaFactory.getVaultDescription(vaults[0]); 

        assertEq(deployersList.length, 2);
        assertEq(vaultDesc.deployer, deployersList[1]);
        assertEq(deployersList[1], user);
        assertEq(vaultDesc.token1, WETH);

    }

    function testDeployerCanDeployMultipleVaults() public {
        // Prepare Resolver
        expectedAddressesInResolver.push(
            ContractInfo("WETH", WETH)
        );
        configureResolver();

        // Vault 1 parameters
        VaultDeployParams memory vault1Params = VaultDeployParams(
            "Vault One Token",  // Name
            "V1",               // Symbol
            18,                 // Decimals
            100e18,             // Total supply
            1e18,               // IDO Price
            0,
            WETH,               // Token1 address
            3000,               // Uniswap V3 Fee tier
            0                   // Presale
        );

        // Vault 2 parameters
        VaultDeployParams memory vault2Params = VaultDeployParams(
            "Vault Two Token",  // Name
            "V2",               // Symbol
            18,                 // Decimals
            200e18,             // Total supply
            2e18,               // IDO Price
            0,
            WETH,               // Token1 address
            3000,               // Uniswap V3 Fee tier
            0                   // Presale
        );

        // Set permissionless deploy to allow multiple vaults
        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(true);

        PresaleUserParams memory presaleParams1 =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams1,
            vault1Params
        );

        // Deploy Vault 2
        PresaleUserParams memory presaleParams2 =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams2,
            vault2Params
        );

        // Retrieve deployer's vaults
        address[] memory vaults = nomaFactory.getVaults(deployer);

        // Validate number of vaults
        assertEq(vaults.length, 2);

        // Validate Vault 1 details
        VaultDescription memory vault1Desc = nomaFactory.getVaultDescription(vaults[0]);

        assertEq(vault1Desc.token1, WETH);

        // Validate Vault 2 details
        VaultDescription memory vault2Desc = nomaFactory.getVaultDescription(vaults[1]);

        assertEq(vault2Desc.token1, WETH);

        // Validate deployers list
        address[] memory deployersList = nomaFactory.getDeployers();
        assertEq(deployersList.length, 1);
        assertEq(deployersList[0], deployer);
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
            vm.prank(deployer);
            resolver.importAddresses(names, addresses);
        }

        areAddressesInResolver = resolver.areAddressesImported(names, addresses);
        console.log("Addresses are imported in resolver: %s", areAddressesInResolver);
    }
}