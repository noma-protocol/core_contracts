// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "./token/TestGons.sol";
import "./token/TestMockNomaToken.sol";
import "../src/staking/Staking.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TestRebaseTokenTransfers is Test {
    using SafeERC20 for IERC20;

    TestGons rebaseToken;
    TestMockNomaToken mockNomaToken;
    Staking staking;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 INITIAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        mockNomaToken = new TestMockNomaToken();
        mockNomaToken.initialize(address(this), 100_000_000e18, "TEST", "TEST", address(0));

        rebaseToken = new TestGons();
        staking = new Staking(address(mockNomaToken), address(rebaseToken), address(this));        
        mockNomaToken.mintTest(address(staking), INITIAL_SUPPLY);
        // staking.setup(address(this), address(mockNomaToken), address(rebaseToken));
        rebaseToken.initialize(address(staking));

        // Distribute some tokens to Alice and Bob
        vm.startPrank(address(staking));
        rebaseToken.transfer(alice, 10_000e18);
        rebaseToken.transfer(bob, 5_000e18);
        vm.stopPrank();
    }

    function testTransferFromAliceToBob() public {
        uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);
        uint256 bobBalanceBefore = rebaseToken.balanceOf(bob);

        vm.prank(alice);
        rebaseToken.transfer(bob, 1_000e18);

        assertEq(rebaseToken.balanceOf(alice), aliceBalanceBefore - 1_000e18, "Alice's balance should decrease");
        assertEq(rebaseToken.balanceOf(bob), bobBalanceBefore + 1_000e18, "Bob's balance should increase");
    }

    function testTransferFromBobToAlice() public {
        uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);
        uint256 bobBalanceBefore = rebaseToken.balanceOf(bob);

        vm.prank(bob);
        rebaseToken.transfer(alice, 500e18);

        assertEq(rebaseToken.balanceOf(bob), bobBalanceBefore - 500e18, "Bob's balance should decrease");
        assertEq(rebaseToken.balanceOf(alice), aliceBalanceBefore + 500e18, "Alice's balance should increase");
    }

    // function testTransferFromWithApproval() public {
    //     uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);
    //     uint256 charlieBalanceBefore = rebaseToken.balanceOf(charlie);

    //     vm.prank(alice);
    //     rebaseToken.approve(bob, 2_000e18);

    //     vm.prank(bob);
    //     rebaseToken.transferFrom(alice, charlie, 1_500e18);

    //     assertEq(rebaseToken.balanceOf(alice), aliceBalanceBefore - 1_500e18, "Alice's balance should decrease");
    //     assertEq(rebaseToken.balanceOf(charlie), charlieBalanceBefore + 1_500e18, "Charlie's balance should increase");
    //     assertEq(rebaseToken.allowance(alice, bob), 500e18, "Allowance should decrease");
    // }

    function testTransferFromWithoutApproval() public {
        vm.prank(bob);
        vm.expectRevert();
        rebaseToken.transferFrom(alice, charlie, 1_000e18);
    }

    function testTransferMoreThanBalance() public {
        uint256 aliceBalance = rebaseToken.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert();
        rebaseToken.transfer(bob, aliceBalance + 1);
    }

    function testTransferFromMoreThanAllowance() public {
        vm.prank(alice);
        rebaseToken.approve(bob, 1_000e18);

        vm.prank(bob);
        vm.expectRevert();
        rebaseToken.transferFrom(alice, charlie, 1_001e18);
    }

    function testTransferZeroAmount() public {
        uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);
        uint256 bobBalanceBefore = rebaseToken.balanceOf(bob);

        vm.prank(alice);
        rebaseToken.transfer(bob, 0);

        assertEq(rebaseToken.balanceOf(alice), aliceBalanceBefore, "Alice's balance should not change");
        assertEq(rebaseToken.balanceOf(bob), bobBalanceBefore, "Bob's balance should not change");
    }

    function testTransferToSelf() public {
        uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);

        vm.prank(alice);
        rebaseToken.transfer(alice, 1_000e18);

        assertEq(rebaseToken.balanceOf(alice), aliceBalanceBefore, "Alice's balance should not change");
    }

    // function testTransferFromToSelf() public {
    //     uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);

    //     vm.prank(alice);
    //     rebaseToken.approve(alice, 1_000e18);

    //     vm.prank(alice);
    //     rebaseToken.transferFrom(alice, alice, 1_000e18);

    //     assertEq(rebaseToken.balanceOf(alice), aliceBalanceBefore, "Alice's balance should not change");
    //     assertEq(rebaseToken.allowance(alice, alice), 0, "Allowance should be consumed");
    // }

    function testTransferAfterRebase() public {
        uint256 rebaseAmount = 1_000e18;
        rebaseToken.rebase(rebaseAmount);

        uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);
        uint256 bobBalanceBefore = rebaseToken.balanceOf(bob);

        vm.prank(alice);
        rebaseToken.transfer(bob, 1_000e18);

        assertEq(rebaseToken.balanceOf(alice), aliceBalanceBefore - 1_000e18, "Alice's balance should decrease");
        assertEq(rebaseToken.balanceOf(bob), bobBalanceBefore + 1_000e18, "Bob's balance should increase");
    }

    // function testTransferFromAfterRebase() public {
    //     uint256 rebaseAmount = 1_000e18;
    //     rebaseToken.rebase(rebaseAmount);

    //     vm.prank(alice);
    //     rebaseToken.approve(bob, 2_000e18);

    //     uint256 aliceBalanceBefore = rebaseToken.balanceOf(alice);
    //     uint256 charlieBalanceBefore = rebaseToken.balanceOf(charlie);

    //     vm.prank(bob);
    //     rebaseToken.transferFrom(alice, charlie, 1_500e18);

    //     assertEq(rebaseToken.balanceOf(alice), aliceBalanceBefore - 1_500e18, "Alice's balance should decrease");
    //     assertEq(rebaseToken.balanceOf(charlie), charlieBalanceBefore + 1_500e18, "Charlie's balance should increase");
    //     assertEq(rebaseToken.allowance(alice, bob), 500e18, "Allowance should decrease");
    // }

}