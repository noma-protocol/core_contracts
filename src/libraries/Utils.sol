

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Utils {
    
    function addBips(uint256 _price, int256 bips) public pure returns (uint256) {
        if (bips >= 0) {
            // Increase the price
            uint256 increase = (_price * uint256(bips)) / 10_000;
            return _price + increase;
        } else {
            // Decrease the price
            uint256 decrease = (_price * uint256(-bips)) / 10_000;
            // Ensure that the decrease does not go below zero
            if (decrease > _price) {
                return 0;
            } else {
                return _price - decrease;
            }
        }
    }

    function intToString(int256 _value) public pure returns (string memory) {
        // Handle zero case explicitly
        if (_value == 0) {
            return "0";
        }
        
        // Temporary buffer to store the reversed string
        bytes memory buffer = new bytes(100);
        uint256 length = 0;

        // Handle negative values
        bool isNegative = _value < 0;
        uint256 value = isNegative ? uint256(-_value) : uint256(_value);

        // Construct the string in reverse
        while (value != 0) {
            buffer[length++] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }

        // Add '-' for negative numbers
        if (isNegative) {
            buffer[length++] = '-';
        }

        // Reverse the string to get the correct representation
        bytes memory strBytes = new bytes(length);
        for (uint256 i = 0; i < length; ++i) {
            strBytes[i] = buffer[length - 1 - i];
        }

        return string(strBytes);
    }
    
    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function int24ToUint256(int24 _value) public pure returns (uint256) {
        require(_value >= 0, "Value is negative");
        return uint256(uint24(_value));
    }

    function toHexChar(uint8 byteValue) private pure returns (bytes memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(1);
        result[0] = alphabet[byteValue];
        return result;
    }

    function addressToString(address _address) public pure returns (string memory) {
        bytes32 _bytes = bytes32(uint256(uint160(_address)));
        bytes memory hexString = new bytes(42);
        hexString[0] = "0";
        hexString[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            uint8 byteValue = uint8(_bytes[i]);
            bytes memory stringValue = toHexChar(byteValue / 16);
            hexString[i * 2 + 2] = stringValue[0];
            stringValue = toHexChar(byteValue % 16);
            hexString[i * 2 + 3] = stringValue[0];
        }
        return string(hexString);
    }
    
    function bytesToString(bytes memory byteData) public pure returns (string memory) {
        bytes memory stringBytes = new bytes(byteData.length);

        for (uint i=0; i<byteData.length; i++) {
            stringBytes[i] = byteData[i];
        }

        return string(stringBytes);
    }
}
