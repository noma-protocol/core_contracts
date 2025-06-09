// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "./token/TestMockOikosToken.sol";
import "./token/TestMockOikosTokenV2.sol";
import "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployToken is Test {
    TestMockOikosToken public mockOikosToken;
    TestMockOikosTokenV2 public mockOikosTokenV2;
    ERC1967Proxy public proxy;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    address user = address(2);

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy the implementation contract
        mockOikosToken = new TestMockOikosToken();

        // Encode the initialize function call
        bytes memory data = abi.encodeWithSelector(
            mockOikosToken.initialize.selector,
            deployer,
            1000000 ether,
            2000000 ether,
            "Mock NOMA",
            "MOKS",
            address(0)
        );

        // Deploy the proxy contract
        proxy = new ERC1967Proxy(
            address(mockOikosToken),
            data
        );

        // Cast the proxy to MockOikosToken to interact with it
        mockOikosToken = TestMockOikosToken(address(proxy));

        // Mint tokens
        mockOikosToken.mintTest(deployer, 100 ether);
        mockOikosToken.transfer(user, 100 ether);

        vm.stopPrank();
    }

    function testInitialSupply() public {
        uint256 deployerBalance = mockOikosToken.balanceOf(deployer);
        assertEq(deployerBalance, 1000000 ether);
    }

    function testTransfer() public {
        uint256 userBalance = mockOikosToken.balanceOf(user);
        assertEq(userBalance, 100 ether);
    }

    function testUpgrade() public {
        // Deploy new implementation
        mockOikosTokenV2 = new TestMockOikosTokenV2();

        // Upgrade the proxy to use the new implementation
        vm.prank(deployer);
        TestMockOikosToken(address(proxy)).upgradeToAndCall(address(mockOikosTokenV2), new bytes(0));

        // Cast the proxy to TestMockOikosTokenV2 to interact with the new implementation
        TestMockOikosTokenV2 upgraded = TestMockOikosTokenV2(address(proxy));

        mockOikosTokenV2 = upgraded;
        bytes32 uuid = mockOikosTokenV2.proxiableUUID();

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

        assertEq(mockOikosToken.proxiableUUID(), uuid);

        // Deploy new implementation
        mockOikosTokenV2 = new TestMockOikosTokenV2();
        assertEq(mockOikosTokenV2.proxiableUUID(), uuid);
    }
}
