// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NomaDividends} from "../src/controllers/NomaDividends.sol";
import {Resolver} from "../src/Resolver.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {VaultDescription} from "../src/types/Types.sol";
import "../src/errors/Errors.sol";

/// @notice Mock ERC20 token for testing rewards
contract MockRewardToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock shares token that integrates with NomaDividends
contract MockSharesToken is ERC20 {
    NomaDividends public dividendsManager;

    constructor() ERC20("Mock NOMA", "mNOMA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setDividendsManager(NomaDividends _manager) external {
        dividendsManager = _manager;
    }

    function _update(address from, address to, uint256 value) internal override {
        // Call dividends hook BEFORE balances change
        if (address(dividendsManager) != address(0)) {
            dividendsManager.onSharesTransferHook(from, to);
        }
        super._update(from, to, value);
    }
}

/// @notice Mock factory that returns vault descriptions
contract MockFactory {
    mapping(address => bool) public registeredVaults;

    function registerVault(address vault) external {
        registeredVaults[vault] = true;
    }

    function getVaultsRepository(address vault) external view returns (VaultDescription memory) {
        if (registeredVaults[vault]) {
            return VaultDescription({
                tokenName: "Test",
                tokenSymbol: "TST",
                tokenDecimals: 18,
                token0: address(0),
                token1: address(0),
                deployer: address(0),
                vault: vault,
                presaleContract: address(0),
                stakingContract: address(0),
                deployerContract: address(0)
            });
        }
        return VaultDescription({
            tokenName: "",
            tokenSymbol: "",
            tokenDecimals: 0,
            token0: address(0),
            token1: address(0),
            deployer: address(0),
            vault: address(0),
            presaleContract: address(0),
            stakingContract: address(0),
            deployerContract: address(0)
        });
    }
}

