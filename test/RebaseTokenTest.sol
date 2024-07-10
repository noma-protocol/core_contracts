// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/staking/RebaseToken.sol";
import "../src/staking/sStaking.sol";

import {MockNomaToken} from "../src/token/MockNomaToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    MockNomaToken mockNomaToken;
    sStaking staking;

    address userA = address(0x1);
    address userB = address(0x2);
    address userC = address(0x3);

    function setUp() public {

        mockNomaToken = new MockNomaToken();
        mockNomaToken.initialize(address(this), 1_000_000e18);

        rebaseToken = new RebaseToken(address(this), address(mockNomaToken));
        staking = new sStaking(address(mockNomaToken), address(rebaseToken), address(this));        
        
        rebaseToken.initialize(address(staking));

        try rebaseToken.mint(userA, 1_000_000 * 10**18) {
            emit log("Minting to userA successful");
        } catch Error(string memory reason) {
            emit log_named_string("Minting to userA failed", reason);
        } catch (bytes memory reason) {
            emit log_named_bytes("Minting to userA failed", reason);
        }

        try rebaseToken.mint(userB, 2_000_000 * 10**18) {
            emit log("Minting to userB successful");
        } catch Error(string memory reason) {
            emit log_named_string("Minting to userB failed", reason);
        } catch (bytes memory reason) {
            emit log_named_bytes("Minting to userB failed", reason);
        }

        try rebaseToken.mint(userC, 2_000_000 * 10**18) {
            emit log("Minting to userC successful");
        } catch Error(string memory reason) {
            emit log_named_string("Minting to userC failed", reason);
        } catch (bytes memory reason) {
            emit log_named_bytes("Minting to userC failed", reason);
        }
    }

    function testInitialBalances() public {
        assertEq(rebaseToken.balanceOf(userA), 1_000_000 * 10**18);
        assertEq(rebaseToken.balanceOf(userB), 2_000_000 * 10**18);
        assertEq(rebaseToken.balanceOf(userC), 2_000_000 * 10**18);
    }

    function testRebase() public {
        uint256 profit = 500_000 * 10**18;

        rebaseToken.rebase(profit);

        assertEq(rebaseToken.balanceOf(userA), 1_100_000 * 10**18);
        assertEq(rebaseToken.balanceOf(userB), 2_200_000 * 10**18);
        assertEq(rebaseToken.balanceOf(userC), 2_200_000 * 10**18);
        assertEq(rebaseToken.totalSupply(), 5_500_000 * 10**18);
    }

    function testMultipleRebases() public {
        uint256[] memory profits = new uint256[](10);
        profits[0] = 100_000 * 10**18;
        profits[1] = 200_000 * 10**18;
        profits[2] = 300_000 * 10**18;
        profits[3] = 400_000 * 10**18;
        profits[4] = 500_000 * 10**18;
        profits[5] = 600_000 * 10**18;
        profits[6] = 700_000 * 10**18;
        profits[7] = 800_000 * 10**18;
        profits[8] = 900_000 * 10**18;
        profits[9] = 1_000_000 * 10**18;

        uint256 initialTotalSupply = rebaseToken.totalSupply();

        for (uint256 i = 0; i < profits.length; i++) {
            rebaseToken.rebase(profits[i]);
        }

        uint256 expectedTotalSupply = initialTotalSupply;

        for (uint256 i = 0; i < profits.length; i++) {
            expectedTotalSupply += profits[i];
        }

        assertEq(rebaseToken.totalSupply(), expectedTotalSupply);
        assertEq(rebaseToken.balanceOf(userA), 1_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
        assertEq(rebaseToken.balanceOf(userB), 2_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
        assertEq(rebaseToken.balanceOf(userC), 2_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
    }

    function testRandomRebases() public {
        uint256 initialTotalSupply = rebaseToken.totalSupply();

        for (uint256 i = 0; i < 100; i++) {
            uint256 profit = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, i))) % (1_000_000 * 10**18);
            rebaseToken.rebase(profit);
        }

        uint256 expectedTotalSupply = initialTotalSupply;
        for (uint256 i = 0; i < 100; i++) {
            uint256 profit = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, i))) % (1_000_000 * 10**18);
            expectedTotalSupply += profit;
        }

        assertEq(rebaseToken.totalSupply(), expectedTotalSupply);
        assertEq(rebaseToken.balanceOf(userA), 1_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
        assertEq(rebaseToken.balanceOf(userB), 2_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
        assertEq(rebaseToken.balanceOf(userC), 2_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
    }

    function testPrecisionLoss() public {
        uint256 initialTotalSupply = rebaseToken.totalSupply();

        for (uint256 i = 0; i < 1000; i++) {
            uint256 profit = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, i))) % (1_000 * 10**18);
            rebaseToken.rebase(profit);
        }

        uint256 expectedTotalSupply = initialTotalSupply;
        for (uint256 i = 0; i < 1000; i++) {
            uint256 profit = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, i))) % (1_000 * 10**18);
            expectedTotalSupply += profit;
        }

        // Check total supply
        assertApproxEqRel(rebaseToken.totalSupply(), expectedTotalSupply, 1e14); // Allowing a small relative error

        // Check balances
        assertApproxEqRel(rebaseToken.balanceOf(userA), 1_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18, 1e14); // Allowing a small relative error
        assertApproxEqRel(rebaseToken.balanceOf(userB), 2_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18, 1e14); // Allowing a small relative error
        assertApproxEqRel(rebaseToken.balanceOf(userC), 2_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18, 1e14); // Allowing a small relative error
    }

    function testZeroProfitRebase() public {
        uint256 initialTotalSupply = rebaseToken.totalSupply();
        uint256 initialScalingFactor = rebaseToken.scalingFactor();

        rebaseToken.rebase(0);

        assertEq(rebaseToken.totalSupply(), initialTotalSupply);
        assertEq(rebaseToken.scalingFactor(), initialScalingFactor);
        assertEq(rebaseToken.balanceOf(userA), 1_000_000 * 10**18);
        assertEq(rebaseToken.balanceOf(userB), 2_000_000 * 10**18);
        assertEq(rebaseToken.balanceOf(userC), 2_000_000 * 10**18);
    }

    function testLargeProfitRebase() public {
        uint256 initialTotalSupply = rebaseToken.totalSupply();
        uint256 profit = 1e24; // Large profit

        rebaseToken.rebase(profit);

        uint256 expectedTotalSupply = initialTotalSupply + profit;
        assertEq(rebaseToken.totalSupply(), expectedTotalSupply);
        assertEq(rebaseToken.balanceOf(userA), 1_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
        assertEq(rebaseToken.balanceOf(userB), 2_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
        assertEq(rebaseToken.balanceOf(userC), 2_000_000 * 10**18 * rebaseToken.scalingFactor() / 1e18);
    }

    function testNegativeProfitRebase() public {
        uint256 initialTotalSupply = rebaseToken.totalSupply();
        uint256 initialScalingFactor = rebaseToken.scalingFactor();

        // Simulate invalid input scenario by calling rebase with a very large profit to check negative effect
        try rebaseToken.rebase(type(uint256).max) {
            fail(); // This should fail as the rebase amount would be unrealistic
        } catch {}

        assertEq(rebaseToken.totalSupply(), initialTotalSupply);
        assertEq(rebaseToken.scalingFactor(), initialScalingFactor);
    }

    function testStake() public {
        
        mockNomaToken.mint(userA, 100e18);

        uint256 balanceBefore = rebaseToken.balanceOf(userA);

        vm.startPrank(userA);
        mockNomaToken.approve(address(staking), 100e18);
        staking.stake(userA, 100e18);
        vm.stopPrank();

        assertEq(rebaseToken.balanceOf(userA) , 100e18 + balanceBefore);
    }

    function testUnstake() public {
        
        uint256 balanceBefore = rebaseToken.balanceOf(userA);
        console.log("Balance is %d", balanceBefore);

        testStake();

        uint256 sNomaAmount = rebaseToken.balanceOf(userA);
        console.log("sNomaAmount is %d", sNomaAmount);

        vm.startPrank(userA);
        rebaseToken.approve(address(staking), sNomaAmount - balanceBefore);
        staking.unStake(sNomaAmount - balanceBefore);
        vm.stopPrank();

        // Check balances
        assertEq(mockNomaToken.balanceOf(userA), 100e18); // userA should get back 100 Noma tokens
        assertEq(rebaseToken.balanceOf(userA), balanceBefore); // userA should have 0 sNoma tokens
    }
}

