// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/token/MockNomaToken.sol";
import "./token/MockNomaTokenV2.sol";
import "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockNomaTokenTest is Test {
    MockNomaToken public mockNomaToken;
    MockNomaTokenV2 public mockNomaTokenV2;
    ERC1967Proxy public proxy;

    address deployer = address(1);
    address user = address(2);

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy the implementation contract
        mockNomaToken = new MockNomaToken();

        // Encode the initialize function call
        bytes memory data = abi.encodeWithSelector(
            mockNomaToken.initialize.selector,
            deployer,
            1000000 ether
        );

        // Deploy the proxy contract
        proxy = new ERC1967Proxy(
            address(mockNomaToken),
            data
        );

        // Cast the proxy to MockNomaToken to interact with it
        mockNomaToken = MockNomaToken(address(proxy));

        // Mint some tokens to user
        mockNomaToken.transfer(user, 100 ether);

        vm.stopPrank();
    }

    function testInitialSupply() public {
        uint256 deployerBalance = mockNomaToken.balanceOf(deployer);
        assertEq(deployerBalance, 999900 ether);
    }

    function testTransfer() public {
        uint256 userBalance = mockNomaToken.balanceOf(user);
        assertEq(userBalance, 100 ether);
    }

    function testUpgrade() public {
        // Deploy new implementation
        mockNomaTokenV2 = new MockNomaTokenV2();

        // Upgrade the proxy to use the new implementation
        vm.prank(deployer);
        MockNomaToken(address(proxy)).upgradeToAndCall(address(mockNomaTokenV2), new bytes(0));

        // Cast the proxy to MockNomaTokenV2 to interact with the new implementation
        MockNomaTokenV2 upgraded = MockNomaTokenV2(address(proxy));

        // Check if the new implementation is in use
        assertEq(upgraded.version(), "V2");
    }
}
