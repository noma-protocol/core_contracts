// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RewardsCalculator} from "../../src/controllers/supply/RewardsCalculator.sol";
import {RewardParams} from "../../src/types/Types.sol";

contract RewardCalculatorTest is Test {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    RewardsCalculator calculator;

    function setUp() public {
        // Initialize the contract
        calculator = new RewardsCalculator();
    }

    function testCalculateRewards() public {
        RewardParams memory params = 
        RewardParams({
            ethAmount: 10e18,   // 10 ETH
            imv: 0.05e18,       // IMV = 0.05 ETH per token
            spotPrice: 0.09e18,    // Spot price = 1 ETH per token
            circulating: 1e17,  // Circulating supply
            totalSupply: 5e18,  // Total supply
            kr: 10e18          // Sensitivity for sigmoid
        });

        uint256 tMint = calculator.calculateRewards(params, 1 days);

        console.log("tMint:", tMint);
        assertGt(tMint, 0, "Final rewards should be greater than zero");
    }

    // Test: Low volatility
    function testLowVolatility() public {
        RewardParams memory params = 
        RewardParams({
            ethAmount: 10e18,
            imv: 0.5e18,
            spotPrice: 1e18,
            circulating: 100e18,
            totalSupply: 500e18,
            kr: 10e18
        });

        uint256 tMint = calculator.calculateRewards(params, 1 days);
        console.log("tMint (low volatility):", tMint);
        assertGt(tMint, 0, "Final rewards should be greater than zero with low volatility");
    }

    // Test: High circulating vs. total supply
    function testHighCirculating() public {
        RewardParams memory params = 
        RewardParams({
            ethAmount: 10e18,
            imv: 1.05e18,
            spotPrice: 1.10e18,
            circulating: 4e18, // Equal to total supply
            totalSupply: 5e18,
            kr: 10e18
        });

        uint256 tMint =  calculator.calculateRewards(params, 7 days);
        console.log("tMint (high circulating):", tMint);
        assertGt(tMint, 0, "Final rewards should be greater than zero with high circulating supply");
    }

    // Test: High volatility
    function testHighVolatility() public {
        RewardParams memory params = 
        RewardParams({
            ethAmount: 10e18,
            imv: 1.05e18,
            spotPrice: 6.10e18,
            circulating: 100e18,  
            totalSupply: 500e18,
            kr: 10e18
        });

        uint256 tMint = calculator.calculateRewards(params, 1 days);
        console.log("tMint (high volatility):", tMint);
        assertGt(tMint, 0, "Final rewards should be greater than zero with high volatility");
    }

    // function testPrecomputedVectors() public {
    //     // Test vector 1
    //     RewardParams memory params1 = RewardParams({
    //         ethAmount: 10e18,
    //         imv: 0.05e18,
    //         circulating: 1e17,
    //         totalSupply: 5e18,
    //         volatility: 1e18,
    //         kr: 10e18,
    //         kv: 1e18
    //     });

    //     uint256 expected1 = 49940432244446213200; // Precomputed
    //     uint256 tMint1 = calculator.calculateRewards(params1);
    //     assertEq(tMint1, expected1, "Precomputed vector 1 failed");

    //     // Test vector 2
    //     RewardParams memory params2 = RewardParams({
    //         ethAmount: 10e18,
    //         imv: 0.05e18,
    //         circulating: 4e18,
    //         totalSupply: 5e18,
    //         volatility: 1e18,
    //         kr: 10e18,
    //         kv: 1e18
    //     });

    //     uint256 expected2 = 49230769230769230750; // Precomputed
    //     uint256 tMint2 = calculator.calculateRewards(params2);
    //     assertEq(tMint2, expected2, "Precomputed vector 2 failed");

    //     // Test vector 3
    //     RewardParams memory params3 = RewardParams({
    //         ethAmount: 10e18,
    //         imv: 0.05e18,
    //         circulating: 1e18,
    //         totalSupply: 5e18,
    //         volatility: 0.1e18,
    //         kr: 10e18,
    //         kv: 1e18
    //     });

    //     uint256 expected3 = 178183368474773577382; // Precomputed
    //     uint256 tMint3 = calculator.calculateRewards(params3);
    //     assertEq(tMint3, expected3, "Precomputed vector 3 failed");

    //     // Test vector 4
    //     RewardParams memory params4 = RewardParams({
    //         ethAmount: 10e18,
    //         imv: 0.05e18,
    //         circulating: 1e18,
    //         totalSupply: 5e18,
    //         volatility: 5e18,
    //         kr: 10e18,
    //         kv: 1e18
    //     });

    //     uint256 expected4 = 192307692307692308; // Precomputed
    //     uint256 tMint4 = calculator.calculateRewards(params4);
    //     // assertEq(tMint4, expected4, "Precomputed vector 4 failed");
    //     // check that tMint4 and expected4 are within 1 wei of each other
    //     assertApproxEqAbs(tMint4, expected4, 1);

    //     // Test vector 5
    //     RewardParams memory params5 = RewardParams({
    //         ethAmount: 10e18,
    //         imv: 0.05e18,
    //         circulating: 1e18,
    //         totalSupply: 5e18,
    //         volatility: 1e18,
    //         kr: 100e18,
    //         kv: 1e18
    //     });

    //     uint256 expected5 = 50000000000000000000; // Precomputed
    //     uint256 tMint5 = calculator.calculateRewards(params5);
    //     assertEq(tMint5, expected5, "Precomputed vector 5 failed");
    // }

    // Test: High volatility
    // function testSmallEthAmount() public {
    //     RewardParams memory params = 
    //     RewardParams({
    //         ethAmount: 2e16,
    //         imv: 1.018e18,
    //         circulating: 88e18,
    //         totalSupply: 143e18,
    //         volatility: 1e18,  
    //         kr: 10e18,
    //         kv: 1e18
    //     });

    //     uint256 tMint = calculator.calculateRewards(params);
    //     console.log("tMint (high volatility):", tMint);
    //     assertGt(tMint, 0, "Final rewards should be greater than zero with high volatility");
    // }    
}
