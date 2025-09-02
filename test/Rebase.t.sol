// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "./token/TestGons.sol";
import "./token/TestMockNomaToken.sol";
import "../src/staking/Staking.sol";

contract TestRebase is Test {
    TestGons rebaseToken;
    TestMockNomaToken mockNomaToken;
    Staking staking;

    address userA = address(0x1);
    address userB = address(0x2);
    address userC = address(0x3);
    address userD = address(0x4);

    uint256 INITIAL_SUPPLY = 1_000e18;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    function setUp() public {
        mockNomaToken = new TestMockNomaToken();
        mockNomaToken.initialize(address(this), 100_000e18, 200_000_000e18, "TEST", "TEST", address(0));

        rebaseToken = new TestGons();

        vm.prank(deployer);
        staking = new Staking(address(mockNomaToken), address(rebaseToken), address(this));        
        mockNomaToken.mintTest(address(staking), INITIAL_SUPPLY);
        // staking.setup(address(this), address(mockNomaToken), address(rebaseToken));
        rebaseToken.initialize(address(staking));
        rebaseToken.setIndex(1);

    }

    function testTotalSupply() public returns (uint256) {
        uint256 totalSupplyBefore = rebaseToken.totalSupply();

        uint256 profit = 150e18;

        vm.prank(address(staking));
        staking.notifyRewardAmount(0);

        mockNomaToken.approve(address(staking), profit);

        vm.prank(address(staking));
        staking.notifyRewardAmount(profit);

        uint256 expectedTotalSupply = totalSupplyBefore + profit;
        uint256 actualTotalSupply = rebaseToken.totalSupply();

        // console.log("Actual total supply: %s", actualTotalSupply);

        uint256 balanceOfStakingContract = rebaseToken.balanceOf(address(staking));
        // console.log("Balance of staking contract: %s", balanceOfStakingContract);

        assertEq(actualTotalSupply, expectedTotalSupply);
        return actualTotalSupply;        
    }

    function testStakeUserA() public {
        mockNomaToken.mintTest(userA, 1000e18);

        uint256 rebaseTokenBalance = rebaseToken.balanceOf(userA);
        // console.log("rebaseTokenBalance: %s", rebaseTokenBalance);

        vm.prank(userA);
        mockNomaToken.approve(address(staking), 100e18);
        vm.stopPrank();

        vm.prank(userA);
        staking.stake(100e18);
        vm.stopPrank();

        uint256 balanceAfterStaking = rebaseToken.balanceOf(userA);
        // console.log("balanceAfterStaking: %s", balanceAfterStaking);

        assertGt(rebaseToken.balanceOf(userA), rebaseTokenBalance);
    }

    function testStakeUserB() public {
        mockNomaToken.mintTest(userB, 1000e18);
        uint256 nomaBalanceBefore = mockNomaToken.balanceOf(userB);

        vm.prank(userB);
        mockNomaToken.approve(address(staking), 100e18);
        vm.stopPrank();

        vm.prank(userB);
        staking.stake(100e18);
        vm.stopPrank();

        uint256 nomaBalanceAfter = mockNomaToken.balanceOf(userB);
        assertLt(nomaBalanceAfter, nomaBalanceBefore);
    
    }

    function testStakeAndProfit() public {
        mockNomaToken.mintTest(userA, 1000e18);

        uint256 rebaseTokenBalance = rebaseToken.balanceOf(userA);
        // console.log("rebaseTokenBalance: %s", rebaseTokenBalance);

        vm.prank(userA);
        mockNomaToken.approve(address(staking), 100e18);
        vm.stopPrank();

        vm.prank(userA);
        staking.stake(100e18);
        vm.stopPrank();

        uint256 balanceAfterStaking = rebaseToken.balanceOf(userA);
        // console.log("balanceAfterStaking: %s", balanceAfterStaking);

        assertGt(rebaseToken.balanceOf(userA), rebaseTokenBalance);

        mockNomaToken.mintTest(userB, 1000e18);
        uint256 nomaBalanceBefore = mockNomaToken.balanceOf(userB);

        vm.prank(userB);
        mockNomaToken.approve(address(staking), 100e18);
        vm.stopPrank();

        vm.prank(userB);
        staking.stake(100e18);
        vm.stopPrank();

        uint256 nomaBalanceAfter = mockNomaToken.balanceOf(userB);
        assertLt(nomaBalanceAfter, nomaBalanceBefore); 
        
        mockNomaToken.mintTest(userC, 1000e18);

        vm.prank(userC);
        mockNomaToken.approve(address(staking), 100e18);
        vm.stopPrank();

        vm.prank(userC);
        staking.stake(100e18);
        vm.stopPrank();

        mockNomaToken.mintTest(userD, 1000e18);

        vm.prank(userD);
        mockNomaToken.approve(address(staking), 100e18);
        vm.stopPrank();

        vm.prank(userD);
        staking.stake(100e18);
        vm.stopPrank();

        uint256 profit = 3000e18;
        mockNomaToken.approve(address(staking), profit);

        vm.prank(address(staking));
        staking.notifyRewardAmount(0);
        
        vm.prank(address(staking));
        staking.notifyRewardAmount(profit); 

        uint256 balanceAfterProfitUserA = rebaseToken.balanceOf(userA);
        uint256 balanceAfterProfitUserB = rebaseToken.balanceOf(userB);
        uint256 balanceAfterProfitUserC = rebaseToken.balanceOf(userC);
        uint256 balanceAfterProfitUserD = rebaseToken.balanceOf(userD);

        uint256 balanceAfterProfitStaking = rebaseToken.balanceOf(address(staking));
        uint256 nomaBalanceStaking = mockNomaToken.balanceOf(address(staking));

        require(nomaBalanceStaking >= (balanceAfterProfitUserA + balanceAfterProfitUserB + balanceAfterProfitUserC + balanceAfterProfitUserD), "Staking contract should have enough Noma tokens");
        // console.log("balanceAfterProfitUserA: %s", balanceAfterProfitUserA);    
        // console.log("balanceAfterProfitUserB: %s", balanceAfterProfitUserB);   
        // console.log("balanceAfterProfitUserC: %s", balanceAfterProfitUserC);      
        // console.log("balanceAfterProfitUserD: %s", balanceAfterProfitUserD);    
        // console.log("balanceAfterProfitStaking: %s", balanceAfterProfitStaking);
        // console.log("nomaBalanceStaking: %s", nomaBalanceStaking);
    }

    function testArbitraryStakesWithProfit() public {
        uint8 numUsers = 32;
        require(numUsers > 0 && numUsers <= 255, "Number of users should be between 1 and 255");

        uint256 stakeAmount = 100e18;
        uint256 initialBalance = 1000e18;
        address[] memory users = new address[](numUsers);
        uint256[] memory initialRebaseBalances = new uint256[](numUsers);
        uint256[] memory afterStakeRebaseBalances = new uint256[](numUsers);

        uint256 balanceBeforeProfitStaking = rebaseToken.balanceOf(address(staking));

        // Create users, mint tokens, and stake
        for (uint8 i = 0; i < numUsers; i++) {
            users[i] = address(uint160(i + 1));
            mockNomaToken.mintTest(users[i], initialBalance);

            initialRebaseBalances[i] = rebaseToken.balanceOf(users[i]);

            vm.prank(users[i]);
            mockNomaToken.approve(address(staking), stakeAmount);
            vm.stopPrank();

            vm.prank(users[i]);
            staking.stake(stakeAmount);
            vm.stopPrank();

            afterStakeRebaseBalances[i] = rebaseToken.balanceOf(users[i]);
            assertGt(afterStakeRebaseBalances[i], initialRebaseBalances[i], "Rebase balance should increase after staking");
            assertEq(mockNomaToken.balanceOf(users[i]), initialBalance - stakeAmount, "Noma balance should decrease by stake amount");
        }

        // Distribute profit
        uint256 profit = 1000e18; // Scale profit with number of users

        vm.prank(address(staking));
        staking.notifyRewardAmount(0);
        vm.stopPrank();

        mockNomaToken.approve(address(staking), profit);
        
        vm.prank(address(staking));
        staking.notifyRewardAmount(profit);
        vm.stopPrank();

        // Check balances after profit distribution
        uint256 totalRebaseBalance = 0;
        for (uint8 i = 0; i < numUsers; i++) {
            uint256 balanceAfterProfit = rebaseToken.balanceOf(users[i]);
            // console.log("Balance after profit for user %s: %s", i, balanceAfterProfit);
            assertGt(balanceAfterProfit, afterStakeRebaseBalances[i], "Balance should increase after profit distribution");
            totalRebaseBalance += balanceAfterProfit;
        }

        uint256 balanceAfterProfitStaking = rebaseToken.balanceOf(address(staking));
        uint256 nomaBalanceStaking = mockNomaToken.balanceOf(address(staking));

        // console.log("Balance after profit for staking contract: %s", balanceAfterProfitStaking);
        // console.log("Noma balance of staking contract: %s", nomaBalanceStaking);

        assertGe(nomaBalanceStaking, totalRebaseBalance - (balanceAfterProfitStaking - balanceAfterProfitStaking), "Staking contract should have enough Noma tokens");
    }

    function testArbitraryStakesWithRandomAmountsAndProfit() public {
        uint16 numUsers = 254;

        uint256 initialBalance = 1000e18;

        address[] memory users = new address[](numUsers);
        uint256[] memory initialRebaseBalances = new uint256[](numUsers);
        uint256[] memory afterStakeRebaseBalances = new uint256[](numUsers);
        uint256[] memory stakeAmounts = new uint256[](numUsers);
        
        uint256 totalStaked = 0;

        uint256 balanceBeforeProfitStakingContract = rebaseToken.balanceOf(address(staking));

        // Create users, mint tokens, and stake random amounts
        for (uint8 i = 0; i < numUsers; i++) {
            
            users[i] = address(uint160(i + 1));
            mockNomaToken.mintTest(users[i], initialBalance);

            initialRebaseBalances[i] = rebaseToken.balanceOf(users[i]);

            // Generate a random stake amount between 1e18 and 500e18
            uint256 stakeAmount = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 500e18 + 1e18;
            stakeAmounts[i] = stakeAmount;
            totalStaked += stakeAmount;

            vm.prank(users[i]);
            mockNomaToken.approve(address(staking), stakeAmount);
            vm.stopPrank();

            vm.prank(users[i]);
            staking.stake(stakeAmount);
            vm.stopPrank();

            afterStakeRebaseBalances[i] = rebaseToken.balanceOf(users[i]);
            assertGt(afterStakeRebaseBalances[i], initialRebaseBalances[i], "Rebase balance should increase after staking");
            assertEq(mockNomaToken.balanceOf(users[i]), initialBalance - stakeAmount, "Noma balance should decrease by stake amount");

            // console.log("User %s staked amount: %s", i, stakeAmount);
        }
        
        // Distribute profit
        uint256 profit = 300_000e18; // Set profit to 50% of total staked amount
        mockNomaToken.mintTest(address(staking), profit);

        vm.prank(address(staking));
        staking.notifyRewardAmount(0);
        vm.stopPrank();

        vm.prank(address(staking));
        mockNomaToken.approve(address(staking), profit);

        vm.prank(address(staking));
        staking.notifyRewardAmount(profit);
        vm.stopPrank();
        
        // console.log("Total staked: %s", totalStaked);
        // console.log("Profit distributed: %s", profit);

        // Check balances after profit distribution
        uint256 totalRebaseBalance = 0;
        for (uint8 i = 0; i < numUsers; i++) {
            uint256 balanceAfterProfit = rebaseToken.balanceOf(users[i]);
            // console.log("Balance after profit for user %s: %s", i, balanceAfterProfit);
            assertGt(balanceAfterProfit, afterStakeRebaseBalances[i], "Balance should increase after profit distribution");
            totalRebaseBalance += balanceAfterProfit;
        }

        // uint256 balanceAfterProfitStaking = rebaseToken.balanceOf(address(staking));
        uint256 nomaBalanceStaking = mockNomaToken.balanceOf(address(staking));

        // console.log("Balance after profit for staking contract: %s", balanceAfterProfitStaking);
        // console.log("Noma balance of staking contract: %s", nomaBalanceStaking);

        assertGe(nomaBalanceStaking, totalRebaseBalance , "Staking contract should have enough Noma tokens");
        // assertEq(rebaseToken.totalSupply(),  balanceAfterProfitStaking, "Total supply should match sum of all balances");
    }

    function testArbitraryStakesWithRandomAmountsAndProfit2() public {
        uint16 numUsers = 254;

        uint256 initialBalance = 1000e18;
        address[] memory users = new address[](numUsers);
        uint256[] memory initialRebaseBalances = new uint256[](numUsers);
        uint256[] memory afterStakeRebaseBalances = new uint256[](numUsers);
        uint256[] memory stakeAmounts = new uint256[](numUsers);
        uint256 totalStaked = 0;

        uint256 balanceBeforeProfitStakingContract = rebaseToken.balanceOf(address(staking));
        // console.log("Initial staking contract balance:");
        // console.log(balanceBeforeProfitStakingContract);

        // Create users, mint tokens, and stake random amounts
        for (uint8 i = 0; i < numUsers; i++) {
            users[i] = address(uint160(i + 1));
            mockNomaToken.mintTest(users[i], initialBalance);

            initialRebaseBalances[i] = rebaseToken.balanceOf(users[i]);

            uint256 stakeAmount = uint256(keccak256(abi.encodePacked(block.timestamp, i))) % 500e18 + 1e18;
            stakeAmounts[i] = stakeAmount;
            totalStaked += stakeAmount;

            vm.prank(users[i]);
            mockNomaToken.approve(address(staking), stakeAmount);
            vm.stopPrank();

            vm.prank(users[i]);
            staking.stake(stakeAmount);
            vm.stopPrank();

            afterStakeRebaseBalances[i] = rebaseToken.balanceOf(users[i]);
        }

        // console.log("Total staked:");
        // console.log(totalStaked);
        
        // Distribute profit
        uint256 profit = 300_000e18;
        mockNomaToken.mintTest(address(staking), profit);

        // console.log("Before first notifyRewardAmount(0):");
        // console.log("Total supply:");
        // console.log(rebaseToken.totalSupply());
        // console.log("Circulating supply:");
        // console.log(rebaseToken.circulatingSupply());

        vm.prank(address(staking));
        staking.notifyRewardAmount(0);

        // console.log("After first notifyRewardAmount(0):");
        // console.log("Total supply:");
        // console.log(rebaseToken.totalSupply());
        // console.log("Circulating supply:");
        // console.log(rebaseToken.circulatingSupply());

        // Log balances after first notifyRewardAmount(0)
        for (uint8 i = 0; i < numUsers; i++) {
            uint256 balanceAfterFirstNotify = rebaseToken.balanceOf(users[i]);
            // console.log("User balance after first notify:");
            // console.log(i);
            // console.log(balanceAfterFirstNotify);
        }

        // console.log("Before second notifyRewardAmount(profit):");
        // console.log("Total supply:");
        // console.log(rebaseToken.totalSupply());
        // console.log("Circulating supply:");
        // console.log(rebaseToken.circulatingSupply());

        vm.prank(address(staking));
        mockNomaToken.approve(address(staking), profit);

        vm.prank(address(staking));
        staking.notifyRewardAmount(profit);

        // console.log("After second notifyRewardAmount(profit):");
        // console.log("Total supply:");
        // console.log(rebaseToken.totalSupply());
        // console.log("Circulating supply:");
        // console.log(rebaseToken.circulatingSupply());

        // Check balances after profit distribution
        uint256 totalRebaseBalance = 0;
        for (uint8 i = 0; i < numUsers; i++) {
            uint256 balanceAfterProfit = rebaseToken.balanceOf(users[i]);
            // console.log("User balance:");
            // console.log(i);
            // console.log("Before stake:");
            // console.log(initialRebaseBalances[i]);
            // console.log("After stake:");
            // console.log(afterStakeRebaseBalances[i]);
            // console.log("After profit:");
            // console.log(balanceAfterProfit);
            assertGt(balanceAfterProfit, afterStakeRebaseBalances[i], "Balance should increase after profit distribution");
            totalRebaseBalance += balanceAfterProfit;
        }

        uint256 balanceAfterProfitStaking = rebaseToken.balanceOf(address(staking));
        uint256 nomaBalanceStaking = mockNomaToken.balanceOf(address(staking));

        // console.log("Balance after profit for staking contract:");
        // console.log(balanceAfterProfitStaking);
        // console.log("Noma balance of staking contract:");
        // console.log(nomaBalanceStaking);

        assertGe(nomaBalanceStaking, totalRebaseBalance, "Staking contract should have enough Noma tokens");
    }

    function testDirectRebase() public {
        uint256 initialTotalSupply = rebaseToken.totalSupply();
        uint256 initialCirculatingSupply = rebaseToken.circulatingSupply();
        uint256 rebaseAmount = 1000e18;

        // console.log("Initial Total Supply:", initialTotalSupply);
        // console.log("Initial Circulating Supply:", initialCirculatingSupply);
        // console.log("Rebase Amount:", rebaseAmount);
        
        rebaseToken.rebase(rebaseAmount);
        
        uint256 newTotalSupply = rebaseToken.totalSupply();
        uint256 newCirculatingSupply = rebaseToken.circulatingSupply();
        
        console.log("New Total Supply:", newTotalSupply);
        console.log("New Circulating Supply:", newCirculatingSupply);
        // console.log("Total Supply Difference:", newTotalSupply - initialTotalSupply);
        // console.log("Circulating Supply Difference:", newCirculatingSupply - initialCirculatingSupply);
        
        // Check if total supply increased
        assertGt(newTotalSupply, initialTotalSupply, "Total supply should increase after rebase");
        
        // Check if circulating supply remained stable or increased
        assertGe(newCirculatingSupply, initialCirculatingSupply, "Circulating supply should not decrease");
        
        // Check if the increase in total supply matches the rebase amount, allowing for 1 wei discrepancy
        uint256 supplyDifference = newTotalSupply > initialTotalSupply + rebaseAmount ? 
                                newTotalSupply - (initialTotalSupply + rebaseAmount) :
                                (initialTotalSupply + rebaseAmount) - newTotalSupply;
        
        assertLe(supplyDifference, 1, "Total supply should increase by rebase amount (allowing 1 wei discrepancy)");
    }

    function testRebaseWithSpecificAmount() public {
        uint256 rebaseAmount = 4130710;  // The amount that's causing issues
        
        uint256 initialTotalSupply = rebaseToken.totalSupply();
        uint256 initialCirculatingSupply = rebaseToken.circulatingSupply();
        
        // console.log("Initial Total Supply:", initialTotalSupply);
        // console.log("Initial Circulating Supply:", initialCirculatingSupply);
        // console.log("Rebase Amount:", rebaseAmount);
        
        try rebaseToken.rebase(rebaseAmount) {
            uint256 newTotalSupply = rebaseToken.totalSupply();
            uint256 newCirculatingSupply = rebaseToken.circulatingSupply();
            
            // console.log("New Total Supply:", newTotalSupply);
            // console.log("New Circulating Supply:", newCirculatingSupply);
            // console.log("Total Supply Difference:", newTotalSupply - initialTotalSupply);
            // console.log("Circulating Supply Difference:", newCirculatingSupply - initialCirculatingSupply);
            
            assertGt(newTotalSupply, initialTotalSupply, "Total supply should increase after rebase");
            assertGe(newCirculatingSupply, initialCirculatingSupply, "Circulating supply should not decrease");
        } catch Error(string memory reason) {
            console.log("Rebase failed with reason:", reason);
            assertTrue(false, "Rebase should not revert");
        } catch (bytes memory lowLevelData) {
            console.log("Rebase failed with no reason string");
            assertTrue(false, "Rebase should not revert");
        }
    }

    function stakingEnabled() public returns (bool) {
        return true;
    }


    function testRebaseDistribution() public {
        uint256 NUM_USERS = 32;
        uint256 STAKE_AMOUNT = 100e18;
        uint256 REWARD_AMOUNT = 1000e18;
        address[] memory users = new address[](NUM_USERS);

        for (uint i = 0; i < NUM_USERS; i++) {
            users[i] = address(uint160(i + 1));
            mockNomaToken.mintTest(users[i], 1000e18);

            vm.prank(users[i]);
            mockNomaToken.approve(address(staking), STAKE_AMOUNT);
            vm.stopPrank();

            vm.prank(users[i]);
            staking.stake(STAKE_AMOUNT);
            vm.stopPrank();
        }

        uint256 initialTotalSupply = rebaseToken.totalSupply();

        vm.prank(address(staking));
        staking.notifyRewardAmount(0);

        mockNomaToken.mintTest(address(staking), REWARD_AMOUNT);
        vm.prank(address(staking));
        staking.notifyRewardAmount(REWARD_AMOUNT);

        uint256 expectedTotalSupply = initialTotalSupply + REWARD_AMOUNT;
        assertEq(rebaseToken.totalSupply(), expectedTotalSupply, "Total supply mismatch after rebase");

        for (uint i = 0; i < NUM_USERS; i++) {
            users[i] = address(uint160(i + 1));
            uint256 userBalance = rebaseToken.balanceOf(users[i]);
            uint256 expectedUserBalance = (STAKE_AMOUNT * (initialTotalSupply + REWARD_AMOUNT)) / initialTotalSupply;
            assertApproxEqAbs(userBalance, expectedUserBalance, 2e17, "User balance incorrect after rebase");
        }
    }

    // function testTotalTokensDistributed() public {
    //     for (uint i = 0; i < NUM_USERS; i++) {
    //         vm.prank(users[i]);
    //         staking.stake(users[i], STAKE_AMOUNT);
    //     }

    //     uint256 initialTotalSupply = sNOMA.totalSupply();

    //     vm.prank(address(staking));
    //     staking.notifyRewardAmount(0);

    //     NOMA.mintTest(address(staking), REWARD_AMOUNT);
    //     vm.prank(address(staking));
    //     staking.notifyRewardAmount(REWARD_AMOUNT);

    //     uint256 totalTokensDistributed = sNOMA.totalSupply() - initialTotalSupply;
    //     assertEq(totalTokensDistributed, REWARD_AMOUNT, "Total distributed tokens mismatch with notified reward amount");
    // }    
}


