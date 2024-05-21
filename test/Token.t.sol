// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/token/MockNomaToken.sol";
import "./token/TestMockNomaTokenV2.sol";
import "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockNomaTokenTest is Test {
    MockNomaToken public mockNomaToken;
    TestMockNomaTokenV2 public mockNomaTokenV2;
    ERC1967Proxy public proxy;

    address deployer = vm.envAddress("DEPLOYER");
    address user = address(2);
    address uniswapV3Pool = 0x18255e6a727Ed2f9c7261E8A59Fb6F884CB6C368;
    address nonUniswapV3Pool = address(4);

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
        mockNomaTokenV2 = new TestMockNomaTokenV2();

        // Upgrade the proxy to use the new implementation
        vm.prank(deployer);
        MockNomaToken(address(proxy)).upgradeToAndCall(address(mockNomaTokenV2), new bytes(0));

        // Cast the proxy to MockNomaTokenV2 to interact with the new implementation
        TestMockNomaTokenV2 upgraded = TestMockNomaTokenV2(address(proxy));

        // Check if the new implementation is in use
        assertEq(upgraded.version(), "V2");
    }

    function testOnlyUniswapV3Restriction() public {
        // Deploy new implementation and upgrade the proxy
        mockNomaTokenV2 = new TestMockNomaTokenV2();
        vm.prank(deployer);
        MockNomaToken(address(proxy)).upgradeToAndCall(address(mockNomaTokenV2), new bytes(0));
        TestMockNomaTokenV2 upgraded = TestMockNomaTokenV2(address(proxy));

        // Allow uniswapV3Pool to perform transfers
        vm.prank(deployer);
        upgraded.addAllowedPool(uniswapV3Pool);

        // Transfer tokens to and from allowed Uniswap V3 pool (should succeed)
        vm.prank(deployer);
        bool success = upgraded.transfer(uniswapV3Pool, 10 ether);
        
        vm.prank(uniswapV3Pool);
        success = upgraded.transfer(user, 10 ether);
        assertTrue(success);

        uint256 userBalance = upgraded.balanceOf(user);
        assertEq(userBalance, 110 ether); // 100 ether from setup + 10 ether transfer

        // Attempt transfer through non-allowed pool (should fail)
        vm.prank(nonUniswapV3Pool);
        vm.expectRevert("Token can only be transferred via Uniswap V3");
        upgraded.transfer(user, 10 ether);
    }
}
