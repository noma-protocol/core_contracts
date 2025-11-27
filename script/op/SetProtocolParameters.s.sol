// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import { NomaFactory } from  "../../src/factory/NomaFactory.sol";
import { ProtocolParameters, PresaleProtocolParams } from "../../src/types/Types.sol";
import { AuxVault } from "../../src/vault/AuxVault.sol";

struct ContractAddressesJson {
    address Factory;
    address ModelHelper;
}

interface IVault {
    function setProtocolParameters(ProtocolParameters memory _params) external;
    function setModelHelper(address _modelHelper) external;
}

contract SetProtocolParameters is Script {
    using stdJson for string;

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address vault = 0x1df48d9738e38A40fBf3B329865f4bc772e907F4; // Replace with actual AuxVault address

    function run() public {  
        vm.startBroadcast(privateKey);
        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);

        string memory networkId = "10143";
        // Parse the data for network ID `1337`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Factory Address:", addresses.Factory);

        ProtocolParameters memory _params =
        ProtocolParameters(
            10,         // Floor percentage of total supply
            5,          // Anchor percentage of total supply
            3,          // IDO price multiplier
            [200, 500], // Floor bips
            90e16,      // Shift liquidity ratio
            115e16,     // Slide liquidity ratio
            15000,      // Discovery deploy bips
            10,         // shiftAnchorUpperBips
            300,        // slideAnchorUpperBips
            5,          // lowBalanceThresholdFactor
            2,          // highBalanceThresholdFactor
            5,          // inflationFee
            27,         // loan interest fee
            25,         // maxLoanUtilization
            0,          // deployFee (ETH)
            25,         // presalePremium (25%)
            1_250,      // self repaying loan ltv treshold
            0.5e18      // Adaptive supply curve half step
        );

        // NomaFactory nomaFactory = NomaFactory(addresses.Factory);
        // nomaFactory.setProtocolParameters(_params);

        AuxVault auxVault = AuxVault(vault);
        IVault(vault).setProtocolParameters(_params);

        // Set the ModelHelper address in the vault
        // IVault(vault).setModelHelper(0x550300cDd2579A5D2198E7b5A95b54B6A3103c5a);

        console.log("Presale Protocol Parameters set successfully.");

    }
}