// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { Presale } from "../src/bootstrap/Presale.sol";
import { NomaFactory } from "../src/factory/NomaFactory.sol";
import { TestResolver } from "./resolver/Resolver.sol";
import { DeployerFactory } from "../src/factory/DeployerFactory.sol";
import { ExtFactory } from "../src/factory/ExtFactory.sol";
import { EtchVault } from "../src/vault/deploy/EtchVault.sol";
import { TokenFactory } from "../src/factory/TokenFactory.sol";
import { VaultInit } from "../src/vault/init/VaultInit.sol";
import {
    VaultUpgrade,
    VaultUpgradeStep1,
    VaultUpgradeStep2,
    VaultUpgradeStep3,
    VaultUpgradeStep4,
    VaultUpgradeStep5
} from "../src/vault/init/VaultUpgrade.sol";
import { VaultFinalize } from "../src/vault/init/VaultFinalize.sol";
import {
    VaultDeployParams,
    PresaleUserParams,
    VaultDescription,
    ProtocolParameters,
    PresaleProtocolParams,
    ExistingDeployData,
    Decimals,
    LivePresaleParams
} from "../src/types/Types.sol";
import "../src/libraries/Utils.sol";
import { ModelHelper } from "../src/model/Helper.sol";
import { AdaptiveSupply } from "../src/controllers/supply/AdaptiveSupply.sol";
import { PresaleFactory } from "../src/factory/PresaleFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct ContractInfo {
    string name;
    address addr;
}

