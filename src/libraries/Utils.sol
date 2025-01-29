
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Conversions} from "./Conversions.sol";

library Utils {
    
    int24 public constant MIN_TICK = -887272;
    int24 public constant MAX_TICK = 887272;

    error OutOfRange();
    error NegativeValue();
    error InvalidChars();
    error InvalidTickSpacing();

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

    // Function to add bips to a tick value
    function addBipsToTick(int24 currentTick, int24 bips, uint8 _decimals, int24 _tickSpacing) public pure returns (int24) {

        uint256 tickToPrice = Conversions
        .sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(currentTick), 
            _decimals
        );

        uint256 newPrice = addBips(tickToPrice, bips);
        int24 newTickValue = Conversions
        .priceToTick(
            int256(newPrice), 
            _tickSpacing,
            _decimals
        );

        // Ensure the new tick value is within the range of int24 and within Uniswap's tick range
        if (newTickValue < MIN_TICK || newTickValue > MAX_TICK) {
            revert OutOfRange();
        }

        return newTickValue;
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

    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        } else if (tempEmptyStringTest.length > 32) {
            revert();
        } else {
            assembly {
                result := mload(add(source, 32))
            }
            for (uint256 i = tempEmptyStringTest.length; i < 32; i++) {
                result |= bytes32(uint256(0) << (8 * (31 - i)));
            }
            return result;
        }
    }

    // TICK CALCULATION FUNCTIONS
    function nearestUsableTick(int24 tick, int24 tickSpacing) public pure returns (int24) {
        require(tickSpacing > 0, "Invalid tick spacing");
        require(tick >= MIN_TICK && tick <= MAX_TICK, "Out of range");

        int24 remainder = tick % tickSpacing;
        int24 rounded = _roundTick(tick, remainder, tickSpacing);

        return _clampTick(rounded, tickSpacing);
    }

    function _roundTick(int24 tick, int24 remainder, int24 tickSpacing) internal pure returns (int24) {
        int24 rounded = tick - remainder;

        if (remainder * 2 >= tickSpacing) {
            rounded += tickSpacing;
        } else if (remainder * 2 <= -tickSpacing) {
            rounded -= tickSpacing;
        }

        return rounded;
    }

    function _clampTick(int24 rounded, int24 tickSpacing) internal pure returns (int24) {
        if (rounded < MIN_TICK) {
            return rounded + tickSpacing;
        } else if (rounded > MAX_TICK) {
            return rounded - tickSpacing;
        } else {
            return rounded;
        }
    }

   
}
