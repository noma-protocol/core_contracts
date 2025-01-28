// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { NomaFactory } from  "../../src/factory/NomaFactory.sol";
import { VaultDeployParams, VaultDescription, LiquidityStructureParameters } from "../../src/types/Types.sol";
import { IDOHelper } from "../../test/IDO_Helper/IDOHelper.sol";

contract DeployVault is Script {
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private nomaFactoryAddress = 0xe819370DE33df08F8080E99818f6a3653F742812;
    address private modelHelper = 0x0E90A3D616F9Fe2405325C3a7FB064837817F45F;

    IDOHelper private idoManager;

    function run() public {  

        vm.startBroadcast(privateKey);
        NomaFactory nomaFactory = NomaFactory(nomaFactoryAddress);

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "Noma Token",
            "NOMA",
            18,
            100e18,
            10,
            1e18,
            WETH
        );

        (address vault, address pool, address proxy) = 
        nomaFactory
        .deployVault(
            vaultDeployParams
        );

        idoManager = new IDOHelper(pool, vault, modelHelper, proxy, WETH);

        console.log("Vault address: ", vault);
        console.log("Pool address: ", pool);
        console.log("Proxy address: ", proxy);
        console.log("IDOHelper address: ", address(idoManager));

        
    }
}