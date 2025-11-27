// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "../../src/bootstrap/Presale.sol";

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

contract RecoverPresaleFunds is Script {

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address public presaleAddress = 0xC300e137Fc4c7E3a85da9d3221a6F7b73fB50D73;
    
    function run() public {
        vm.startBroadcast(privateKey);


        Presale presale = Presale(presaleAddress);
        // presale.recoverFunds(deployer);


        vm.stopBroadcast();
    }

}
