// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Resolver } from "../../src/Resolver.sol";
import { VaultDeployParams, VaultDescription, ProtocolParameters, PresaleProtocolParams } from "../../src/types/Types.sol";
import { 
    VaultUpgrade, 
    VaultUpgradeStep1, 
    VaultUpgradeStep2,
    VaultUpgradeStep3,
    VaultUpgradeStep4,
    VaultUpgradeStep5
} from "../../src/vault/init/VaultUpgrade.sol";
import { 
    VaultInit
} from "../../src/vault/init/VaultInit.sol";
import { Utils } from "../../src/libraries/Utils.sol";

struct ContractInfo {
    string name;
    address addr;
}

struct ContractAddressesJson {
    address Factory;
    address ModelHelper;
    address Resolver;
}

contract DeployVaultUpgrade1 is Script {
    using stdJson for string;

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bool isMainnet = vm.envBool("DEPLOY_FLAG_MAINNET"); 
    bool isChainFork = vm.envBool("DEPLOY_FLAG_FORK");     

    ContractInfo[] private expectedAddressesInResolver;
    Resolver private resolver;

    // Constants
    address WMON_monad_mainnet = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address uniswapFactory_monad_mainnet = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address pancakeSwapFactory__monad_mainnet = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

    address WMON_monad_testnet = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address uniswapFactory_monad_testnet = 0x961235a9020B05C44DF1026D956D1F4D78014276;
    address pancakeSwapFactory__monad_testnet = 0x3b7838D96Fc18AD1972aFa17574686be79C50040;
    address WMON = isMainnet ? WMON_monad_mainnet : WMON_monad_testnet;

    function run() public {  
        vm.startBroadcast(privateKey);

        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out_dummy.json");

        // Read the JSON file
        string memory json = vm.readFile(path);
        string memory networkId = isChainFork ? "1337" : isMainnet ? "143" : "10143"; 

        // Parse the data for network ID 
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Factory Address:", addresses.Factory);

        resolver = Resolver(addresses.Resolver);

        VaultUpgrade vaultUpgrade = new VaultUpgrade(deployer, address(addresses.Factory));
        VaultInit vaultStep1 = new VaultInit(deployer, address(addresses.Factory));
    
        VaultUpgradeStep1 vaultUpgradeStep1 = new VaultUpgradeStep1(deployer, address(addresses.Factory));
        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer, address(addresses.Factory));
    
        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgrade", address(vaultUpgrade))
        );
        
        expectedAddressesInResolver.push(
            ContractInfo("VaultStep1", address(vaultStep1))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep1", address(vaultUpgradeStep1))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep2", address(vaultUpgradeStep2))
        );

        // Configure resolver
        configureResolver();

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