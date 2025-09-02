// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { NomaFactory } from  "../../src/factory/NomaFactory.sol";
import { 
    ProtocolAddresses,
    VaultDeployParams, 
    PresaleUserParams, 
    VaultDescription, 
    ProtocolParameters 
} from "../../src/types/Types.sol";
import { IDOHelper } from "../../test/IDO_Helper/IDOHelper.sol";
import { BaseVault } from  "../../src/vault/BaseVault.sol";
import { Migration } from "../../src/bootstrap/Migration.sol";
struct ContractAddressesJson {
    address Factory;
    address ModelHelper;
}

interface IPresaleContract {
    function setMigrationContract(address _migrationContract) external ;

}

contract DeployVault is Script {
    using stdJson for string;

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WMON = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address private nomaFactoryAddress;
    address private modelHelper;

    IDOHelper private idoManager;

    function run() public {  
        vm.startBroadcast(privateKey);

        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);
        string memory networkId = "1337"; //"10143"; 

        // Parse the data for network ID `1337`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Model Helper Address:", addresses.ModelHelper);
        console2.log("Factory Address:", addresses.Factory);

        // Extract addresses from JSON
        modelHelper = addresses.ModelHelper;
        nomaFactoryAddress = addresses.Factory;

        NomaFactory nomaFactory = NomaFactory(nomaFactoryAddress);

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "NOMA TOKEN",
            "NOMA",
            18,
            14000000000000000000000000,
            1400000000000000000000000000,
            10000000000000,
            0,
            WMON,
            3000,
            0 // 0 = no presale
        );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            27000000000000000000, // softCap
            900 //2592000          // duration (seconds)
        );

        (address vault, address pool, address proxy) = 
        nomaFactory
        .deployVault(
            presaleParams,
            vaultDeployParams
        );

        BaseVault vaultContract = BaseVault(vault);
        ProtocolAddresses memory protocolAddresses = vaultContract.getProtocolAddresses();

        idoManager = new IDOHelper(pool, vault, modelHelper, proxy, WMON);

        console.log("Vault address: ", vault);
        console.log("Pool address: ", pool);
        console.log("Proxy address: ", proxy);
        console.log("IDOHelper address: ", address(idoManager));
    }
}