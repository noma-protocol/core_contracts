// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IAddressResolver} from "../../src/interfaces/IAddressResolver.sol";


contract ConfigureResolver is Script {

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address resolverAddress = 0x454e616449D9A2E4E672aA301e8657a5a56b71De;
    address AdaptiveSupplyAddress = 0x79d3bea5A5C4C776443c6d962C01B4E451453832;
    address vaultAddress = 0x1df48d9738e38A40fBf3B329865f4bc772e907F4;

    function run() public {
        vm.startBroadcast(privateKey);
        
        IAddressResolver resolver = IAddressResolver(resolverAddress);


        bytes32[] memory names = new bytes32[](1);
        names[0] = bytes32("AdaptiveSupply");
        address[] memory addresses = new address[](1);
        addresses[0] = AdaptiveSupplyAddress;

        resolver.importAddresses(
            names, 
            addresses
        );

        resolver.importVaultAddress(
            vaultAddress, 
            names, 
            addresses
        );

        vm.stopBroadcast();
    }

}
