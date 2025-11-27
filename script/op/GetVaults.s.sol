// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {NomaFactory} from "../../src/factory/NomaFactory.sol";

import {VaultDescription} from "../../src/types/Types.sol";

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

contract GetVaults is Script {

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address deployerAddress = 0x5368bDd0F9BC14C223a67b95874842dD77250d08;
    
    function run() public {
        vm.startBroadcast(privateKey);
        
        NomaFactory factory = NomaFactory(0x2c6ab111bcdDAC86B5e42990F1BC05F8e8Aa63cA);

        address[] memory vaults = factory.getVaults(deployerAddress);

        for (uint256 i = 0; i < vaults.length; i++) {
            console.log(vaults[i]);
        }

        vm.stopBroadcast();
    }

}
