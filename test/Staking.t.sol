// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/staking/Staking.sol";
import "../src/token/Gons.sol";
import "./token/TestMockOikosToken.sol";

contract TestStaking is Test {
    Staking staking;
    GonsToken sOKS;
    TestMockOikosToken NOMA;

    address[] users;
    uint256 constant NUM_USERS = 100;
    uint256 constant INITIAL_OKS_BALANCE = 1000e18;
    uint256 constant STAKE_AMOUNT = 100e18;
    uint256 constant INITIAL_FRAGMENTS_SUPPLY = 3_025_000 * 1e18;
    uint256 constant MAX_STAKE_AMOUNT = 1000e18;
    uint256 constant MAX_REWARD_AMOUNT = 10000e18;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    function setUp() public {
        
        NOMA = new TestMockOikosToken();
        NOMA.initialize(address(this), 1_000_000e18, 200_000_000e18, "TEST", "TEST", address(0)); // Large initial supply

        sOKS = new GonsToken("Noma Staked Token", "sOKS");
        vm.prank(deployer);
        staking = new Staking(address(NOMA), address(sOKS), address(this));

        // sOKS.initialize(address(staking));

        // Create users and give them NOMA tokens
        for (uint i = 0; i < NUM_USERS; i++) {
            address user = address(uint160(i + 1000));
            users.push(user);
            NOMA.transfer(user, INITIAL_OKS_BALANCE);
            vm.prank(user);
            NOMA.approve(address(staking), type(uint256).max);
        }
    }

    function testMultipleStakersStakeAndUnstake() public {
        // All users stake
        for (uint i = 0; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            staking.stake(STAKE_AMOUNT);
            vm.stopPrank();

        }

        // Check balances after staking
        for (uint i = 0; i < NUM_USERS; i++) {
            assertEq(NOMA.balanceOf(users[i]), INITIAL_OKS_BALANCE - STAKE_AMOUNT, "NOMA balance incorrect after stake");
            // assertEq(sOKS.balanceOf(users[i]), STAKE_AMOUNT, "sOKS balance should be slightly higher than stake amount");
        }

        // Simulate some rewards
        vm.prank(address(staking));
        staking.notifyRewardAmount(0);

        uint256 rewardAmount = 1000e18;
        NOMA.mintTest(address(staking), rewardAmount);
        vm.prank(address(staking));
        staking.notifyRewardAmount(rewardAmount);

        // All users unstake
        for (uint i = 0; i < NUM_USERS; i++) {
            uint256 sOKSBalanceBefore = sOKS.balanceOf(users[i]);
            uint256 OKSBalanceBefore = NOMA.balanceOf(users[i]);

            vm.prank(users[i]);
            sOKS.approve(address(staking), type(uint256).max);
            vm.stopPrank();

            vm.prank(users[i]);
            staking.unstake();
            vm.stopPrank();

            assertEq(sOKS.balanceOf(users[i]), 0, "sOKS balance should be 0 after unstake");
            assertEq(NOMA.balanceOf(users[i]), OKSBalanceBefore + sOKSBalanceBefore, "NOMA balance incorrect after unstake");
        }

        // testCheckSolvency();
    }

    function testCheckSolvency() public {
        console.log("Circulating sOKS supply:", sOKS.totalSupply());
        console.log("Staking contract sOKS balance:", sOKS.balanceOf(address(staking)));
        // Check if staking contract has enough NOMA to cover all unstakes
        uint256 circulatingSupply = sOKS.totalSupply() - sOKS.balanceOf(address(staking));
        uint256 stakingOKSBalance = NOMA.balanceOf(address(staking));
        uint256 initialStakingBalance = sOKS.balanceForGons(INITIAL_FRAGMENTS_SUPPLY);
        uint256 availableOKS = stakingOKSBalance > initialStakingBalance ? stakingOKSBalance - initialStakingBalance : 0;

        // console.log("Circulating sOKS supply:", circulatingSupply);
        // console.log("Staking contract NOMA balance:", stakingOKSBalance);
        // console.log("Initial staking balance (in current sOKS terms):", initialStakingBalance);
        // console.log("Available NOMA for unstaking:", availableOKS);

        assertGe(availableOKS, circulatingSupply, "Staking contract should have enough NOMA to cover all circulating sOKS");
    }
    
    function testStakeUnstakeWithRebases() public {
        // All users stake
        for (uint i = 0; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            staking.stake(STAKE_AMOUNT);
        }
        
        vm.prank(address(staking));
        staking.notifyRewardAmount(0);

        // Simulate multiple rebases
        uint256 rewardAmount = 1000e18;
        for (uint i = 0; i < 10; i++) {
            NOMA.mintTest(address(staking), rewardAmount);
            vm.prank(address(staking));
            staking.notifyRewardAmount(rewardAmount);
        }

        // All users unstake
        for (uint i = 0; i < NUM_USERS; i++) {
            uint256 sOKSBalanceBefore = sOKS.balanceOf(users[i]);
            uint256 OKSBalanceBefore = NOMA.balanceOf(users[i]);

            vm.prank(users[i]);
            sOKS.approve(address(staking), type(uint256).max);
            vm.stopPrank();

            vm.prank(users[i]);
            staking.unstake();
            vm.stopPrank();
            
            assertEq(sOKS.balanceOf(users[i]), 0, "sOKS balance should be 0 after unstake");
            assertEq(NOMA.balanceOf(users[i]), OKSBalanceBefore + sOKSBalanceBefore, "NOMA balance incorrect after unstake");
        }

    }

    function testNonLinearStakingAndUnstaking() public {
        // Half of users stake
        for (uint i = 0; i < NUM_USERS / 2; i++) {
            vm.prank(users[i]);
            staking.stake(STAKE_AMOUNT);
        }

        // Simulate some rewards
        vm.prank(address(staking));
        staking.notifyRewardAmount(0);

        uint256 rewardAmount = 500e18;
        NOMA.mintTest(address(staking), rewardAmount);
        vm.prank(address(staking));
        staking.notifyRewardAmount(rewardAmount);

        // Other half of users stake
        for (uint i = NUM_USERS / 2; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            staking.stake(STAKE_AMOUNT);
        }

        // Simulate more rewards
        NOMA.mintTest(address(staking), rewardAmount);
        vm.prank(address(staking));
        staking.notifyRewardAmount(rewardAmount);

        // All users unstake
        for (uint i = 0; i < NUM_USERS; i++) {
            uint256 sOKSBalanceBefore = sOKS.balanceOf(users[i]);
            uint256 OKSBalanceBefore = NOMA.balanceOf(users[i]);

            vm.prank(users[i]);
            sOKS.approve(address(staking), type(uint256).max);
            vm.stopPrank(); 

            vm.prank(users[i]);
            staking.unstake();
            vm.stopPrank();

            assertEq(sOKS.balanceOf(users[i]), 0, "sOKS balance should be 0 after unstake");
            assertEq(NOMA.balanceOf(users[i]), OKSBalanceBefore + sOKSBalanceBefore, "NOMA balance incorrect after unstake");
        }
    }

    function testRandomStakingAndUnstaking() public {
        uint256[] memory stakeAmounts = new uint256[](NUM_USERS);
        uint256 totalStaked = 0;

        // All users stake random amounts
        for (uint i = 0; i < NUM_USERS; i++) {
            uint256 stakeAmount = _randomAmount(1e18, MAX_STAKE_AMOUNT);
            stakeAmounts[i] = stakeAmount;
            totalStaked += stakeAmount;

            vm.prank(users[i]);
            staking.stake(stakeAmount);

            assertEq(NOMA.balanceOf(users[i]), INITIAL_OKS_BALANCE - stakeAmount, "NOMA balance incorrect after stake");
            assertGe(sOKS.balanceOf(users[i]), stakeAmount, "sOKS balance should be equal or slightly higher than stake amount");
            // console.log("User", i);
            // console.log("staked:", stakeAmount);
            // console.log("User", i);
            // console.log("sOKS balance after stake:", sOKS.balanceOf(users[i]));
        }

        // Simulate random rewards
        uint256 totalRewards = 0;
        for (uint i = 0; i < 5; i++) {
            uint256 rewardAmount = _randomAmount(100e18, MAX_REWARD_AMOUNT);
            totalRewards += rewardAmount;
            NOMA.mintTest(address(staking), rewardAmount);
            vm.prank(address(staking));
            staking.notifyRewardAmount(rewardAmount);
            
            console.log("Reward distributed:", rewardAmount);
        }

        // Unstake for all users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 sOikosBalanceBefore = sOKS.balanceOf(users[i]);
            uint256 OKSBalanceBefore = NOMA.balanceOf(users[i]);

            vm.startPrank(users[i]);
            sOKS.approve(address(staking), sOikosBalanceBefore);
            staking.unstake();
            vm.stopPrank();

            uint256 OKSBalanceAfter = NOMA.balanceOf(users[i]);
            int256 OKSDifference = int256(OKSBalanceAfter) - int256(OKSBalanceBefore);

            // console.log("User", i);
            // console.log("Initial stake:", stakeAmounts[i]);
            // console.log("sOKS balance before unstake:", sOikosBalanceBefore);
            // console.log("NOMA balance before unstake:", OKSBalanceBefore);
            // console.log("NOMA balance after unstake:", OKSBalanceAfter);
            // console.log("NOMA difference:", uint256(OKSDifference));
            // console.log("Percentage gain:", uint256((OKSDifference * 10000) / int256(stakeAmounts[i])), "basis points");

            assertGt(OKSBalanceAfter, OKSBalanceBefore, "NOMA balance should be greater after unstake");
            assertEq(sOKS.balanceOf(users[i]), 0, "sOKS balance should be 0 after unstaking");

            if (i == NUM_USERS - 1) {
                // Special check for the last user
                assertNotEq(uint256(OKSDifference), type(uint256).max, "Last user difference should not be max uint256");
            }
        }
    }

    function testRandomNonLinearStakingAndUnstaking() public {
        uint256[] memory stakeAmounts = new uint256[](NUM_USERS);
        uint256 totalStaked = 0;

        // Half of users stake random amounts
        for (uint i = 0; i < NUM_USERS / 2; i++) {
            uint256 stakeAmount = _randomAmount(1e18, MAX_STAKE_AMOUNT);
            stakeAmounts[i] = stakeAmount;
            totalStaked += stakeAmount;

            vm.prank(users[i]);
            staking.stake(stakeAmount);
            
            // console.log("User", i);
            // console.log("staked:", stakeAmount);
            // console.log("sOKS balance after stake:", sOKS.balanceOf(users[i]));
        }

        // Simulate random rewards
        uint256 rewardAmount = _randomAmount(100e18, MAX_REWARD_AMOUNT);
        NOMA.mintTest(address(staking), rewardAmount);
        vm.prank(address(staking));
        staking.notifyRewardAmount(rewardAmount);
        // console.log("First reward distributed:", rewardAmount);

        // Other half of users stake random amounts
        for (uint i = NUM_USERS / 2; i < NUM_USERS; i++) {
            uint256 stakeAmount = _randomAmount(1e18, MAX_STAKE_AMOUNT);
            stakeAmounts[i] = stakeAmount;
            totalStaked += stakeAmount;

            vm.prank(users[i]);
            staking.stake(stakeAmount);
            
            // console.log("User", i);
            // console.log("staked:", stakeAmount);
            // console.log("sOKS balance after stake:", sOKS.balanceOf(users[i]));
        }

        // Simulate more random rewards
        uint256 additionalReward = _randomAmount(100e18, MAX_REWARD_AMOUNT);
        rewardAmount += additionalReward;
        NOMA.mintTest(address(staking), additionalReward);
        vm.prank(address(staking));
        staking.notifyRewardAmount(additionalReward);
        // console.log("Second reward distributed:", additionalReward);

        // All users unstake
        for (uint i = 0; i < NUM_USERS; i++) {
            uint256 sOKSBalanceBefore = sOKS.balanceOf(users[i]);
            uint256 OKSBalanceBefore = NOMA.balanceOf(users[i]);

            vm.prank(users[i]);
            sOKS.approve(address(staking), type(uint256).max);
            vm.stopPrank();

            vm.prank(users[i]);
            staking.unstake();
            vm.stopPrank();

            uint256 OKSBalanceAfter = NOMA.balanceOf(users[i]);
            int256 OKSDifference = int256(OKSBalanceAfter) - int256(OKSBalanceBefore);

            // console.log("User", i);
            // console.log("Initial stake:", stakeAmounts[i]);
            // console.log("sOKS balance before unstake:", sOKSBalanceBefore);
            // console.log("NOMA balance before unstake:", OKSBalanceBefore);
            // console.log("NOMA balance after unstake:", OKSBalanceAfter);
            // console.log("NOMA difference:", uint256(OKSDifference));
            // console.log("Percentage gain:", uint256((OKSDifference * 10000) / int256(stakeAmounts[i])), "basis points");

            assertEq(sOKS.balanceOf(users[i]), 0, "sOKS balance should be 0 after unstake");
            assertGt(OKSBalanceAfter, OKSBalanceBefore, "NOMA balance should be greater after unstake");
        }

    }

    function _randomAmount(uint256 min, uint256 max) internal view returns (uint256) {
        return min + (uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % (max - min + 1));
    }    

    function stakingEnabled() public returns (bool) {
        return true;
    }    
}