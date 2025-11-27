

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { Utils } from "../../src/libraries/Utils.sol";
import { Resolver } from "../../src/Resolver.sol";
import { NomaDividends } from "../../src/controllers/NomaDividends.sol";

struct ContractInfo {
    string name;
    address addr;
}

interface INomaToken {
    function setDividendsManager(NomaDividends _manager) external;
    function owner() external returns (address);
}

contract ConfigureResolver is Script {
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bool isMainnet = vm.envBool("DEPLOY_FLAG_MAINNET"); 
    bool isChainFork = vm.envBool("DEPLOY_FLAG_FORK");     

    ContractInfo[] private expectedAddressesInResolver;

    Resolver private resolver;
    NomaDividends private nomaDividends;

    address private resolverAddress = 0x9c7fEaDb1e588b53928B8e1573Aa96bd009B8CCC;
    address private nomaTokenAddres = 0x3912a474AD7D35D5Cd8D9e0172FF92e971dE3044;
    address private dividenDistributorAddress = 0x8D3BeA1A26d2359CE273C800c08d6ca5d4b2251e;

    function run() public {  
        vm.startBroadcast(privateKey);

        resolver = Resolver(resolverAddress);
        
        nomaDividends = NomaDividends(dividenDistributorAddress);

        expectedAddressesInResolver.push(
            ContractInfo("NomaToken", nomaTokenAddres)
        );

        // Configure resolver
        configureResolver();

        nomaDividends.setSharesToken();

        address contractOwner = INomaToken(nomaTokenAddres).owner();
        console.log("Contract owner is ", contractOwner);

        INomaToken(nomaTokenAddres).setDividendsManager(nomaDividends);

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