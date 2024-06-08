

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Utils {
    
    int24 public constant MIN_TICK = -887272;
    int24 public constant MAX_TICK = 887272;

    function addBips(uint256 _price, int256 bips) public pure returns (uint256) {
        if (bips >= 0) {
            uint256 increase = (_price * uint256(bips)) / 10_000;
            return _price + increase;
        } else {
            uint256 decrease = (_price * uint256(-bips)) / 10_000;
            if (decrease > _price) {
                return 0;
            } else {
                return _price - decrease;
            }
        }
    }

    // Function to add bips to a tick value, assuming bips can be within int24 positive range
    function addBipsToTick(int24 currentTick, int24 bips) public pure returns (int24) {
        require(currentTick >= 0, "Current tick must be non-negative");
        require(bips >= 0 && bips <= 10000, "Bips must be positive and not exceed 10000");

        // Convert int24 to int256 for calculations to prevent overflow
        int256 currentTick256 = int256(currentTick);
        int256 bips256 = int256(bips);
        int256 additionalAmount256 = (currentTick256 * bips256) / 10000;

        // Calculate the new tick value
        int256 newTickValue256 = currentTick256 + additionalAmount256;

        // Ensure the new tick value is within the range of int24
        require(newTickValue256 >= 0 && newTickValue256 <= type(int24).max, "Resulting tick value out of int24 positive range");

        return int24(newTickValue256);
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

    function strToUint(string memory s) public pure returns (uint256) {
       bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 0x30 && b[i] <= 0x39) { // 0x30 is '0' and 0x39 is '9'
                result = result * 10 + (uint8(b[i]) - 0x30);
            } else {
                revert("Invalid character in string: non-numeric character encountered");
            }
        }
        return result;
    }

    function int24ToUint256(int24 _value) public pure returns (uint256) {
        require(_value >= 0, "Value is negative");
        return uint256(uint24(_value));
    }

    function toHexChar(uint8 byteValue) internal pure returns (bytes memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(1);
        result[0] = alphabet[byteValue];
        return result;
    }

    function addressToString(address _address) internal pure returns (string memory) {
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
    
    function bytesToString(bytes memory byteData) internal pure returns (string memory) {
        bytes memory stringBytes = new bytes(byteData.length);

        for (uint i=0; i<byteData.length; i++) {
            stringBytes[i] = byteData[i];
        }

        return string(stringBytes);
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    // TICK CALCULATION FUNCTIONS

    function nearestUsableTick(int24 tick) public pure returns (int24) {
        int24 tickSpacing = 60;

        require(tickSpacing > 0, "TICK_SPACING");
        require(tick >= MIN_TICK && tick <= MAX_TICK, "TICK_BOUND");
        
        int24 remainder = tick % tickSpacing;
        int24 rounded = tick - remainder;
        
        if (remainder * 2 >= tickSpacing) {
            rounded += tickSpacing;
        } else if (remainder * 2 <= -tickSpacing) {
            rounded -= tickSpacing;
        }

        if (rounded < MIN_TICK) return rounded + tickSpacing;
        else if (rounded > MAX_TICK) return rounded - tickSpacing;
        else return rounded;
    }

    // function nearestUsableTick(int24 _tick) pure public returns (int24) {
    //     if (_tick < 0) {
    //         return -_nearestNumber(-_tick, 60);
    //     } else {
    //         return _nearestNumber(_tick, 60);
    //     }
    // }

    // function _nearestNumber(int24 _tick, int24 _tickInterval) internal pure returns (int24) {
    //     int24 high = ((_tick + _tickInterval - 1) / _tickInterval) * _tickInterval;
    //     int24 low = high - _tickInterval;
    //     if (abs(_tick - high) < abs(_tick - low)) return high;
    //     else return low;
    // }

    function abs(int x) pure private returns (uint) {
        return uint(x >= 0 ? x : -x);
    }    
}
