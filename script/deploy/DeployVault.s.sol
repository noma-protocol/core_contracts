// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { OikosFactory } from  "../../src/factory/OikosFactory.sol";
import { ProtocolAddresses, VaultDeployParams, PresaleUserParams, VaultDescription, ProtocolParameters } from "../../src/types/Types.sol";
import { IDOHelper } from "../../test/IDO_Helper/IDOHelper.sol";
import { BaseVault } from  "../../src/vault/BaseVault.sol";

struct ContractAddressesJson {
    address Factory;
    address ModelHelper;
}

interface IPresaleContract {
    function setIsOksPresale(bool isOksPresale) external;
}

contract DeployVault is Script {
    using stdJson for string;

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
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
            "OIKOS TOKEN",
            "OKS",
            18,
            3367606000000000000000000,
            10102818000000000000000000,
            37850000000000,
            0,
            WBNB,
            3000,
            1 // 0 = no presale
        );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            29826549581000000000,     // softCap
            60                       // duration (seconds)
        );

        (address vault, address pool, address proxy) = 
        oikosFactory
        .deployVault(
            presaleParams,
            vaultDeployParams
        );

        BaseVault vaultContract = BaseVault(vault);
        ProtocolAddresses memory protocolAddresses = vaultContract.getProtocolAddresses();
        IPresaleContract(protocolAddresses.presaleContract).setIsOksPresale(true);

        idoManager = new IDOHelper(pool, vault, modelHelper, proxy, WBNB);

        console.log("Vault address: ", vault);
        console.log("Pool address: ", pool);
        console.log("Proxy address: ", proxy);
        console.log("IDOHelper address: ", address(idoManager));

        
    }
}