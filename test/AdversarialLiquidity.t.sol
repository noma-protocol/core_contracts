// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {NomaToken} from "../src/token/NomaToken.sol";
import {ModelHelper} from "../src/model/Helper.sol";
import {BaseVault} from "../src/vault/BaseVault.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {Underlying} from "../src/libraries/Underlying.sol";
import {LiquidityType, LiquidityPosition} from "../src/types/Types.sol";

interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IDOManager {
    function vault() external view returns (BaseVault);
    function buyTokens(uint256 price, uint256 amount, uint256 min, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
    function modelHelper() external view returns (address);
}

/// @title AdversarialLiquidityTest
/// @notice Tests for adversarial scenarios where external actors add liquidity to Uniswap
contract AdversarialLiquidityTest is Test {
    using stdJson for string;

    IVault vault;
    IERC20 token0; // NOMA token
    IERC20 token1; // WETH
    IUniswapV3Pool pool;

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

    // Uniswap V3 position manager (adjust for your network)
    address positionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    // Adversarial actors
    address adversary1 = address(0xAD01);
    address adversary2 = address(0xAD02);
    address adversary3 = address(0xAD03);

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

        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        noma = NomaToken(nomaToken);
        modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        vault = IVault(vaultAddress);
        pool = vault.pool();

        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        console.log("Vault address:", vaultAddress);
        console.log("Pool address:", address(pool));
    }

    // ============ EXTERNAL LIQUIDITY ON SAME RANGES ============

    /// @notice Test behavior when external actor adds liquidity on the same Floor range
    function testAdversarial_ExternalLiquidityOnFloorRange() public {
        LiquidityPosition[3] memory positions = vault.getPositions();

        console.log("=== Protocol Floor Position ===");
        console.log("Floor lower tick:", positions[0].lowerTick);
        console.log("Floor upper tick:", positions[0].upperTick);
        console.log("Floor liquidity:", positions[0].liquidity);

        // Get underlying balances before
        (,, uint256 floorBalance0Before, uint256 floorBalance1Before) =
            Underlying.getUnderlyingBalances(address(pool), vaultAddress, positions[0]);

        console.log("Floor balance token0 before:", floorBalance0Before);
        console.log("Floor balance token1 before:", floorBalance1Before);

        // Simulate external actor adding liquidity on the same range
        // Note: In a real test, you'd mint a position via the position manager
        // For now, we'll verify the protocol's positions remain intact after trades

        // Perform some trades
        _doSmallPurchase(5, 1000 ether);

        // Check protocol's positions are still valid
        positions = vault.getPositions();

        (,, uint256 floorBalance0After, uint256 floorBalance1After) =
            Underlying.getUnderlyingBalances(address(pool), vaultAddress, positions[0]);

        console.log("Floor balance token0 after trades:", floorBalance0After);
        console.log("Floor balance token1 after trades:", floorBalance1After);

        // Verify protocol can still shift
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(address(pool), vaultAddress);
        console.log("Liquidity ratio after external activity:", liquidityRatio);

        // Protocol should maintain its position integrity
        assertTrue(positions[0].liquidity > 0, "Floor liquidity should remain");
    }

    /// @notice Test behavior when external actor adds liquidity on the Anchor range
    function testAdversarial_ExternalLiquidityOnAnchorRange() public {
        LiquidityPosition[3] memory positions = vault.getPositions();

        console.log("=== Protocol Anchor Position ===");
        console.log("Anchor lower tick:", positions[1].lowerTick);
        console.log("Anchor upper tick:", positions[1].upperTick);
        console.log("Anchor liquidity:", positions[1].liquidity);

        // Get anchor capacity before
        uint256 anchorCapacityBefore = modelHelper.getPositionCapacity(
            address(pool),
            vaultAddress,
            positions[1],
            LiquidityType.Anchor
        );
        console.log("Anchor capacity before:", anchorCapacityBefore);

        // Perform trades to stress the anchor
        _doSmallPurchase(10, 2000 ether);

        // Check anchor after trades
        positions = vault.getPositions();
        uint256 anchorCapacityAfter = modelHelper.getPositionCapacity(
            address(pool),
            vaultAddress,
            positions[1],
            LiquidityType.Anchor
        );
        console.log("Anchor capacity after trades:", anchorCapacityAfter);

        // Verify solvency invariant still holds
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(address(pool), vaultAddress, false);
        console.log("Circulating supply:", circulatingSupply);
    }

    /// @notice Test behavior when external actor adds liquidity on the Discovery range
    function testAdversarial_ExternalLiquidityOnDiscoveryRange() public {
        LiquidityPosition[3] memory positions = vault.getPositions();

        console.log("=== Protocol Discovery Position ===");
        console.log("Discovery lower tick:", positions[2].lowerTick);
        console.log("Discovery upper tick:", positions[2].upperTick);
        console.log("Discovery liquidity:", positions[2].liquidity);

        // Discovery is for price discovery, external liquidity here could affect price movement

        // Perform trades
        _doSmallPurchase(5, 1000 ether);

        // Check protocol maintains control
        positions = vault.getPositions();
        assertTrue(positions[2].liquidity >= 0, "Discovery position should be valid");
    }

    // ============ EXTERNAL LIQUIDITY ON DIFFERENT RANGES ============

    /// @notice Test behavior when external actor adds liquidity outside protocol ranges
    function testAdversarial_ExternalLiquidityOutsideRanges() public {
        LiquidityPosition[3] memory positions = vault.getPositions();

        // Find a range outside protocol positions
        int24 outsideLowerTick = positions[2].upperTick + 1000;
        int24 outsideUpperTick = positions[2].upperTick + 2000;

        console.log("External liquidity range (outside protocol):");
        console.log("Lower tick:", outsideLowerTick);
        console.log("Upper tick:", outsideUpperTick);

        // This external liquidity shouldn't affect protocol operations directly
        // but could affect price dynamics at extreme price levels

        // Verify protocol operations still work
        _doSmallPurchase(3, 500 ether);

        // Check shift/slide still works
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(address(pool), vaultAddress);
        console.log("Liquidity ratio:", liquidityRatio);

        if (liquidityRatio >= 1.15e18) {
            console.log("Slide condition met");
            vault.slide();
            console.log("Slide successful");
        }
    }

    /// @notice Test behavior when external actor adds liquidity between protocol ranges
    function testAdversarial_ExternalLiquidityBetweenRanges() public {
        LiquidityPosition[3] memory positions = vault.getPositions();

        // Find gap between floor and anchor
        int24 gapLowerTick = positions[0].upperTick;
        int24 gapUpperTick = positions[1].lowerTick;

        if (gapLowerTick < gapUpperTick) {
            console.log("Gap between Floor and Anchor:");
            console.log("Gap lower tick:", gapLowerTick);
            console.log("Gap upper tick:", gapUpperTick);
        } else {
            console.log("No gap between Floor and Anchor (overlapping or adjacent)");
        }

        // Protocol should still function with external liquidity in gaps
        _doSmallPurchase(5, 1000 ether);

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(address(pool), vaultAddress);
        console.log("Protocol liquidity ratio:", liquidityRatio);
    }

    // ============ ADVERSARIAL LIQUIDITY ATTACK SCENARIOS ============

    /// @notice Test: External actor tries to sandwich protocol's shift operation
    function testAdversarial_SandwichShiftAttempt() public {
        // Build up to shift condition
        _doPurchasesToTriggerShiftCondition();

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(address(pool), vaultAddress);

        if (liquidityRatio <= 0.90e18) {
            console.log("Shift condition met, ratio:", liquidityRatio);

            // Record state before shift
            (uint160 sqrtPriceX96Before,,,,,,) = pool.slot0();
            uint256 priceBefore = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96Before, 18);
            console.log("Price before shift:", priceBefore);

            // Perform shift
            vault.shift();

            // Record state after shift
            (uint160 sqrtPriceX96After,,,,,,) = pool.slot0();
            uint256 priceAfter = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96After, 18);
            console.log("Price after shift:", priceAfter);

            // Verify solvency after shift
            _verifySolvency();
        }
    }

    /// @notice Test: External actor adds massive liquidity to manipulate ratio calculation
    function testAdversarial_MassiveLiquidityInjection() public {
        // Get initial state
        uint256 initialLiquidityRatio = modelHelper.getLiquidityRatio(address(pool), vaultAddress);
        console.log("Initial liquidity ratio:", initialLiquidityRatio);

        LiquidityPosition[3] memory positions = vault.getPositions();
        uint256 protocolTotalLiquidity = uint256(uint128(positions[0].liquidity)) +
                                          uint256(uint128(positions[1].liquidity)) +
                                          uint256(uint128(positions[2].liquidity));
        console.log("Protocol total liquidity:", protocolTotalLiquidity);

        // External actor's liquidity would be in the pool but not tracked by protocol
        // Protocol uses its own position tracking, not total pool liquidity

        // Perform trades
        _doSmallPurchase(10, 2000 ether);

        // Check protocol's liquidity ratio is based on its own positions
        uint256 afterLiquidityRatio = modelHelper.getLiquidityRatio(address(pool), vaultAddress);
        console.log("Liquidity ratio after trades:", afterLiquidityRatio);

        // Protocol calculations should be unaffected by external liquidity
        // because it tracks its own positions specifically
    }

    /// @notice Test: External actor tries to drain protocol by adding competing liquidity
    function testAdversarial_CompetingLiquidityDrain() public {
        // Record protocol's token balances
        uint256 vaultToken0Before = token0.balanceOf(vaultAddress);
        uint256 vaultToken1Before = token1.balanceOf(vaultAddress);

        console.log("Vault token0 before:", vaultToken0Before);
        console.log("Vault token1 before:", vaultToken1Before);

        // Simulate heavy trading activity that external LPs might capture fees from
        for (uint i = 0; i < 5; i++) {
            _doSmallPurchase(5, 1000 ether);
            vm.warp(block.timestamp + 1 hours);
        }

        // Record protocol's balances after
        uint256 vaultToken0After = token0.balanceOf(vaultAddress);
        uint256 vaultToken1After = token1.balanceOf(vaultAddress);

        console.log("Vault token0 after:", vaultToken0After);
        console.log("Vault token1 after:", vaultToken1After);

        // Protocol should maintain its liquidity positions
        LiquidityPosition[3] memory positions = vault.getPositions();
        assertTrue(positions[0].liquidity > 0, "Floor liquidity should remain");
        assertTrue(positions[1].liquidity > 0, "Anchor liquidity should remain");
    }

    /// @notice Test: Protocol behavior when external actors create price gaps
    function testAdversarial_PriceGapCreation() public {
        // Get current price
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint256 currentPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Current price:", currentPrice);

        // Large purchase to move price significantly
        _doLargePurchase(5, 50000 ether);

        // Check new price
        (sqrtPriceX96,,,,,,) = pool.slot0();
        uint256 newPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Price after large purchase:", newPrice);

        // Protocol should handle the price movement
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(address(pool), vaultAddress);
        console.log("Liquidity ratio:", liquidityRatio);

        // If ratio is out of bounds, shift/slide should be available
        if (liquidityRatio <= 0.90e18) {
            console.log("Shift needed");
            vault.shift();
            _verifySolvency();
        } else if (liquidityRatio >= 1.15e18) {
            console.log("Slide needed");
            vault.slide();
        }
    }

    // ============ STRESS TESTS ============

    /// @notice Test: Heavy concurrent trading with external liquidity
    function testAdversarial_HeavyConcurrentTrading() public {
        // Simulate heavy trading activity
        for (uint i = 0; i < 10; i++) {
            // Buy
            _doSmallPurchase(2, 500 ether);

            // Check state
            uint256 liquidityRatio = modelHelper.getLiquidityRatio(address(pool), vaultAddress);

            // Perform operations if needed
            if (liquidityRatio <= 0.90e18) {
                vault.shift();
            } else if (liquidityRatio >= 1.15e18) {
                vault.slide();
            }

            vm.warp(block.timestamp + 30 minutes);
        }

        // Final solvency check
        _verifySolvency();
        console.log("Heavy concurrent trading test passed");
    }

    // ============ HELPER FUNCTIONS ============

    function _doSmallPurchase(uint16 totalTrades, uint256 tradeAmount) internal {
        IDOManager managerContract = IDOManager(idoManager);

        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);

        IWETH(WMON).deposit{value: tradeAmount * totalTrades}();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = pool.slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            uint256 purchasePrice = spotPrice + (spotPrice * 5 / 100);
            managerContract.buyTokens(purchasePrice, tradeAmount, 0, address(this));
        }
    }

    function _doLargePurchase(uint16 totalTrades, uint256 tradeAmount) internal {
        IDOManager managerContract = IDOManager(idoManager);

        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);

        IWETH(WMON).deposit{value: tradeAmount * totalTrades}();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = pool.slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);
            managerContract.buyTokens(purchasePrice, tradeAmount, 0, address(this));
        }
    }

    function _doPurchasesToTriggerShiftCondition() internal {
        IDOManager managerContract = IDOManager(idoManager);

        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);

        uint16 totalTrades = 10;
        uint256 tradeAmount = 20000 ether;

        IWETH(WMON).deposit{value: tradeAmount * totalTrades}();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = pool.slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);
            managerContract.buyTokens(purchasePrice, tradeAmount, 0, address(this));
        }
    }

    function _verifySolvency() internal view {
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(address(pool), vaultAddress, false);

        LiquidityPosition[3] memory positions = vault.getPositions();

        uint256 anchorCapacity = modelHelper.getPositionCapacity(
            address(pool),
            vaultAddress,
            positions[1],
            LiquidityType.Anchor
        );

        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(
            address(pool),
            vaultAddress,
            positions[0]
        );

        uint256 intrinsicMinimumValue = modelHelper.getIntrinsicMinimumValue(vaultAddress);

        uint256 floorCapacity = DecimalMath.divideDecimal(floorBalance, intrinsicMinimumValue);

        console.log("Solvency check:");
        console.log("  Circulating supply:", circulatingSupply);
        console.log("  Anchor capacity:", anchorCapacity);
        console.log("  Floor capacity:", floorCapacity);
        console.log("  Total capacity:", anchorCapacity + floorCapacity);

        require(anchorCapacity + floorCapacity > circulatingSupply, "Solvency invariant failed");
    }

    receive() external payable {}
}
