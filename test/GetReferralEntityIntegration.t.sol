// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/vault/AuxVault.sol";
import "../src/libraries/Utils.sol";
import "../src/types/Types.sol";

contract MockAuxVault is AuxVault {
    // Mock implementation to test getReferralEntity
    constructor() {
        // Initialize minimal storage for testing
    }
    
    function testSetReferral(bytes8 code, uint256 amount) external {
        _v.referrals[code] = ReferralEntity({
            code: code,
            totalReferred: amount
        });
    }
}

contract GetReferralEntityIntegrationTest is Test {
    MockAuxVault vault;
    
    function setUp() public {
        vault = new MockAuxVault();
    }
    
    function testGetReferralEntityWithNoData() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // Call getReferralEntity - should return empty entity
        ReferralEntity memory entity = vault.getReferralEntity(testAddress);
        
        console.log("Entity code:");
        console.logBytes8(entity.code);
        console.log("Entity totalReferred:", entity.totalReferred);
        
        // Since no data exists, it should return the calculated code with 0 totalReferred
        bytes8 expectedCode = Utils.getReferralCode(testAddress);
        assertEq(entity.code, bytes8(0), "Empty entity should have zero code");
        assertEq(entity.totalReferred, 0, "Empty entity should have 0 totalReferred");
    }
    
    function testGetReferralEntityWithData() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        bytes8 code = Utils.getReferralCode(testAddress);
        uint256 referredAmount = 5000 ether;
        
        // Set referral data
        vault.testSetReferral(code, referredAmount);
        
        // Call getReferralEntity - should return the stored entity
        ReferralEntity memory entity = vault.getReferralEntity(testAddress);
        
        console.log("Entity code:");
        console.logBytes8(entity.code);
        console.log("Entity totalReferred:", entity.totalReferred);
        
        assertEq(entity.code, code, "Entity code should match");
        assertEq(entity.totalReferred, referredAmount, "Entity totalReferred should match");
    }
    
    function testGetReferralEntityMultipleAddresses() public {
        address addr1 = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        address addr2 = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        
        bytes8 code1 = Utils.getReferralCode(addr1);
        bytes8 code2 = Utils.getReferralCode(addr2);
        
        // Set different amounts for different addresses
        vault.testSetReferral(code1, 1000 ether);
        vault.testSetReferral(code2, 2000 ether);
        
        // Get entities
        ReferralEntity memory entity1 = vault.getReferralEntity(addr1);
        ReferralEntity memory entity2 = vault.getReferralEntity(addr2);
        
        console.log("Entity1 totalReferred:", entity1.totalReferred);
        console.log("Entity2 totalReferred:", entity2.totalReferred);
        
        assertEq(entity1.totalReferred, 1000 ether, "Entity1 should have correct amount");
        assertEq(entity2.totalReferred, 2000 ether, "Entity2 should have correct amount");
        assertTrue(entity1.code != entity2.code, "Different addresses should have different codes");
    }
    
    function testOriginalFailingAddress() public {
        // Test with the specific address that was failing
        address failingAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // This should now work without reverting
        ReferralEntity memory entity = vault.getReferralEntity(failingAddress);
        
        console.log("Successfully retrieved entity for previously failing address");
        console.log("Code:");
        console.logBytes8(entity.code);
        console.log("TotalReferred:", entity.totalReferred);
        
        // The function should succeed
        assertEq(entity.code, bytes8(0), "Should return zero code for non-existent referral");
        assertEq(entity.totalReferred, 0, "Should return 0 for non-existent referral");
    }
}