

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { Utils } from "../../src/libraries/Utils.sol";
import { Resolver } from "../../src/Resolver.sol";
import { EtchVault } from "../../src/vault/deploy/EtchVault.sol";

struct ContractInfo {
    string name;
    address addr;
}

struct ContractAddressesJson {
    address Factory;
    address ModelHelper;
    address Resolver;
}

contract ConfigureFactory is Script {
    using stdJson for string;
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bool isMainnet = vm.envBool("DEPLOY_FLAG_MAINNET"); 
    bool isChainFork = vm.envBool("DEPLOY_FLAG_FORK");     

    ContractInfo[] private expectedAddressesInResolver;

    EtchVault private etchVault;
    Resolver private resolver;

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
        
        etchVault = new EtchVault(addresses.Factory, addresses.Resolver);

        resolver = Resolver(addresses.Resolver);
        
        expectedAddressesInResolver.push(
            ContractInfo("EtchVault", address(etchVault))
        );
        
        expectedAddressesInResolver.push(
            ContractInfo("RootAuthority", deployer)
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