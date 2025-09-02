// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import { AuxVault } from "../../src/vault/AuxVault.sol";
import { ExchangeHelper } from  "../../src/ExchangeHelper.sol";

contract DeployVault is Script {
    using stdJson for string;

    // Constants
    address WMON = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    function run() public {  
        vm.startBroadcast(privateKey);

        // Exchange Helper
        ExchangeHelper exchangeHelper = new ExchangeHelper(
            WMON
        );
        console.log("Exchange Helper address: ", address(exchangeHelper));
    }
}