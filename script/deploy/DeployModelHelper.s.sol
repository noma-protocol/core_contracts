// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { Utils } from "../../src/libraries/Utils.sol";
import { IAddressResolver } from "../../src/interfaces/IAddressResolver.sol";
import { Resolver } from "../../src/Resolver.sol";
import { ModelHelper } from "../../src/model/Helper.sol";


struct ContractInfo {
    string name;
    address addr;
}

contract DeployFactory is Script {
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    ContractInfo[] private expectedAddressesInResolver;

    IAddressResolver private resolver;
    ModelHelper private modelHelper;

    address resolverAddress = 0x4363087aC747128b53A74f5eB7c8DeAa678B00fe;

    function run() public {  

        vm.startBroadcast(privateKey);

        // Model Helper
        modelHelper = new ModelHelper();
        
        console.log("Model Helper address: ", address(modelHelper));
        
        expectedAddressesInResolver.push(
            ContractInfo("ModelHelper", address(modelHelper))
        );

        // Resolver
        resolver =  IAddressResolver(resolverAddress);

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
