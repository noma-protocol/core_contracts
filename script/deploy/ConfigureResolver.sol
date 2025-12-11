

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
    function owner() external view returns (address);
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

    address private resolverAddress = 0x488eBfab208ADFBf97f98579EC694B82664d6e6B;
    address private nomaTokenAddress = 0x11d9e5b4Fd7CB81eE9c40AB2561CeD9C58D66146;
    address private nomaFactoryAddress = 0xA2839bA831284Ea6567B8a6Ab3BA02aaE2b3f147;

    function run() public {  
        vm.startBroadcast(privateKey);

        resolver = Resolver(resolverAddress);
        
        nomaDividends = new NomaDividends(nomaFactoryAddress, resolverAddress);

        expectedAddressesInResolver.push(
            ContractInfo("DividendDistributor", address(nomaDividends))
        );
        
        console.log("DividendDistributor deployed to address: ", address(nomaDividends));

        expectedAddressesInResolver.push(
            ContractInfo("NomaToken", nomaTokenAddress)
        );

        // Configure resolver
        configureResolver();

        nomaDividends.setSharesToken{gas: 1000000}();

        address contractOwner = INomaToken(nomaTokenAddress).owner();
        console.log("Contract owner is ", contractOwner);

        INomaToken(nomaTokenAddress).setDividendsManager{gas: 3000000}(nomaDividends);

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