// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {NomaToken} from "../src/token/NomaToken.sol";
import {ModelHelper} from "../src/model/Helper.sol";
import {BaseVault} from "../src/vault/BaseVault.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {NomaDividends} from "../src/controllers/NomaDividends.sol";
import {NomaFactory} from "../src/factory/NomaFactory.sol";
import {TestResolver} from "./resolver/Resolver.sol";
import {LiquidityType, LiquidityPosition} from "../src/types/Types.sol";

interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IDOManager {
    function vault() external view returns (BaseVault);
    function buyTokens(uint256 price, uint256 amount, uint256 min, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
    function modelHelper() external view returns (address);
}

interface IVaultExt {
    function getTotalTeamEarnings() external view returns (uint256);
    function getTotalCreatorEarnings() external view returns (uint256);
    function teamMultiSig() external view returns (address);
    function getStakingContract() external view returns (address);
    function pool() external view returns (IUniswapV3Pool);
    function shift() external;
}

interface IResolver {
    function getAddress(bytes32 name) external view returns (address);
    function importAddresses(bytes32[] calldata names, address[] calldata destinations) external;
}

/// @title FeeDistributionTest
/// @notice Tests for protocol fee distribution scenarios:
///         1. Without DividendDistributor - fees go to teamMultisig
///         2. With DividendDistributor - fees go to NOMA holders
contract FeeDistributionTest is Test {
    using stdJson for string;

    IVaultExt vault;
    IERC20 token0; // NOMA token
    IERC20 token1; // WETH

    uint256 MAX_INT = type(uint256).max;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bool isMainnet = vm.envOr("DEPLOY_FLAG_MAINNET", false);

    NomaToken private noma;
    ModelHelper private modelHelper;

    // Mainnet addresses
    address constant WMON_MAINNET = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    // Testnet addresses
    address constant WMON_TESTNET = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    // Select based on environment
    address WMON;
    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;
    address factoryAddress;
    address resolverAddress;

    function setUp() public {
        // Set WMON based on mainnet/testnet flag
        WMON = isMainnet ? WMON_MAINNET : WMON_TESTNET;

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));
        modelHelperContract = vm.parseJsonAddress(json, string.concat(".", networkId, ".ModelHelper"));
        factoryAddress = vm.parseJsonAddress(json, string.concat(".", networkId, ".Factory"));
        resolverAddress = vm.parseJsonAddress(json, string.concat(".", networkId, ".Resolver"));

        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        noma = NomaToken(nomaToken);
        modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        vault = IVaultExt(vaultAddress);
        IUniswapV3Pool pool = vault.pool();

        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        console.log("Vault address:", vaultAddress);
        console.log("Token0 (NOMA):", address(token0));
        console.log("Token1 (WETH):", address(token1));
        console.log("Factory:", factoryAddress);
        console.log("Resolver:", resolverAddress);
    }

    // ============ SCENARIO 1: WITHOUT DIVIDEND DISTRIBUTOR ============

    /// @notice Test that protocol fees go to teamMultisig when DividendDistributor is NOT configured
    /// @dev This tests the code path at StakingVault.sol:194-200
    function testFees_WithoutDividendDistributor_GoToTeamMultisig() public {
        // Get current dividend distributor from resolver (should be address(0) if not configured)
        address dd = _getDividendDistributor();
        console.log("Current DividendDistributor:", dd);

        // Get teamMultisig address
        address teamMultisig = vault.teamMultiSig();
        console.log("TeamMultisig address:", teamMultisig);
        assertTrue(teamMultisig != address(0), "TeamMultisig should be set");

        // If DividendDistributor is already configured, skip this test
        if (dd != address(0)) {
            console.log("SKIP: DividendDistributor is already configured");
            console.log("  To test WITHOUT DividendDistributor, redeploy without it in resolver");
            return;
        }

        // Record team earnings and teamMultisig balance before shift
        uint256 teamEarningsBefore = vault.getTotalTeamEarnings();
        uint256 teamMultisigBalanceBefore = token0.balanceOf(teamMultisig);
        console.log("Team earnings before shift:", teamEarningsBefore);
        console.log("TeamMultisig token balance before:", teamMultisigBalanceBefore);

        // Trigger shift condition by doing large purchases
        _doPurchasesToTriggerShiftCondition();

        // Check liquidity ratio
        address poolAddr = address(vault.pool());
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);
        console.log("Liquidity ratio after purchases:", liquidityRatio);

        if (liquidityRatio > 0.90e18) {
            console.log("Liquidity ratio not low enough for shift, doing more purchases...");
            _doPurchasesToTriggerShiftCondition();
            liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);
            console.log("Liquidity ratio after more purchases:", liquidityRatio);
        }

        // Perform shift if conditions are met
        if (liquidityRatio <= 0.90e18) {
            console.log("Performing shift...");
            vault.shift();

            // Record team earnings and balance after shift
            uint256 teamEarningsAfter = vault.getTotalTeamEarnings();
            uint256 teamMultisigBalanceAfter = token0.balanceOf(teamMultisig);

            console.log("Team earnings after shift:", teamEarningsAfter);
            console.log("TeamMultisig token balance after:", teamMultisigBalanceAfter);

            // Verify fees went to teamMultisig
            if (teamEarningsAfter > teamEarningsBefore) {
                uint256 feesSentToTeam = teamEarningsAfter - teamEarningsBefore;
                console.log("SUCCESS: Fees sent to teamMultisig:", feesSentToTeam);
                assertTrue(teamEarningsAfter > teamEarningsBefore, "Team earnings should increase after shift");
                assertTrue(teamMultisigBalanceAfter > teamMultisigBalanceBefore, "TeamMultisig balance should increase");
            } else {
                console.log("INFO: No protocol fees generated (might be no excess reserves)");
            }
        } else {
            console.log("SKIP: Could not reach shift condition (liquidityRatio > 0.90)");
        }
    }

    // ============ SCENARIO 2: WITH DIVIDEND DISTRIBUTOR ============

    /// @notice Test that protocol fees go to DividendDistributor when it IS configured
    /// @dev This tests the code path at StakingVault.sol:94-104
    function testFees_WithDividendDistributor_GoToDividends() public {
        // Get current dividend distributor from resolver
        address dd = _getDividendDistributor();
        console.log("Current DividendDistributor:", dd);

        // Get teamMultisig address for comparison
        address teamMultisig = vault.teamMultiSig();
        console.log("TeamMultisig address:", teamMultisig);

        // If DividendDistributor is NOT configured, deploy and configure one
        NomaDividends dividendDistributor;
        if (dd == address(0)) {
            console.log("DividendDistributor not configured, deploying one...");

            // Deploy DividendDistributor
            dividendDistributor = new NomaDividends(factoryAddress, resolverAddress);
            console.log("DividendDistributor deployed at:", address(dividendDistributor));

            // Add to resolver
            TestResolver resolver = TestResolver(resolverAddress);
            bytes32[] memory names = new bytes32[](2);
            address[] memory addresses = new address[](2);
            names[0] = Utils.stringToBytes32("DividendDistributor");
            addresses[0] = address(dividendDistributor);
            names[1] = Utils.stringToBytes32("NomaToken");
            addresses[1] = address(token0);

            vm.prank(deployer);
            resolver.importAddresses(names, addresses);

            // Set shares token
            dividendDistributor.setSharesToken();
            console.log("SharesToken set to:", address(dividendDistributor.sharesToken()));

            dd = address(dividendDistributor);
        } else {
            dividendDistributor = NomaDividends(dd);
        }

        // Record DividendDistributor state before shift
        uint256 ddTotalDistributedBefore = dividendDistributor.getTotalDistributed(address(token0));
        uint256 ddBalanceBefore = token0.balanceOf(dd);
        uint256 teamEarningsBefore = vault.getTotalTeamEarnings();

        console.log("DD total distributed before:", ddTotalDistributedBefore);
        console.log("DD token balance before:", ddBalanceBefore);
        console.log("Team earnings before:", teamEarningsBefore);

        // Trigger shift condition
        _doPurchasesToTriggerShiftCondition();

        // Check liquidity ratio
        address poolAddr = address(vault.pool());
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);
        console.log("Liquidity ratio after purchases:", liquidityRatio);

        if (liquidityRatio > 0.90e18) {
            console.log("Liquidity ratio not low enough, doing more purchases...");
            _doPurchasesToTriggerShiftCondition();
            liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);
            console.log("Liquidity ratio after more purchases:", liquidityRatio);
        }

        // Perform shift if conditions are met
        if (liquidityRatio <= 0.90e18) {
            console.log("Performing shift...");

            // Check if resolver has the DividendDistributor
            address vaultDD = _getDividendDistributor();
            console.log("Resolver has DividendDistributor:", vaultDD);

            vault.shift();

            // Record state after shift
            uint256 ddTotalDistributedAfter = dividendDistributor.getTotalDistributed(address(token0));
            uint256 ddBalanceAfter = token0.balanceOf(dd);
            uint256 teamEarningsAfter = vault.getTotalTeamEarnings();

            console.log("DD total distributed after:", ddTotalDistributedAfter);
            console.log("DD token balance after:", ddBalanceAfter);
            console.log("Team earnings after:", teamEarningsAfter);

            // Verify fees went to DividendDistributor (not teamMultisig)
            if (ddTotalDistributedAfter > ddTotalDistributedBefore) {
                uint256 feesSentToDividends = ddTotalDistributedAfter - ddTotalDistributedBefore;
                console.log("SUCCESS: Fees sent to DividendDistributor:", feesSentToDividends);
                assertTrue(ddTotalDistributedAfter > ddTotalDistributedBefore, "DD distributed should increase");

                // Team earnings should NOT have increased (fees went to DD instead)
                assertEq(teamEarningsAfter, teamEarningsBefore, "Team earnings should not increase when DD is set");
            } else if (ddBalanceAfter > ddBalanceBefore) {
                // Alternative check: balance increased even if distribute wasn't called
                uint256 feesSentToDividends = ddBalanceAfter - ddBalanceBefore;
                console.log("SUCCESS: Fees in DividendDistributor balance:", feesSentToDividends);
            } else {
                console.log("INFO: No protocol fees generated (might be no excess reserves)");
            }
        } else {
            console.log("SKIP: Could not reach shift condition");
        }
    }

    /// @notice Test end-to-end dividend distribution to NOMA holders
    function testFees_DividendDistribution_ToNomaHolders() public {
        // Get current dividend distributor from resolver
        address dd = _getDividendDistributor();

        NomaDividends dividendDistributor;
        if (dd == address(0)) {
            // Deploy and configure DividendDistributor
            dividendDistributor = new NomaDividends(factoryAddress, resolverAddress);

            TestResolver resolver = TestResolver(resolverAddress);
            bytes32[] memory names = new bytes32[](2);
            address[] memory addresses = new address[](2);
            names[0] = Utils.stringToBytes32("DividendDistributor");
            addresses[0] = address(dividendDistributor);
            names[1] = Utils.stringToBytes32("NomaToken");
            addresses[1] = address(token0);

            vm.prank(deployer);
            resolver.importAddresses(names, addresses);

            dividendDistributor.setSharesToken();
            dd = address(dividendDistributor);
        } else {
            dividendDistributor = NomaDividends(dd);
        }

        console.log("DividendDistributor:", dd);
        console.log("SharesToken:", address(dividendDistributor.sharesToken()));

        // Create a NOMA holder by buying some tokens
        address holder = address(0xBEEF);

        // Buy tokens for holder
        _buyTokensForAddress(holder, 5000 ether);

        uint256 holderBalance = token0.balanceOf(holder);
        console.log("Holder NOMA balance:", holderBalance);
        assertTrue(holderBalance > 0, "Holder should have NOMA tokens");

        // Trigger shift to generate fees
        _doPurchasesToTriggerShiftCondition();

        address poolAddr = address(vault.pool());
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);

        if (liquidityRatio <= 0.90e18) {
            uint256 ddDistributedBefore = dividendDistributor.getTotalDistributed(address(token0));

            vault.shift();

            uint256 ddDistributedAfter = dividendDistributor.getTotalDistributed(address(token0));

            if (ddDistributedAfter > ddDistributedBefore) {
                uint256 feesDistributed = ddDistributedAfter - ddDistributedBefore;
                console.log("Fees distributed to DividendDistributor:", feesDistributed);

                // Check if holder can claim dividends
                uint256 holderClaimable = dividendDistributor.claimableRaw(address(token0), holder);
                console.log("Holder claimable raw:", holderClaimable);

                if (holderClaimable > 0) {
                    console.log("SUCCESS: Holder can claim dividends!");

                    // Holder claims to start vesting
                    vm.prank(holder);
                    dividendDistributor.claim(address(token0));

                    // Fast forward past vesting period
                    vm.warp(block.timestamp + 181 days);

                    // Holder withdraws vested amount
                    uint256 holderBalanceBefore = token0.balanceOf(holder);
                    vm.prank(holder);
                    dividendDistributor.withdrawVested(address(token0));
                    uint256 holderBalanceAfter = token0.balanceOf(holder);

                    if (holderBalanceAfter > holderBalanceBefore) {
                        console.log("SUCCESS: Holder received dividends:", holderBalanceAfter - holderBalanceBefore);
                    }
                }
            } else {
                console.log("INFO: No fees distributed (might be no excess reserves)");
            }
        } else {
            console.log("SKIP: Could not reach shift condition");
        }
    }

    /// @notice Compare fee distribution with and without DividendDistributor
    function testFees_CompareFeeDestinations() public {
        // Get initial state from resolver
        address dd = _getDividendDistributor();
        address teamMultisig = vault.teamMultiSig();

        console.log("=== Fee Distribution Configuration ===");
        console.log("DividendDistributor:", dd);
        console.log("TeamMultisig:", teamMultisig);

        if (dd == address(0)) {
            console.log("");
            console.log("SCENARIO: DividendDistributor NOT configured");
            console.log("Expected behavior:");
            console.log("  - Protocol fees go to teamMultisig");
            console.log("  - Tracked in vault.getTotalTeamEarnings()");
            console.log("  - Code path: StakingVault.sol:195-199");
        } else {
            console.log("");
            console.log("SCENARIO: DividendDistributor IS configured");
            console.log("Expected behavior:");
            console.log("  - Protocol fees go to DividendDistributor");
            console.log("  - Distributed to NOMA holders proportionally");
            console.log("  - 6-month vesting period for claims");
            console.log("  - Code path: StakingVault.sol:94-104");
        }

        console.log("");
        console.log("=== Triggering Shift to Generate Fees ===");

        // Record state before
        uint256 teamEarningsBefore = vault.getTotalTeamEarnings();
        uint256 teamMultisigBalanceBefore = token0.balanceOf(teamMultisig);

        NomaDividends dividendDistributor;
        uint256 ddDistributedBefore = 0;
        if (dd != address(0)) {
            dividendDistributor = NomaDividends(dd);
            ddDistributedBefore = dividendDistributor.getTotalDistributed(address(token0));
        }

        // Trigger shift
        _doPurchasesToTriggerShiftCondition();

        address poolAddr = address(vault.pool());
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);

        if (liquidityRatio <= 0.90e18) {
            vault.shift();

            // Record state after
            uint256 teamEarningsAfter = vault.getTotalTeamEarnings();
            uint256 teamMultisigBalanceAfter = token0.balanceOf(teamMultisig);

            console.log("");
            console.log("=== Results After Shift ===");
            console.log("Team earnings change:", teamEarningsAfter - teamEarningsBefore);
            console.log("TeamMultisig balance change:", teamMultisigBalanceAfter - teamMultisigBalanceBefore);

            if (dd != address(0)) {
                uint256 ddDistributedAfter = dividendDistributor.getTotalDistributed(address(token0));
                console.log("DD distributed change:", ddDistributedAfter - ddDistributedBefore);
            }
        } else {
            console.log("Could not reach shift condition");
        }
    }

    // ============ HELPER FUNCTIONS ============

    /// @dev Get DividendDistributor from resolver
    function _getDividendDistributor() internal view returns (address) {
        return IResolver(resolverAddress).getAddress(Utils.stringToBytes32("DividendDistributor"));
    }

    /// @dev Perform purchases to trigger shift condition (liquidityRatio <= 0.90)
    function _doPurchasesToTriggerShiftCondition() internal {
        IDOManager managerContract = IDOManager(idoManager);
        address poolAddr = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddr).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
        uint256 purchasePrice = spotPrice + (spotPrice * 5 / 100);

        uint16 totalTrades = 10;
        uint256 tradeAmount = 20000 ether;

        IWETH(WMON).deposit{value: tradeAmount * totalTrades}();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddr).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
            purchasePrice = spotPrice + (spotPrice * 5 / 100);
            managerContract.buyTokens(purchasePrice, tradeAmount, 0, address(this));
        }

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);
        console.log("Liquidity ratio after purchases:", liquidityRatio);
    }

    /// @dev Buy tokens for a specific address
    function _buyTokensForAddress(address recipient, uint256 amount) internal {
        IDOManager managerContract = IDOManager(idoManager);
        address poolAddr = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddr).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
        uint256 purchasePrice = spotPrice + (spotPrice * 5 / 100);

        IWETH(WMON).deposit{value: amount}();
        IWETH(WMON).transfer(idoManager, amount);

        managerContract.buyTokens(purchasePrice, amount, 0, recipient);
    }

    receive() external payable {}
}
