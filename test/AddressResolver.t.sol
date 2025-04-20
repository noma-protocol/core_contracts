// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { TestResolver } from "./resolver/Resolver.sol";
import { Utils } from "../src/libraries/Utils.sol";

struct ContractInfo {
    string name;
    address addr;
}

contract AddressResolverTest is Test {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    address user = address(2);

    TestResolver resolver;
    ContractInfo[] private expectedAddressesInResolver;

    address WBNB = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;

    function setUp() public {
        // Resolver
        resolver = new TestResolver(deployer);
    }
    
    function testAreAddressesImported() public {
        expectedAddressesInResolver.push(ContractInfo("Resolver", address(resolver)));
        expectedAddressesInResolver.push(ContractInfo("WBNB", WBNB));

        bytes32[] memory names = new bytes32[](expectedAddressesInResolver.length);
        address[] memory addresses = new address[](expectedAddressesInResolver.length);

        for (uint256 i = 0; i < expectedAddressesInResolver.length; i++) {
            names[i] = Utils.stringToBytes32(expectedAddressesInResolver[i].name);
            addresses[i] = expectedAddressesInResolver[i].addr;
        }

        vm.prank(deployer);
        resolver.importAddresses(names, addresses);

        bool result = resolver.areAddressesImported(names, addresses);
        assertTrue(result, "Expected all addresses to be imported");

        // Test edge case - mismatched addresses
        addresses[0] = address(0xdead); // Introduce a mismatch
        result = resolver.areAddressesImported(names, addresses);
        assertFalse(result, "Expected mismatch to return false");

        // Test edge case - mismatched names
        names[0] = Utils.stringToBytes32("InvalidName"); // Introduce a mismatch
        result = resolver.areAddressesImported(names, addresses);
        assertFalse(result, "Expected mismatch to return false");
    }

    function testEmptyResolver() public {
         for (uint256 i = 0; i < expectedAddressesInResolver.length; i++) {
            ContractInfo memory contractInfo = expectedAddressesInResolver[i];

            vm.expectRevert(abi.encodeWithSignature("AddressNotFound(string)", "not found"));

            resolver.requireAndGetAddress(Utils.stringToBytes32(contractInfo.name), "not found");
        }
    }

    function testResolverConfiguration() public {
        expectedAddressesInResolver.push(
            ContractInfo("Resolver", address(resolver))
        );  

        expectedAddressesInResolver.push(
            ContractInfo("WBNB", WBNB)
        );

        vm.prank(deployer);
        configureResolver();

        for (uint256 i = 0; i < expectedAddressesInResolver.length; i++) {
            ContractInfo memory contractInfo = expectedAddressesInResolver[i];
            assertEq(
                resolver.requireAndGetAddress(Utils.stringToBytes32(contractInfo.name), "not found"),
                contractInfo.addr
            );
        }
    }    

    function testConfigureDeployerACL() public {
        vm.expectRevert(abi.encodeWithSignature("OnlyFactoryOrManagerAllowed()"));
        
        vm.prank(user);
        resolver.configureDeployerACL(address(1));
        
        vm.prank(deployer);
        resolver.configureDeployerACL(address(2));
    }

    function configureResolver() internal {
        bytes32[] memory names = new bytes32[](expectedAddressesInResolver.length);
        address[] memory addresses = new address[](expectedAddressesInResolver.length);

        for (uint256 i = 0; i < expectedAddressesInResolver.length; i++) {
            names[i] = Utils.stringToBytes32(expectedAddressesInResolver[i].name);
            addresses[i] = expectedAddressesInResolver[i].addr;
        }

        bool areAddressesInResolver = resolver.areAddressesImported(names, addresses);

        if (!areAddressesInResolver) {
            vm.prank(deployer);
            resolver.importAddresses(names, addresses);
        }
    }
}