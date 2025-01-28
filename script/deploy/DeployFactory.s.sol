// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { BaseVault } from  "../../src/vault/BaseVault.sol";
import { Utils } from "../../src/libraries/Utils.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { IAddressResolver } from "../../src/interfaces/IAddressResolver.sol";
import { Resolver } from "../../src/Resolver.sol";
import { ModelHelper } from "../../src/model/Helper.sol";
import { Deployer } from "../../src/Deployer.sol";
import { NomaFactory } from "../../src/factory/NomaFactory.sol";
import { VaultDeployParams, VaultDescription, LiquidityStructureParameters } from "../../src/types/Types.sol";
import { 
    VaultUpgrade, 
    VaultUpgradeStep1, 
    VaultUpgradeStep2
} from "../../src/vault/init/VaultUpgrade.sol";
import { VaultFinalize } from "../../src/vault/init/VaultFinalize.sol";
import { EtchVault } from "../../src/vault/deploy/EtchVault.sol";
import { Staking } from "../../src/staking/Staking.sol";
import { GonsToken } from "../../src/staking/Gons.sol";
import { DeployerFactory } from "../../src/factory/DeployerFactory.sol"; 
import { ExtFactory } from "../../src/factory/ExtFactory.sol";
import { AdaptiveSupply } from "../../src/controllers/supply/AdaptiveSupply.sol";
import { RewardsCalculator } from "../../src/controllers/supply/RewardsCalculator.sol";

interface IWETH {
    function mintTo(address to, uint256 amount) external;
    function deposit() external payable;
    function depositTo(address receiver) external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

struct ContractInfo {
    string name;
    address addr;
}

contract DeployFactory is Script {
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    ContractInfo[] private expectedAddressesInResolver;

    Resolver private resolver;
    ModelHelper private modelHelper;
    NomaFactory private nomaFactory;
    EtchVault private etchVault;
    GonsToken private sNoma;
    AdaptiveSupply private adaptiveSupply;
    RewardsCalculator private rewardsCalculator;

    function run() public {  

        vm.startBroadcast(privateKey);

        expectedAddressesInResolver.push(
            ContractInfo("WETH", WETH)
        );

        // Model Helper
        modelHelper = new ModelHelper();
        
        expectedAddressesInResolver.push(
            ContractInfo("ModelHelper", address(modelHelper))
        );

        // Adaptive Supply
        adaptiveSupply = new AdaptiveSupply();

        rewardsCalculator = new RewardsCalculator();
        
        expectedAddressesInResolver.push(
            ContractInfo("AdaptiveSupply", address(adaptiveSupply))
        );

        expectedAddressesInResolver.push(
            ContractInfo("RewardsCalculator", address(rewardsCalculator))
        );

        // Resolver
        resolver = new Resolver(deployer);

        expectedAddressesInResolver.push(
            ContractInfo("Resolver", address(resolver))
        );  

        console.log("Resolver address: ", address(resolver));

        DeployerFactory deploymentFactory = new DeployerFactory(address(resolver));
        ExtFactory extFactory = new ExtFactory(address(resolver));

        // Noma Factory
        nomaFactory = new NomaFactory(
            uniswapFactory,
            address(resolver),
            address(deploymentFactory),
            address(extFactory)
        );
        
        expectedAddressesInResolver.push(
            ContractInfo("NomaFactory", address(nomaFactory))
        );

        LiquidityStructureParameters memory _params =
        LiquidityStructureParameters(
            10, // Floor percentage of total supply
            5, // Anchor percentage of total supply
            3, // IDO price multiplier
            [200, 500], // Floor bips
            90e16, // Shift liquidity ratio
            120e16, // Slide liquidity ratio,
            25000, // Discovery deploy bips,
            10, // shiftAnchorUpperBips
            300, // slideAnchorUpperBips
            100, // lowBalanceThresholdFactor
            100, // highBalanceThresholdFactor
            5e15 // inflationFee
        );

        nomaFactory.setLiquidityStructureParameters(_params);

        resolver.initFactory(address(nomaFactory));
        etchVault = new EtchVault(address(nomaFactory), address(resolver));

        expectedAddressesInResolver.push(
            ContractInfo("EtchVault", address(etchVault))
        );
        
        VaultUpgrade vaultUpgrade = new VaultUpgrade(deployer, address(nomaFactory));
        VaultUpgradeStep1 vaultUpgradeStep1 = new VaultUpgradeStep1(deployer);
        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer);
        VaultFinalize vaultFinalize = new VaultFinalize(deployer);

        vaultUpgrade.init(address(0), address(vaultUpgradeStep1));
        vaultUpgradeStep1.init(address(vaultUpgradeStep2), address(vaultUpgrade));
        vaultUpgradeStep2.init(address(vaultFinalize), address(vaultUpgradeStep1));
        vaultFinalize.init(/*address(nomaFactory)*/ deployer, address(vaultUpgradeStep2));

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgrade", address(vaultUpgrade))
        );
        
        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeFinalize", address(vaultFinalize))
        );

        // Configure resolver
        configureResolver();

        console.log("Factory deployed to address: ", address(nomaFactory));
        console.log("ModelHelper deployed to address: ", address(modelHelper));
        console.log("AdaptiveSupply deployed to address: ", address(adaptiveSupply));
        console.log("RewardsCalculator deployed to address: ", address(rewardsCalculator));

        vm.stopBroadcast();
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
