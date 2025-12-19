// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/libraries/Utils.sol";
import "../src/types/Types.sol";
import {Utils as UtilsLib} from "../src/libraries/Utils.sol";

/// @notice Helper contract to test internal library functions with expectRevert
contract StringToBytes8Caller {
    function callStringToBytes8(string memory source) external pure returns (bytes8) {
        return Utils.stringToBytes8(source);
    }
}

contract ReferralCodeTest is Test {
    StringToBytes8Caller internal caller;

    function setUp() public {
        caller = new StringToBytes8Caller();
    }

    function testGenerateReferralCodeFromAddress() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // Test generateReferralCode
        bytes32 code = Utils.generateReferralCode(testAddress);
        console.log("Generated referral code (bytes32):");
        console.logBytes32(code);
        
        // Convert to string representation for analysis
        bytes memory codeBytes = new bytes(32);
        for (uint i = 0; i < 32; i++) {
            codeBytes[i] = code[i];
        }
        console.log("First 8 bytes as hex string:");
        console.logBytes(codeBytes);
    }
    
    function testGetCodeString() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;

        // Test getCodeString
        string memory codeStr = Utils.getCodeString(testAddress);
        console.log("Code string from getCodeString:", codeStr);
        console.log("Code string length:", bytes(codeStr).length);

        // This should fail with InvalidInputLength
        // Using external call wrapper so vm.expectRevert works
        vm.expectRevert(UtilsLib.InvalidInputLength.selector);
        caller.callStringToBytes8(codeStr);
    }
    
    function testStringToBytes8WithValidInput() public {
        // Test with 8-character string
        string memory validStr = "12345678";
        bytes8 result = Utils.stringToBytes8(validStr);
        console.log("Valid string to bytes8:");
        console.logBytes8(result);
        
        // Test with shorter string
        string memory shortStr = "1234";
        bytes8 shortResult = Utils.stringToBytes8(shortStr);
        console.log("Short string to bytes8:");
        console.logBytes8(shortResult);
    }
    
    function testReferralCodeGeneration() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // Show what happens with keccak256
        bytes32 hash = keccak256(abi.encodePacked(testAddress));
        console.log("Keccak256 hash of address:");
        console.logBytes32(hash);
        
        // Extract first 8 bytes
        bytes8 first8Bytes = bytes8(hash);
        console.log("First 8 bytes of hash:");
        console.logBytes8(first8Bytes);
        
        // Convert to hex string manually
        bytes16 _HEX_SYMBOLS = "0123456789abcdef";
        bytes memory buffer = new bytes(16); // 8 bytes = 16 hex chars
        for (uint256 i = 0; i < 8; i++) {
            buffer[2*i]   = _HEX_SYMBOLS[uint8(first8Bytes[i] >> 4)];
            buffer[2*i+1] = _HEX_SYMBOLS[uint8(first8Bytes[i] & 0x0f)];
        }
        string memory hexString = string(buffer);
        console.log("Hex string representation (16 chars):", hexString);
        console.log("Hex string length:", bytes(hexString).length);
    }
    
    function testProblemDemonstration() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;

        // This is what getReferralEntity tries to do
        string memory codeStr = Utils.getCodeString(testAddress);
        console.log("getCodeString returns:", codeStr);
        console.log("Length:", bytes(codeStr).length);

        // This will fail because codeStr is 16 characters (8 bytes as hex)
        // but stringToBytes8 expects at most 8 characters
        // Using external call wrapper so vm.expectRevert works
        vm.expectRevert(UtilsLib.InvalidInputLength.selector);
        caller.callStringToBytes8(codeStr);
    }
    
    function testFixedApproach() public {
        address testAddress = 0x12e30FcC16B741a08cCf066074F0547F3ce79F32;
        
        // Direct approach - just use first 8 bytes of hash
        bytes8 code = bytes8(keccak256(abi.encodePacked(testAddress)));
        console.log("Direct bytes8 code:");
        console.logBytes8(code);
        
        // Or if you need the string, take only first 8 chars
        string memory fullCodeStr = Utils.getCodeString(testAddress);
        bytes memory strBytes = bytes(fullCodeStr);
        bytes memory truncated = new bytes(8);
        for (uint i = 0; i < 8; i++) {
            truncated[i] = strBytes[i];
        }
        string memory truncatedStr = string(truncated);
        console.log("Truncated string (8 chars):", truncatedStr);
        
        // This should work
        bytes8 truncatedCode = Utils.stringToBytes8(truncatedStr);
        console.log("Truncated code as bytes8:");
        console.logBytes8(truncatedCode);
    }
}