// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { OikosFactory } from  "../../src/factory/OikosFactory.sol";
import { VaultDeployParams, PresaleUserParams, VaultDescription, ProtocolParameters } from "../../src/types/Types.sol";
import { IDOHelper } from "../../test/IDO_Helper/IDOHelper.sol";

struct ContractAddressesJson {
    address Factory;
    address ModelHelper;
}

contract DeployVault is Script {
    using stdJson for string;

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private oikosFactoryAddress;
    address private modelHelper;

    IDOHelper private idoManager;

    function run() public {  
        vm.startBroadcast(privateKey);

        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);

        string memory networkId = "1337";
        // Parse the data for network ID `1337`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Model Helper Address:", addresses.ModelHelper);
        console2.log("Factory Address:", addresses.Factory);

        // Extract addresses from JSON
        modelHelper = addresses.ModelHelper;
        oikosFactoryAddress = addresses.Factory;

        OikosFactory oikosFactory = OikosFactory(oikosFactoryAddress);

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
        oikosFactory
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