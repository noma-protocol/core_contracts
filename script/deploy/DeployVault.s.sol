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
    ProtocolParameters,
    ExistingDeployData
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
    bool isMainnet = vm.envBool("DEPLOY_FLAG_MAINNET"); 
    bool isChainFork = vm.envBool("DEPLOY_FLAG_FORK"); 
    bool deployTests = vm.envBool("DEPLOY_TEST"); 

    // Constants
    address WMON_monad_mainnet = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address WMON_monad_testnet = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address WMON = isMainnet ? WMON_monad_mainnet : WMON_monad_testnet;

    address private nomaFactoryAddress;
    address private modelHelper;

    IDOHelper private idoManager;

    function run() public {  
        vm.startBroadcast(privateKey);

        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out_dummy.json");

        // Read the JSON file
        string memory json = vm.readFile(path);
        string memory networkId = isChainFork ? "1337" : isMainnet ? "143" : "10143"; 

        // Parse the data for network ID 
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

        bool useUniswap = true;
        bool isFreshDeploy = true;

        VaultDeployParams memory vaultDeployParams = 
        VaultDeployParams(
            "NOMA TOKEN",
            "NOMA",
            18,
            14000000000000000000000000,
            1400000000000000000000000000,
            25000000000000000,
            1,
            WMON,
            useUniswap ? 3000 : 2500,   
            0,                          // 0 = no presale
            isFreshDeploy,              // isFreshDeploy
            useUniswap                  // useUniswap 
        );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            3000000000000000000000,     // softCap
            86400 * 3                   // duration (seconds)
        );

        (address vault, address pool, address proxy) = 
        nomaFactory
        .deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })            
        );

        if (deployTests) {
            nomaFactory.configureVault(vault, 0);

            idoManager = new IDOHelper(pool, vault, modelHelper, proxy, WMON);
            console.log("IDOHelper address: ", address(idoManager));
        }

        console.log("Vault address: ", vault);
        console.log("Pool address: ", pool);
        console.log("Proxy address: ", proxy);
    }

    
}