// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { Utils } from "../../src/libraries/Utils.sol";
import { Resolver } from "../../src/Resolver.sol";
import { WETH9 } from "../../src/token/WETH9.sol";
import { BaseVault } from "../../src/vault/BaseVault.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import {ModelHelper} from  "../../src/model/Helper.sol";
import { LiquidityType } from "../../src/types/Types.sol";

interface IDOManager {
    function vault() external view returns (BaseVault);
}

struct ContractInfo {
    string name;
    address addr;
}

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}
 
contract BumpFloor is Script {
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    address modelHelperContract;

    ModelHelper public modelHelper;
    Resolver public resolver;
    ContractInfo[] private expectedAddressesInResolver;
    address payable idoManager;

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
        
        // Extract addresses from JSON
        idoManager = payable(addresses.IDOHelper);
        modelHelperContract = addresses.ModelHelper;
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));
        address pool = address(vault.pool());
        
        modelHelper = ModelHelper(modelHelperContract);

        IVault(address(vault)).bumpRewards(
            1000 ether
        );

    }   

    function bumpFloor() public {
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        uint256 imvBeforeShift = modelHelper.getIntrinsicMinimumValue(address(vault));
        uint256 imvAfterShift = modelHelper.getIntrinsicMinimumValue(address(vault));


        (,,, uint256 anchorToken1Balance) = modelHelper
        .getUnderlyingBalances(
            address(pool), 
            address(vault), 
            LiquidityType.Anchor
        );

        IVault(address(vault)).bumpFloor(
            anchorToken1Balance / 8
        );

        uint256 imvAfterBump = modelHelper.getIntrinsicMinimumValue(address(vault));

        console.log("IMV after bump is: ", imvAfterBump);
        console.log("IMV before bump is: ", imvBeforeShift);
        console.log("IMV after shift is: ", imvAfterShift);
        console.log("Anchor token1 balance is: ", anchorToken1Balance);
    }  
}