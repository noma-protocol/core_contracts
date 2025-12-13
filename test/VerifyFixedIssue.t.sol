// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/libraries/Utils.sol";

contract VerifyFixedIssueTest is Test {
    
    function testOriginalIssueIsFixed() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // This was the original failing code path
        string memory codeStr = Utils.getCodeString(testAddress);
        console.log("getCodeString returns:", codeStr);
        console.log("Length:", bytes(codeStr).length);
        
        // This would fail before with "String too long for bytes8"
        // Now we're using a different approach with getReferralCode
        bytes8 code = Utils.getReferralCode(testAddress);
        console.log("getReferralCode returns:");
        console.logBytes8(code);
        
        // Verify the code matches expected value
        bytes32 hash = keccak256(abi.encodePacked(testAddress));
        assertEq(code, bytes8(hash), "Code should match first 8 bytes of address hash");
    }
}