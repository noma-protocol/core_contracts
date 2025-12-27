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
import {LiquidityType, ProtocolAddresses} from "../src/types/Types.sol";

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

/// @title ShiftDivisionByZeroTest
/// @notice Reproduces the division by zero bug in shift after buy->shift->sell->slide->buy sequence
contract ShiftDivisionByZeroTest is Test {
    using stdJson for string;

    IVault vault;
    IERC20 token0;
    IERC20 token1;
    NomaToken noma;
    ModelHelper modelHelper;

    uint256 MAX_INT = type(uint256).max;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bool isMainnet = vm.envOr("DEPLOY_FLAG_MAINNET", false);

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
    address pool;

    IDOManager managerContract;

    function setUp() public {
        // Set WMON based on mainnet/testnet flag
        WMON = isMainnet ? WMON_MAINNET : WMON_TESTNET;

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
        vaultAddress = address(managerContract.vault());

        // Get the ModelHelper from the vault (which uses the resolver)
        // to ensure we use the same one the vault uses
        ProtocolAddresses memory protocolAddrs = IVault(vaultAddress).getProtocolAddresses();
        modelHelper = ModelHelper(protocolAddrs.modelHelper);

        vault = IVault(vaultAddress);
        IUniswapV3Pool poolContract = vault.pool();
        pool = address(poolContract);

        token0 = IERC20(poolContract.token0());
        token1 = IERC20(poolContract.token1());

        console.log("Vault address:", vaultAddress);
        console.log("Pool address:", pool);
        console.log("Token0 (NOMA):", address(token0));
        console.log("Token1 (WETH):", address(token1));
    }

    // ============ HELPER FUNCTIONS ============

    function getCurrentPrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        // Handle max price case - avoid calling vault from test contract
        if (sqrtPriceX96 >= 1461446703485210103287273052203988822378723970341) {
            // At max price, return a large value indicator
            return type(uint256).max;
        }
        return Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
    }

    function getCurrentSqrtPriceX96() internal view returns (uint160) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        return sqrtPriceX96;
    }

    function getLiquidityRatio() internal view returns (uint256) {
        // Handle max price case - getLiquidityRatio will fail if sqrtPriceX96 is at max
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        if (sqrtPriceX96 >= 1461446703485210103287273052203988822378723970341) {
            // At max price, return 0 to indicate extreme state
            return 0;
        }
        return modelHelper.getLiquidityRatio(pool, vaultAddress);
    }

    function getCirculatingSupply() internal view returns (uint256) {
        return modelHelper.getCirculatingSupply(pool, vaultAddress, true);
    }

    function isAtMaxPrice() internal view returns (bool) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        return sqrtPriceX96 >= 1461446703485210103287273052203988822378723970341;
    }

    function buyTokens(uint256 amount) internal returns (uint256 tokensBought) {
        uint256 balanceBefore = noma.balanceOf(address(this));

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100); // 25% slippage

        IWETH(WMON).deposit{value: amount}();
        IWETH(WMON).transfer(idoManager, amount);

        managerContract.buyTokens(purchasePrice, amount, 0, address(this));

        tokensBought = noma.balanceOf(address(this)) - balanceBefore;
    }

    function sellTokens(uint256 tokenAmount) internal {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18, address(0));
        uint256 sellPrice = spotPrice - (spotPrice * 25 / 100); // 25% slippage

        noma.transfer(idoManager, tokenAmount);
        managerContract.sellTokens(sellPrice, tokenAmount, address(this));
    }

    function logState(string memory label) internal view {
        uint256 price = getCurrentPrice();
        uint256 circSupply = getCirculatingSupply();
        uint256 totalSupply = noma.totalSupply();
        bool atMax = isAtMaxPrice();

        console.log("---", label, "---");
        console.log("  At Max Price:", atMax);
        if (!atMax) {
            uint256 ratio = getLiquidityRatio();
            console.log("  Price:", price);
            console.log("  Liquidity Ratio:", ratio);
        } else {
            console.log("  Price: MAX (exhausted liquidity)");
            console.log("  Liquidity Ratio: N/A (at max)");
        }
        console.log("  Circulating Supply:", circSupply);
        console.log("  Total Supply:", totalSupply);
        console.log("  User NOMA balance:", noma.balanceOf(address(this)));
    }

    // ============ BUG REPRODUCTION TEST ============

    /// @notice Simple test that directly triggers shift in extreme state
    /// The pool is already at MAX price from previous operations
    function testBug_DirectShiftAtMaxPrice() public {
        console.log("\n=== Test: Direct Shift At Max Price ===");

        // Log initial state
        logState("Initial State");

        // Check if we're at max price
        bool atMax = isAtMaxPrice();
        console.log("At max price:", atMax);

        // Get circulating supply
        uint256 circSupply = getCirculatingSupply();
        console.log("Circulating supply:", circSupply);

        // Try to trigger shift directly - this should fail with division by zero
        // if circulating supply is 0
        console.log("\n>>> Attempting direct shift...");
        try vault.shift() {
            console.log("Shift succeeded");
            logState("After Shift");
        } catch Error(string memory reason) {
            console.log("Shift failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Shift failed with panic/low-level error");
            console.logBytes(lowLevelData);

            // Check if it's the division by zero panic
            if (lowLevelData.length >= 36) {
                bytes4 selector = bytes4(lowLevelData);
                if (selector == bytes4(0x4e487b71)) {
                    // This is a Panic error
                    uint256 panicCode;
                    assembly {
                        panicCode := mload(add(lowLevelData, 36))
                    }
                    console.log("Panic code:", panicCode);
                    if (panicCode == 0x12) {
                        console.log("*** BUG CONFIRMED: Division by zero! ***");
                    }
                }
            }
        }

        logState("Final State");
    }

    /// @notice Reproduces the division by zero bug in shift
    /// Scenario:
    /// 1. Buy a large quantity of tokens (175000 MON worth)
    /// 2. Trigger a shift
    /// 3. Sell all the tokens
    /// 4. Trigger a slide
    /// 5. Buy an enormously large amount of tokens
    /// Expected: shift fails with "Division or modulo by zero"
    function testBug_ShiftDivisionByZero() public {
        console.log("\n=== Test: Shift Division By Zero Bug Reproduction ===");

        logState("Initial State");

        // Step 1: Buy a large quantity of tokens (175000 MON worth)
        console.log("\n>>> Step 1: Buy 175000 MON worth of tokens");
        uint256 largePurchase = 175000 ether;
        uint256 tokensBought = buyTokens(largePurchase);
        console.log("Tokens bought:", tokensBought);
        logState("After Large Purchase");

        // Step 2: Trigger a shift
        console.log("\n>>> Step 2: Trigger shift");
        uint256 ratioAfterBuy = getLiquidityRatio();
        if (ratioAfterBuy <= 0.90e18) {
            console.log("Shift condition met, triggering shift...");
            vault.shift();
            logState("After First Shift");
        } else {
            console.log("Shift condition not met. Ratio:", ratioAfterBuy);
            // Force more buying to trigger shift condition
            while (getLiquidityRatio() > 0.90e18) {
                buyTokens(50000 ether);
                tokensBought = noma.balanceOf(address(this));
            }
            vault.shift();
            logState("After Forced Shift");
        }

        // Step 3: Sell all the tokens
        console.log("\n>>> Step 3: Sell all tokens");
        uint256 tokenBalance = noma.balanceOf(address(this));
        console.log("Selling all tokens:", tokenBalance);
        sellTokens(tokenBalance);
        logState("After Sell All");

        // Step 4: Trigger a slide
        console.log("\n>>> Step 4: Trigger slide");
        uint256 ratioAfterSell = getLiquidityRatio();
        if (ratioAfterSell >= 1.10e18) { // slideRatio is typically 11000 (1.10)
            console.log("Slide condition met, triggering slide...");
            vault.slide();
            logState("After Slide");
        } else {
            console.log("Slide condition not met. Ratio:", ratioAfterSell);
            console.log("Attempting slide anyway to test...");
            // The slide might fail if ratio isn't high enough - that's okay for this test
            try vault.slide() {
                logState("After Slide");
            } catch {
                console.log("Slide failed - ratio not high enough");
            }
        }

        // Step 5: Buy an enormously large amount of tokens
        // This should trigger a shift that fails with division by zero
        console.log("\n>>> Step 5: Buy enormous amount to trigger buggy shift");

        // Check circulating supply before the massive buy
        uint256 circSupplyBefore = getCirculatingSupply();
        console.log("Circulating supply before massive buy:", circSupplyBefore);

        // Buy in chunks to avoid any single-transaction issues
        uint256 enormousPurchase = 500000 ether;
        uint256 chunkSize = 100000 ether;

        for (uint i = 0; i < enormousPurchase / chunkSize; i++) {
            console.log("\nBuying chunk", i + 1, "of", enormousPurchase / chunkSize);
            buyTokens(chunkSize);

            uint256 ratio = getLiquidityRatio();
            uint256 circSupply = getCirculatingSupply();
            console.log("  Ratio:", ratio);
            console.log("  Circulating Supply:", circSupply);

            // Try to trigger shift if conditions are met
            if (ratio <= 0.90e18) {
                console.log("  Shift condition met! Attempting shift...");
                // This is where the bug should manifest
                try vault.shift() {
                    console.log("  Shift succeeded");
                    logState("After Shift in Loop");
                } catch Error(string memory reason) {
                    console.log("  Shift failed with reason:", reason);
                    revert(reason);
                } catch (bytes memory lowLevelData) {
                    // Panic codes: 0x12 = Division/modulo by zero
                    console.log("  Shift failed with panic");
                    console.logBytes(lowLevelData);

                    // Check if it's the division by zero panic
                    if (lowLevelData.length >= 36) {
                        bytes4 selector = bytes4(lowLevelData);
                        if (selector == bytes4(0x4e487b71)) {
                            // This is a Panic error
                            uint256 panicCode;
                            assembly {
                                panicCode := mload(add(lowLevelData, 36))
                            }
                            console.log("  Panic code:", panicCode);
                            if (panicCode == 0x12) {
                                console.log("  *** BUG CONFIRMED: Division by zero in shift! ***");
                            }
                        }
                    }
                    revert("Shift panicked - likely division by zero");
                }
            }
        }

        logState("Final State");
        console.log("\n=== Test completed without hitting the bug ===");
    }

    /// @notice Alternative approach: more aggressive scenario
    function testBug_ShiftDivisionByZero_Aggressive() public {
        console.log("\n=== Test: Aggressive Division By Zero Bug Reproduction ===");

        logState("Initial State");

        // Step 1: Multiple large purchases to drain the liquidity
        console.log("\n>>> Step 1: Multiple large purchases");
        uint256 totalBought = 0;
        for (uint i = 0; i < 5; i++) {
            uint256 bought = buyTokens(50000 ether);
            totalBought += bought;
            console.log("Purchase", i + 1, "- Bought:", bought);
            console.log("  Total:", totalBought);

            uint256 ratio = getLiquidityRatio();
            console.log("  Ratio:", ratio);

            // Shift when possible
            if (ratio <= 0.90e18) {
                vault.shift();
                console.log("  Shifted!");
            }
        }
        logState("After Purchases");

        // Step 2: Sell everything
        console.log("\n>>> Step 2: Sell everything");
        uint256 balance = noma.balanceOf(address(this));
        console.log("Selling:", balance);
        sellTokens(balance);
        logState("After Selling All");

        // Step 3: Try slide
        console.log("\n>>> Step 3: Try slide");
        uint256 ratioNow = getLiquidityRatio();
        console.log("Current ratio:", ratioNow);

        if (ratioNow >= 1.10e18) {
            vault.slide();
            console.log("Slide executed!");
            logState("After Slide");
        }

        // Step 4: Massive buy to trigger the bug
        console.log("\n>>> Step 4: Massive buy to trigger bug");

        // First check circulating supply
        uint256 circSupply = getCirculatingSupply();
        console.log("Circulating supply before massive buy:", circSupply);

        // If circulating supply is already very low, the next shift might fail
        if (circSupply < 1e18) {
            console.log("WARNING: Circulating supply is dangerously low!");
        }

        // Buy massive amounts
        for (uint i = 0; i < 10; i++) {
            uint256 bought = buyTokens(100000 ether);
            console.log("Massive buy", i + 1, "- Bought:", bought);

            uint256 ratio = getLiquidityRatio();
            circSupply = getCirculatingSupply();
            console.log("  Ratio:", ratio);
            console.log("  Circulating Supply:", circSupply);

            if (ratio <= 0.90e18) {
                console.log("  Attempting shift...");
                // This might fail with division by zero
                vault.shift();
                console.log("  Shift succeeded");
            }
        }

        logState("Final State");
    }

    /// @notice Direct test with minimal circulating supply
    function testBug_MinimalCirculatingSupply() public {
        console.log("\n=== Test: Minimal Circulating Supply Scenario ===");

        logState("Initial State");

        // Keep buying and shifting until circulating supply is minimal
        console.log("\n>>> Phase 1: Drain circulating supply through shifts");

        uint256 iterations = 0;
        uint256 maxIterations = 20;

        while (iterations < maxIterations) {
            // Buy tokens
            uint256 bought = buyTokens(75000 ether);
            console.log("\nIteration", iterations + 1);
            console.log("  Bought:", bought);

            uint256 ratio = getLiquidityRatio();
            uint256 circSupply = getCirculatingSupply();
            console.log("  Ratio:", ratio);
            console.log("  Circulating Supply:", circSupply);

            // Trigger shift if possible
            if (ratio <= 0.90e18) {
                vault.shift();
                console.log("  Shift executed");

                // Immediately sell all to reduce circulating supply
                uint256 balance = noma.balanceOf(address(this));
                if (balance > 0) {
                    sellTokens(balance);
                    console.log("  Sold all:", balance);
                }

                // Check new circulating supply
                circSupply = getCirculatingSupply();
                console.log("  New Circulating Supply:", circSupply);

                // If circulating supply is very low, try triggering another shift
                if (circSupply < 1e18) {
                    console.log("  *** Circulating supply is minimal! ***");

                    // Now buy again to trigger the buggy shift
                    console.log("\n>>> Attempting to trigger division by zero...");
                    buyTokens(100000 ether);

                    ratio = getLiquidityRatio();
                    circSupply = getCirculatingSupply();
                    console.log("  Ratio after buy:", ratio);
                    console.log("  Circulating Supply after buy:", circSupply);

                    if (ratio <= 0.90e18) {
                        console.log("  Triggering final shift...");
                        vault.shift(); // This should fail with division by zero
                    }
                    break;
                }

                // Try slide if conditions met
                ratio = getLiquidityRatio();
                if (ratio >= 1.10e18) {
                    vault.slide();
                    console.log("  Slide executed");
                }
            }

            iterations++;
        }

        logState("Final State");
    }

    // Allow receiving ETH
    receive() external payable {}
}
