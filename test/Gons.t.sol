// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "./token/TestGons.sol";

contract TestGonsToken is Test {
    TestGons gons;

    function setUp() public {
        gons = new TestGons();
        gons.setIndex(1);
        gons.initialize(address(this));
    }

    function testRebase() public {

        uint256 balance = gons.balanceOf(address(this));    
        assertEq(balance, 1000e18);

        gons.rebase(1e18);
        assertEq(gons.totalSupply(), 1001e18);

        gons.rebase(100e18);
        assertEq(gons.totalSupply(), 1101e18);

    }
}