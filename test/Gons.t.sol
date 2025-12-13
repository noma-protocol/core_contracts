// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "./token/TestGons.sol";

contract TestGonsToken is Test {
    TestGons gons;

    function setUp() public {
        gons = new TestGons(1_000_000e18);
        // gons.setIndex(1);
        gons.initialize(address(this));

        // gons.mint(address(this), 1000e18);
        uint256 actualSupply = gons.totalSupply();
        console.log("actualSupply: ", actualSupply);
    }

    function testRebase() public {
        uint256 initialSupply = 10 * 10**18 * 10**18;
        uint256 balance = gons.balanceOf(address(this));    

        assertEq(balance, initialSupply);

        gons.rebase(1e18);
        
        uint256 expectedSupply = initialSupply + 1e18;
        uint256 actualSupply = gons.totalSupply();
        
        uint256 tolerance = 10e18; // Allow small precision error
        assertApproxEqAbs(actualSupply, expectedSupply, tolerance);

        gons.rebase(100e18);
        
        expectedSupply = initialSupply + 101e18;
        actualSupply = gons.totalSupply();

        assertApproxEqAbs(actualSupply, expectedSupply, tolerance); 
    }
}