/// @title DividendsTest
/// @notice Comprehensive tests for NomaDividends contract
contract DividendsTest is Test {
    NomaDividends public dividends;
    MockSharesToken public sharesToken;
    MockRewardToken public rewardToken1;
    MockRewardToken public rewardToken2;
    MockFactory public factory;
    Resolver public resolver;

    address public owner;
    address public vault;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant VESTING_DURATION = 180 days;
    uint256 constant PRECISION = 1e18;

    function setUp() public {
        owner = address(this);
        vault = address(0x1111);
        user1 = address(0x2222);
        user2 = address(0x3333);
        user3 = address(0x4444);

        // Deploy resolver
        resolver = new Resolver(owner);

        // Deploy mock factory and register vault
        factory = new MockFactory();
        factory.registerVault(vault);

        // Deploy dividends contract
        dividends = new NomaDividends(address(factory), address(resolver));

        // Deploy shares token
        sharesToken = new MockSharesToken();

        // Deploy reward tokens
        rewardToken1 = new MockRewardToken("Reward Token 1", "RWD1");
        rewardToken2 = new MockRewardToken("Reward Token 2", "RWD2");

        // Configure resolver with NomaToken address
        bytes32[] memory names = new bytes32[](1);
        address[] memory addresses = new address[](1);
        names[0] = Utils.stringToBytes32("NomaToken");
        addresses[0] = address(sharesToken);
        resolver.importAddresses(names, addresses);

        // Set shares token in dividends
        dividends.setSharesToken();

        // Configure shares token to use dividends
        sharesToken.setDividendsManager(dividends);

        // Mint shares to users
        sharesToken.mint(user1, 1000 ether);
        sharesToken.mint(user2, 500 ether);
        sharesToken.mint(user3, 500 ether);

        // Mint reward tokens to vault for distribution
        rewardToken1.mint(vault, 1_000_000 ether);
        rewardToken2.mint(vault, 1_000_000 ether);

        // Initialize user indices for reward tokens by doing initial micro-distributions
        // This simulates the system being bootstrapped
        initializeRewardToken(address(rewardToken1));
        initializeRewardToken(address(rewardToken2));
    }

    /// @dev Initialize a reward token and user indices with an initial distribution
    /// This is needed because users only earn from distributions AFTER their index is set
    /// Note: The amount must be large enough to result in a non-zero index increase
    /// index += (amount * PRECISION) / totalShares, so amount must be >= totalShares / PRECISION
    /// With 2000 ether totalShares, we need at least 2001 wei for index > 0
    function initializeRewardToken(address token) internal {
        // Do an initial distribution to register the token and create non-zero index
        // Amount needs to be > totalShares / PRECISION to avoid rounding to 0
        uint256 initAmount = 1 ether; // More than enough to ensure non-zero index
        vm.startPrank(vault);
        IERC20(token).approve(address(dividends), initAmount);
        dividends.distribute(token, initAmount);
        vm.stopPrank();

        // Trigger transfers to set user indices to current global index
        // After this, users will earn from future distributions
        vm.prank(user1);
        sharesToken.transfer(user1, 0);
        vm.prank(user2);
        sharesToken.transfer(user2, 0);
        vm.prank(user3);
        sharesToken.transfer(user3, 0);
    }

    // ============ DISTRIBUTION TESTS ============

    function testDistribute_BasicDistribution() public {
        uint256 distributeAmount = 1000 ether;

        // Note: 1 wei was already distributed in setUp for initialization
        uint256 initialDistributed = dividends.getTotalDistributed(address(rewardToken1));

        // Approve and distribute from vault
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // Check total distributed (includes initial micro-distribution)
        assertEq(dividends.getTotalDistributed(address(rewardToken1)), initialDistributed + distributeAmount);

        // Check reward token is registered
        assertTrue(dividends.isRewardToken(address(rewardToken1)));

        // Check reward tokens list (both tokens registered in setUp)
        address[] memory tokens = dividends.getRewardTokens();
        assertEq(tokens.length, 2); // Both tokens initialized in setUp
    }

    function testDistribute_MultipleRewardTokens() public {
        uint256 amount1 = 1000 ether;
        uint256 amount2 = 2000 ether;

        // Track initial amounts from setUp initialization
        uint256 initial1 = dividends.getTotalDistributed(address(rewardToken1));
        uint256 initial2 = dividends.getTotalDistributed(address(rewardToken2));

        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), amount1);
        dividends.distribute(address(rewardToken1), amount1);

        rewardToken2.approve(address(dividends), amount2);
        dividends.distribute(address(rewardToken2), amount2);
        vm.stopPrank();

        // Check both tokens registered (already registered in setUp)
        address[] memory tokens = dividends.getRewardTokens();
        assertEq(tokens.length, 2);
        assertEq(dividends.getTotalDistributed(address(rewardToken1)), initial1 + amount1);
        assertEq(dividends.getTotalDistributed(address(rewardToken2)), initial2 + amount2);
    }

    function testDistribute_OnlyVaultsCanDistribute() public {
        uint256 amount = 1000 ether;

        // Try to distribute from non-vault address
        rewardToken1.mint(user1, amount);
        vm.startPrank(user1);
        rewardToken1.approve(address(dividends), amount);
        vm.expectRevert(OnlyVault.selector);
        dividends.distribute(address(rewardToken1), amount);
        vm.stopPrank();
    }

    function testDistribute_RevertOnZeroAmount() public {
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 1000 ether);
        vm.expectRevert(ZeroAmount.selector);
        dividends.distribute(address(rewardToken1), 0);
        vm.stopPrank();
    }

    function testDistribute_RevertOnZeroRewardToken() public {
        vm.startPrank(vault);
        vm.expectRevert(InvalidRewardToken.selector);
        dividends.distribute(address(0), 1000 ether);
        vm.stopPrank();
    }

    // ============ HELPER TO TRIGGER ACCRUAL ============

    /// @dev Trigger accrual for a user by doing a self-transfer (0 amount)
    function triggerAccrual(address user) internal {
        vm.prank(user);
        sharesToken.transfer(user, 0);
    }

    // ============ CLAIMABLE RAW TESTS ============

    function testClaimableRaw_ProportionalToShares() public {
        uint256 distributeAmount = 2000 ether;

        // Total shares: 2000 ether (user1: 1000, user2: 500, user3: 500)
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // Trigger accrual for users (required after distribution to update their index)
        triggerAccrual(user1);
        triggerAccrual(user2);
        triggerAccrual(user3);

        // user1 has 50% of shares -> should get 50% of rewards
        uint256 user1Claimable = dividends.claimableRaw(address(rewardToken1), user1);
        assertEq(user1Claimable, 1000 ether); // 50% of 2000

        // user2 has 25% of shares -> should get 25% of rewards
        uint256 user2Claimable = dividends.claimableRaw(address(rewardToken1), user2);
        assertEq(user2Claimable, 500 ether); // 25% of 2000

        // user3 has 25% of shares -> should get 25% of rewards
        uint256 user3Claimable = dividends.claimableRaw(address(rewardToken1), user3);
        assertEq(user3Claimable, 500 ether);
    }

    function testClaimableRaw_AccumulatesOverMultipleDistributions() public {
        // First distribution
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 2000 ether);
        dividends.distribute(address(rewardToken1), 1000 ether);
        vm.stopPrank();

        uint256 user1ClaimableAfter1 = dividends.claimableRaw(address(rewardToken1), user1);

        // Second distribution
        vm.startPrank(vault);
        dividends.distribute(address(rewardToken1), 1000 ether);
        vm.stopPrank();

        uint256 user1ClaimableAfter2 = dividends.claimableRaw(address(rewardToken1), user1);

        // Claimable should have doubled
        assertEq(user1ClaimableAfter2, user1ClaimableAfter1 * 2);
    }

    // ============ VESTING / ESCROW TESTS ============

    function testClaim_CreatesVestingEntry() public {
        uint256 distributeAmount = 2000 ether;

        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // User1 claims (locks into vesting)
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Check vesting entry created
        NomaDividends.VestingEntry[] memory entries = dividends.getVestingEntries(address(rewardToken1));
        vm.prank(user1);
        entries = dividends.getVestingEntries(address(rewardToken1));

        assertEq(entries.length, 1);
        assertEq(entries[0].amount, 1000 ether); // 50% of distribution
        assertEq(entries[0].claimed, 0);
        assertEq(entries[0].start, block.timestamp);
    }

    function testClaimAll_CreatesEntriesForAllTokens() public {
        // Distribute both tokens
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 2000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        rewardToken2.approve(address(dividends), 4000 ether);
        dividends.distribute(address(rewardToken2), 4000 ether);
        vm.stopPrank();

        // User1 claims all
        vm.prank(user1);
        dividends.claimAll();

        // Check vesting entries for both tokens
        vm.startPrank(user1);
        NomaDividends.VestingEntry[] memory entries1 = dividends.getVestingEntries(address(rewardToken1));
        NomaDividends.VestingEntry[] memory entries2 = dividends.getVestingEntries(address(rewardToken2));
        vm.stopPrank();

        assertEq(entries1.length, 1);
        assertEq(entries1[0].amount, 1000 ether);

        assertEq(entries2.length, 1);
        assertEq(entries2[0].amount, 2000 ether);
    }

    function testVesting_LinearOverSixMonths() public {
        uint256 distributeAmount = 2000 ether;

        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // User1 claims
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // At t=0, nothing vested yet
        uint256 claimableNow = dividends.claimable(address(rewardToken1), user1);
        assertEq(claimableNow, 0);

        // After 90 days (half of vesting), 50% should be vested
        vm.warp(block.timestamp + 90 days);
        uint256 claimableHalf = dividends.claimable(address(rewardToken1), user1);
        assertEq(claimableHalf, 500 ether); // 50% of 1000 ether

        // After 180 days (full vesting), 100% should be vested
        vm.warp(block.timestamp + 90 days); // total 180 days
        uint256 claimableFull = dividends.claimable(address(rewardToken1), user1);
        assertEq(claimableFull, 1000 ether); // 100% vested
    }

    function testWithdrawVested_PartialWithdrawal() public {
        uint256 distributeAmount = 2000 ether;

        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // User1 claims
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // After 90 days, withdraw partial
        vm.warp(block.timestamp + 90 days);

        uint256 balanceBefore = rewardToken1.balanceOf(user1);

        vm.prank(user1);
        dividends.withdrawVested(address(rewardToken1));

        uint256 balanceAfter = rewardToken1.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, 500 ether);

        // Check vesting entry updated
        vm.prank(user1);
        NomaDividends.VestingEntry[] memory entries = dividends.getVestingEntries(address(rewardToken1));
        assertEq(entries[0].claimed, 500 ether);
    }

    function testWithdrawVested_FullWithdrawalAfterVesting() public {
        uint256 distributeAmount = 2000 ether;

        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // User1 claims
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // After full vesting period
        vm.warp(block.timestamp + VESTING_DURATION);

        uint256 balanceBefore = rewardToken1.balanceOf(user1);

        vm.prank(user1);
        dividends.withdrawVested(address(rewardToken1));

        uint256 balanceAfter = rewardToken1.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, 1000 ether);
    }

    function testWithdrawAllVested_MultipleTokens() public {
        // Distribute both tokens
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 2000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        rewardToken2.approve(address(dividends), 4000 ether);
        dividends.distribute(address(rewardToken2), 4000 ether);
        vm.stopPrank();

        // User1 claims all
        vm.prank(user1);
        dividends.claimAll();

        // Full vesting
        vm.warp(block.timestamp + VESTING_DURATION);

        uint256 balance1Before = rewardToken1.balanceOf(user1);
        uint256 balance2Before = rewardToken2.balanceOf(user1);

        vm.prank(user1);
        dividends.withdrawAllVested();

        uint256 balance1After = rewardToken1.balanceOf(user1);
        uint256 balance2After = rewardToken2.balanceOf(user1);

        assertEq(balance1After - balance1Before, 1000 ether);
        assertEq(balance2After - balance2Before, 2000 ether);
    }

    // ============ MULTIPLE VESTING TRANCHES TESTS ============

    function testMultipleTranches_SeperateVestingSchedules() public {
        // First distribution and claim
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 4000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.stopPrank();

        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Advance 90 days
        vm.warp(block.timestamp + 90 days);

        // Second distribution and claim
        vm.prank(vault);
        dividends.distribute(address(rewardToken1), 2000 ether);

        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Check two tranches exist
        vm.prank(user1);
        NomaDividends.VestingEntry[] memory entries = dividends.getVestingEntries(address(rewardToken1));
        assertEq(entries.length, 2);

        // First tranche: 1000 ether, 50% vested (90 days)
        // Second tranche: 1000 ether, 0% vested (just started)

        uint256 claimable = dividends.claimable(address(rewardToken1), user1);
        assertEq(claimable, 500 ether); // Only first tranche is 50% vested
    }

    // ============ SHARES TOKEN HOOK TESTS ============

    function testSharesTransferHook_AccruesOnTransfer() public {
        // Distribute rewards
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 2000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.stopPrank();

        // Before transfer, check claimable
        uint256 user1ClaimableBefore = dividends.claimableRaw(address(rewardToken1), user1);

        // Transfer shares from user1 to user2
        vm.prank(user1);
        sharesToken.transfer(user2, 500 ether);

        // After transfer, rewards should be accrued
        // Note: claimableRaw includes accrued, so user1 should still have their rewards
        uint256 user1ClaimableAfter = dividends.claimableRaw(address(rewardToken1), user1);

        // User1 rewards should be preserved after transfer
        assertEq(user1ClaimableAfter, user1ClaimableBefore);
    }

    function testSharesTransferHook_NewUserGetsRewardsFromNextDistribution() public {
        address newUser = address(0x5555);

        // First distribution (newUser has 0 shares)
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 4000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.stopPrank();

        // newUser has no claimable from first distribution
        uint256 newUserClaimable = dividends.claimableRaw(address(rewardToken1), newUser);
        assertEq(newUserClaimable, 0);

        // Transfer shares to newUser
        vm.prank(user1);
        sharesToken.transfer(newUser, 500 ether);

        // Second distribution
        vm.prank(vault);
        dividends.distribute(address(rewardToken1), 2000 ether);

        // newUser should get rewards from second distribution only
        // Total shares: 2000 ether, newUser: 500 ether (25%)
        newUserClaimable = dividends.claimableRaw(address(rewardToken1), newUser);
        assertEq(newUserClaimable, 500 ether); // 25% of 2000
    }

    function testSharesTransferHook_AutoWithdrawOnTransfer() public {
        // Enable auto-claim (default is true)
        assertTrue(dividends.autoClaimOnTransfer());

        // Distribute and claim
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 2000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.stopPrank();

        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Wait for full vesting
        vm.warp(block.timestamp + VESTING_DURATION);

        uint256 balanceBefore = rewardToken1.balanceOf(user1);

        // Transfer shares - should auto-withdraw vested
        vm.prank(user1);
        sharesToken.transfer(user2, 100 ether);

        uint256 balanceAfter = rewardToken1.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, 1000 ether);
    }

    function testSetAutoClaimOnTransfer_DisableAutoWithdraw() public {
        // Disable auto-claim
        dividends.setAutoClaimOnTransfer(false);
        assertFalse(dividends.autoClaimOnTransfer());

        // Distribute and claim
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 2000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.stopPrank();

        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Wait for full vesting
        vm.warp(block.timestamp + VESTING_DURATION);

        uint256 balanceBefore = rewardToken1.balanceOf(user1);

        // Transfer shares - should NOT auto-withdraw
        vm.prank(user1);
        sharesToken.transfer(user2, 100 ether);

        uint256 balanceAfter = rewardToken1.balanceOf(user1);
        assertEq(balanceAfter, balanceBefore); // No auto-withdrawal
    }

    // ============ EDGE CASES ============

    function testDistribute_NoSharesReverts() public {
        // Create new dividends with empty shares token
        MockSharesToken emptySharesToken = new MockSharesToken();

        // Setup new dividends pointing to empty token
        bytes32[] memory names = new bytes32[](1);
        address[] memory addresses = new address[](1);
        names[0] = Utils.stringToBytes32("NomaToken");
        addresses[0] = address(emptySharesToken);
        resolver.importAddresses(names, addresses);

        NomaDividends emptyDividends = new NomaDividends(address(factory), address(resolver));
        emptyDividends.setSharesToken();

        vm.startPrank(vault);
        rewardToken1.approve(address(emptyDividends), 1000 ether);
        vm.expectRevert(NoShares.selector);
        emptyDividends.distribute(address(rewardToken1), 1000 ether);
        vm.stopPrank();
    }

    function testClaimable_UserWithZeroShares() public {
        address zeroShareUser = address(0x9999);

        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 2000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.stopPrank();

        uint256 claimable = dividends.claimableRaw(address(rewardToken1), zeroShareUser);
        assertEq(claimable, 0);
    }

    function testVesting_ExcessTimeDoesNotIncreaseClaim() public {
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 2000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.stopPrank();

        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Warp way beyond vesting period
        vm.warp(block.timestamp + 365 days);

        uint256 claimable = dividends.claimable(address(rewardToken1), user1);
        assertEq(claimable, 1000 ether); // Still just 100%, not more
    }

    function testOnlyOwner_SetAutoClaimOnTransfer() public {
        vm.prank(user1);
        vm.expectRevert(OnlyOwner.selector);
        dividends.setAutoClaimOnTransfer(false);
    }

    function testOnlyOwner_SetSharesToken() public {
        vm.prank(user1);
        vm.expectRevert(OnlyOwner.selector);
        dividends.setSharesToken();
    }

    function testOnlySharesToken_TransferHook() public {
        vm.prank(user1);
        vm.expectRevert(NotSharesToken.selector);
        dividends.onSharesTransferHook(user1, user2);
    }

    // ============ ESCROW BEHAVIOR TESTS ============

    function testEscrow_TokensHeldUntilVested() public {
        uint256 distributeAmount = 2000 ether;
        // Note: 1 ether already distributed in setUp for initialization
        uint256 initialBalance = rewardToken1.balanceOf(address(dividends));

        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // Check tokens are in dividends contract (including initial distribution)
        assertEq(rewardToken1.balanceOf(address(dividends)), initialBalance + distributeAmount);

        // User claims (locks into vesting)
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Tokens should still be in contract (escrowed)
        assertEq(rewardToken1.balanceOf(address(dividends)), initialBalance + distributeAmount);

        // User cannot withdraw before vesting
        vm.prank(user1);
        dividends.withdrawVested(address(rewardToken1));
        assertEq(rewardToken1.balanceOf(user1), 0); // Nothing vested yet

        // After full vesting
        vm.warp(block.timestamp + VESTING_DURATION);

        vm.prank(user1);
        dividends.withdrawVested(address(rewardToken1));

        // Now user has their tokens (50% of 2000 ether)
        assertEq(rewardToken1.balanceOf(user1), 1000 ether);

        // Remaining in escrow for other users (initial 1 ether + 1000 for others)
        assertEq(rewardToken1.balanceOf(address(dividends)), initialBalance + 1000 ether);
    }

    function testEscrow_MultipleClaimsMultipleTranches() public {
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 6000 ether);
        vm.stopPrank();

        // Week 1: Distribute and claim
        vm.prank(vault);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Week 2: Another distribution and claim
        vm.warp(block.timestamp + 7 days);
        vm.prank(vault);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Week 3: Another distribution and claim
        vm.warp(block.timestamp + 7 days);
        vm.prank(vault);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Check 3 tranches
        vm.prank(user1);
        NomaDividends.VestingEntry[] memory entries = dividends.getVestingEntries(address(rewardToken1));
        assertEq(entries.length, 3);
        assertEq(entries[0].amount, 1000 ether);
        assertEq(entries[1].amount, 1000 ether);
        assertEq(entries[2].amount, 1000 ether);

        // Full vesting of first tranche only
        vm.warp(block.timestamp + VESTING_DURATION - 14 days);

        uint256 claimable = dividends.claimable(address(rewardToken1), user1);
        // First tranche: 100% vested = 1000
        // Second tranche: ~96% vested
        // Third tranche: ~92% vested
        // This should be close to but less than 3000
        assertTrue(claimable > 2800 ether && claimable < 3000 ether);
    }

    // ============ GAS OPTIMIZATION TESTS ============

    function testGasEfficiency_ManyRewardTokens() public {
        // Already have 2 tokens from setUp, add 8 more for total of 10
        MockRewardToken[] memory tokens = new MockRewardToken[](8);
        for (uint i = 0; i < 8; i++) {
            tokens[i] = new MockRewardToken(
                string(abi.encodePacked("Token", i)),
                string(abi.encodePacked("TKN", i))
            );
            tokens[i].mint(vault, 10000 ether);
        }

        // Distribute new tokens
        vm.startPrank(vault);
        for (uint i = 0; i < 8; i++) {
            tokens[i].approve(address(dividends), 1000 ether);
            dividends.distribute(address(tokens[i]), 1000 ether);
        }
        vm.stopPrank();

        // Need to trigger accrual for user1 for the new tokens
        vm.prank(user1);
        sharesToken.transfer(user1, 0);

        // Gas test: claimAll with many tokens (2 from setUp + 8 new = 10 total)
        vm.prank(user1);
        uint256 gasBefore = gasleft();
        dividends.claimAll();
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for claimAll with 10 tokens:", gasUsed);

        // Verify all tokens have entries (2 from setUp + 8 new)
        assertEq(dividends.getRewardTokens().length, 10);
    }

    // ============ NOMA TOKEN ACTIVE/INACTIVE FLOW TESTS ============

    /// @notice Test dividend flow when $NOMA token is NOT active (sharesToken = address(0))
    function testFlow_WithoutNomaToken_DistributeSilentlyReturns() public {
        // Create fresh dividends contract without setting shares token
        NomaDividends freshDividends = new NomaDividends(address(factory), address(resolver));

        // Verify shares token is not set
        assertEq(address(freshDividends.sharesToken()), address(0));

        // Mint reward tokens to vault
        rewardToken1.mint(vault, 1000 ether);

        uint256 vaultBalanceBefore = rewardToken1.balanceOf(vault);
        uint256 dividendsBalanceBefore = rewardToken1.balanceOf(address(freshDividends));

        // Try to distribute - should silently return without transferring tokens
        vm.startPrank(vault);
        rewardToken1.approve(address(freshDividends), 1000 ether);
        freshDividends.distribute(address(rewardToken1), 1000 ether);
        vm.stopPrank();

        // Verify no tokens were transferred (distribute returned early)
        assertEq(rewardToken1.balanceOf(vault), vaultBalanceBefore);
        assertEq(rewardToken1.balanceOf(address(freshDividends)), dividendsBalanceBefore);

        // Verify no reward token was registered
        assertEq(freshDividends.getRewardTokens().length, 0);
        assertEq(freshDividends.getTotalDistributed(address(rewardToken1)), 0);
    }

    /// @notice Test that claim operations fail gracefully when sharesToken is not set
    function testFlow_WithoutNomaToken_ClaimRevertsOnBalanceCall() public {
        // Create fresh dividends contract without setting shares token
        NomaDividends freshDividends = new NomaDividends(address(factory), address(resolver));

        // Verify shares token is not set
        assertEq(address(freshDividends.sharesToken()), address(0));

        // Try to call claimableRaw - should revert when trying to call balanceOf on address(0)
        vm.expectRevert();
        freshDividends.claimableRaw(address(rewardToken1), user1);
    }

    /// @notice Test that claim fails when sharesToken is not set
    function testFlow_WithoutNomaToken_ClaimFails() public {
        // Create fresh dividends contract without setting shares token
        NomaDividends freshDividends = new NomaDividends(address(factory), address(resolver));

        // Try to claim - should revert
        vm.prank(user1);
        vm.expectRevert();
        freshDividends.claim(address(rewardToken1));
    }

    /// @notice Test that claimAll is a no-op when sharesToken is not set (no reward tokens registered)
    function testFlow_WithoutNomaToken_ClaimAllIsNoOp() public {
        // Create fresh dividends contract without setting shares token
        NomaDividends freshDividends = new NomaDividends(address(factory), address(resolver));

        // claimAll returns early when no reward tokens registered (doesn't revert)
        // This is expected behavior - nothing to claim
        vm.prank(user1);
        freshDividends.claimAll(); // Should not revert, just return early

        // Verify no vesting entries were created
        assertEq(freshDividends.getRewardTokens().length, 0);
    }

    /// @notice Test the full dividend flow with $NOMA token active
    function testFlow_WithNomaToken_FullDividendCycle() public {
        // This test uses the main dividends contract which has sharesToken set

        // Verify shares token is set
        assertTrue(address(dividends.sharesToken()) != address(0));
        assertEq(address(dividends.sharesToken()), address(sharesToken));

        // Track initial state
        uint256 user1InitialBalance = rewardToken1.balanceOf(user1);
        uint256 user2InitialBalance = rewardToken1.balanceOf(user2);

        // Step 1: Distribute rewards
        uint256 distributeAmount = 4000 ether;
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // Step 2: Trigger accrual for users
        triggerAccrual(user1);
        triggerAccrual(user2);

        // Step 3: Verify claimable amounts (proportional to shares)
        // user1 has 1000/2000 = 50% of shares
        // user2 has 500/2000 = 25% of shares
        uint256 user1Claimable = dividends.claimableRaw(address(rewardToken1), user1);
        uint256 user2Claimable = dividends.claimableRaw(address(rewardToken1), user2);

        assertEq(user1Claimable, 2000 ether); // 50% of 4000
        assertEq(user2Claimable, 1000 ether); // 25% of 4000

        // Step 4: Users claim (lock into vesting)
        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        vm.prank(user2);
        dividends.claim(address(rewardToken1));

        // Step 5: Verify vesting entries created
        vm.prank(user1);
        NomaDividends.VestingEntry[] memory user1Entries = dividends.getVestingEntries(address(rewardToken1));
        assertEq(user1Entries.length, 1);
        assertEq(user1Entries[0].amount, 2000 ether);

        vm.prank(user2);
        NomaDividends.VestingEntry[] memory user2Entries = dividends.getVestingEntries(address(rewardToken1));
        assertEq(user2Entries.length, 1);
        assertEq(user2Entries[0].amount, 1000 ether);

        // Step 6: At t=0, nothing vested yet
        assertEq(dividends.claimable(address(rewardToken1), user1), 0);
        assertEq(dividends.claimable(address(rewardToken1), user2), 0);

        // Step 7: After 90 days (50% vesting)
        vm.warp(block.timestamp + 90 days);

        uint256 user1Vested = dividends.claimable(address(rewardToken1), user1);
        uint256 user2Vested = dividends.claimable(address(rewardToken1), user2);

        assertEq(user1Vested, 1000 ether); // 50% of 2000
        assertEq(user2Vested, 500 ether);  // 50% of 1000

        // Step 8: Users withdraw partial vested amounts
        vm.prank(user1);
        dividends.withdrawVested(address(rewardToken1));

        vm.prank(user2);
        dividends.withdrawVested(address(rewardToken1));

        // Verify tokens received
        assertEq(rewardToken1.balanceOf(user1) - user1InitialBalance, 1000 ether);
        assertEq(rewardToken1.balanceOf(user2) - user2InitialBalance, 500 ether);

        // Step 9: After full vesting (180 days total)
        vm.warp(block.timestamp + 90 days);

        // Step 10: Withdraw remaining vested amounts
        vm.prank(user1);
        dividends.withdrawVested(address(rewardToken1));

        vm.prank(user2);
        dividends.withdrawVested(address(rewardToken1));

        // Verify full amounts received
        assertEq(rewardToken1.balanceOf(user1) - user1InitialBalance, 2000 ether);
        assertEq(rewardToken1.balanceOf(user2) - user2InitialBalance, 1000 ether);

        console.log("Full dividend cycle completed successfully:");
        console.log("  User1 received:", rewardToken1.balanceOf(user1) - user1InitialBalance);
        console.log("  User2 received:", rewardToken1.balanceOf(user2) - user2InitialBalance);
    }

    /// @notice Test activating $NOMA token after contract deployment
    function testFlow_ActivatingNomaToken_EnablesDividends() public {
        // Create fresh dividends contract
        NomaDividends freshDividends = new NomaDividends(address(factory), address(resolver));

        // Create a fresh shares token for this test
        MockSharesToken freshSharesToken = new MockSharesToken();

        // Phase 1: Without NOMA token - distributions are no-ops
        assertEq(address(freshDividends.sharesToken()), address(0));

        rewardToken1.mint(vault, 3000 ether);
        vm.startPrank(vault);
        rewardToken1.approve(address(freshDividends), 1000 ether);
        freshDividends.distribute(address(rewardToken1), 1000 ether);
        vm.stopPrank();

        // No tokens transferred, no reward registered
        assertEq(freshDividends.getRewardTokens().length, 0);

        // Phase 2: Activate NOMA token
        // First update the resolver to point to new shares token
        bytes32[] memory names = new bytes32[](1);
        address[] memory addresses = new address[](1);
        names[0] = Utils.stringToBytes32("NomaToken");
        addresses[0] = address(freshSharesToken);
        resolver.importAddresses(names, addresses);

        // Set shares token in dividends
        freshDividends.setSharesToken();

        // Configure shares token to use dividends
        freshSharesToken.setDividendsManager(freshDividends);

        // Mint shares to user
        freshSharesToken.mint(user1, 1000 ether);

        // Verify shares token is now set
        assertEq(address(freshDividends.sharesToken()), address(freshSharesToken));

        // Phase 3: First do an initialization distribution to set non-zero index
        // (Required because userIndex=0 causes early return in accrueForUser)
        vm.startPrank(vault);
        rewardToken1.approve(address(freshDividends), 2000 ether);
        freshDividends.distribute(address(rewardToken1), 1 ether); // Small init distribution
        vm.stopPrank();

        // User triggers accrual to set their index baseline
        vm.prank(user1);
        freshSharesToken.transfer(user1, 0);

        // Phase 4: Now do the real distribution
        vm.prank(vault);
        freshDividends.distribute(address(rewardToken1), 1000 ether);

        // Trigger accrual for user1 to capture rewards
        vm.prank(user1);
        freshSharesToken.transfer(user1, 0);

        // User should have claimable rewards from the 1000 ether distribution
        uint256 claimable = freshDividends.claimableRaw(address(rewardToken1), user1);
        assertEq(claimable, 1000 ether); // 100% since user1 has all shares

        // Verify total distributed
        assertEq(freshDividends.getRewardTokens().length, 1);
        assertEq(freshDividends.getTotalDistributed(address(rewardToken1)), 1001 ether); // 1 init + 1000

        console.log("NOMA token activation test passed:");
        console.log("  Before activation: distributions were no-ops");
        console.log("  After activation: user1 can claim", claimable);
    }

    /// @notice Test that dividend hook integration works correctly with shares transfers
    function testFlow_WithNomaToken_TransferHookIntegration() public {
        // Distribute rewards
        uint256 distributeAmount = 2000 ether;
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // User1 has 1000 ether shares, user2 has 500 ether shares
        // Before transfer: user1 claimable = 1000 ether (50%), user2 = 500 ether (25%)

        // Transfer 500 shares from user1 to user2
        // This should:
        // 1. Accrue user1's rewards before the transfer
        // 2. Accrue user2's rewards before the transfer
        // 3. Update balances

        vm.prank(user1);
        sharesToken.transfer(user2, 500 ether);

        // After transfer:
        // user1: 500 ether shares
        // user2: 1000 ether shares
        assertEq(sharesToken.balanceOf(user1), 500 ether);
        assertEq(sharesToken.balanceOf(user2), 1000 ether);

        // Claimable should still reflect the pre-transfer accruals
        uint256 user1Claimable = dividends.claimableRaw(address(rewardToken1), user1);
        uint256 user2Claimable = dividends.claimableRaw(address(rewardToken1), user2);

        // user1 earned 1000 ether from this distribution (50%)
        assertEq(user1Claimable, 1000 ether);
        // user2 earned 500 ether from this distribution (25%)
        assertEq(user2Claimable, 500 ether);

        // New distribution after share transfer
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), distributeAmount);
        dividends.distribute(address(rewardToken1), distributeAmount);
        vm.stopPrank();

        // Trigger accrual
        triggerAccrual(user1);
        triggerAccrual(user2);

        // Now user1 gets 25% (500/2000) and user2 gets 50% (1000/2000)
        user1Claimable = dividends.claimableRaw(address(rewardToken1), user1);
        user2Claimable = dividends.claimableRaw(address(rewardToken1), user2);

        // user1: 1000 (first) + 500 (second) = 1500
        assertEq(user1Claimable, 1500 ether);
        // user2: 500 (first) + 1000 (second) = 1500
        assertEq(user2Claimable, 1500 ether);

        console.log("Transfer hook integration test passed:");
        console.log("  User1 claimable after transfers:", user1Claimable);
        console.log("  User2 claimable after transfers:", user2Claimable);
    }

    /// @notice Test multiple distribution cycles with $NOMA token
    function testFlow_WithNomaToken_MultipleDistributionCycles() public {
        // Disable auto-claim to test vesting accumulation cleanly
        dividends.setAutoClaimOnTransfer(false);

        uint256 user1InitialBalance = rewardToken1.balanceOf(user1);

        // Cycle 1: Week 1
        vm.startPrank(vault);
        rewardToken1.approve(address(dividends), 6000 ether);
        dividends.distribute(address(rewardToken1), 2000 ether);
        vm.stopPrank();

        triggerAccrual(user1);

        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Cycle 2: Week 2
        vm.warp(block.timestamp + 7 days);

        vm.prank(vault);
        dividends.distribute(address(rewardToken1), 2000 ether);

        triggerAccrual(user1);

        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Cycle 3: Week 3
        vm.warp(block.timestamp + 7 days);

        vm.prank(vault);
        dividends.distribute(address(rewardToken1), 2000 ether);

        triggerAccrual(user1);

        vm.prank(user1);
        dividends.claim(address(rewardToken1));

        // Verify 3 vesting tranches
        vm.prank(user1);
        NomaDividends.VestingEntry[] memory entries = dividends.getVestingEntries(address(rewardToken1));
        assertEq(entries.length, 3);

        // Each tranche should have 1000 ether (50% of 2000)
        for (uint i = 0; i < 3; i++) {
            assertEq(entries[i].amount, 1000 ether);
        }

        // Fast forward to full vesting of all tranches
        // Need to warp from the last tranche's start time + VESTING_DURATION
        vm.warp(block.timestamp + VESTING_DURATION);

        // Withdraw all vested
        vm.prank(user1);
        dividends.withdrawAllVested();

        uint256 user1TotalReceived = rewardToken1.balanceOf(user1) - user1InitialBalance;

        // Should have received 3000 ether total (3 * 1000)
        assertEq(user1TotalReceived, 3000 ether);

        console.log("Multiple distribution cycles test passed:");
        console.log("  Total claimed by user1:", user1TotalReceived);
    }
}
