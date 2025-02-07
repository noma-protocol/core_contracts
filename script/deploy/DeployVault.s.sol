// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { NomaFactory } from  "../../src/factory/NomaFactory.sol";
import { VaultDeployParams, PresaleUserParams, VaultDescription, ProtocolParameters } from "../../src/types/Types.sol";
import { IDOHelper } from "../../test/IDO_Helper/IDOHelper.sol";

contract DeployVault is Script {
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private nomaFactoryAddress = 0xB13231827E46E9c83b9278a9035813941cE95Db8;
    address private modelHelper = 0x6D47E56d5CD83d396AC92F1f66e7D095925B4D0C;

    IDOHelper private idoManager;

    function run() public {  

        vm.startBroadcast(privateKey);
        NomaFactory nomaFactory = NomaFactory(nomaFactoryAddress);

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "MY TOKEN 2",
            "MINE",
            18,
            100e18,
            1e18,
            0,
            WETH,
            3000,
            0 // 0 = no presale
        );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            6e18,       // softCap
            125e16,     // initialPrice
            90 days     // deadline
        );

        (address vault, address pool, address proxy) = 
        nomaFactory
        .deployVault(
            presaleParams,
            vaultDeployParams
        );

        idoManager = new IDOHelper(pool, vault, modelHelper, proxy, WETH);

        console.log("Vault address: ", vault);
        console.log("Pool address: ", pool);
        console.log("Proxy address: ", proxy);
        console.log("IDOHelper address: ", address(idoManager));

        
    }
}