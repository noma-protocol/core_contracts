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
    VaultInit
} from "../../src/vault/init/VaultInit.sol";
import { 
    VaultUpgrade, 
    VaultUpgradeStep1, 
    VaultUpgradeStep2,
    VaultUpgradeStep3,
    VaultUpgradeStep4,
    VaultUpgradeStep5
} from "../src/vault/init/VaultUpgrade.sol";

import { VaultFinalize } from "../src/vault/init/VaultFinalize.sol";

import { 
    VaultDeployParams,
    PresaleUserParams, 
    VaultDescription, 
    ProtocolParameters,
    ExistingDeployData,
    Decimals
} from "../src/types/Types.sol";

import "../src/libraries/Utils.sol";
import { SupplyRules } from "../src/libraries/SupplyRules.sol";
import { ModelHelper } from "../src/model/Helper.sol";
import { AdaptiveSupply } from "../src/controllers/supply/AdaptiveSupply.sol";
import { PresaleFactory } from "../src/factory/PresaleFactory.sol";

struct ContractInfo {
    string name;
    address addr;
}

/// @notice Helper contract to test SupplyRules library reverts
contract SupplyRulesHarness {
    function getMinTotalSupplyForPrice(
        uint256 price,
        uint256 basePrice
    ) external pure returns (uint256) {
        return SupplyRules.getMinTotalSupplyForPrice(price, basePrice);
    }

    function enforceMinTotalSupply(
        uint256 price,
        uint256 totalSupply,
        uint256 basePrice
    ) external pure {
        SupplyRules.enforceMinTotalSupply(price, totalSupply, basePrice);
    }
}

