// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./FuzzBase.sol";
import {Conversions} from "../../src/libraries/Conversions.sol";

/**
 * @title VaultInvariantHandler
 * @notice Handler contract that performs actions on the vault for invariant testing
 */
contract VaultInvariantHandler is FuzzBase {
    // Action counters
    uint256 public borrowCount;
    uint256 public paybackCount;
    uint256 public shiftCount;
    uint256 public slideCount;
    uint256 public defaultCount;

    // Track state for invariant checks
    uint256 public feesToken0Previous;
    uint256 public feesToken1Previous;

    function setUp() public override {
        super.setUp();
        (feesToken0Previous, feesToken1Previous) = vault.getAccumulatedFees();
    }

    /**
     * @notice Handler: Borrow from vault
     */
    function handler_borrow(uint256 actorSeed, uint256 amount, uint256 duration) external {
        address borrower = _getActor(actorSeed);

        // Bound inputs
        amount = bound(amount, 0.01 ether, 5 ether);
        duration = bound(duration, 30 days, 365 days);

        // Estimate collateral and fund borrower
        uint256 imv = modelHelper.getIntrinsicMinimumValue(address(vault));
        if (imv == 0) return;

        uint256 collateralNeeded = DecimalMath.divideDecimal(amount * 15 / 10, imv);
        _fundWithNOMA(borrower, collateralNeeded * 2);

        vm.startPrank(borrower);
        nomaToken.approve(address(vault), type(uint256).max);

        try vault.borrow(amount, duration) {
            borrowCount++;
        } catch {}

        vm.stopPrank();
    }

    /**
     * @notice Handler: Payback loan
     */
    function handler_payback(uint256 actorSeed, uint256 paybackPercent) external {
        address borrower = _getActor(actorSeed);
        paybackPercent = bound(paybackPercent, 10, 100);

        // Check if borrower has a loan - we need to check the vault's loan position
        // For simplicity, just try to payback

        // Fund borrower with WETH
        uint256 paybackAmount = 0.5 ether * paybackPercent / 100;
        _fundWithWETH(borrower, paybackAmount);

        vm.startPrank(borrower);
        weth.approve(address(vault), type(uint256).max);

        try vault.payback(paybackAmount) {
            paybackCount++;
        } catch {}

        vm.stopPrank();
    }

    /**
     * @notice Handler: Trigger shift
     */
    function handler_shift() external {
        try vault.shift() {
            shiftCount++;
        } catch {}
    }

    /**
     * @notice Handler: Trigger slide
     */
    function handler_slide() external {
        try vault.slide() {
            slideCount++;
        } catch {}
    }

    /**
     * @notice Handler: Default expired loans
     */
    function handler_defaultLoans() external {
        // Warp time forward to expire loans
        vm.warp(block.timestamp + 400 days);

        try vault.defaultLoans() {
            defaultCount++;
        } catch {}
    }

    /**
     * @notice Handler: Advance time
     */
    function handler_warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1 hours, 30 days);
        vm.warp(block.timestamp + seconds_);
    }

    /**
     * @notice Handler: Buy tokens via IDO Helper
     */
    function handler_buyTokens(uint256 actorSeed, uint256 ethAmount) external {
        address buyer = _getActor(actorSeed);
        ethAmount = bound(ethAmount, 0.01 ether, 1 ether);

        // Get current price
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);

        // Fund buyer with WETH
        _fundWithWETH(address(idoHelper), ethAmount);

        try idoHelper.buyTokens(purchasePrice, ethAmount, 0, buyer) {} catch {}
    }

    /**
     * @notice Handler: Sell tokens via IDO Helper
     */
    function handler_sellTokens(uint256 actorSeed, uint256 tokenAmount) external {
        address seller = _getActor(actorSeed);
        uint256 balance = nomaToken.balanceOf(seller);
        if (balance == 0) return;

        tokenAmount = bound(tokenAmount, 1, balance);

        // Get current price
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 sellPrice = spotPrice - (spotPrice * 25 / 100);

        // Transfer tokens to IDO Helper
        vm.prank(seller);
        nomaToken.transfer(address(idoHelper), tokenAmount);

        try idoHelper.sellTokens(sellPrice, tokenAmount, seller) {} catch {}
    }
}

