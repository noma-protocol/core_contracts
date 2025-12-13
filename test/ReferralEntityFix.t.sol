// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/libraries/Utils.sol";
import "../src/types/Types.sol";
import "../src/vault/AuxVault.sol";
import "../src/libraries/LibAppStorage.sol";

contract ReferralEntityFixTest is Test {
    
    function testGetReferralCode() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // Test the new getReferralCode function
        bytes8 code = Utils.getReferralCode(testAddress);
        console.log("Referral code (bytes8):");
        console.logBytes8(code);
        
        // Verify it matches the expected value
        bytes32 hash = keccak256(abi.encodePacked(testAddress));
        bytes8 expectedCode = bytes8(hash);
        assertEq(code, expectedCode, "Referral code should match first 8 bytes of hash");
    }
    
    function testReferralEntityStorage() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // Get the referral code
        bytes8 code = Utils.getReferralCode(testAddress);
        console.log("Referral code for storage test:");
        console.logBytes8(code);
        
        // Create a referral entity
        ReferralEntity memory entity = ReferralEntity({
            code: code,
            totalReferred: 1000 ether
        });
        
        console.log("Created entity with totalReferred:", entity.totalReferred);
        assertEq(entity.code, code, "Entity code should match");
        assertEq(entity.totalReferred, 1000 ether, "Entity totalReferred should match");
    }
    
    function testMultipleAddresses() public {
        address addr1 = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        address addr2 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT address
        address addr3 = 0x0000000000000000000000000000000000000000; // Zero address
        
        bytes8 code1 = Utils.getReferralCode(addr1);
        bytes8 code2 = Utils.getReferralCode(addr2);
        bytes8 code3 = Utils.getReferralCode(addr3);
        
        console.log("Code for addr1:");
        console.logBytes8(code1);
        console.log("Code for addr2:");
        console.logBytes8(code2);
        console.log("Code for addr3:");
        console.logBytes8(code3);
        
        // Ensure different addresses produce different codes
        assertTrue(code1 != code2, "Different addresses should have different codes");
        assertTrue(code1 != code3, "Different addresses should have different codes");
        assertTrue(code2 != code3, "Different addresses should have different codes");
    }
    
    function testCompatibilityWithOldApproach() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // Old approach would generate a 16-char hex string
        string memory codeStr = Utils.getCodeString(testAddress);
        console.log("Old approach hex string:", codeStr);
        console.log("Length:", bytes(codeStr).length);
        
        // New approach generates bytes8 directly
        bytes8 newCode = Utils.getReferralCode(testAddress);
        console.log("New approach bytes8:");
        console.logBytes8(newCode);
        
        // Verify they represent the same underlying data
        bytes32 hash = keccak256(abi.encodePacked(testAddress));
        bytes8 expectedCode = bytes8(hash);
        assertEq(newCode, expectedCode, "New code should match expected");
    }
}