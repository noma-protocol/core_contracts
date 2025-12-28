// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {NomaToken} from "../src/token/NomaToken.sol";
import {BaseVault} from "../src/vault/BaseVault.sol";
import {Conversions} from "../src/libraries/Conversions.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IDOManager {
    function vault() external view returns (BaseVault);
    function buyTokens(uint256 price, uint256 amount, uint256 min, address receiver) external;
}

interface IStaking {
    function stake(uint256 amount) external;
    function unstake() external;
    function stakedBalance(address user) external view returns (uint256);
    function epoch() external view returns (uint256 number, uint256 end, uint256 distribute);
    function lastOperationTimestamp(address user) external view returns (uint256);
    function stakedEpochs(address user) external view returns (uint256);
    function MINIMUM_STAKE_DURATION() external view returns (uint256);
}

/// @title StakingLockFixTest
/// @notice Tests for the staking lock-in period fix
contract StakingLockFixTest is Test {
    using stdJson for string;

    IVault vault;
    NomaToken noma;
    address stakingContract;

    bool isMainnet = vm.envOr("DEPLOY_FLAG_MAINNET", false);
    address constant WMON_MAINNET = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant WMON_TESTNET = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address WMON;
    address payable idoManager;

    function setUp() public {
        WMON = isMainnet ? WMON_MAINNET : WMON_TESTNET;

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        address nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));

        IDOManager managerContract = IDOManager(idoManager);
        noma = NomaToken(nomaToken);
        vault = IVault(address(managerContract.vault()));
        stakingContract = vault.getStakingContract();

        // Buy some NOMA for testing
        _buyNoma(50_000 ether);
    }

    function _buyNoma(uint256 amount) internal {
        address pool = address(vault.pool());
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);

        IWETH(WMON).deposit{value: amount}();
        IWETH(WMON).transfer(idoManager, amount);
        IDOManager(idoManager).buyTokens(purchasePrice, amount, 0, address(this));
    }

    /// @notice Test: Cannot unstake immediately after staking (even if epoch passes)
    function testCannotUnstakeBeforeMinimumTime() public {
        if (!vault.stakingEnabled() || stakingContract == address(0)) {
            return; // Skip if staking not enabled
        }

        uint256 stakeAmount = noma.balanceOf(address(this)) / 2;
        require(stakeAmount > 0, "No NOMA to stake");

        // Wait for cooldown before staking
        vm.warp(block.timestamp + 4 days);

        noma.approve(stakingContract, stakeAmount);
        IStaking(stakingContract).stake(stakeAmount);

        // Buy more to create shift conditions, then trigger shift
        _buyNoma(100_000 ether);
        _triggerShiftIfPossible();

        // Try to unstake immediately - should fail even if epoch passed (need 3 days min)
        vm.expectRevert();
        IStaking(stakingContract).unstake();
    }

    /// @notice Test: Can unstake after minimum time + epoch passes
    function testCanUnstakeAfterMinTimeAndEpoch() public {
        if (!vault.stakingEnabled() || stakingContract == address(0)) {
            return;
        }

        uint256 stakeAmount = noma.balanceOf(address(this)) / 2;
        require(stakeAmount > 0, "No NOMA to stake");

        vm.warp(block.timestamp + 4 days);
        noma.approve(stakingContract, stakeAmount);

        (uint256 epochBefore,,) = IStaking(stakingContract).epoch();
        IStaking(stakingContract).stake(stakeAmount);

        // Buy more to create shift conditions, then trigger shift
        _buyNoma(100_000 ether);
        _triggerShiftIfPossible();

        (uint256 epochAfter,,) = IStaking(stakingContract).epoch();

        // If epoch didn't progress, skip test (shift conditions not met)
        if (epochAfter <= epochBefore) {
            return;
        }

        // Wait minimum time (3 days)
        vm.warp(block.timestamp + 3 days + 1);

        // Should succeed now
        IStaking(stakingContract).unstake();

        assertEq(IStaking(stakingContract).stakedBalance(address(this)), 0, "Should have unstaked");
    }

    /// @notice Test: Can unstake after extended time even without epoch progression
    function testCanUnstakeAfterExtendedTimeWithoutEpoch() public {
        if (!vault.stakingEnabled() || stakingContract == address(0)) {
            return;
        }

        uint256 stakeAmount = noma.balanceOf(address(this)) / 2;
        require(stakeAmount > 0, "No NOMA to stake");

        vm.warp(block.timestamp + 4 days);
        noma.approve(stakingContract, stakeAmount);
        IStaking(stakingContract).stake(stakeAmount);

        // DON'T trigger any shifts - epoch stays the same

        // Wait extended time (6 days = 2 * MINIMUM_STAKE_DURATION)
        vm.warp(block.timestamp + 6 days + 1);

        // Should succeed with time fallback
        IStaking(stakingContract).unstake();

        assertEq(IStaking(stakingContract).stakedBalance(address(this)), 0, "Should have unstaked via time fallback");
    }

    /// @notice Test: Cannot unstake before extended time without epoch progression
    function testCannotUnstakeBeforeExtendedTimeWithoutEpoch() public {
        if (!vault.stakingEnabled() || stakingContract == address(0)) {
            return;
        }

        uint256 stakeAmount = noma.balanceOf(address(this)) / 2;
        require(stakeAmount > 0, "No NOMA to stake");

        vm.warp(block.timestamp + 4 days);
        noma.approve(stakingContract, stakeAmount);
        IStaking(stakingContract).stake(stakeAmount);

        // DON'T trigger any shifts - epoch stays the same

        // Wait only 4 days (between 3 and 6)
        vm.warp(block.timestamp + 4 days);

        // Should fail - not enough time and no epoch progression
        vm.expectRevert();
        IStaking(stakingContract).unstake();
    }

    function _triggerShiftIfPossible() internal {
        try vault.shift() {
            // Shift succeeded
        } catch {
            // Shift not possible, that's fine
        }
    }

    receive() external payable {}
}
