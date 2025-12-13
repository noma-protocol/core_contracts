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
import {TickMath} from "v3-core/libraries/TickMath.sol";

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

// Note: Foundry JSON parsing decodes struct fields alphabetically
// So we define them in alphabetical order to match JSON keys
struct ContractAddressesJson {
    address ExchangeHelper;
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
    address Resolver;
}

/// @title Adversarial Tests for Noma Protocol
/// @notice Tests extreme market scenarios including price manipulation and recovery
contract AdversarialTests is Test {
    using stdJson for string;

    IVault vault;
    IERC20 token0;
    IERC20 token1;
    NomaToken noma;
    ModelHelper modelHelper;

    uint256 MAX_INT = type(uint256).max;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;
    address pool;

    IDOManager managerContract;

    // Track state for assertions
    uint256 initialPrice;
    uint256 initialLiquidityRatio;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        // Parse individual fields to avoid struct ordering issues
        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));
        modelHelperContract = vm.parseJsonAddress(json, string.concat(".", networkId, ".ModelHelper"));

        managerContract = IDOManager(idoManager);
        noma = NomaToken(nomaToken);
        modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        vault = IVault(vaultAddress);
        IUniswapV3Pool poolContract = vault.pool();
        pool = address(poolContract);

        token0 = IERC20(poolContract.token0());
        token1 = IERC20(poolContract.token1());

        // Record initial state
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        initialPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        initialLiquidityRatio = modelHelper.getLiquidityRatio(pool, vaultAddress);

        console.log("Initial price:", initialPrice);
        console.log("Initial liquidity ratio:", initialLiquidityRatio);
    }

    // ============ HELPER FUNCTIONS ============

    function getCurrentPrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        return Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
    }

    function getCurrentSqrtPrice() internal view returns (uint160) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        return sqrtPriceX96;
    }

    function getLiquidityRatio() internal view returns (uint256) {
        return modelHelper.getLiquidityRatio(pool, vaultAddress);
    }

    function isNearMaxPrice() internal view returns (bool) {
        uint160 sqrtPriceX96 = getCurrentSqrtPrice();
        return Conversions.isNearMaxSqrtPrice(sqrtPriceX96);
    }

    function buyTokens(uint256 amount) internal returns (uint256 tokensBought) {
        uint256 balanceBefore = noma.balanceOf(address(this));

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100); // 25% slippage

        IWETH(WMON).deposit{value: amount}();
        IWETH(WMON).transfer(idoManager, amount);

        managerContract.buyTokens(purchasePrice, amount, 0, address(this));

        tokensBought = noma.balanceOf(address(this)) - balanceBefore;
    }

    function sellTokens(uint256 tokenAmount) internal {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 sellPrice = spotPrice - (spotPrice * 25 / 100); // 25% slippage

        noma.transfer(idoManager, tokenAmount);
        managerContract.sellTokens(sellPrice, tokenAmount, address(this));
    }

    function attemptShift() internal returns (bool shifted) {
        uint256 liquidityRatio = getLiquidityRatio();
        console.log("Liquidity ratio before shift attempt:", liquidityRatio);

        if (liquidityRatio < 0.90e18) {
            console.log("Triggering shift...");
            vault.shift();
            shifted = true;
        } else {
            console.log("Shift condition not met");
            shifted = false;
        }
    }

    function attemptSlide() internal returns (bool slid) {
        uint256 liquidityRatio = getLiquidityRatio();
        console.log("Liquidity ratio before slide attempt:", liquidityRatio);

        if (liquidityRatio > 1.15e18) {
            console.log("Triggering slide...");
            vault.slide();
            slid = true;
        } else {
            console.log("Slide condition not met");
            slid = false;
        }
    }

    // ============ ADVERSARIAL TEST SCENARIOS ============

    /// @notice Test: Normal purchase followed by slide
    /// Buy 3000 MON worth of tokens which should push price up and trigger slide
    function testAdversarial_NormalPurchaseThenSlide() public {
        console.log("\n=== Test: Normal Purchase Then Slide ===");

        uint256 purchaseAmount = 3000 ether; // 3000 MON

        uint256 priceBefore = getCurrentPrice();
        uint256 ratioBefore = getLiquidityRatio();
        console.log("Price before purchase:", priceBefore);
        console.log("Ratio before purchase:", ratioBefore);

        // Buy tokens
        uint256 tokensBought = buyTokens(purchaseAmount);
        console.log("Tokens bought:", tokensBought);

        uint256 priceAfter = getCurrentPrice();
        uint256 ratioAfter = getLiquidityRatio();
        console.log("Price after purchase:", priceAfter);
        console.log("Ratio after purchase:", ratioAfter);

        // Price should have increased after buying
        assertGt(priceAfter, priceBefore, "Price should increase after buying");

        // Try to trigger slide if ratio is high enough
        if (ratioAfter > 1.15e18) {
            vault.slide();
            uint256 ratioAfterSlide = getLiquidityRatio();
            console.log("Ratio after slide:", ratioAfterSlide);

            // Ratio should decrease after slide
            assertLt(ratioAfterSlide, ratioAfter, "Ratio should decrease after slide");
        }
    }

    /// @notice Test: Buy then sell all tokens
    /// This tests the sell pressure scenario
    function testAdversarial_BuyThenSellAll() public {
        console.log("\n=== Test: Buy Then Sell All ===");

        uint256 purchaseAmount = 3000 ether;

        // First buy tokens
        uint256 tokensBought = buyTokens(purchaseAmount);
        console.log("Tokens bought:", tokensBought);

        uint256 priceAfterBuy = getCurrentPrice();
        console.log("Price after buy:", priceAfterBuy);

        // Now sell all tokens
        uint256 tokenBalance = noma.balanceOf(address(this));
        console.log("Selling all tokens:", tokenBalance);

        sellTokens(tokenBalance);

        uint256 priceAfterSell = getCurrentPrice();
        uint256 ratioAfterSell = getLiquidityRatio();
        console.log("Price after sell:", priceAfterSell);
        console.log("Ratio after sell:", ratioAfterSell);

        // Price should have decreased
        assertLt(priceAfterSell, priceAfterBuy, "Price should decrease after selling");
    }

    /// @notice Test: Full cycle - buy, slide, sell, shift
    function testAdversarial_FullCycle_BuySlideSellShift() public {
        console.log("\n=== Test: Full Cycle (Buy -> Slide -> Sell -> Shift) ===");

        // Phase 1: Buy 3000 MON worth
        console.log("\n--- Phase 1: Initial Purchase ---");
        uint256 purchaseAmount = 3000 ether;
        uint256 tokensBought = buyTokens(purchaseAmount);
        console.log("Tokens bought:", tokensBought);

        uint256 ratioAfterBuy = getLiquidityRatio();
        console.log("Ratio after buy:", ratioAfterBuy);

        // Phase 2: Try slide
        console.log("\n--- Phase 2: Attempt Slide ---");
        bool slid = attemptSlide();
        if (slid) {
            console.log("Slide successful");
        }

        // Phase 3: Sell all
        console.log("\n--- Phase 3: Sell All Tokens ---");
        uint256 tokenBalance = noma.balanceOf(address(this));
        if (tokenBalance > 0) {
            sellTokens(tokenBalance);
        }

        uint256 ratioAfterSell = getLiquidityRatio();
        console.log("Ratio after sell:", ratioAfterSell);

        // Phase 4: Try shift
        console.log("\n--- Phase 4: Attempt Shift ---");
        bool shifted = attemptShift();
        if (shifted) {
            console.log("Shift successful");
            uint256 ratioAfterShift = getLiquidityRatio();
            console.log("Ratio after shift:", ratioAfterShift);
        }
    }

    /// @notice Test: Huge purchase causing near-max price state
    /// Buy 30k MON which should push price to extreme levels
    function testAdversarial_HugePurchase_NearMaxPrice() public {
        console.log("\n=== Test: Huge Purchase Near Max Price ===");

        // First do some moderate buying to warm up
        console.log("--- Warm-up purchases ---");
        for (uint i = 0; i < 5; i++) {
            buyTokens(2000 ether);
            console.log("Warm-up purchase", i + 1, "- Price:", getCurrentPrice());
        }

        // Now do the huge purchase
        console.log("\n--- Huge Purchase Phase ---");
        uint256 hugeAmount = 30000 ether; // 30k MON

        uint256 priceBefore = getCurrentPrice();
        bool wasNearMax = isNearMaxPrice();
        console.log("Price before huge purchase:", priceBefore);
        console.log("Was near max before:", wasNearMax);

        // Split the huge purchase into chunks to avoid single-transaction limits
        uint256 chunkSize = 5000 ether;
        uint256 remaining = hugeAmount;

        while (remaining > 0) {
            uint256 thisChunk = remaining > chunkSize ? chunkSize : remaining;
            buyTokens(thisChunk);
            remaining -= thisChunk;

            uint256 currentPrice = getCurrentPrice();
            bool currentNearMax = isNearMaxPrice();
            console.log("After chunk - Price:", currentPrice, "Near max:", currentNearMax);

            // Check if we hit the near-max condition
            if (currentNearMax && !wasNearMax) {
                console.log("*** Reached near-max price condition! ***");
            }
        }

        uint256 priceAfter = getCurrentPrice();
        uint256 ratioAfter = getLiquidityRatio();
        bool isNearMax = isNearMaxPrice();

        console.log("\nFinal state:");
        console.log("Price after huge purchase:", priceAfter);
        console.log("Liquidity ratio:", ratioAfter);
        console.log("Is near max price:", isNearMax);
    }

    /// @notice Test: Recovery from extreme state via consecutive shifts
    /// This is the full adversarial scenario the user described
    function testAdversarial_ExtremeStateRecovery() public {
        console.log("\n=== Test: Extreme State Recovery ===");

        // Phase 1: Normal purchase (3000 MON)
        console.log("\n--- Phase 1: Normal Purchase (3000 MON) ---");
        uint256 normalAmount = 3000 ether;
        uint256 tokensFromNormal = buyTokens(normalAmount);
        console.log("Tokens from normal purchase:", tokensFromNormal);
        console.log("Price after:", getCurrentPrice());
        console.log("Ratio after:", getLiquidityRatio());

        // Phase 2: First slide
        console.log("\n--- Phase 2: First Slide ---");
        attemptSlide();

        // Phase 3: Sell all tokens
        console.log("\n--- Phase 3: Sell All ---");
        uint256 tokenBalance = noma.balanceOf(address(this));
        if (tokenBalance > 0) {
            sellTokens(tokenBalance);
        }
        console.log("Price after selling:", getCurrentPrice());
        console.log("Ratio after selling:", getLiquidityRatio());

        // Phase 4: Try slide after sell
        console.log("\n--- Phase 4: Slide After Sell ---");
        attemptSlide();

        // Phase 5: Huge purchase (30k MON)
        console.log("\n--- Phase 5: Huge Purchase (30k MON) ---");

        // Do it in chunks
        uint256 totalHuge = 30000 ether;
        uint256 chunkSize = 5000 ether;

        for (uint i = 0; i < totalHuge / chunkSize; i++) {
            buyTokens(chunkSize);
            console.log("Chunk %s - Price: %s - Near max: %s", i + 1, getCurrentPrice(), isNearMaxPrice());
        }

        uint256 priceAfterHuge = getCurrentPrice();
        uint256 ratioAfterHuge = getLiquidityRatio();
        bool nearMaxAfterHuge = isNearMaxPrice();

        console.log("\nAfter huge purchase:");
        console.log("Price:", priceAfterHuge);
        console.log("Ratio:", ratioAfterHuge);
        console.log("Near max:", nearMaxAfterHuge);

        // Phase 6: Recovery with consecutive shifts
        console.log("\n--- Phase 6: Recovery via Consecutive Shifts ---");

        uint256 shiftCount = 0;
        uint256 maxShifts = 5; // Safety limit

        while (shiftCount < maxShifts) {
            uint256 currentRatio = getLiquidityRatio();
            bool currentNearMax = isNearMaxPrice();

            console.log("\nShift attempt", shiftCount + 1);
            console.log("Current ratio:", currentRatio);
            console.log("Current near max:", currentNearMax);

            if (currentRatio < 0.90e18) {
                vault.shift();
                shiftCount++;
                console.log("Shift executed");

                // Check state after shift
                uint256 ratioAfterShift = getLiquidityRatio();
                bool nearMaxAfterShift = isNearMaxPrice();
                console.log("Ratio after shift:", ratioAfterShift);
                console.log("Near max after shift:", nearMaxAfterShift);

                // If we've recovered (not near max and ratio is healthy), we're done
                if (!nearMaxAfterShift && ratioAfterShift >= 0.90e18) {
                    console.log("*** Recovery complete! ***");
                    break;
                }
            } else {
                console.log("Shift condition not met, ratio too high");
                // Try slide instead
                if (currentRatio > 1.15e18) {
                    vault.slide();
                    console.log("Slide executed instead");
                }
                break;
            }
        }

        console.log("\n=== Final State ===");
        console.log("Total shifts executed:", shiftCount);
        console.log("Final price:", getCurrentPrice());
        console.log("Final ratio:", getLiquidityRatio());
        console.log("Final near max:", isNearMaxPrice());
    }

    /// @notice Test: Multiple buy-sell cycles stress test
    function testAdversarial_MultipleCycles() public {
        console.log("\n=== Test: Multiple Buy-Sell Cycles ===");

        uint256 cycleAmount = 2000 ether;
        uint256 numCycles = 5;

        for (uint i = 0; i < numCycles; i++) {
            console.log("\n--- Cycle", i + 1, "---");

            // Buy
            uint256 tokensBought = buyTokens(cycleAmount);
            console.log("Bought tokens:", tokensBought);
            console.log("Price after buy:", getCurrentPrice());

            // Try slide
            attemptSlide();

            // Sell half
            uint256 tokensToSell = noma.balanceOf(address(this)) / 2;
            if (tokensToSell > 0) {
                sellTokens(tokensToSell);
                console.log("Sold tokens:", tokensToSell);
                console.log("Price after sell:", getCurrentPrice());
            }

            // Try shift
            attemptShift();
        }

        console.log("\n=== Final State After Cycles ===");
        console.log("Final price:", getCurrentPrice());
        console.log("Final ratio:", getLiquidityRatio());
    }

    /// @notice Test: Rapid price movement detection
    function testAdversarial_RapidPriceMovement() public {
        console.log("\n=== Test: Rapid Price Movement ===");

        uint256[] memory priceHistory = new uint256[](10);

        // Record prices during rapid buying
        for (uint i = 0; i < 10; i++) {
            buyTokens(1000 ether);
            priceHistory[i] = getCurrentPrice();
            console.log("Step", i + 1, "- Price:", priceHistory[i]);
        }

        // Calculate price volatility
        uint256 maxPrice = priceHistory[0];
        uint256 minPrice = priceHistory[0];

        for (uint i = 1; i < 10; i++) {
            if (priceHistory[i] > maxPrice) maxPrice = priceHistory[i];
            if (priceHistory[i] < minPrice) minPrice = priceHistory[i];
        }

        uint256 priceRange = maxPrice - minPrice;
        console.log("\nPrice range during rapid movement:", priceRange);
        console.log("Max price:", maxPrice);
        console.log("Min price:", minPrice);

        // Verify prices always increased (buying pressure)
        for (uint i = 1; i < 10; i++) {
            assertGe(priceHistory[i], priceHistory[i-1], "Price should not decrease during continuous buying");
        }
    }

    /// @notice Test: Verify shift recovers from high liquidity imbalance
    function testAdversarial_ShiftRecovery() public {
        console.log("\n=== Test: Shift Recovery ===");

        // Create imbalance by heavy selling after some buys
        console.log("--- Creating initial position ---");
        uint256 tokensBought = buyTokens(5000 ether);
        console.log("Initial tokens:", tokensBought);

        // Try to trigger shift by selling
        console.log("\n--- Heavy selling to trigger shift ---");
        uint256 balance = noma.balanceOf(address(this));
        sellTokens(balance);

        uint256 ratioAfterSell = getLiquidityRatio();
        console.log("Ratio after sell:", ratioAfterSell);

        // Execute shift if conditions met
        if (ratioAfterSell < 0.90e18) {
            console.log("\n--- Executing shift recovery ---");
            uint256 priceBeforeShift = getCurrentPrice();

            vault.shift();

            uint256 priceAfterShift = getCurrentPrice();
            uint256 ratioAfterShift = getLiquidityRatio();

            console.log("Price before shift:", priceBeforeShift);
            console.log("Price after shift:", priceAfterShift);
            console.log("Ratio after shift:", ratioAfterShift);

            // Ratio should improve
            assertGe(ratioAfterShift, ratioAfterSell, "Ratio should improve or stay same after shift");
        }
    }

    /// @notice Test: Extreme purchase to actually trigger near-max price
    /// This test uses very large amounts to push the pool to extreme state
    function testAdversarial_ExtremePurchase_TriggerRecovery() public {
        console.log("\n=== Test: Extreme Purchase to Trigger Recovery ===");

        // Record initial state
        uint256 initialRatio = getLiquidityRatio();
        console.log("Initial liquidity ratio:", initialRatio);

        // Do massive consecutive purchases to push price up significantly
        console.log("\n--- Massive Purchase Phase ---");
        uint256 totalPurchased = 0;
        uint256 chunkSize = 50000 ether; // 50k MON per chunk
        uint256 maxIterations = 20;

        for (uint i = 0; i < maxIterations; i++) {
            uint256 currentRatio = getLiquidityRatio();
            bool currentNearMax = isNearMaxPrice();

            console.log("Iteration", i + 1);
            console.log("  Price:", getCurrentPrice());
            console.log("  Ratio:", currentRatio);
            console.log("  Near max:", currentNearMax);

            // If we hit near max or ratio drops below shift threshold, we've triggered the extreme state
            if (currentNearMax || currentRatio < 0.90e18) {
                console.log("*** Extreme state reached! ***");
                break;
            }

            // Buy more tokens
            buyTokens(chunkSize);
            totalPurchased += chunkSize;
        }

        console.log("\nTotal purchased:", totalPurchased / 1e18, "MON");

        uint256 finalRatio = getLiquidityRatio();
        uint256 finalPrice = getCurrentPrice();
        bool finalNearMax = isNearMaxPrice();

        console.log("\n--- Final State ---");
        console.log("Final price:", finalPrice);
        console.log("Final ratio:", finalRatio);
        console.log("Final near max:", finalNearMax);

        // If we hit extreme conditions, test recovery
        if (finalRatio < 0.90e18 || finalNearMax) {
            console.log("\n--- Recovery Phase ---");

            uint256 shiftCount = 0;
            uint256 maxShifts = 3;

            while (shiftCount < maxShifts && (finalRatio < 0.90e18 || finalNearMax)) {
                console.log("Executing shift", shiftCount + 1);
                vault.shift();
                shiftCount++;

                finalRatio = getLiquidityRatio();
                finalNearMax = isNearMaxPrice();
                console.log("  Ratio after shift:", finalRatio);
                console.log("  Near max after shift:", finalNearMax);
            }

            console.log("\nRecovery complete after", shiftCount, "shifts");

            // Verify recovery
            assertTrue(!finalNearMax || finalRatio >= 0.85e18, "Protocol should recover from extreme state");
        }
    }

    /// @notice Test: Verify slide triggers at high ratio
    function testAdversarial_SlideTriggered() public {
        console.log("\n=== Test: Verify Slide Mechanism ===");

        // Make purchases until ratio drops enough, then sell to push ratio up
        // The slide should trigger when ratio > 1.15e18 (115%)

        console.log("Initial ratio:", getLiquidityRatio());

        // First, make some buys to get tokens
        uint256 tokens = buyTokens(10000 ether);
        console.log("Bought tokens:", tokens);
        console.log("Ratio after buys:", getLiquidityRatio());

        // Selling should increase the ratio (price goes down, floor approaches spot)
        sellTokens(tokens / 2);
        uint256 ratioAfterSell = getLiquidityRatio();
        console.log("Ratio after selling half:", ratioAfterSell);

        // Check if slide conditions could be met
        if (ratioAfterSell > 1.15e18) {
            console.log("Slide conditions met, triggering slide...");
            vault.slide();
            console.log("Ratio after slide:", getLiquidityRatio());
        } else {
            console.log("Ratio not high enough for slide (need > 1.15e18)");
        }
    }

    // Allow receiving ETH
    receive() external payable {}
}