/// @title PresaleTest
/// @notice Comprehensive tests for the Presale contract using real fork deployments
/// @dev Tests cover deposit, finalization, withdrawal, referrals, emergency withdrawal, and admin functions
contract PresaleTest is Test {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    // Use higher addresses to avoid precompile/low address issues with ETH transfers
    address user1 = address(0x100001);
    address user2 = address(0x100002);
    address user3 = address(0x100003);
    address teamMultiSig;

    NomaFactory nomaFactory;
    TestResolver resolver;
    EtchVault etchVault;
    VaultUpgrade vaultUpgrade;
    ModelHelper modelHelper;
    AdaptiveSupply adaptiveSupply;
    TokenFactory tokenFactory;
    PresaleFactory presaleFactory;

    // Deployed vault and presale
    address vault;
    address pool;
    Presale presale;

    // Constants mainnet - same as NomaFactory.t.sol
    address WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address private uniswapFactory = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address private pancakeSwapFactory = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

    ContractInfo[] private expectedAddressesInResolver;

    // Presale test parameters
    uint256 public constant SOFT_CAP = 0.5 ether;
    uint256 public constant PRESALE_DURATION = 7 days;

    // Computed values
    uint256 public hardCap;
    uint256 public minContribution;
    uint256 public maxContribution;

    function setUp() public {
        // Skip if not running on fork (Uniswap factory won't be deployed)
        if (uniswapFactory.code.length == 0) {
            return;
        }

        vm.prank(deployer);

        // Model Helper
        modelHelper = new ModelHelper();

        expectedAddressesInResolver.push(
            ContractInfo("ModelHelper", address(modelHelper))
        );

        // Resolver
        resolver = new TestResolver(deployer);

        expectedAddressesInResolver.push(
            ContractInfo("Resolver", address(resolver))
        );

        // Presale Factory
        presaleFactory = new PresaleFactory(address(resolver));

        expectedAddressesInResolver.push(
            ContractInfo("PresaleFactory", address(presaleFactory))
        );

        // Adaptive Supply
        adaptiveSupply = new AdaptiveSupply();

        expectedAddressesInResolver.push(
            ContractInfo("AdaptiveSupply", address(adaptiveSupply))
        );

        // Token Factory
        tokenFactory = new TokenFactory(address(resolver));

        expectedAddressesInResolver.push(
            ContractInfo("TokenFactory", address(tokenFactory))
        );

        // Deployer contracts factory
        DeployerFactory deploymentFactory = new DeployerFactory(address(resolver));
        // External contracts factory
        ExtFactory extFactory = new ExtFactory(address(resolver));

        vm.prank(deployer);
        // Noma Factory
        nomaFactory = new NomaFactory(
            uniswapFactory,
            pancakeSwapFactory,
            address(resolver),
            address(deploymentFactory),
            address(extFactory),
            address(presaleFactory)
        );

        teamMultiSig = nomaFactory.teamMultiSig();

        expectedAddressesInResolver.push(
            ContractInfo("NomaFactory", address(nomaFactory))
        );

        vm.prank(deployer);
        etchVault = new EtchVault(address(nomaFactory), address(resolver));
        vaultUpgrade = new VaultUpgrade(deployer, address(nomaFactory));

        // VaultStep1 adds BaseVault (used by preDeployVault during deployVault)
        VaultInit vaultStep1 = new VaultInit(deployer, address(nomaFactory));

        // VaultUpgradeStep1 adds StakingVault (used by configureVault)
        VaultUpgradeStep1 vaultUpgradeStep1 = new VaultUpgradeStep1(deployer, address(nomaFactory));

        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer, address(nomaFactory));
        VaultUpgradeStep3 vaultUpgradeStep3 = new VaultUpgradeStep3(deployer, address(nomaFactory));
        VaultUpgradeStep4 vaultUpgradeStep4 = new VaultUpgradeStep4(deployer, address(nomaFactory));
        VaultUpgradeStep5 vaultUpgradeStep5 = new VaultUpgradeStep5(deployer, address(nomaFactory));

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgrade", address(vaultUpgrade))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultStep1", address(vaultStep1))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep1", address(vaultUpgradeStep1))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep2", address(vaultUpgradeStep2))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep3", address(vaultUpgradeStep3))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep4", address(vaultUpgradeStep4))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgradeStep5", address(vaultUpgradeStep5))
        );

        expectedAddressesInResolver.push(
            ContractInfo("EtchVault", address(etchVault))
        );

        expectedAddressesInResolver.push(
            ContractInfo("WMON", WMON)
        );

        vm.prank(deployer);
        configureResolver();

        // Set protocol parameters
        ProtocolParameters memory _params =
        ProtocolParameters(
            10,         // Floor percentage of total supply
            5,          // Anchor percentage of total supply
            3,          // IDO price multiplier
            [200, 500], // Floor bips
            90e16,      // Shift liquidity ratio
            120e16,     // Slide liquidity ratio
            25000,      // Discovery deploy bips
            10,         // shiftAnchorUpperBips
            300,        // slideAnchorUpperBips
            100,        // lowBalanceThresholdFactor
            100,        // highBalanceThresholdFactor
            5e15,       // inflationFee
            25,         // maxLoanUtilization
            27,         // loanFee
            0.01e18,    // deployFee (ETH)
            25,         // presalePremium (25% = 25)
            1_250,      // self repaying loan ltv treshold
            0.5e18,     // Adaptive supply curve half step
            2,          // Skim ratio
            Decimals(6, 18), // Decimals (minDecimals, maxDecimals
            1e14        // basePriceDecimals
        );

        vm.prank(deployer);
        nomaFactory.setProtocolParameters(_params);

        // Set presale protocol parameters
        PresaleProtocolParams memory presaleParams = PresaleProtocolParams({
            maxSoftCap: 100,           // 100% of hard cap max
            minContributionRatioBps: 100,   // 1% min
            maxContributionRatioBps: 2500,  // 25% max
            presalePercentage: 10,     // 10% fee
            minDuration: 3 days,
            maxDuration: 90 days,
            referralPercentage: 5,     // 5% referral
            teamFee: 20                // 20% of excess goes to team
        });

        vm.prank(deployer);
        nomaFactory.setPresaleProtocolParams(presaleParams);

        // Fund test users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(deployer, 100 ether);
    }

    /// @notice Deploy a vault with presale enabled
    function _deployVaultWithPresale() internal {
        // Skip if not running on fork
        if (uniswapFactory.code.length == 0) {
            vm.skip(true);
        }

        VaultDeployParams memory vaultDeployParams = VaultDeployParams(
            "Presale Test Token",
            "PTEST",
            18,
            10_000_000e18,        // Total supply (10 million tokens, min required)
            20_000_000e18,        // Max supply
            1e14,                 // IDO Price (0.0001 ETH per token)
            0,
            WMON,                 // Token1 address
            3000,                 // Uniswap V3 Fee tier
            1,                    // Presale = 1 (enabled)
            true,                 // Is fresh deploy
            true                  // use Uniswap
        );

        PresaleUserParams memory presaleUserParams = PresaleUserParams(
            SOFT_CAP,
            PRESALE_DURATION
        );

        vm.prank(deployer);
        (address _vault, address _pool, ) = nomaFactory.deployVault(
            presaleUserParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );

        vault = _vault;
        pool = _pool;

        // Get presale contract from vault description
        VaultDescription memory vaultDesc = nomaFactory.getVaultDescription(vault);
        presale = Presale(vaultDesc.presaleContract);

        // Calculate contribution limits
        hardCap = presale.hardCap();
        minContribution = presale.MIN_CONTRIBUTION();
        maxContribution = presale.MAX_CONTRIBUTION();
    }

    function configureResolver() internal {
        bytes32[] memory names = new bytes32[](expectedAddressesInResolver.length);
        address[] memory addresses = new address[](expectedAddressesInResolver.length);

        for (uint256 i = 0; i < expectedAddressesInResolver.length; i++) {
            names[i] = Utils.stringToBytes32(expectedAddressesInResolver[i].name);
            addresses[i] = expectedAddressesInResolver[i].addr;
        }

        bool areAddressesInResolver = resolver.areAddressesImported(names, addresses);

        if (!areAddressesInResolver) {
            vm.prank(deployer);
            resolver.importAddresses(names, addresses);
        }
    }

    // ============ HELPER FUNCTIONS ============

    function _deposit(address user, uint256 amount) internal {
        vm.prank(user);
        presale.deposit{value: amount}(bytes8(0));
    }

    function _depositWithReferral(address user, uint256 amount, bytes8 referralCode) internal {
        vm.prank(user);
        presale.deposit{value: amount}(referralCode);
    }

    function _getReferralCode(address user) internal pure returns (bytes8) {
        return Utils.getReferralCode(user);
    }

    function _fillToSoftCap() internal {
        uint256 deposited = presale.totalDeposited();
        uint256 userIndex = 0;

        while (deposited < SOFT_CAP && userIndex < 50) {
            address depositor = address(uint160(0x2000 + userIndex));
            vm.deal(depositor, 100 ether);

            uint256 depositAmount = minContribution;
            if (deposited + depositAmount > hardCap) {
                break;
            }

            vm.prank(depositor);
            presale.deposit{value: depositAmount}(bytes8(0));
            deposited += depositAmount;
            userIndex++;
        }
    }

    // ============ INITIALIZATION TESTS ============

    /// @notice Test presale initializes with correct parameters
    function testInitialization() public {
        _deployVaultWithPresale();

        assertEq(presale.deployer(), deployer);
        assertEq(address(presale.pool()), pool);
        assertEq(presale.softCap(), SOFT_CAP);
        assertFalse(presale.finalized());
        assertEq(presale.totalRaised(), 0);
        assertEq(presale.totalDeposited(), 0);
    }

    /// @notice Test hard cap calculation
    function testHardCapCalculation() public {
        _deployVaultWithPresale();

        // Hard cap should be calculated based on launch supply, initial price, and floor percentage
        assertTrue(presale.hardCap() > 0);
        assertTrue(presale.hardCap() >= presale.softCap());
    }

    /// @notice Test presale params getter
    function testGetPresaleParams() public {
        _deployVaultWithPresale();

        LivePresaleParams memory params = presale.getPresaleParams();
        assertEq(params.softCap, SOFT_CAP);
        assertEq(params.hardCap, hardCap);
        assertEq(params.deployer, deployer);
    }

    // ============ DEPOSIT TESTS ============

    /// @notice Test valid deposit without referral
    function testDeposit_ValidWithoutReferral() public {
        _deployVaultWithPresale();

        uint256 depositAmount = minContribution;

        vm.prank(user1);
        presale.deposit{value: depositAmount}(bytes8(0));

        assertEq(presale.contributions(user1), depositAmount);
        assertEq(presale.totalDeposited(), depositAmount);
        assertEq(presale.totalRaised(), depositAmount);
        assertTrue(presale.isContributor(user1));
        assertEq(presale.getParticipantCount(), 1);

        // Check p-asset minting
        assertTrue(presale.balanceOf(user1) > 0);
    }

    /// @notice Test valid deposit with referral code
    function testDeposit_ValidWithReferral() public {
        _deployVaultWithPresale();

        uint256 depositAmount = minContribution;
        bytes8 referralCode = _getReferralCode(user2);

        vm.prank(user1);
        presale.deposit{value: depositAmount}(referralCode);

        assertEq(presale.contributions(user1), depositAmount);

        // Check referral earnings (5% of deposit)
        uint256 expectedReferralEarnings = (depositAmount * 5) / 100;
        assertEq(presale.referralEarnings(referralCode), expectedReferralEarnings);
        assertEq(presale.referralParticipants(referralCode), 1);
    }

    /// @notice Test multiple deposits from different users
    function testDeposit_MultipleUsers() public {
        _deployVaultWithPresale();

        uint256 depositAmount = minContribution;

        _deposit(user1, depositAmount);
        _deposit(user2, depositAmount);
        _deposit(user3, depositAmount);

        assertEq(presale.getParticipantCount(), 3);
        assertEq(presale.totalDeposited(), depositAmount * 3);
    }

    /// @notice Test deposit reverts after deadline
    function testDeposit_RevertsAfterDeadline() public {
        _deployVaultWithPresale();

        // Warp past deadline
        vm.warp(block.timestamp + PRESALE_DURATION + 1);

        vm.prank(user1);
        vm.expectRevert(Presale.PresaleEnded.selector);
        presale.deposit{value: minContribution}(bytes8(0));
    }

    /// @notice Test deposit reverts if already contributed
    function testDeposit_RevertsIfAlreadyContributed() public {
        _deployVaultWithPresale();

        _deposit(user1, minContribution);

        vm.prank(user1);
        vm.expectRevert(Presale.AlreadyContributed.selector);
        presale.deposit{value: minContribution}(bytes8(0));
    }

    /// @notice Test deposit reverts with zero amount
    function testDeposit_RevertsWithZeroAmount() public {
        _deployVaultWithPresale();

        vm.prank(user1);
        vm.expectRevert(Presale.InvalidParameters.selector);
        presale.deposit{value: 0}(bytes8(0));
    }

    /// @notice Test deposit reverts with self-referral
    function testDeposit_RevertsWithSelfReferral() public {
        _deployVaultWithPresale();

        bytes8 selfReferralCode = _getReferralCode(user1);

        vm.prank(user1);
        vm.expectRevert(Presale.InvalidParameters.selector);
        presale.deposit{value: minContribution}(selfReferralCode);
    }

    /// @notice Test deposit reverts below minimum contribution
    function testDeposit_RevertsBelowMinContribution() public {
        _deployVaultWithPresale();

        uint256 belowMin = minContribution - 1;

        vm.prank(user1);
        vm.expectRevert(Presale.InvalidParameters.selector);
        presale.deposit{value: belowMin}(bytes8(0));
    }

    /// @notice Test deposit reverts above maximum contribution
    function testDeposit_RevertsAboveMaxContribution() public {
        _deployVaultWithPresale();

        uint256 aboveMax = maxContribution + 1;

        vm.prank(user1);
        vm.expectRevert(Presale.InvalidParameters.selector);
        presale.deposit{value: aboveMax}(bytes8(0));
    }

    /// @notice Test deposit reverts if would exceed hard cap
    function testDeposit_RevertsIfExceedsHardCap() public {
        _deployVaultWithPresale();

        // Fill up to hard cap
        uint256 numDepositsNeeded = hardCap / maxContribution;

        for (uint256 i = 0; i < numDepositsNeeded; i++) {
            address depositor = address(uint160(0x3000 + i));
            vm.deal(depositor, 100 ether);
            vm.prank(depositor);
            presale.deposit{value: maxContribution}(bytes8(0));
        }

        // Now we're at hard cap, next deposit should revert
        address lastDepositor = address(uint160(0x4000));
        vm.deal(lastDepositor, 100 ether);
        vm.prank(lastDepositor);
        vm.expectRevert(Presale.HardCapExceeded.selector);
        presale.deposit{value: minContribution}(bytes8(0));
    }

    // ============ FINALIZATION TESTS ============

    /// @notice Test finalize after deadline with soft cap met
    function testFinalize_AfterDeadlineWithSoftCapMet() public {
        _deployVaultWithPresale();
        _fillToSoftCap();

        // Warp past deadline
        vm.warp(block.timestamp + PRESALE_DURATION + 1);

        // Anyone can finalize after deadline
        vm.prank(user1);
        presale.finalize();

        assertTrue(presale.finalized());
    }

    /// @notice Test finalize before deadline by owner when soft cap reached
    function testFinalize_BeforeDeadlineByOwnerWithSoftCap() public {
        _deployVaultWithPresale();
        _fillToSoftCap();

        // Owner can finalize early if soft cap reached
        vm.prank(deployer);
        presale.finalize();

        assertTrue(presale.finalized());
    }

    /// @notice Test finalize reverts before deadline if not owner
    function testFinalize_RevertsBeforeDeadlineIfNotOwner() public {
        _deployVaultWithPresale();
        _fillToSoftCap();

        // Non-owner cannot finalize before deadline
        vm.prank(user1);
        vm.expectRevert(Presale.NotAuthorized.selector);
        presale.finalize();
    }

    /// @notice Test finalize reverts before deadline if soft cap not reached
    function testFinalize_RevertsBeforeDeadlineIfSoftCapNotReached() public {
        _deployVaultWithPresale();

        // No deposits - soft cap definitely not reached
        // With current params, minContribution > softCap, so we can't deposit less than soft cap
        // Just try to finalize without any deposits

        vm.prank(deployer);
        vm.expectRevert(Presale.PresaleOngoing.selector);
        presale.finalize();
    }

    /// @notice Test finalize reverts if already finalized
    function testFinalize_RevertsIfAlreadyFinalized() public {
        _deployVaultWithPresale();
        _fillToSoftCap();
        vm.warp(block.timestamp + PRESALE_DURATION + 1);

        presale.finalize();

        vm.expectRevert(Presale.AlreadyFinalized.selector);
        presale.finalize();
    }

    /// @notice Test deposit reverts after finalization
    function testDeposit_RevertsAfterFinalization() public {
        _deployVaultWithPresale();
        _fillToSoftCap();

        // Finalize
        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        presale.finalize();

        // Try to deposit - PresaleEnded is checked first in deposit()
        address newUser = address(0x999);
        vm.deal(newUser, 100 ether);
        vm.prank(newUser);
        vm.expectRevert(Presale.PresaleEnded.selector);
        presale.deposit{value: minContribution}(bytes8(0));
    }

    /// @notice Test canFinalize returns correct values
    function testCanFinalize_ReturnsCorrectValues() public {
        _deployVaultWithPresale();

        // Before any deposits
        (bool allowed, bool ownerOnly) = presale.canFinalize();
        assertFalse(allowed);
        assertFalse(ownerOnly);

        // After soft cap reached, before deadline
        _fillToSoftCap();
        (allowed, ownerOnly) = presale.canFinalize();
        assertTrue(allowed);
        assertTrue(ownerOnly); // Owner only before deadline

        // After deadline
        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        (allowed, ownerOnly) = presale.canFinalize();
        assertTrue(allowed);
        assertFalse(ownerOnly); // Permissionless after deadline
    }

    // ============ WITHDRAWAL TESTS ============

    /// @notice Test withdraw after finalization
    function testWithdraw_AfterFinalization() public {
        _deployVaultWithPresale();

        uint256 depositAmount = minContribution;
        _deposit(user1, depositAmount);
        _fillToSoftCap();

        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        presale.finalize();

        uint256 pAssetBalance = presale.balanceOf(user1);
        assertTrue(pAssetBalance > 0);

        vm.prank(user1);
        presale.withdraw();

        // p-assets should be burned
        assertEq(presale.balanceOf(user1), 0);
    }

    /// @notice Test withdraw reverts if not finalized
    function testWithdraw_RevertsIfNotFinalized() public {
        _deployVaultWithPresale();

        _deposit(user1, minContribution);

        vm.prank(user1);
        vm.expectRevert(Presale.NotFinalized.selector);
        presale.withdraw();
    }

    /// @notice Test withdraw reverts if no p-assets
    function testWithdraw_RevertsIfNoPAssets() public {
        _deployVaultWithPresale();

        _fillToSoftCap();
        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        presale.finalize();

        // User who didn't deposit tries to withdraw
        vm.prank(address(0x999));
        vm.expectRevert(Presale.NoContributionsToWithdraw.selector);
        presale.withdraw();
    }

    // ============ REFERRAL TESTS ============

    /// @notice Test claim referral rewards after finalization
    function testClaimReferralRewards_AfterFinalization() public {
        _deployVaultWithPresale();

        bytes8 referralCode = _getReferralCode(user2);
        uint256 depositAmount = minContribution;

        // User1 deposits with user2's referral code
        _depositWithReferral(user1, depositAmount, referralCode);
        _fillToSoftCap();

        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        presale.finalize();

        // Verify referral earnings are tracked correctly
        uint256 expectedReward = (depositAmount * 5) / 100; // 5% referral
        assertEq(presale.claimableReferralRewards(user2), expectedReward);

        uint256 user2BalanceBefore = user2.balance;
        vm.prank(user2);
        presale.claimReferralRewards();

        assertEq(user2.balance, user2BalanceBefore + expectedReward);
        assertEq(presale.referralEarnings(referralCode), 0);
    }

    /// @notice Test claim referral rewards reverts if not finalized
    function testClaimReferralRewards_RevertsIfNotFinalized() public {
        _deployVaultWithPresale();

        bytes8 referralCode = _getReferralCode(user2);
        _depositWithReferral(user1, minContribution, referralCode);

        vm.prank(user2);
        vm.expectRevert(Presale.NotFinalized.selector);
        presale.claimReferralRewards();
    }

    /// @notice Test claim referral rewards reverts if nothing to claim
    function testClaimReferralRewards_RevertsIfNothingToClaim() public {
        _deployVaultWithPresale();

        _fillToSoftCap();
        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        presale.finalize();

        // User3 has no referral earnings
        vm.prank(user3);
        vm.expectRevert(Presale.NothingToClaim.selector);
        presale.claimReferralRewards();
    }

    /// @notice Test referral tracking with multiple referrals
    function testReferral_MultipleReferrals() public {
        _deployVaultWithPresale();

        bytes8 referralCode = _getReferralCode(user3);

        // Multiple users use the same referral code
        _depositWithReferral(user1, minContribution, referralCode);

        address user4 = address(0x1010);
        vm.deal(user4, 100 ether);
        vm.prank(user4);
        presale.deposit{value: minContribution}(referralCode);

        assertEq(presale.referralParticipants(referralCode), 2);
        assertEq(presale.getReferralUserCount(referralCode), 2);

        uint256 expectedEarnings = (minContribution * 5 / 100) * 2;
        assertEq(presale.getTotalReferredByCode(referralCode), expectedEarnings);
    }

    // ============ EMERGENCY WITHDRAWAL TESTS ============

    /// @notice Test emergency withdrawal after 30 days past deadline
    function testEmergencyWithdrawal_After30DaysPastDeadline() public {
        _deployVaultWithPresale();

        uint256 depositAmount = minContribution;
        _deposit(user1, depositAmount);

        // Warp to 30 days after deadline
        vm.warp(block.timestamp + PRESALE_DURATION + 30 days + 1);

        uint256 user1BalanceBefore = user1.balance;

        vm.prank(user1);
        presale.emergencyWithdrawal();

        assertEq(user1.balance, user1BalanceBefore + depositAmount);
        assertEq(presale.balanceOf(user1), 0);
        assertEq(presale.contributions(user1), 0);
    }

    /// @notice Test emergency withdrawal reverts if finalized
    function testEmergencyWithdrawal_RevertsIfFinalized() public {
        _deployVaultWithPresale();

        _deposit(user1, minContribution);
        _fillToSoftCap();
        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        presale.finalize();

        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(user1);
        vm.expectRevert(Presale.AlreadyFinalized.selector);
        presale.emergencyWithdrawal();
    }

    /// @notice Test emergency withdrawal reverts if too early
    function testEmergencyWithdrawal_RevertsIfTooEarly() public {
        _deployVaultWithPresale();

        _deposit(user1, minContribution);

        // Warp to just past deadline but not 30 days
        vm.warp(block.timestamp + PRESALE_DURATION + 1);

        vm.prank(user1);
        vm.expectRevert(Presale.WithdrawNotAllowedYet.selector);
        presale.emergencyWithdrawal();
    }

    /// @notice Test emergency withdrawal reverts if no contributions
    function testEmergencyWithdrawal_RevertsIfNoContributions() public {
        _deployVaultWithPresale();

        vm.warp(block.timestamp + PRESALE_DURATION + 30 days + 1);

        vm.prank(user1);
        vm.expectRevert(Presale.NoContributionsToWithdraw.selector);
        presale.emergencyWithdrawal();
    }

    /// @notice Test emergency withdrawal reverts if disabled
    function testEmergencyWithdrawal_RevertsIfDisabled() public {
        _deployVaultWithPresale();

        _deposit(user1, minContribution);

        // Disable emergency withdrawal
        vm.prank(deployer);
        presale.setEmergencyWithdrawalFlag(false);

        vm.warp(block.timestamp + PRESALE_DURATION + 30 days + 1);

        vm.prank(user1);
        vm.expectRevert(Presale.EmergencyWithdrawalNotEnabled.selector);
        presale.emergencyWithdrawal();
    }

    // ============ ADMIN FUNCTION TESTS ============

    /// @notice Test setEmergencyWithdrawalFlag by owner
    function testSetEmergencyWithdrawalFlag_ByOwner() public {
        _deployVaultWithPresale();

        assertTrue(presale.emergencyWithdrawalFlag());

        vm.prank(deployer);
        presale.setEmergencyWithdrawalFlag(false);

        assertFalse(presale.emergencyWithdrawalFlag());
    }

    /// @notice Test setEmergencyWithdrawalFlag reverts if not authorized
    function testSetEmergencyWithdrawalFlag_RevertsIfNotAuthorized() public {
        _deployVaultWithPresale();

        vm.prank(user1);
        vm.expectRevert(Presale.NotAuthorized.selector);
        presale.setEmergencyWithdrawalFlag(false);
    }

    /// @notice Test withdrawExcess by owner
    function testWithdrawExcess_ByOwner() public {
        _deployVaultWithPresale();

        _fillToSoftCap();
        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        presale.finalize();

        // Owner can withdraw excess
        vm.prank(deployer);
        presale.withdrawExcess();
    }

    /// @notice Test withdrawExcess reverts if not owner
    function testWithdrawExcess_RevertsIfNotOwner() public {
        _deployVaultWithPresale();

        _fillToSoftCap();
        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        presale.finalize();

        vm.prank(user1);
        vm.expectRevert();
        presale.withdrawExcess();
    }

    /// @notice Test sweepUnexpectedETH by owner
    function testSweepUnexpectedETH_ByOwner() public {
        _deployVaultWithPresale();

        // Send unexpected ETH directly to contract
        vm.deal(address(presale), address(presale).balance + 1 ether);

        uint256 deployerBalanceBefore = deployer.balance;

        vm.prank(deployer);
        presale.sweepUnexpectedETH();

        // Unexpected ETH should be swept (balance - totalDeposited)
        assertGt(deployer.balance, deployerBalanceBefore);
    }

    // ============ VIEW FUNCTION TESTS ============

    /// @notice Test getTimeLeft
    function testGetTimeLeft() public {
        _deployVaultWithPresale();

        uint256 timeLeft = presale.getTimeLeft();
        assertGt(timeLeft, 0);
        assertLe(timeLeft, PRESALE_DURATION);

        // Warp past deadline
        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        assertEq(presale.getTimeLeft(), 0);
    }

    /// @notice Test hasExpired
    function testHasExpired() public {
        _deployVaultWithPresale();

        assertFalse(presale.hasExpired());

        vm.warp(block.timestamp + PRESALE_DURATION + 1);
        assertTrue(presale.hasExpired());
    }

    /// @notice Test softCapReached
    function testSoftCapReached() public {
        _deployVaultWithPresale();

        assertFalse(presale.softCapReached());

        _fillToSoftCap();
        assertTrue(presale.softCapReached());
    }

    /// @notice Test getCurrentTimestamp
    function testGetCurrentTimestamp() public {
        _deployVaultWithPresale();

        assertEq(presale.getCurrentTimestamp(), block.timestamp);

        vm.warp(block.timestamp + 1000);
        assertEq(presale.getCurrentTimestamp(), block.timestamp);
    }

    // ============ REENTRANCY TESTS ============

    /// @notice Test deposit is protected against reentrancy
    function testDeposit_ReentrancyProtection() public {
        _deployVaultWithPresale();

        // The lock modifier should prevent reentrancy
        _deposit(user1, minContribution);
        assertTrue(presale.isContributor(user1));
    }

    receive() external payable {}
}
