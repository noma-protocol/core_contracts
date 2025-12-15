// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FuzzHelpers
 * @notice Utility functions for fuzzing harnesses
 */
library FuzzHelpers {
    /**
     * @notice Bound a value to a range [min, max]
     * @dev If min > max, swaps them
     */
    function bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min > max) {
            (min, max) = (max, min);
        }
        if (max == min) return min;

        // Use modulo to get value in range
        uint256 range = max - min + 1;
        return min + (value % range);
    }

    /**
     * @notice Bound a signed value to a range
     */
    function boundInt(int256 value, int256 min, int256 max) internal pure returns (int256) {
        if (min > max) {
            (min, max) = (max, min);
        }
        if (max == min) return min;

        int256 range = max - min + 1;
        int256 bounded = value % range;
        if (bounded < 0) bounded += range;
        return min + bounded;
    }

    /**
     * @notice Clamp uint256 to range without modulo (preserves distribution)
     */
    function clamp(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    /**
     * @notice Check if value is within percentage tolerance of target
     * @param value The value to check
     * @param target The target value
     * @param toleranceBps Tolerance in basis points (100 = 1%)
     */
    function isWithinTolerance(
        uint256 value,
        uint256 target,
        uint256 toleranceBps
    ) internal pure returns (bool) {
        if (target == 0) return value == 0;

        uint256 diff = value > target ? value - target : target - value;
        uint256 maxDiff = (target * toleranceBps) / 10000;
        return diff <= maxDiff;
    }

    /**
     * @notice Calculate percentage difference
     * @return Difference in basis points (100 = 1%)
     */
    function percentageDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 && b == 0) return 0;
        uint256 max = a > b ? a : b;
        uint256 diff = a > b ? a - b : b - a;
        return (diff * 10000) / max;
    }

    /**
     * @notice Safe division that returns 0 if denominator is 0
     */
    function safeDiv(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) return 0;
        return numerator / denominator;
    }

    /**
     * @notice Safe multiplication that caps at max uint256
     */
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        uint256 c = a * b;
        if (c / a != b) return type(uint256).max; // Overflow
        return c;
    }

    /**
     * @notice Get balance of token for address
     */
    function getBalance(address token, address account) internal view returns (uint256) {
        if (token == address(0)) return account.balance;
        return IERC20(token).balanceOf(account);
    }

    /**
     * @notice Check if array contains address
     */
    function contains(address[] memory arr, address target) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == target) return true;
        }
        return false;
    }

    /**
     * @notice Sum array of uint256
     */
    function sum(uint256[] memory arr) internal pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            total += arr[i];
        }
        return total;
    }

    /**
     * @notice Get minimum of two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Get maximum of two values
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Convert days to seconds
     */
    function daysToSeconds(uint256 _days) internal pure returns (uint256) {
        return _days * 1 days;
    }

    /**
     * @notice Check if timestamp is expired
     */
    function isExpired(uint256 expiry) internal view returns (bool) {
        return block.timestamp > expiry;
    }
}

/**
 * @title IHevm
 * @notice Hevm cheatcode interface for Echidna/Medusa
 */
interface IHevm {
    function warp(uint256 newTimestamp) external;
    function roll(uint256 newHeight) external;
    function deal(address who, uint256 newBalance) external;
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function store(address account, bytes32 slot, bytes32 value) external;
    function load(address account, bytes32 slot) external view returns (bytes32);
}

/**
 * @title HeapHelpers
 * @notice Heap cheatcode helpers for Echidna/Medusa
 */
library HeapHelpers {
    address constant HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /**
     * @notice Get hevm instance
     */
    function hevm() internal pure returns (IHevm) {
        return IHevm(HEVM_ADDRESS);
    }

    /**
     * @notice Warp to a new timestamp
     */
    function warp(uint256 newTimestamp) internal {
        hevm().warp(newTimestamp);
    }

    /**
     * @notice Advance time by seconds
     */
    function advanceTime(uint256 seconds_) internal {
        hevm().warp(block.timestamp + seconds_);
    }

    /**
     * @notice Roll to a new block
     */
    function roll(uint256 newHeight) internal {
        hevm().roll(newHeight);
    }

    /**
     * @notice Deal ETH to an address
     */
    function deal(address who, uint256 amount) internal {
        hevm().deal(who, amount);
    }

    /**
     * @notice Start a prank as sender
     */
    function startPrank(address sender) internal {
        hevm().startPrank(sender);
    }

    /**
     * @notice Stop the prank
     */
    function stopPrank() internal {
        hevm().stopPrank();
    }

    /**
     * @notice Single call prank
     */
    function prank(address sender) internal {
        hevm().prank(sender);
    }
}
