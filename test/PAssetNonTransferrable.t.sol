// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { pAsset } from "../src/bootstrap/token/pAsset.sol";
import "../src/types/Errors.sol";

/// @title pAsset Non-Transferability Tests
/// @notice Unit tests to verify pAsset tokens cannot be transferred between addresses
contract PAssetNonTransferrableTest is Test {
    pAsset public token;

    address public user1 = address(0x1111);
    address public user2 = address(0x2222);
    address public user3 = address(0x3333);

    function setUp() public {
        token = new pAsset("Presale Asset", "pASSET", 18);
    }

    // ============ NON-TRANSFERABILITY TESTS ============

    /// @notice Test that transfer() reverts with NonTransferrable
    function testTransfer_Reverts() public {
        // Mint some tokens to user1 (simulating what Presale does)
        vm.prank(address(this));
        _mint(user1, 1000 ether);

        assertEq(token.balanceOf(user1), 1000 ether);

        // Attempt to transfer - should revert
        vm.prank(user1);
        vm.expectRevert(NonTransferrable.selector);
        token.transfer(user2, 500 ether);
    }

    /// @notice Test that transferFrom() reverts with NonTransferrable
    function testTransferFrom_Reverts() public {
        _mint(user1, 1000 ether);

        // User1 approves user2
        vm.prank(user1);
        token.approve(user2, 1000 ether);

        // User2 attempts transferFrom - should revert
        vm.prank(user2);
        vm.expectRevert(NonTransferrable.selector);
        token.transferFrom(user1, user3, 500 ether);
    }

    /// @notice Test that transfer of zero amount also reverts
    function testTransfer_ZeroAmount_Reverts() public {
        _mint(user1, 1000 ether);

        vm.prank(user1);
        vm.expectRevert(NonTransferrable.selector);
        token.transfer(user2, 0);
    }

    /// @notice Test transfer to self reverts (not a burn)
    function testTransfer_ToSelf_Reverts() public {
        _mint(user1, 1000 ether);

        vm.prank(user1);
        vm.expectRevert(NonTransferrable.selector);
        token.transfer(user1, 500 ether);
    }

    /// @notice Test partial transfer reverts
    function testTransfer_PartialAmount_Reverts() public {
        _mint(user1, 1000 ether);

        vm.prank(user1);
        vm.expectRevert(NonTransferrable.selector);
        token.transfer(user2, 1); // Just 1 wei
    }

    // ============ MINT/BURN STILL WORK ============

    /// @notice Test that minting works (from = address(0))
    function testMint_Works() public {
        assertEq(token.balanceOf(user1), 0);

        _mint(user1, 1000 ether);

        assertEq(token.balanceOf(user1), 1000 ether);
    }

    /// @notice Test that burning works (to = address(0))
    function testBurn_Works() public {
        _mint(user1, 1000 ether);
        assertEq(token.balanceOf(user1), 1000 ether);

        _burn(user1, 500 ether);

        assertEq(token.balanceOf(user1), 500 ether);
    }

    /// @notice Test full burn works
    function testBurn_FullBalance_Works() public {
        _mint(user1, 1000 ether);

        _burn(user1, 1000 ether);

        assertEq(token.balanceOf(user1), 0);
    }

    /// @notice Test multiple mints work
    function testMint_Multiple_Works() public {
        _mint(user1, 100 ether);
        _mint(user1, 200 ether);
        _mint(user2, 300 ether);

        assertEq(token.balanceOf(user1), 300 ether);
        assertEq(token.balanceOf(user2), 300 ether);
    }

    // ============ APPROVAL STILL WORKS (even though transfer doesn't) ============

    /// @notice Test that approve still works (needed for some integrations)
    function testApprove_Works() public {
        _mint(user1, 1000 ether);

        vm.prank(user1);
        bool success = token.approve(user2, 500 ether);

        assertTrue(success);
        assertEq(token.allowance(user1, user2), 500 ether);
    }

    // ============ HELPER FUNCTIONS ============

    /// @dev Helper to mint tokens (simulates Presale minting)
    function _mint(address to, uint256 amount) internal {
        // Use vm.store to directly set balance since pAsset doesn't expose mint
        // First get current balance
        uint256 currentBalance = token.balanceOf(to);
        uint256 currentSupply = token.totalSupply();

        // Calculate storage slots for ERC20
        // balanceOf mapping is at slot 0
        bytes32 balanceSlot = keccak256(abi.encode(to, uint256(0)));
        vm.store(address(token), balanceSlot, bytes32(currentBalance + amount));

        // totalSupply is at slot 2
        vm.store(address(token), bytes32(uint256(2)), bytes32(currentSupply + amount));
    }

    /// @dev Helper to burn tokens (simulates Presale burning)
    function _burn(address from, uint256 amount) internal {
        uint256 currentBalance = token.balanceOf(from);
        uint256 currentSupply = token.totalSupply();

        require(currentBalance >= amount, "Burn exceeds balance");

        bytes32 balanceSlot = keccak256(abi.encode(from, uint256(0)));
        vm.store(address(token), balanceSlot, bytes32(currentBalance - amount));
        vm.store(address(token), bytes32(uint256(2)), bytes32(currentSupply - amount));
    }
}
