// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "./token/TestMockNomaToken.sol";
import "./token/TestMockNomaTokenV2.sol";
import "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployToken is Test {
    TestMockNomaToken public mockNomaToken;
    TestMockNomaTokenV2 public mockNomaTokenV2;
    ERC1967Proxy public proxy;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    address user = address(2);

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy the implementation contract
        mockNomaToken = new TestMockNomaToken();

        // Encode the initialize function call
        bytes memory data = abi.encodeWithSelector(
            mockNomaToken.initialize.selector,
            deployer,
            1000000 ether,
            "Mock NOMA",
            "MNOMA",
            address(0)
        );

        // Deploy the proxy contract
        proxy = new ERC1967Proxy(
            address(mockNomaToken),
            data
        );

        // Cast the proxy to MockNomaToken to interact with it
        mockNomaToken = TestMockNomaToken(address(proxy));

        // Mint tokens
        mockNomaToken.mintTest(deployer, 100 ether);
        mockNomaToken.transfer(user, 100 ether);

        vm.stopPrank();
    }

    function testInitialSupply() public {
        uint256 deployerBalance = mockNomaToken.balanceOf(deployer);
        assertEq(deployerBalance, 1000000 ether);
    }

    function testTransfer() public {
        uint256 userBalance = mockNomaToken.balanceOf(user);
        assertEq(userBalance, 100 ether);
    }

    function testUpgrade() public {
        // Deploy new implementation
        mockNomaTokenV2 = new TestMockNomaTokenV2();

        // Upgrade the proxy to use the new implementation
        vm.prank(deployer);
        TestMockNomaToken(address(proxy)).upgradeToAndCall(address(mockNomaTokenV2), new bytes(0));

        // Cast the proxy to TestMockNomaTokenV2 to interact with the new implementation
        TestMockNomaTokenV2 upgraded = TestMockNomaTokenV2(address(proxy));

        mockNomaTokenV2 = upgraded;
        bytes32 uuid = mockNomaTokenV2.proxiableUUID();

        console.log("UUID %s", uint256(uuid));

        // Check if the new implementation is in use
        assertEq(upgraded.version(), "V2");

        // Verify the balance functionality remains correct
        uint256 userBalance = upgraded.balanceOf(user);
        assertEq(userBalance, 100 ether);
    }

    function testProxiableUUID() public {
        // Check that the proxiableUUID returns the correct value
        bytes32 uuid = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        console.log("UUID %s", uint256(uuid));

        assertEq(mockNomaToken.proxiableUUID(), uuid);

        // Deploy new implementation
        mockNomaTokenV2 = new TestMockNomaTokenV2();
        assertEq(mockNomaTokenV2.proxiableUUID(), uuid);
    }
}
