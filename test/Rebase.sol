// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/staking/RebaseToken.sol";
import "../src/token/MockNomaToken.sol";
import "../src/staking/Staking.sol";

contract TestRebase is Test {
    RebaseToken rebaseToken;
    MockNomaToken mockNomaToken;
    Staking staking;

    address userA = address(0x1);
    address userB = address(0x2);

    uint256 private constant TOTAL_GONS = type(uint256).max - (type(uint256).max % (1_000 * 10**18));

    function setUp() public {
        mockNomaToken = new MockNomaToken();
        mockNomaToken.initialize(address(this), 1_000_000e18);

        rebaseToken = new RebaseToken(address(this), address(mockNomaToken));
        staking = new Staking(address(mockNomaToken), address(rebaseToken), address(this));        
        staking.setup(address(this), address(mockNomaToken), address(rebaseToken));
        mockNomaToken.mint(address(staking), 1_000e18);
        rebaseToken.initialize(address(this), address(staking));
    }

    function testTotalSupplyAfterRebase() public returns (uint256) {
        uint256 totalSupplyBefore = rebaseToken.totalSupply();

        uint256 profit = 150e18;
        staking.notifyRewardAmount(0);

        mockNomaToken.approve(address(staking), 150e18);

        staking.notifyRewardAmount(profit);

        uint256 expectedTotalSupply = totalSupplyBefore + profit;
        uint256 actualTotalSupply = rebaseToken.totalSupply();

        assertEq(actualTotalSupply, expectedTotalSupply);
        return actualTotalSupply;
    }

    function testTotalSupplyAfterRebaseMany() public {
        uint256 runs = 100;
        uint256 profit = 150e18;
        
        staking.notifyRewardAmount(0);

        for (uint256 i = 0; i < runs; i++) {
            mockNomaToken.approve(address(staking), 150e18);
            staking.notifyRewardAmount(profit);
        }

        uint256 expectedTotalSupply = 1_000e18 + (150e18 * runs);
        assertEq(rebaseToken.totalSupply(), expectedTotalSupply);
    }

    function testNomaBalanceAfterRebase() public {
        uint256 actualTotalSupply = testTotalSupplyAfterRebase();

        uint256 nomaTokenBalance = mockNomaToken.balanceOf(address(staking));
        assertEq(nomaTokenBalance, actualTotalSupply);
    }
    
    function testStakeUserA() public {
        mockNomaToken.mint(userA, 1000e18);

        vm.prank(userA);
        mockNomaToken.approve(address(staking), 100e18);
        staking.stake(userA, 100e18);
        vm.stopPrank();        
    }

    function testStakeUserB() public {
        mockNomaToken.mint(userB, 1000e18);

        vm.prank(userB);
        mockNomaToken.approve(address(staking), 100e18);
        staking.stake(userB, 100e18);
        vm.stopPrank();        
    }

    function testBalanceAfterUnstake() public {
        mockNomaToken.mint(userA, 1000e18);
        uint256 nomaBalanceBefore = mockNomaToken.balanceOf(userA);

        vm.prank(userA);
        mockNomaToken.approve(address(staking), 100e18);
        staking.stake(userA, 100e18);
        vm.stopPrank();

        uint256 nomaBalanceAfter = mockNomaToken.balanceOf(userA);
        assertLt(nomaBalanceAfter, nomaBalanceBefore);

    }

    function testUnstakeUserA() public {

        uint256 balanceBeforeStaking = rebaseToken.balanceOf(userA);

        testStakeUserA();

        uint256 balanceAfterStaking = rebaseToken.balanceOf(userA);

        vm.prank(userA);
        rebaseToken.approve(address(staking), rebaseToken.balanceOf(userA));
        staking.unstake(userA);
        vm.stopPrank();

        uint256 balanceAfterUnstaking = rebaseToken.balanceOf(userA);

        assertLt(balanceBeforeStaking, balanceAfterStaking);
        assertLt(balanceAfterUnstaking, balanceAfterStaking);
    }

    function testUnstake() public {

        uint256 balanceBeforeStaking = rebaseToken.balanceOf(userA);

        testStakeUserA();

        uint256 balanceAfterStaking = rebaseToken.balanceOf(userA);

        vm.prank(userA);
        rebaseToken.approve(address(staking), rebaseToken.balanceOf(userA));
        staking.unstake(userA);
        vm.stopPrank();

        uint256 balanceAfterUnstaking = rebaseToken.balanceOf(userA);

        assertLt(balanceBeforeStaking, balanceAfterStaking);
        assertLt(balanceAfterUnstaking, balanceAfterStaking);

        uint256 balanceBeforeStakeProfitA = mockNomaToken.balanceOf(userA);
        uint256 balanceBeforeStakeProfitB = mockNomaToken.balanceOf(userB);

        testStakeUserA();

        // First epoch
        staking.notifyRewardAmount(0);    
        
        vm.warp(block.timestamp + 30 days);

        mockNomaToken.approve(address(staking), 500e18);
        staking.notifyRewardAmount(500e18);   

        vm.prank(userA);
        rebaseToken.approve(address(staking), rebaseToken.balanceOf(userA));
        staking.unstake(userA);
        vm.stopPrank();      

        uint256 balanceAfterUnstakingProfitA = mockNomaToken.balanceOf(userA);
        assertGt(balanceAfterUnstakingProfitA, balanceBeforeStakeProfitA);

        uint256 balanceAfterUnstakingProfitB = mockNomaToken.balanceOf(userB);
        assertEq(balanceAfterUnstakingProfitB, balanceBeforeStakeProfitB);

    }



}
