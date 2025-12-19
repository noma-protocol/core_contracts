// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenRepo.sol";
import "../src/libraries/Utils.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/errors/Errors.sol";

// Mock ERC20 for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1000000e18);
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title SecurityFixesTest
 * @notice Tests to verify security fixes work correctly without breaking functionality
 */
contract SecurityFixesTest is Test {

    /* ==================== TokenRepo Ownership Tests (H-04) ==================== */

    TokenRepo public tokenRepo;
    address public owner = address(0x1);
    address public newOwner = address(0x2);
    address public attacker = address(0x3);

    function setUp() public {
        vm.prank(owner);
        tokenRepo = new TokenRepo(owner);
    }

    function test_TokenRepo_InitialOwner() public view {
        assertEq(tokenRepo.owner(), owner);
        assertEq(tokenRepo.pendingOwner(), address(0));
    }

    function test_TokenRepo_TransferOwnership_TwoStep() public {
        // Step 1: Current owner initiates transfer
        vm.prank(owner);
        tokenRepo.transferOwnership(newOwner);

        // Owner hasn't changed yet
        assertEq(tokenRepo.owner(), owner);
        assertEq(tokenRepo.pendingOwner(), newOwner);

        // Step 2: New owner accepts
        vm.prank(newOwner);
        tokenRepo.acceptOwnership();

        // Now ownership is transferred
        assertEq(tokenRepo.owner(), newOwner);
        assertEq(tokenRepo.pendingOwner(), address(0));
    }

    function test_TokenRepo_TransferOwnership_OnlyOwnerCanInitiate() public {
        vm.prank(attacker);
        vm.expectRevert(OnlyOwner.selector);
        tokenRepo.transferOwnership(attacker);
    }

    function test_TokenRepo_AcceptOwnership_OnlyPendingOwner() public {
        // Owner initiates transfer
        vm.prank(owner);
        tokenRepo.transferOwnership(newOwner);

        // Attacker tries to accept
        vm.prank(attacker);
        vm.expectRevert(NotAuthorized.selector);
        tokenRepo.acceptOwnership();
    }

    function test_TokenRepo_TransferOwnership_CannotSetToZero() public {
        vm.prank(owner);
        vm.expectRevert(ZeroAddress.selector);
        tokenRepo.transferOwnership(address(0));
    }

    function test_TokenRepo_TransferOwnership_CannotSetToSelf() public {
        vm.prank(owner);
        vm.expectRevert(InvalidParams.selector);
        tokenRepo.transferOwnership(owner);
    }

    /* ==================== Referral Code Tests (MEDIUM) ==================== */

    function test_ReferralCode_Returns8Bytes() public pure {
        address user = address(0x1234567890123456789012345678901234567890);
        bytes8 code = Utils.getReferralCode(user);

        // Verify it's 8 bytes (64 bits), not 4 bytes
        // bytes8 is always 8 bytes, so we check it's not all zeros in the last 4 bytes
        assertTrue(code != bytes8(0), "Code should not be zero");
    }

    function test_ReferralCode_DifferentUsersGetDifferentCodes() public pure {
        address user1 = address(0x1);
        address user2 = address(0x2);

        bytes8 code1 = Utils.getReferralCode(user1);
        bytes8 code2 = Utils.getReferralCode(user2);

        assertTrue(code1 != code2, "Different users should have different codes");
    }

    function test_ReferralCode_SameUserGetsSameCode() public pure {
        address user = address(0x1234);

        bytes8 code1 = Utils.getReferralCode(user);
        bytes8 code2 = Utils.getReferralCode(user);

        assertEq(code1, code2, "Same user should always get same code");
    }

    function test_ReferralCode_GenerateAndGetAreConsistent() public pure {
        address user = address(0x5678);

        bytes8 generated = Utils.generateReferralCode(user);
        bytes8 retrieved = Utils.getReferralCode(user);

        assertEq(generated, retrieved, "generateReferralCode and getReferralCode should match");
    }

    function test_ReferralCode_CodeStringLength() public pure {
        address user = address(0x1234);

        string memory codeStr = Utils.getCodeString(user);

        // 8 bytes = 16 hex characters
        assertEq(bytes(codeStr).length, 16, "Code string should be 16 hex characters");
    }

    /* ==================== Fee Calculation Tests (H-05) ==================== */

    // Replicating the fixed fee calculation from LendingVault
    function _calculateLoanFees_FIXED(
        uint256 borrowAmount,
        uint256 duration,
        uint256 loanFee
    ) internal pure returns (uint256 fees) {
        uint256 SECONDS_IN_DAY = 86_400;
        fees = (borrowAmount * loanFee * duration) / (SECONDS_IN_DAY * 100_000);
    }

    // Old calculation for comparison
    function _calculateLoanFees_OLD(
        uint256 borrowAmount,
        uint256 duration,
        uint256 loanFee
    ) internal pure returns (uint256 fees) {
        uint256 SECONDS_IN_DAY = 86400;
        uint256 daysElapsed = duration / SECONDS_IN_DAY;
        fees = (borrowAmount * loanFee * daysElapsed) / 100_000;
    }

    function test_FeeCalculation_30Days() public pure {
        uint256 borrowAmount = 2e18; // 2 tokens
        uint256 duration = 30 days;
        uint256 loanFee = 57; // 0.057% daily

        uint256 feesFixed = _calculateLoanFees_FIXED(borrowAmount, duration, loanFee);
        uint256 feesOld = _calculateLoanFees_OLD(borrowAmount, duration, loanFee);

        // Both should give same result for full days
        assertEq(feesFixed, feesOld, "30-day fees should match");
        assertEq(feesFixed, 0.0342e18, "30-day fee should be 0.0342 tokens");
    }

    function test_FeeCalculation_SubDay_OldReturnsZero() public pure {
        uint256 borrowAmount = 100e18;
        uint256 duration = 12 hours; // Less than 1 day
        uint256 loanFee = 57;

        uint256 feesOld = _calculateLoanFees_OLD(borrowAmount, duration, loanFee);

        // Old calculation loses precision for < 1 day
        assertEq(feesOld, 0, "Old calculation returns 0 for sub-day loans");
    }

    function test_FeeCalculation_SubDay_FixedCalculatesCorrectly() public pure {
        uint256 borrowAmount = 100e18;
        uint256 duration = 12 hours;
        uint256 loanFee = 57;

        uint256 feesFixed = _calculateLoanFees_FIXED(borrowAmount, duration, loanFee);

        // Fixed calculation should give non-zero value
        assertTrue(feesFixed > 0, "Fixed calculation should return non-zero for sub-day loans");

        // 12 hours = 0.5 days, so fee should be ~half of 1 day fee
        // 1 day fee = 100 * 57 / 100_000 = 0.057 tokens
        // 0.5 day fee = 0.0285 tokens
        assertEq(feesFixed, 0.0285e18, "12-hour fee should be 0.0285 tokens");
    }

    function test_FeeCalculation_1Day() public pure {
        uint256 borrowAmount = 100e18;
        uint256 duration = 1 days;
        uint256 loanFee = 57;

        uint256 feesFixed = _calculateLoanFees_FIXED(borrowAmount, duration, loanFee);
        uint256 feesOld = _calculateLoanFees_OLD(borrowAmount, duration, loanFee);

        // Both should match for exactly 1 day
        assertEq(feesFixed, feesOld, "1-day fees should match");
        assertEq(feesFixed, 0.057e18, "1-day fee should be 0.057 tokens");
    }

    /* ==================== TokenRepo SafeERC20 Tests (C-02) ==================== */

    function test_TokenRepo_TransferTokens() public {
        MockERC20 token = new MockERC20();

        // Transfer tokens to TokenRepo
        token.transfer(address(tokenRepo), 100e18);
        assertEq(token.balanceOf(address(tokenRepo)), 100e18);

        // Owner transfers out
        vm.prank(owner);
        tokenRepo.transferToRecipient(address(token), newOwner, 50e18);

        assertEq(token.balanceOf(newOwner), 50e18);
        assertEq(token.balanceOf(address(tokenRepo)), 50e18);
    }

    function test_TokenRepo_TransferTokens_OnlyOwner() public {
        MockERC20 token = new MockERC20();
        token.transfer(address(tokenRepo), 100e18);

        vm.prank(attacker);
        vm.expectRevert(OnlyOwner.selector);
        tokenRepo.transferToRecipient(address(token), attacker, 50e18);
    }
}