/// @notice Mock WETH/WMON token for testing
contract MockWMON {
    string public name = "Wrapped MON";
    string public symbol = "WMON";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
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
    SupplyRulesHarness supplyRulesHarness;
    MockWMON mockWMON;

    // Constants mainnet
    address WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    // For SupplyRules integration tests, we use a mock
    address testWMON;
    address private uniswapFactory = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address private pancakeSwapFactory = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

    ContractInfo[] private expectedAddressesInResolver;

    function setUp() public {
        vm.prank(deployer);

        // SupplyRules Harness for testing reverts
        supplyRulesHarness = new SupplyRulesHarness();

        // Mock WMON for SupplyRules integration tests
        mockWMON = new MockWMON();
        testWMON = address(mockWMON);

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
            pancakeSwapFactory, 
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

        // VaultStep1 adds BaseVault (used by preDeployVault during deployVault)
        VaultInit vaultStep1 = new VaultInit(deployer, address(nomaFactory));

        // VaultUpgradeStep1 adds StakingVault (used by configureVault)
        // These must be different contracts!
        VaultUpgradeStep1 vaultUpgradeStep1 = new VaultUpgradeStep1(deployer, address(nomaFactory));

        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer, address(nomaFactory));
        VaultUpgradeStep3 vaultUpgradeStep3 = new VaultUpgradeStep3(deployer, address(nomaFactory));
        VaultUpgradeStep4 vaultUpgradeStep4 = new VaultUpgradeStep4(deployer, address(nomaFactory));
        VaultUpgradeStep5 vaultUpgradeStep5 = new VaultUpgradeStep5(deployer, address(nomaFactory));

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgrade", address(vaultUpgrade))
        );

        // VaultStep1 is used by preDeployVault - adds BaseVault
        expectedAddressesInResolver.push(
            ContractInfo("VaultStep1", address(vaultStep1))
        );

        // VaultUpgradeStep1 is used by configureVault - adds StakingVault
        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep1", address(vaultUpgradeStep1))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep2", address(vaultUpgradeStep2))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep3", address(vaultUpgradeStep3))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep4", address(vaultUpgradeStep4))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep5", address(vaultUpgradeStep5))
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
            25,         // maxLoanUtilization
            27,         // loanFee
            0.01e18,    // deployFee (ETH)
            25e16,      // presalePremium (25%)
            1_250,      // self repaying loan ltv treshold
            0.5e18,     // Adaptive supply curve half step
            2,          // Skim ratio  
            Decimals(6, 18), // Decimals (minDecimals, maxDecimals      
            1e14        // basePriceDecimals
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
                100_000_000_000_000e18,       // Total supply
                200_000_000_000_000e18,       // Max supply
                1e18,         // IDO Price
                0,
                WMON,          // Token1 address
                3000,         // Uniswap V3 Fee tier
                0,            // Presale
                true,         // Is fresh deploy
                true          // use Uniswap
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
        (address vault, address pool, address proxy) = 
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
        );

        
    }

    function testCreateVaultShouldSucceed() public {

        expectedAddressesInResolver.push(
            ContractInfo("WMON", WMON)
        );

        vm.prank(deployer);
        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "Noma Token", // Name
            "NOMA2",       // Symbol
            18,           // Decimals
            100_000_000_000_000e18,       // Total supply
            200_000_000_000_000e18,       // Max supply
            1e18,         // IDO Price
            0,
            WMON,         // Token1 address
            3000,         // Uniswap V3 Fee tier
            0,            // Presale
            true,         // Is fresh deploy
            true          // use Uniswap
        );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        vm.prank(deployer);
        (address vault, address pool, address proxy) = 
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );
        
        // vm.prank(deployer);
        // nomaFactory.configureVault(vault, 0);
    }

    function testCreateDuplicateVault() public {

        expectedAddressesInResolver.push(
            ContractInfo("WMON", WMON)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "Noma Token", // Name
            "NOMA",       // Symbol
            18,           // Decimals
            100_000_000e18,       // Total supply
            200e18,       // Max supply
            1e18,         // IDO Price
            0,
            WMON,         // Token1 address
            3000,         // Uniswap V3 Fee tier
            0,            // Presale
            true,         // Is fresh deploy
            true          // use Uniswap
        );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18, // softCap
            90 days // deadline
        );

        // 1. Call the function
        vm.prank(deployer);
        (address vault, address pool, address proxy) = 
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
        );

        // vm.prank(deployer);
        // nomaFactory.configureVault(vault, 0);
        // nomaFactory.setPermissionlessDeploy(true);

        // vaultDeployParams = 
        // VaultDeployParams(
        //     "Noma Token", // Name
        //     "NOMA",       // Symbol
        //     18,           // Decimals
        //     100e18,       // Total supply
        //     200e18,       // Max supply
        //     1e18,         // IDO Price
        //     0,
        //     WMON,         // Token1 address
        //     3000,         // Uniswap V3 Fee tier
        //     0,            // Presale
        //     true,         // Is fresh deploy
        //     true          // use Uniswap
        // );

        // vm.expectRevert(abi.encodeWithSignature("TokenAlreadyExistsError()"));

        // // 1. Call the function
        // vm.prank(user);
        // nomaFactory.deployVault(
        //     presaleParams,
        //     vaultDeployParams,
        //     ExistingDeployData({
        //         pool: address(0),
        //         token0: address(0)
        //     })            
        // );

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
            25,         // maxLoanUtilization
            27,         // loanFee
            0.01e18,    // deployFee (ETH)
            25e16,      // presalePremium (25%)
            1_250,      // self repaying loan ltv treshold
            0.5e18,     // Adaptive supply curve half step       
            2,          // Skim ratio 
            Decimals(6, 18), // Decimals (minDecimals, maxDecimals
            1e14        // basePriceDecimals
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
            ContractInfo("WMON", WMON)
        );

        vm.prank(deployer);
        nomaFactory.setPermissionlessDeploy(false);

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "Noma Token", // Name
            "NOMA2",       // Symbol
            18,           // Decimals
            100_000_000_000e18,       // Total supply
            200_000_000_000e18,       // Max supply
            1e18,         // IDO Price
            0,
            WMON,         // Token1 address
            3000,         // Uniswap V3 Fee tier
            0,            // Presale
            true,         // Is fresh deploy
            true          // use Uniswap
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
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
        );
    }

    function testPermissionlessDeployEnabled() public {

        expectedAddressesInResolver.push(
            ContractInfo("WMON", WMON)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "Noma Token", // Name
            "NOMA2",       // Symbol
            18,           // Decimals
            100_000_000_000e18,       // Total supply
            200_000_000_000e18,       // Max supply
            1e18,         // IDO Price
            0,
            WMON,         // Token1 address
            3000,         // Uniswap V3 Fee tier
            0,            // Presale
            true,         // Is fresh deploy
            true          // use Uniswap
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
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
        );
    }

    function testEnumerateVaults() public {
        expectedAddressesInResolver.push(
            ContractInfo("WMON", WMON)
        );

        configureResolver();    

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "Noma Token", // Name
            "NOMA",       // Symbol
            18,           // Decimals
            100_000_000e18,       // Total supply
            200_000_000e18,       // Max supply
            1e18,         // IDO Price
            0,
            WMON,         // Token1 address
            3000,         // Uniswap V3 Fee tier
            0,            // Presale
            true,         // Is fresh deploy
            true          // use Uniswap
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
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
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
        assertEq(vaultDesc.token1, WMON);

        vaultDeployParams = 
        VaultDeployParams(
            "Test Token", // Name
            "TEST",       // Symbol
            18,           // Decimals
            100_000_000e18,       // Total supply
            200_000_000e18,       // Max supply
            1e18,         // IDO Price
            0,
            WMON,         // Token1 address
            3000,         // Uniswap V3 Fee tier
            0,            // Presale
            true,         // Is fresh deploy
            true          // use Uniswap
        );


        // 1. Call the function
        vm.prank(user);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
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
        assertEq(vaultDesc.token1, WMON);

    }

    function testDeployerCanDeployMultipleVaults() public {
        // Prepare Resolver
        expectedAddressesInResolver.push(
            ContractInfo("WMON", WMON)
        );
        configureResolver();

        // Vault 1 parameters
        VaultDeployParams memory vault1Params = VaultDeployParams(
            "Vault One Token",  // Name
            "V1",               // Symbol
            18,                 // Decimals
            100_000_000e18,             // Total supply
            200_000_000e18,             // Max supply
            1e18,               // IDO Price
            0,
            WMON,               // Token1 address
            3000,               // Uniswap V3 Fee tier
            0,                  // Presale
            true,               // Is fresh deploy
            true                // use Uniswap
        );


        // Vault 2 parameters
        VaultDeployParams memory vault2Params = VaultDeployParams(
            "Vault Two Token",  // Name
            "V2",               // Symbol
            18,                 // Decimals
            200_000_000e18,             // Total supply
            400_000_000e18,             // Max supply
            2e18,               // IDO Price
            0,
            WMON,               // Token1 address
            3000,               // Uniswap V3 Fee tier
            0,                  // Presale
            true,               // Is fresh deploy
            true                // use Uniswap
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
            vault1Params,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
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
            vault2Params,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
        );

        // Retrieve deployer's vaults
        address[] memory vaults = nomaFactory.getVaults(deployer);

        // Validate number of vaults
        assertEq(vaults.length, 2);

        // Validate Vault 1 details
        VaultDescription memory vault1Desc = nomaFactory.getVaultDescription(vaults[0]);

        assertEq(vault1Desc.token1, WMON);

        // Validate Vault 2 details
        VaultDescription memory vault2Desc = nomaFactory.getVaultDescription(vaults[1]);

        assertEq(vault2Desc.token1, WMON);

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

    // ========== SupplyRules Unit Tests ==========

    uint256 constant WAD = 1e18;
    uint256 constant BASE_PRICE = 1e14; // Protocol default

    /// @notice Test tier 0: price > basePrice returns 1M
    function test_GetMinSupply_PriceAboveBasePrice() public pure {
        uint256 price = BASE_PRICE + 1;
        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(price, BASE_PRICE);
        assertEq(minSupply, 1_000_000 * WAD, "Should return 1M for price > basePrice");
    }

    /// @notice Test tier 0: price exactly at basePrice returns 10M (not 1M)
    function test_GetMinSupply_PriceAtBasePrice() public pure {
        uint256 price = BASE_PRICE;
        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(price, BASE_PRICE);
        assertEq(minSupply, 10_000_000 * WAD, "Should return 10M for price == basePrice");
    }

    /// @notice Test tier 1: basePrice/10 < price <= basePrice returns 10M
    function test_GetMinSupply_Tier1() public pure {
        uint256 t1 = BASE_PRICE / 10;

        // Just above t1
        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(t1 + 1, BASE_PRICE);
        assertEq(minSupply, 10_000_000 * WAD, "Should return 10M for price just above t1");

        // At boundary (t1) should return next tier
        minSupply = SupplyRules.getMinTotalSupplyForPrice(t1, BASE_PRICE);
        assertEq(minSupply, 1_000_000_000 * WAD, "Should return 1B for price == t1");
    }

    /// @notice Test tier 2: basePrice/100 < price <= basePrice/10 returns 1B
    function test_GetMinSupply_Tier2() public pure {
        uint256 t2 = BASE_PRICE / 100;

        // Just above t2
        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(t2 + 1, BASE_PRICE);
        assertEq(minSupply, 1_000_000_000 * WAD, "Should return 1B for price just above t2");

        // At boundary (t2)
        minSupply = SupplyRules.getMinTotalSupplyForPrice(t2, BASE_PRICE);
        assertEq(minSupply, 10_000_000_000 * WAD, "Should return 10B for price == t2");
    }

    /// @notice Test tier 3: basePrice/1000 < price <= basePrice/100 returns 10B
    function test_GetMinSupply_Tier3() public pure {
        uint256 t3 = BASE_PRICE / 1_000;

        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(t3 + 1, BASE_PRICE);
        assertEq(minSupply, 10_000_000_000 * WAD, "Should return 10B for price just above t3");

        minSupply = SupplyRules.getMinTotalSupplyForPrice(t3, BASE_PRICE);
        assertEq(minSupply, 100_000_000_000 * WAD, "Should return 100B for price == t3");
    }

    /// @notice Test tier 4: basePrice/10000 < price <= basePrice/1000 returns 100B
    function test_GetMinSupply_Tier4() public pure {
        uint256 t4 = BASE_PRICE / 10_000;

        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(t4 + 1, BASE_PRICE);
        assertEq(minSupply, 100_000_000_000 * WAD, "Should return 100B for price just above t4");

        minSupply = SupplyRules.getMinTotalSupplyForPrice(t4, BASE_PRICE);
        assertEq(minSupply, 1_000_000_000_000 * WAD, "Should return 1T for price == t4");
    }

    /// @notice Test tier 5: basePrice/100000 < price <= basePrice/10000 returns 1T
    function test_GetMinSupply_Tier5() public pure {
        uint256 t5 = BASE_PRICE / 100_000;

        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(t5 + 1, BASE_PRICE);
        assertEq(minSupply, 1_000_000_000_000 * WAD, "Should return 1T for price just above t5");

        minSupply = SupplyRules.getMinTotalSupplyForPrice(t5, BASE_PRICE);
        assertEq(minSupply, 10_000_000_000_000 * WAD, "Should return 10T for price == t5");
    }

    /// @notice Test tier 6: basePrice/1000000 < price <= basePrice/100000 returns 10T
    function test_GetMinSupply_Tier6() public pure {
        uint256 t6 = BASE_PRICE / 1_000_000;

        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(t6 + 1, BASE_PRICE);
        assertEq(minSupply, 10_000_000_000_000 * WAD, "Should return 10T for price just above t6");

        minSupply = SupplyRules.getMinTotalSupplyForPrice(t6, BASE_PRICE);
        assertEq(minSupply, 100_000_000_000_000 * WAD, "Should return 100T for price == t6");
    }

    /// @notice Test tier 7: basePrice/10000000 < price <= basePrice/1000000 returns 100T
    function test_GetMinSupply_Tier7() public pure {
        uint256 t7 = BASE_PRICE / 10_000_000;

        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(t7 + 1, BASE_PRICE);
        assertEq(minSupply, 100_000_000_000_000 * WAD, "Should return 100T for price just above t7");

        minSupply = SupplyRules.getMinTotalSupplyForPrice(t7, BASE_PRICE);
        assertEq(minSupply, 1_000_000_000_000_000 * WAD, "Should return 1000T for price == t7");
    }

    /// @notice Test tier 8: price <= basePrice/10000000 returns 1000T
    function test_GetMinSupply_LowestTier() public pure {
        uint256 t7 = BASE_PRICE / 10_000_000;

        // Price below t7
        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(t7 - 1, BASE_PRICE);
        assertEq(minSupply, 1_000_000_000_000_000 * WAD, "Should return 1000T for price < t7");

        // Very low price
        minSupply = SupplyRules.getMinTotalSupplyForPrice(1, BASE_PRICE);
        assertEq(minSupply, 1_000_000_000_000_000 * WAD, "Should return 1000T for price == 1");

        // Zero price
        minSupply = SupplyRules.getMinTotalSupplyForPrice(0, BASE_PRICE);
        assertEq(minSupply, 1_000_000_000_000_000 * WAD, "Should return 1000T for price == 0");
    }

    /// @notice Test that basePrice of 0 reverts
    function test_GetMinSupply_ZeroBasePriceReverts() public {
        vm.expectRevert("SupplyRules: basePrice is zero");
        supplyRulesHarness.getMinTotalSupplyForPrice(1e18, 0);
    }

    /// @notice Test with different basePrice values
    function test_GetMinSupply_DifferentBasePrice() public pure {
        uint256 altBasePrice = 1e16; // Different base price

        // price > altBasePrice should return 1M
        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(altBasePrice + 1, altBasePrice);
        assertEq(minSupply, 1_000_000 * WAD);

        // altBasePrice/10 < price <= altBasePrice should return 10M
        minSupply = SupplyRules.getMinTotalSupplyForPrice(altBasePrice, altBasePrice);
        assertEq(minSupply, 10_000_000 * WAD);
    }

    // ========== enforceMinTotalSupply Tests ==========

    /// @notice Test that valid supply passes
    function test_EnforceMinSupply_ValidSupplyPasses() public pure {
        uint256 price = BASE_PRICE / 10 + 1; // Should require 10M
        uint256 supply = 10_000_000 * WAD;

        // Should not revert
        SupplyRules.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    /// @notice Test that supply above minimum passes
    function test_EnforceMinSupply_ExcessSupplyPasses() public pure {
        uint256 price = BASE_PRICE / 10 + 1; // Should require 10M
        uint256 supply = 100_000_000 * WAD; // 100M (10x the minimum)

        // Should not revert
        SupplyRules.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    /// @notice Test that supply exactly at minimum passes
    function test_EnforceMinSupply_ExactMinimumPasses() public pure {
        uint256 price = BASE_PRICE / 100 + 1; // Should require 1B
        uint256 supply = 1_000_000_000 * WAD; // Exactly 1B

        // Should not revert
        SupplyRules.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    /// @notice Test that insufficient supply reverts with correct error
    function test_EnforceMinSupply_InsufficientSupplyReverts() public {
        uint256 price = BASE_PRICE / 10 + 1; // Should require 10M
        uint256 supply = 1_000_000 * WAD; // Only 1M

        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyRules.TotalSupplyTooLow.selector,
                10_000_000 * WAD, // expected minimum
                supply            // provided
            )
        );
        supplyRulesHarness.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    /// @notice Test that supply just below minimum reverts
    function test_EnforceMinSupply_JustBelowMinimumReverts() public {
        uint256 price = BASE_PRICE + 1; // Should require 1M
        uint256 supply = 1_000_000 * WAD - 1; // Just under 1M

        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyRules.TotalSupplyTooLow.selector,
                1_000_000 * WAD,
                supply
            )
        );
        supplyRulesHarness.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    // ========== Fuzz Tests ==========

    /// @notice Fuzz test: any supply >= min should pass
    function testFuzz_EnforceMinSupply_ValidSupplyPasses(
        uint256 price,
        uint256 extraSupply
    ) public pure {
        // Bound inputs to reasonable ranges
        price = bound(price, 1, 1e20);
        extraSupply = bound(extraSupply, 0, 1e30);

        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(price, BASE_PRICE);
        uint256 supply = minSupply + extraSupply;

        // Should not revert
        SupplyRules.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    /// @notice Fuzz test: supply < min should revert
    function testFuzz_EnforceMinSupply_InsufficientSupplyReverts(
        uint256 price,
        uint256 deficit
    ) public {
        // Bound inputs
        price = bound(price, 1, 1e20);

        uint256 minSupply = SupplyRules.getMinTotalSupplyForPrice(price, BASE_PRICE);

        // Ensure we have a deficit
        deficit = bound(deficit, 1, minSupply);
        uint256 supply = minSupply - deficit;

        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyRules.TotalSupplyTooLow.selector,
                minSupply,
                supply
            )
        );
        supplyRulesHarness.enforceMinTotalSupply(price, supply, BASE_PRICE);
    }

    /// @notice Fuzz test: verify tier boundaries are correct
    function testFuzz_GetMinSupply_TierConsistency(uint256 basePrice) public pure {
        // Avoid division by zero and unreasonable values
        basePrice = bound(basePrice, 1e10, 1e20);

        // Define all thresholds
        uint256[8] memory thresholds;
        thresholds[0] = basePrice;
        thresholds[1] = basePrice / 10;
        thresholds[2] = basePrice / 100;
        thresholds[3] = basePrice / 1_000;
        thresholds[4] = basePrice / 10_000;
        thresholds[5] = basePrice / 100_000;
        thresholds[6] = basePrice / 1_000_000;
        thresholds[7] = basePrice / 10_000_000;

        // Supply requirements (in WAD)
        uint256[9] memory supplies;
        supplies[0] = 1_000_000 * WAD;
        supplies[1] = 10_000_000 * WAD;
        supplies[2] = 1_000_000_000 * WAD;
        supplies[3] = 10_000_000_000 * WAD;
        supplies[4] = 100_000_000_000 * WAD;
        supplies[5] = 1_000_000_000_000 * WAD;
        supplies[6] = 10_000_000_000_000 * WAD;
        supplies[7] = 100_000_000_000_000 * WAD;
        supplies[8] = 1_000_000_000_000_000 * WAD;

        // Test: price just above each threshold
        for (uint256 i = 0; i < 8; i++) {
            if (thresholds[i] > 0) {
                uint256 result = SupplyRules.getMinTotalSupplyForPrice(thresholds[i] + 1, basePrice);
                assertEq(result, supplies[i], "Tier mismatch above threshold");
            }
        }
    }

    // ========== NomaFactory Integration Tests for SupplyRules ==========

    /// @notice Helper to configure resolver with testWMON for SupplyRules tests
    function configureResolverWithTestWMON() internal {
        expectedAddressesInResolver.push(
            ContractInfo("WMON", testWMON)
        );
        configureResolver();
    }

    /// @notice Test that deployVault reverts when supply is too low for price
    function testDeployVault_SupplyTooLowForPrice_Reverts() public {
        configureResolverWithTestWMON();

        // Price at t1 threshold (basePrice/10 = 1e13) needs 1B minimum
        VaultDeployParams memory vaultDeployParams = VaultDeployParams(
            "Test Token",
            "TSUP",
            18,
            1_000_000e18,      // Only 1M supply - insufficient!
            2_000_000e18,      // Max supply
            1e13,              // Price at t1 threshold - requires 1B
            0,
            testWMON,
            3000,
            0,
            true,
            true
        );

        PresaleUserParams memory presaleParams = PresaleUserParams(
            100e18,
            90 days
        );

        // Should revert with TotalSupplyTooLow
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyRules.TotalSupplyTooLow.selector,
                1_000_000_000e18,  // Required: 1B
                1_000_000e18       // Provided: 1M
            )
        );

        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );
    }

    /// @notice Test high price with minimum required supply succeeds
    /// @dev This test requires a forked environment with Uniswap deployed
    ///      Skip this test when running locally without fork
    function testDeployVault_HighPriceMinSupply_Succeeds() public {
        // Skip if not running on fork (Uniswap factory won't be deployed)
        if (uniswapFactory.code.length == 0) {
            vm.skip(true);
        }

        configureResolverWithTestWMON();

        // High price (above basePrice 1e14) needs only 1M
        VaultDeployParams memory vaultDeployParams = VaultDeployParams(
            "High Price Token",
            "HPT",
            18,
            1_000_000e18,      // Exactly 1M supply
            2_000_000e18,      // Max supply
            1e15,              // Price > basePrice (1e14) - requires only 1M
            0,
            testWMON,
            3000,
            0,
            true,
            true
        );

        PresaleUserParams memory presaleParams = PresaleUserParams(
            100e18,
            90 days
        );

        vm.prank(deployer);
        (address vault, , ) = nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );

        assertTrue(vault != address(0), "Vault should be deployed");
    }

    /// @notice Test medium price with correct supply succeeds
    /// @dev This test requires a forked environment with Uniswap deployed
    ///      Skip this test when running locally without fork
    function testDeployVault_MediumPriceCorrectSupply_Succeeds() public {
        // Skip if not running on fork (Uniswap factory won't be deployed)
        if (uniswapFactory.code.length == 0) {
            vm.skip(true);
        }

        configureResolverWithTestWMON();

        // Price between t1 and t0 (1e13 < price <= 1e14) needs 10M
        VaultDeployParams memory vaultDeployParams = VaultDeployParams(
            "Medium Price Token",
            "MPT",
            18,
            10_000_000e18,     // 10M supply - exactly minimum
            20_000_000e18,     // Max supply
            5e13,              // Price in tier 1 range - requires 10M
            0,
            testWMON,
            3000,
            0,
            true,
            true
        );

        PresaleUserParams memory presaleParams = PresaleUserParams(
            100e18,
            90 days
        );

        vm.prank(deployer);
        (address vault, , ) = nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );

        assertTrue(vault != address(0), "Vault should be deployed");
    }

    /// @notice Test low price requires high supply
    function testDeployVault_LowPriceRequiresHighSupply() public {
        configureResolverWithTestWMON();

        // Very low price (below t7 = 1e7) needs 1000T
        VaultDeployParams memory vaultDeployParams = VaultDeployParams(
            "Low Price Token",
            "LPT",
            18,
            100_000_000_000_000e18,  // 100T supply - insufficient for lowest tier!
            200_000_000_000_000e18,
            1e6,                      // Price below t7 - requires 1000T
            0,
            testWMON,
            3000,
            0,
            true,
            true
        );

        PresaleUserParams memory presaleParams = PresaleUserParams(
            100e18,
            90 days
        );

        // Should revert - needs 1000T but only has 100T
        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyRules.TotalSupplyTooLow.selector,
                1_000_000_000_000_000e18,  // Required: 1000T
                100_000_000_000_000e18     // Provided: 100T
            )
        );

        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );
    }

    /// @notice Test supply just below minimum reverts in factory
    function testDeployVault_SupplyJustBelowMinimum_Reverts() public {
        configureResolverWithTestWMON();

        // Price above basePrice needs 1M, provide 1M - 1 wei
        VaultDeployParams memory vaultDeployParams = VaultDeployParams(
            "Just Below Token",
            "JBT",
            18,
            1_000_000e18 - 1,   // Just under 1M
            2_000_000e18,
            1e15,               // Price > basePrice - requires 1M
            0,
            testWMON,
            3000,
            0,
            true,
            true
        );

        PresaleUserParams memory presaleParams = PresaleUserParams(
            100e18,
            90 days
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SupplyRules.TotalSupplyTooLow.selector,
                1_000_000e18,
                1_000_000e18 - 1
            )
        );

        vm.prank(deployer);
        nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );
    }

    /// @notice Test that changing basePriceDecimals affects supply requirements
    /// @dev This test requires a forked environment with Uniswap deployed
    ///      Skip this test when running locally without fork
    function testDeployVault_DifferentBasePriceDecimals() public {
        // Skip if not running on fork (Uniswap factory won't be deployed)
        if (uniswapFactory.code.length == 0) {
            vm.skip(true);
        }

        configureResolverWithTestWMON();

        // Change basePrice to 1e16 (100x higher than default 1e14)
        ProtocolParameters memory newParams = nomaFactory.getProtocolParameters();
        newParams.basePriceDecimals = 1e16;

        vm.prank(deployer);
        nomaFactory.setProtocolParameters(newParams);

        // Now price 1e15 is in tier 1 (basePrice/10 < price <= basePrice)
        // With basePrice=1e16: t0=1e16, t1=1e15
        // Price 1e15 == t1, so it falls to tier 2 which needs 1B
        VaultDeployParams memory vaultDeployParams = VaultDeployParams(
            "New Base Token",
            "NBT",
            18,
            1_000_000_000e18,  // 1B supply
            2_000_000_000e18,
            1e15,              // Price == t1 with new basePrice - requires 1B
            0,
            testWMON,
            3000,
            0,
            true,
            true
        );

        PresaleUserParams memory presaleParams = PresaleUserParams(
            100e18,
            90 days
        );

        vm.prank(deployer);
        (address vault, , ) = nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );

        assertTrue(vault != address(0), "Vault should be deployed with new basePrice");
    }
}