// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {NomaToken} from  "../src/token/NomaToken.sol";
import {ModelHelper} from  "../src/model/Helper.sol";
import {BaseVault} from  "../src/vault/BaseVault.sol";
import {LendingVault} from  "../src/vault/LendingVault.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {Underlying } from  "../src/libraries/Underlying.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {LiquidityType, LiquidityPosition} from "../src/types/Types.sol";


contract LoanFeesTest is Test {
    using stdJson for string;


    function setUp() public {
    }

    function testLoanFees () public view {

        uint256 borrowAmount = 2 * 10**18; // 2 tokens
        uint256 duration = 30 * 86400; // 30 days in seconds
        uint256 fees = _calculateLoanFees(borrowAmount, duration);

        // Assert
        assertEq(fees, 0.0342e18);  
    }

    function testLoanFeesShouldFail() public {
        uint256 borrowAmount = 2 * 10**18; // 2 tokens
        uint256 duration = 2592000; // 30 days in seconds
        uint256 fees = _calculateLoanFees(borrowAmount, duration);

        // Assert
        assertEq(fees, 0.0342e18);  
    }

    /**
     * @notice Calculate loan fees based on a daily rate of 0.057%
     * @param borrowAmount  principal amount borrowed
     * @param duration      loan duration in seconds
     * @return fees         total fees owed
     */
    function _calculateLoanFees(
        uint256 borrowAmount,
        uint256 duration
    ) internal pure returns (uint256 fees) {
        uint256 SECONDS_IN_DAY = 86400;
        // daily rate = 0.057% -> 57 / 100_000
        uint256 daysElapsed = duration / SECONDS_IN_DAY;
        fees = (borrowAmount * 57 * daysElapsed) / 100_000;
    }

}