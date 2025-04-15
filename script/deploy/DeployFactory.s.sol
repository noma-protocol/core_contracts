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
import { OikosFactory } from "../../src/factory/OikosFactory.sol";
import { VaultDeployParams, VaultDescription, ProtocolParameters, PresaleProtocolParams } from "../../src/types/Types.sol";
import { 
    VaultUpgrade, 
    VaultUpgradeStep1, 
    VaultUpgradeStep2
} from "../../src/vault/init/VaultUpgrade.sol";
import { VaultFinalize } from "../../src/vault/init/VaultFinalize.sol";
import { EtchVault } from "../../src/vault/deploy/EtchVault.sol";
import { Staking } from "../../src/staking/Staking.sol";
import { GonsToken } from "../../src/token/Gons.sol";
import { DeployerFactory } from "../../src/factory/DeployerFactory.sol"; 
import { ExtFactory } from "../../src/factory/ExtFactory.sol";
import { AdaptiveSupply } from "../../src/controllers/supply/AdaptiveSupply.sol";
import { RewardsCalculator } from "../../src/controllers/supply/RewardsCalculator.sol";
import { PresaleFactory } from "../../src/factory/PresaleFactory.sol";
import { TokenFactory } from "../../src/factory/TokenFactory.sol";
import { ExchangeHelper } from "../../src/ExchangeHelper.sol";

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
    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private uniswapFactory = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;

    ContractInfo[] private expectedAddressesInResolver;

    Resolver private resolver;
    ModelHelper private modelHelper;
    OikosFactory private oikosFactory;
    EtchVault private etchVault;
    GonsToken private sNoma;
    AdaptiveSupply private adaptiveSupply;
    RewardsCalculator private rewardsCalculator;
    TokenFactory private tokenFactory;
    ExchangeHelper private exchangeHelper;

    function run() public {  

        vm.startBroadcast(privateKey);

        expectedAddressesInResolver.push(
            ContractInfo("WBNB", WBNB)
        );

        // Model Helper
        modelHelper = new ModelHelper();
        
        // Exchange Helper
        exchangeHelper = new ExchangeHelper();

        console.log("Exchange Helper address: ", address(exchangeHelper));

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

        // Token Factory
        tokenFactory = new TokenFactory(address(resolver));

        expectedAddressesInResolver.push(
            ContractInfo("TokenFactory", address(tokenFactory))
        );
        
        // Presale Factory
        PresaleFactory presaleFactory = new PresaleFactory(address(resolver));

        expectedAddressesInResolver.push(
            ContractInfo("PresaleFactory", address(presaleFactory))
        );

        DeployerFactory deploymentFactory = new DeployerFactory(address(resolver));
        ExtFactory extFactory = new ExtFactory(address(resolver));

        // Noma Factory
        oikosFactory = new OikosFactory(
            uniswapFactory,
            address(resolver),
            address(deploymentFactory),
            address(extFactory),
            address(presaleFactory)
        );
        
        expectedAddressesInResolver.push(
            ContractInfo("OikosFactory", address(oikosFactory))
        );

        ProtocolParameters memory _params =
        ProtocolParameters(
            39,         // Floor percentage of total supply
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
            5,          // inflationFee
            27,         // loan interest fee
            0.01e18,    // deployFee (ETH)
            25          // presalePremium (25%)
        );

        PresaleProtocolParams memory _presaleParams =
        PresaleProtocolParams(
            100,         // Max soft cap (60%)
            100,        // Min contribution ratio 
            25,         // Max contribution ratio 
            20,         // Percentage of funds kept from presale (20%)
            30 days,    // Min deadline
            90 days,    // Max deadline
            3,          // Referral bonus (3%)
            5           // Team fee (5%)
        );

        oikosFactory.setProtocolParameters(_params);
        oikosFactory.setPresaleProtocolParams(_presaleParams);

        resolver.initFactory(address(oikosFactory));
        etchVault = new EtchVault(address(oikosFactory), address(resolver));

        expectedAddressesInResolver.push(
            ContractInfo("EtchVault", address(etchVault))
        );
        
        VaultUpgrade vaultUpgrade = new VaultUpgrade(deployer, address(oikosFactory));
        VaultUpgradeStep1 vaultUpgradeStep1 = new VaultUpgradeStep1(deployer);
        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer);
        VaultFinalize vaultFinalize = new VaultFinalize(deployer);

        vaultUpgrade.init(address(vaultUpgradeStep1));
        vaultUpgradeStep1.init(address(vaultUpgradeStep2), address(vaultUpgrade));
        vaultUpgradeStep2.init(address(vaultFinalize), address(vaultUpgradeStep1));
        vaultFinalize.init(/*address(oikosFactory)*/ deployer, address(vaultUpgradeStep2));

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgrade", address(vaultUpgrade))
        );
        
        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeFinalize", address(vaultFinalize))
        );

        expectedAddressesInResolver.push(
            ContractInfo("RootAuthority", deployer)
        );

        // Configure resolver
        configureResolver();

        console.log("Factory deployed to address: ", address(oikosFactory));
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
