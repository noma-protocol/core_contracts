// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "../../src/token/NomaToken.sol";
import "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

interface NomaFactory {
    function upgradeToken(
        address _token,
        address _newImplementation
    ) external;
}

contract TokenUpgrade is Script {
    NomaToken public nomaToken;
    ERC1967Proxy public proxy;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address public proxyAddress = 0x689d31762f36fE4e5B816c0f5bf3D5947b947dbD;
    address public factoryAddress = 0xe5D683668d6D46bb16e4d4aAbd3c5E0b29a3bfeb;
    
    function run() public {
        vm.startBroadcast(privateKey);
        upgradeThroughFactory();
        vm.stopBroadcast();
    }

    function upgradeThroughFactory() public {
         // Deploy new implementation
        NomaToken newNomaToken = new NomaToken();

        // newNomaToken.initialize(
        //     deployer,
        //     3367606000000000000000000,
        //     10102818000000000000000000,
        //     "TEST TOKEN X",
        //     "TSX",
        //     0x4363087aC747128b53A74f5eB7c8DeAa678B00fe
        // );

        // Upgrade the proxy to use the new implementation
        NomaFactory(factoryAddress).upgradeToken(proxyAddress, address(newNomaToken));

        NomaToken upgraded = NomaToken(proxyAddress);
    }

}