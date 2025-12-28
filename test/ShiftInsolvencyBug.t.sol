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
import {Conversions} from "../src/libraries/Conversions.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {Underlying} from "../src/libraries/Underlying.sol";
import {LiquidityType, LiquidityPosition, ProtocolAddresses} from "../src/types/Types.sol";

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

/// @title ShiftInsolvencyBugTest
/// @notice Tests that demonstrate the insolvency invariant bug after large purchase + shift
contract ShiftInsolvencyBugTest is Test {
    using stdJson for string;

    IVault vault;
    IERC20 token0;
    IERC20 token1;
    NomaToken noma;
    ModelHelper modelHelper;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bool isMainnet = vm.envOr("DEPLOY_FLAG_MAINNET", false);

    address constant WMON_MAINNET = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant WMON_TESTNET = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address WMON;
    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;
    address pool;

    IDOManager managerContract;

    function setUp() public {
        WMON = isMainnet ? WMON_MAINNET : WMON_TESTNET;

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));
        modelHelperContract = vm.parseJsonAddress(json, string.concat(".", networkId, ".ModelHelper"));

        managerContract = IDOManager(idoManager);
        noma = NomaToken(nomaToken);
        vaultAddress = address(managerContract.vault());

        ProtocolAddresses memory protocolAddrs = IVault(vaultAddress).getProtocolAddresses();
        modelHelper = ModelHelper(protocolAddrs.modelHelper);

        vault = IVault(vaultAddress);
        IUniswapV3Pool poolContract = vault.pool();
        pool = address(poolContract);

        token0 = IERC20(poolContract.token0());
        token1 = IERC20(poolContract.token1());
    }

    function getCurrentPrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        if (sqrtPriceX96 >= 1461446703485210103287273052203988822378723970341) {
            return type(uint256).max;
        }
        return Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
    }

    function getLiquidityRatio() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        if (sqrtPriceX96 >= 1461446703485210103287273052203988822378723970341) {
            return 0;
        }
        return modelHelper.getLiquidityRatio(pool, vaultAddress);
    }

    function getCirculatingSupply() internal view returns (uint256) {
        return modelHelper.getCirculatingSupply(pool, vaultAddress, true);
    }

    function buyTokens(uint256 amount) internal returns (uint256 tokensBought) {
        uint256 balanceBefore = noma.balanceOf(address(this));

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);

        IWETH(WMON).deposit{value: amount}();
        IWETH(WMON).transfer(idoManager, amount);

        managerContract.buyTokens(purchasePrice, amount, 0, address(this));

        tokensBought = noma.balanceOf(address(this)) - balanceBefore;
    }

    function checkSolvencyInvariant() internal view returns (bool isSolvent, uint256 anchorCapacity, uint256 floorCapacity, uint256 circulatingSupply) {
        LiquidityPosition[3] memory positions = vault.getPositions();

        circulatingSupply = modelHelper.getCirculatingSupply(pool, vaultAddress, true);
        anchorCapacity = modelHelper.getPositionCapacity(pool, vaultAddress, positions[1], LiquidityType.Anchor);

        uint256 intrinsicMinimumValue = modelHelper.getIntrinsicMinimumValue(vaultAddress);
        (,,, uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, vaultAddress, positions[0]);

        floorCapacity = DecimalMath.divideDecimal(floorBalance, intrinsicMinimumValue);

        isSolvent = (anchorCapacity + floorCapacity) > circulatingSupply;
    }

    function logState(string memory label) internal view {
        console.log("===", label, "===");

        uint256 totalSupply = noma.totalSupply();
        uint256 circSupply = getCirculatingSupply();
        uint256 ratio = getLiquidityRatio();
        uint256 price = getCurrentPrice();

        console.log("  Total Supply:      ", totalSupply);
        console.log("  Circulating Supply:", circSupply);
        console.log("  Liquidity Ratio:   ", ratio);
        console.log("  Spot Price:        ", price);
        console.log("  User NOMA balance: ", noma.balanceOf(address(this)));

        (bool isSolvent, uint256 anchorCap, uint256 floorCap, uint256 circForCheck) = checkSolvencyInvariant();
        console.log("  --- Solvency Check ---");
        console.log("  Anchor Capacity:   ", anchorCap);
        console.log("  Floor Capacity:    ", floorCap);
        console.log("  Total Capacity:    ", anchorCap + floorCap);
        console.log("  Circulating Supply:", circForCheck);
        console.log("  Is Solvent:        ", isSolvent);

        if (!isSolvent) {
            console.log("  *** INSOLVENCY DETECTED! ***");
            console.log("  Shortfall:", circForCheck - (anchorCap + floorCap));
        }
    }

    /// @notice Test that demonstrates the insolvency bug after large purchase + shift
    function testInsolvencyAfterLargePurchaseAndShift() public {
        console.log("\n=== Test: Insolvency After Large Purchase and Shift ===\n");

        logState("Initial State");

        // Check initial solvency
        (bool initialSolvent,,,) = checkSolvencyInvariant();
        assertTrue(initialSolvent, "Should be solvent initially");

        // Step 1: Make a large purchase (100M MON)
        console.log("\n>>> Step 1: Large purchase of 100M MON");
        uint256 purchaseAmount = 100_000_000 ether; // 100M MON

        uint256 tokensBought = buyTokens(purchaseAmount);
        console.log("Tokens bought:", tokensBought);

        logState("After Large Purchase");

        // Step 2: Check liquidity ratio and trigger shift if below threshold
        uint256 ratioAfterBuy = getLiquidityRatio();
        console.log("\n>>> Step 2: Check if shift is needed");
        console.log("Liquidity ratio:", ratioAfterBuy);

        if (ratioAfterBuy <= 0.90e18) {
            console.log("Shift condition met (ratio <= 0.90), triggering shift...");

            // Log state before shift
            uint256 totalSupplyBefore = noma.totalSupply();
            uint256 circSupplyBefore = getCirculatingSupply();

            console.log("\n  Before Shift:");
            console.log("    Total Supply:       ", totalSupplyBefore);
            console.log("    Circulating Supply: ", circSupplyBefore);

            // Trigger shift
            vault.shift();

            // Log state after shift
            uint256 totalSupplyAfter = noma.totalSupply();
            uint256 circSupplyAfter = getCirculatingSupply();

            console.log("\n  After Shift:");
            console.log("    Total Supply:       ", totalSupplyAfter);
            console.log("    Circulating Supply: ", circSupplyAfter);
            console.log("    Tokens Minted:      ", totalSupplyAfter - totalSupplyBefore);
            console.log("    Circulating Change: ", circSupplyAfter > circSupplyBefore ? circSupplyAfter - circSupplyBefore : 0);

            logState("After Shift");

            // Check solvency after shift
            (bool solventAfterShift, uint256 anchorCap, uint256 floorCap, uint256 circSupply) = checkSolvencyInvariant();

            console.log("\n>>> SOLVENCY CHECK RESULT:");
            if (!solventAfterShift) {
                console.log("*** BUG CONFIRMED: INSOLVENCY AFTER SHIFT! ***");
                console.log("  Anchor Capacity + Floor Capacity:", anchorCap + floorCap);
                console.log("  Circulating Supply:", circSupply);
                console.log("  Shortfall:", circSupply - (anchorCap + floorCap));

                // Calculate the ratio of circulating supply to capacity
                uint256 totalCapacity = anchorCap + floorCap;
                if (totalCapacity > 0) {
                    uint256 insolvencyRatio = (circSupply * 1e18) / totalCapacity;
                    console.log("  Insolvency Ratio (circ/cap):", insolvencyRatio);
                }
            } else {
                console.log("System remains solvent after shift");
            }

            // This assertion should fail if the bug exists
            assertTrue(solventAfterShift, "Should remain solvent after shift");

        } else {
            console.log("Shift condition not met. Test may need larger purchase.");
            console.log("Try increasing purchase amount or running multiple purchases.");
        }
    }

    /// @notice Test to analyze the mint amount calculation discrepancy
    function testMintAmountDiscrepancy() public {
        console.log("\n=== Test: Mint Amount Calculation Analysis ===\n");

        logState("Initial State");

        uint256 totalSupply = noma.totalSupply();
        uint256 circSupply = getCirculatingSupply();

        console.log("\nKey Metrics:");
        console.log("  Total Supply:       ", totalSupply);
        console.log("  Circulating Supply: ", circSupply);
        console.log("  Ratio (total/circ): ", totalSupply > 0 && circSupply > 0 ? totalSupply * 100 / circSupply : 0, "%");

        // The bug: mintAmount is calculated using totalSupply, but thresholds use circulatingSupply
        // If totalSupply >> circulatingSupply, the mint amount will be disproportionately large

        // Simulate what would happen with a 5% lowBalanceThresholdFactor
        uint256 lowBalanceThreshold = (circSupply * 5) / 100;

        console.log("\n  Expected low threshold (5% of circ): ", lowBalanceThreshold);
        console.log("  If mint based on totalSupply...");
        console.log("  Potential mint (5% of total):        ", (totalSupply * 5) / 100);

        // Make purchase to trigger shift
        console.log("\n>>> Making large purchase to analyze mint behavior...");
        uint256 tokensBought = buyTokens(50_000_000 ether);
        console.log("Tokens bought:", tokensBought);

        logState("After Purchase");

        uint256 ratio = getLiquidityRatio();
        if (ratio <= 0.90e18) {
            console.log("\nShift will be triggered. Analyzing...");

            uint256 totalSupplyBefore = noma.totalSupply();
            vault.shift();
            uint256 totalSupplyAfter = noma.totalSupply();

            uint256 actualMint = totalSupplyAfter - totalSupplyBefore;
            console.log("\nActual tokens minted during shift:", actualMint);
            console.log("Expected (based on circulating):  ", lowBalanceThreshold);

            if (lowBalanceThreshold > 0 && actualMint > lowBalanceThreshold * 10) {
                console.log("*** BUG: Minted way more than expected! ***");
                console.log("Mint was", actualMint / lowBalanceThreshold, "x the expected amount");
            } else if (lowBalanceThreshold == 0 && actualMint > 0) {
                console.log("*** BUG: Minted tokens when threshold was 0! ***");
            }
        }
    }

    receive() external payable {}
}