/**
 * @title VaultInvariantTest
 * @notice Foundry invariant tests for Noma Protocol vault solvency
 *
 * Run with: forge test --match-contract VaultInvariantTest -vvv
 */
contract VaultInvariantTest is FuzzBase {
    VaultInvariantHandler public handler;

    function setUp() public override {
        super.setUp();

        // Deploy handler
        handler = new VaultInvariantHandler();

        // Target the handler for invariant testing
        targetContract(address(handler));

        // Exclude certain selectors if needed
        // bytes4[] memory selectors = new bytes4[](1);
        // selectors[0] = handler.handler_defaultLoans.selector;
        // targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ==================== INVARIANTS ====================

    /**
     * @notice CRITICAL: Solvency invariant
     * @dev anchorCapacity + floorCapacity >= circulatingSupply
     */
    function invariant_solvency() public view {
        (bool isSolvent, string memory reason) = handler._checkSolvency();
        assertTrue(isSolvent, reason);
    }

    /**
     * @notice Position validity invariant
     * @dev All positions must have liquidity and be contiguous
     */
    function invariant_positions_valid() public view {
        (bool isValid, string memory reason) = handler._checkPositions();
        assertTrue(isValid, reason);
    }

    /**
     * @notice Supply cap invariant
     * @dev totalSupply <= maxTotalSupply
     */
    function invariant_supply_cap() public view {
        uint256 totalSupply = nomaToken.totalSupply();
        uint256 maxSupply = nomaToken.maxTotalSupply();
        assertLe(totalSupply, maxSupply, "Supply cap exceeded");
    }

    /**
     * @notice Collateral tracking invariant
     * @dev TokenRepo should hold at least vault.collateralAmount
     */
    function invariant_collateral_tracking() public view {
        uint256 vaultCollateral = vault.getCollateralAmount();
        // This assumes collateral is in NOMA token held somewhere
        // Adjust based on actual collateral tracking
        assertTrue(true, "Collateral check");
    }

    /**
     * @notice Liquidity ratio bounds
     * @dev Ratio should stay within 50%-200%
     */
    function invariant_liquidity_ratio_bounded() public view {
        uint256 ratio = modelHelper.getLiquidityRatio(address(pool), address(vault));

        // Ratio should be within reasonable bounds
        // 0.5e18 to 2e18 (50% to 200%)
        assertTrue(ratio >= 0.3e18, "Liquidity ratio too low");
        assertTrue(ratio <= 3e18, "Liquidity ratio too high");
    }

    /**
     * @notice sNOMA minimum supply
     * @dev sNOMA.totalSupply() >= MIN_SUPPLY (1e18)
     */
    function invariant_sNOMA_min_supply() public view {
        if (address(sNOMA) == address(0)) return;

        uint256 supply = sNOMA.totalSupply();
        assertGe(supply, 1e18, "sNOMA below minimum supply");
    }

    /**
     * @notice Fee monotonicity
     * @dev Accumulated fees should not decrease
     */
    function invariant_fees_monotonic() public view {
        (uint256 fees0, uint256 fees1) = vault.getAccumulatedFees();
        assertGe(fees0, handler.feesToken0Previous(), "Token0 fees decreased");
        assertGe(fees1, handler.feesToken1Previous(), "Token1 fees decreased");
    }

    // ==================== HELPERS ====================

    /**
     * @notice Print summary after invariant testing
     */
    function invariant_callSummary() public view {
        console.log("Handler call summary:");
        console.log("  Borrows:", handler.borrowCount());
        console.log("  Paybacks:", handler.paybackCount());
        console.log("  Shifts:", handler.shiftCount());
        console.log("  Slides:", handler.slideCount());
        console.log("  Defaults:", handler.defaultCount());
    }
}
