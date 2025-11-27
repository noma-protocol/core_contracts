// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { IDOHelper } from  "../../test/IDO_Helper/IDOHelper.sol";
import { Utils } from  "../../src/libraries/Utils.sol";
import {LendingVault} from  "../../src/vault/LendingVault.sol";
import {IDOHelper} from  "../../test/IDO_Helper/IDOHelper.sol";
import {LiquidityType} from "../../src/types/Types.sol";
import {Deployer} from "../../src/Deployer.sol";
import "../../src/libraries/DecimalMath.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IModelHelper {
    function getTotalSupply(address pool, bool isToken0) external view returns (uint256);
}

interface IBaseVault {
    function shift() external;
    function slide() external;
}

struct ContractAddressesJson {
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

contract Shift is Script {
    // Command to deploy:
    // forge script script/Deploy.s.sol --rpc-url=<RPC_URL> --broadcast --slow

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    address payable idoManagerAddress;
    address modelHelperAddress;

    function run() public {  
        vm.recordLogs();
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

        // Extract addresses from JSON
        idoManagerAddress = payable(addresses.IDOHelper);
        modelHelperAddress = addresses.ModelHelper;

        IDOHelper idoManager = IDOHelper(idoManagerAddress);

        LendingVault vault = LendingVault(address(idoManager.vault()));

        uint256 totalSupplyBeforeShift = IModelHelper(modelHelperAddress)
        .getTotalSupply(
            address(idoManager.pool()), 
            true
        );
        
        console.log("totalSupplyBeforeShift is %d", totalSupplyBeforeShift);

        IBaseVault(address(vault)).shift();

        uint256 totalSupplyAfterShift = IModelHelper(modelHelperAddress)
        .getTotalSupply(
            address(idoManager.pool()), 
            true
        );

        console.log("totalSupplyAfterShift is %d", totalSupplyAfterShift);

        uint256 supplyRatio = DecimalMath.divideDecimal(totalSupplyBeforeShift, totalSupplyAfterShift);

        console.log("Supply ratio is %d", supplyRatio);

        // uint256 upperDiscoveryPrice = 0.00065e18 * 15;

        // // Upper bound for discovery position
        // // vault.deployDiscovery(
        // //     upperDiscoveryPrice
        // // );
        
        // VmSafe.Log[] memory entries = vm.getRecordedLogs();
        // console.log("Entries: %s", entries.length);

        // assert(entries[0].topics[0] == keccak256("FloorUpdated(uint256,uint256)"));
        vm.stopBroadcast();
    }

}
