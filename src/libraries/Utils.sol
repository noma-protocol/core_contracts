// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Conversions} from "./Conversions.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";

/**
 * @title Utils
 * @notice A utility library providing helper functions for mathematical operations, tick calculations, and string manipulations.
 */
library Utils {
    
    // Constants for Uniswap V3 tick range
    int24 public constant MIN_TICK = -887272;
    int24 public constant MAX_TICK = 887272;

    // Custom errors
    error OutOfRange();
    error NegativeValue();
    error InvalidChars();
    error InvalidTickSpacing();
    error InvalidFeeTier();

    /**
     * @notice Adds or subtracts basis points (bips) from a given price.
     * @param _price The original price.
     * @param bips The basis points to add (positive) or subtract (negative).
     * @return The new price after applying the bips.
     */
    function addBips(uint256 _price, int256 bips) internal pure returns (uint256) {
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

    /**
     * @notice Adds basis points (bips) to a tick value and returns the new tick.
     * @param currentTick The current tick value.
     * @param bips The basis points to add.
     * @param decimals The number of decimals for the price calculation.
     * @param _tickSpacing The tick spacing of the pool.
     * @return The new tick value after applying the bips.
     */
    function addBipsToTick(int24 currentTick, int24 bips, uint8 decimals, int24 _tickSpacing) internal pure returns (int24) {

        uint256 tickToPrice = Conversions
        .sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(currentTick), 
            decimals
        );

        uint256 newPrice = addBips(tickToPrice, bips);
        int24 newTickValue = Conversions
        .priceToTick(
            int256(newPrice), 
            _tickSpacing,
            decimals
        );

        // Ensure the new tick value is within the range of int24 and within Uniswap's tick range
        if (newTickValue < MIN_TICK || newTickValue > MAX_TICK) {
            revert OutOfRange();
        }

        return newTickValue;
    }


    function _validateFeeTier(uint24 _feeTier) internal pure returns (int24) {
        return _getTickSpacing(_feeTier);
    }

    function _getTickSpacing(uint24 _feeTier) internal pure returns (int24) {
        if (_feeTier == 100) return 1;
        if (_feeTier == 500) return 10;
        if (_feeTier == 3000) return 60;
        if (_feeTier == 10000) return 200;
        revert InvalidFeeTier();
    }

    function configureVaultResolver(
        address resolverAddress,
        address vaultAddress,
        address stakingContract,
        address sOKS,
        address presaleContract,
        address adaptiveSupply,
        address modelHelper,
        address deployer
    ) internal {
        bytes32[] memory names = new bytes32[](6);
        names[0] = Utils.stringToBytes32("AdaptiveSupply");
        names[1] = Utils.stringToBytes32("ModelHelper");
        names[2] = Utils.stringToBytes32("Staking");
        names[3] = Utils.stringToBytes32("sOKS");
        names[4] = Utils.stringToBytes32("Deployer");
        names[5] = Utils.stringToBytes32("Presale");

        address[] memory destinations  = new address[](6);

        destinations[0] = adaptiveSupply;
        destinations[1] = modelHelper;
        destinations[2] = stakingContract;
        destinations[3] = sOKS;
        destinations[4] = deployer;
        destinations[5] = presaleContract;

        IAddressResolver(resolverAddress).configureDeployerACL(vaultAddress);  
        IAddressResolver(resolverAddress).importVaultAddress(vaultAddress, names, destinations);
    }

    /**
     * @notice Converts a uint256 value to a string.
     * @param _i The uint256 value to convert.
     * @return _uintAsString The string representation of the uint256 value.
     */
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

    /**
     * @notice Converts a byte value to a hexadecimal character.
     * @param byteValue The byte value to convert.
     * @return The hexadecimal character as a bytes array.
     */
    function toHexChar(uint8 byteValue) internal pure returns (bytes memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory result = new bytes(1);
        result[0] = alphabet[byteValue];
        return result;
    }

    /**
     * @notice Converts an Ethereum address to a string.
     * @param _address The address to convert.
     * @return The string representation of the address.
     */
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

    /**
     * @notice Converts a string to a bytes32 value.
     * @param source The string to convert.
     * @return result The bytes32 representation of the string.
     */
    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
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

    /**
     * @notice Finds the nearest usable tick based on the given tick and tick spacing.
     * @param tick The original tick value.
     * @param tickSpacing The tick spacing of the pool.
     * @return The nearest usable tick.
     */
    function nearestUsableTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        require(tickSpacing > 0, "Invalid tick spacing");
        require(tick >= MIN_TICK && tick <= MAX_TICK, "Out of range");

        int24 remainder = tick % tickSpacing;
        int24 rounded = _roundTick(tick, remainder, tickSpacing);

        return _clampTick(rounded, tickSpacing);
    }

    /**
     * @notice Rounds a tick value based on the remainder and tick spacing.
     * @param tick The original tick value.
     * @param remainder The remainder of the tick divided by the tick spacing.
     * @param tickSpacing The tick spacing of the pool.
     * @return The rounded tick value.
     */
    function _roundTick(int24 tick, int24 remainder, int24 tickSpacing) internal pure returns (int24) {
        int24 rounded = tick - remainder;

        if (remainder * 2 >= tickSpacing) {
            rounded += tickSpacing;
        } else if (remainder * 2 <= -tickSpacing) {
            rounded -= tickSpacing;
        }

        return rounded;
    }

    /**
     * @notice Clamps a tick value to ensure it is within the valid range.
     * @param rounded The rounded tick value.
     * @param tickSpacing The tick spacing of the pool.
     * @return The clamped tick value.
     */
    function _clampTick(int24 rounded, int24 tickSpacing) internal pure returns (int24) {
        if (rounded < MIN_TICK) {
            return rounded + tickSpacing;
        } else if (rounded > MAX_TICK) {
            return rounded - tickSpacing;
        } else {
            return rounded;
        }
    }

    /**
    * @notice Generates an 8‐character hex referral code from an address
    * @param user Address to generate a referral code for.
    * @return A bytes32 where the first 8 bytes are ASCII hex chars (0–9, a–f) and the remaining 24 bytes are zero.
    */
    function generateReferralCode(address user) public pure returns (bytes32) {
        bytes16 _HEX_SYMBOLS = "0123456789abcdef";

        // 1) Hash the user address
        bytes32 hash = keccak256(abi.encodePacked(user));

        // 2) Allocate an 8‐byte buffer for ASCII hex (8 chars)
        bytes memory buf = new bytes(8);

        // 3) Convert first 4 bytes of hash into 8 hex digits
        for (uint256 i = 0; i < 4; i++) {
            uint8 b = uint8(hash[i]);              // extract one byte
            buf[2 * i]     = _HEX_SYMBOLS[b >> 4]; // high nibble → ASCII
            buf[2 * i + 1] = _HEX_SYMBOLS[b & 0x0f]; // low nibble → ASCII
        }

        // 4) Load those 8 bytes into a bytes32 (left‐aligned in the 32‐byte word)
        bytes32 code;
        assembly {
            code := mload(add(buf, 32))
        }

        return code;
    }
    
}