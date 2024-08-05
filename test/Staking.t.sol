// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/staking/Staking.sol";
import "../src/staking/Gons.sol";
import "../src/token/MockNomaToken.sol";

contract TestStaking is Test {
    Staking staking;
    GonsToken sNOMA;
    MockNomaToken NOMA;

    address authority = address(0x1);
    address vault = address(0x2);
    address[] users;
    uint256 constant NUM_USERS = 100;
    uint256 constant INITIAL_NOMA_BALANCE = 1000e18;
    uint256 constant STAKE_AMOUNT = 100e18;
    uint256 constant INITIAL_FRAGMENTS_SUPPLY = 3_025_000 * 1e18;

    function setUp() public {
        NOMA = new MockNomaToken();
        NOMA.initialize(address(this), 1000000e18); // Large initial supply

        sNOMA = new GonsToken(address(this));
        staking = new Staking(address(NOMA), address(sNOMA), authority);

        sNOMA.initialize(address(staking));
        staking.setup(vault, address(NOMA), address(sNOMA));

        // Create users and give them NOMA tokens
        for (uint i = 0; i < NUM_USERS; i++) {
            address user = address(uint160(i + 1000));
            users.push(user);
            NOMA.transfer(user, INITIAL_NOMA_BALANCE);
            vm.prank(user);
            NOMA.approve(address(staking), type(uint256).max);
        }
    }

    function testMultipleStakersStakeAndUnstake() public {
        // All users stake
        for (uint i = 0; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            staking.stake(users[i], STAKE_AMOUNT);
        }

        // Check balances after staking
        for (uint i = 0; i < NUM_USERS; i++) {
            assertEq(NOMA.balanceOf(users[i]), INITIAL_NOMA_BALANCE - STAKE_AMOUNT, "NOMA balance incorrect after stake");
            assertGt(sNOMA.balanceOf(users[i]), STAKE_AMOUNT, "sNOMA balance should be slightly higher than stake amount");
        }

        // Simulate some rewards
        vm.prank(vault);
        staking.notifyRewardAmount(0);

        uint256 rewardAmount = 1000e18;
        NOMA.mint(address(staking), rewardAmount);
        vm.prank(vault);
        staking.notifyRewardAmount(rewardAmount);

        // All users unstake
        for (uint i = 0; i < NUM_USERS; i++) {
            uint256 sNOMABalanceBefore = sNOMA.balanceOf(users[i]);
            uint256 NOMABalanceBefore = NOMA.balanceOf(users[i]);

            vm.prank(users[i]);
            sNOMA.approve(address(staking), type(uint256).max);
            staking.unstake(users[i]);

            assertEq(sNOMA.balanceOf(users[i]), 0, "sNOMA balance should be 0 after unstake");
            assertEq(NOMA.balanceOf(users[i]), NOMABalanceBefore + sNOMABalanceBefore, "NOMA balance incorrect after unstake");
        }

        // Check if staking contract has enough NOMA to cover all unstakes
        uint256 circulatingSupply = sNOMA.totalSupply() - sNOMA.balanceOf(address(staking));
        uint256 stakingNOMABalance = NOMA.balanceOf(address(staking));
        uint256 initialStakingBalance = sNOMA.balanceForGons(INITIAL_FRAGMENTS_SUPPLY);
        uint256 availableNOMA = stakingNOMABalance > initialStakingBalance ? stakingNOMABalance - initialStakingBalance : 0;

        console.log("Circulating sNOMA supply:", circulatingSupply);
        console.log("Staking contract NOMA balance:", stakingNOMABalance);
        console.log("Initial staking balance (in current sNOMA terms):", initialStakingBalance);
        console.log("Available NOMA for unstaking:", availableNOMA);

        assertGe(availableNOMA, circulatingSupply, "Staking contract should have enough NOMA to cover all circulating sNOMA");
    }

    function testStakeUnstakeWithRebases() public {
        // All users stake
        for (uint i = 0; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            staking.stake(users[i], STAKE_AMOUNT);
        }
        
        vm.prank(vault);
        staking.notifyRewardAmount(0);

        // Simulate multiple rebases
        uint256 rewardAmount = 1000e18;
        for (uint i = 0; i < 10; i++) {
            NOMA.mint(address(staking), rewardAmount);
            vm.prank(vault);
            staking.notifyRewardAmount(rewardAmount);
        }

        // All users unstake
        for (uint i = 0; i < NUM_USERS; i++) {
            uint256 sNOMABalanceBefore = sNOMA.balanceOf(users[i]);
            uint256 NOMABalanceBefore = NOMA.balanceOf(users[i]);

            vm.prank(users[i]);
            sNOMA.approve(address(staking), type(uint256).max);
            staking.unstake(users[i]);

            assertEq(sNOMA.balanceOf(users[i]), 0, "sNOMA balance should be 0 after unstake");
            assertEq(NOMA.balanceOf(users[i]), NOMABalanceBefore + sNOMABalanceBefore, "NOMA balance incorrect after unstake");
        }

        // Check if staking contract has enough NOMA to cover all unstakes
        uint256 circulatingSupply = sNOMA.totalSupply() - sNOMA.balanceOf(address(staking));
        uint256 stakingNOMABalance = NOMA.balanceOf(address(staking));
        uint256 initialStakingBalance = sNOMA.balanceForGons(INITIAL_FRAGMENTS_SUPPLY);
        uint256 availableNOMA = stakingNOMABalance > initialStakingBalance ? stakingNOMABalance - initialStakingBalance : 0;

        console.log("Circulating sNOMA supply:", circulatingSupply);
        console.log("Staking contract NOMA balance:", stakingNOMABalance);
        console.log("Initial staking balance (in current sNOMA terms):", initialStakingBalance);
        console.log("Available NOMA for unstaking:", availableNOMA);

        assertGe(availableNOMA, circulatingSupply, "Staking contract should have enough NOMA to cover all circulating sNOMA");
    }

    function testStaggeredStakingAndUnstaking() public {
        // Half of users stake
        for (uint i = 0; i < NUM_USERS / 2; i++) {
            vm.prank(users[i]);
            staking.stake(users[i], STAKE_AMOUNT);
        }

        // Simulate some rewards
        vm.prank(vault);
        staking.notifyRewardAmount(0);

        uint256 rewardAmount = 500e18;
        NOMA.mint(address(staking), rewardAmount);
        vm.prank(vault);
        staking.notifyRewardAmount(rewardAmount);

        // Other half of users stake
        for (uint i = NUM_USERS / 2; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            staking.stake(users[i], STAKE_AMOUNT);
        }

        // Simulate more rewards
        NOMA.mint(address(staking), rewardAmount);
        vm.prank(vault);
        staking.notifyRewardAmount(rewardAmount);

        // All users unstake
        for (uint i = 0; i < NUM_USERS; i++) {
            uint256 sNOMABalanceBefore = sNOMA.balanceOf(users[i]);
            uint256 NOMABalanceBefore = NOMA.balanceOf(users[i]);

            vm.prank(users[i]);
            sNOMA.approve(address(staking), type(uint256).max);
            staking.unstake(users[i]);

            assertEq(sNOMA.balanceOf(users[i]), 0, "sNOMA balance should be 0 after unstake");
            assertEq(NOMA.balanceOf(users[i]), NOMABalanceBefore + sNOMABalanceBefore, "NOMA balance incorrect after unstake");
        }

        // Check if staking contract has enough NOMA to cover all unstakes
        uint256 circulatingSupply = sNOMA.totalSupply() - sNOMA.balanceOf(address(staking));
        uint256 stakingNOMABalance = NOMA.balanceOf(address(staking));
        uint256 initialStakingBalance = sNOMA.balanceForGons(INITIAL_FRAGMENTS_SUPPLY);
        uint256 availableNOMA = stakingNOMABalance > initialStakingBalance ? stakingNOMABalance - initialStakingBalance : 0;

        console.log("Circulating sNOMA supply:", circulatingSupply);
        console.log("Staking contract NOMA balance:", stakingNOMABalance);
        console.log("Initial staking balance (in current sNOMA terms):", initialStakingBalance);
        console.log("Available NOMA for unstaking:", availableNOMA);

        assertGe(availableNOMA, circulatingSupply, "Staking contract should have enough NOMA to cover all circulating sNOMA");
    }
}