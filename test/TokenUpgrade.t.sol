// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./token/TestMockOikosToken.sol";
import "./token/TestMockOikosTokenV2.sol";
import "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

interface OikosFactory {
    function upgradeToken(
        address _token,
        address _newImplementation
    ) external;
}

contract TestTokenUpgrade is Test {
    TestMockOikosToken public mockOikosToken;
    TestMockOikosTokenV2 public mockOikosTokenV2;
    ERC1967Proxy public proxy;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address user = address(2);
    address uniswapV3Pool = 0x18255e6a727Ed2f9c7261E8A59Fb6F884CB6C368;
    address nonUniswapV3Pool = address(4);
    address factoryAddress = address(0);
    address proxyAddress = address(0);

    function setUp() public {
        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);

        string memory networkId = "56";
        // Parse the data for network ID `56`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));

        // Extract addresses from JSON
        factoryAddress = addresses.Factory;
        proxyAddress = addresses.Proxy;

    }

    function testDirectUpgrade() public {

        // Deploy new implementation
        mockOikosTokenV2 = new TestMockOikosTokenV2();

        // Upgrade the proxy to use the new implementation
        vm.prank(factoryAddress);
        TestMockOikosToken(proxyAddress).upgradeToAndCall(address(mockOikosTokenV2), new bytes(0));

        // Cast the proxy to MockOikosTokenV2 to interact with the new implementation
        TestMockOikosTokenV2 upgraded = TestMockOikosTokenV2(proxyAddress);

        // Check if the new implementation is in use
        assertEq(upgraded.version(), "V2");        

    }
    
    function testUpgradeThroughFactory() public {
        // Deploy new implementation
        mockOikosTokenV2 = new TestMockOikosTokenV2();

        // Upgrade the proxy to use the new implementation
        vm.prank(deployer);
        OikosFactory(factoryAddress).upgradeToken(proxyAddress, address(mockOikosTokenV2));

        // Cast the proxy to MockOikosTokenV2 to interact with the new implementation
        TestMockOikosTokenV2 upgraded = TestMockOikosTokenV2(proxyAddress);

        // Check if the new implementation is in use
        assertEq(upgraded.version(), "V2");        
    }

    function testCannotUpgradeFromNonDeployer() public {
        // Deploy new implementation
        mockOikosTokenV2 = new TestMockOikosTokenV2();

        // Try to upgrade the proxy from a non-deployer account
        vm.prank(user);
        vm.expectRevert();
        OikosFactory(factoryAddress).upgradeToken(proxyAddress, address(mockOikosTokenV2));
        
        // Verify that the upgrade did not happen by checking the version is still V1
        assertEq(TestMockOikosToken(proxyAddress).version(), "1");
    }
}