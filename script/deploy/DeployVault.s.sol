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
    address private nomaFactoryAddress = 0x0a856bD938e251A21504B3053f830FCfa24f46Fe;
    address private modelHelper = 0x34Bd850baC7e1E27BC8D494D01445BADe8138a75;

    IDOHelper private idoManager;

    function run() public {  

        vm.startBroadcast(privateKey);
        NomaFactory nomaFactory = NomaFactory(nomaFactoryAddress);

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "TEST TOKEN 2",
            "TOK",
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
            6e18,  // softCap
            30     // deadline
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