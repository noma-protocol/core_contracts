// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/bootstrap/Migration.sol";
import "solmate/tokens/ERC20.sol";

/// @notice Mock implementation of IModelHelper to control IMV in tests
contract MockModelHelper is IModelHelper {
    uint256 internal imv;

    function setIMV(uint256 _imv) external {
        imv = _imv;
    }

    function getIntrinsicMinimumValue(address) external view override returns (uint256) {
        return imv;
    }
}

/// @notice Simple ERC20 for minting and transfers in tests
contract DummyERC20 is ERC20 {
    constructor() ERC20("Dummy", "DUM", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MigrationTest is Test {
    Migration       public migration;
    MockModelHelper public helper;
    DummyERC20      public token;

    address public constant HOLDER1 = address(0x1);
    address public constant HOLDER2 = address(0x2);
    address public constant VAULT   = address(0x3);

    uint256 public constant INITIAL_IMV = 100;
    uint256 public constant DURATION    = 1000;
    uint256 public constant BAL1        = 1_000;
    uint256 public constant BAL2        = 2_000;
    uint256 public constant TOTAL_SUP   = BAL1 + BAL2;
    
    function setUp() public {
        helper = new MockModelHelper();
        helper.setIMV(INITIAL_IMV);

        token = new DummyERC20();

        // --- Declare and populate holders & balances here ---
        address[] memory holders = new address[](2);
        holders[0] = HOLDER1;
        holders[1] = HOLDER2;

        uint256[] memory balances = new uint256[](2);
        balances[0] = BAL1;
        balances[1] = BAL2;
        // ----------------------------------------------------

        migration = new Migration(
            address(helper),
            address(token),
            VAULT,
            INITIAL_IMV,
            DURATION,
            holders,
            balances
        );

        token.mint(address(migration), TOTAL_SUP);
    }

    function test_constructor_setsState() public {
        assertEq(migration.initialIMV(), INITIAL_IMV);
        assertEq(migration.vault(), VAULT);
        assertEq(migration.migrationEnd(), block.timestamp + DURATION);

        assertEq(migration.initialBalanceOf(HOLDER1), BAL1);
        assertEq(migration.initialBalanceOf(HOLDER2), BAL2);
    }

    function test_firstHolder_withdrawsAll() public {
        vm.prank(HOLDER1);
        migration.withdraw();

        assertEq(token.balanceOf(HOLDER1), BAL1);
        assertEq(migration.withdrawnOf(HOLDER1), BAL1);
        assertEq(migration.totalWithdrawn(), BAL1);
    }

    function test_nonFirstHolder_cannotWithdrawBeforeIMVIncrease() public {
        vm.prank(HOLDER2);
        vm.expectRevert(abi.encodeWithSignature("IMVNotGrown()"));
        migration.withdraw();
    }

    function test_nonFirstHolder_withdrawsAfterIMVIncrease() public {
        helper.setIMV((INITIAL_IMV * 150) / 100);

        vm.prank(HOLDER2);
        migration.withdraw();

        uint256 expected = (BAL2 * 50) / 100;
        assertEq(token.balanceOf(HOLDER2), expected);
        assertEq(migration.withdrawnOf(HOLDER2), expected);
        // firstHolder auto‑withdraws BAL1 on first non‑first call
        assertEq(migration.totalWithdrawn(), BAL1 + expected);
    }

    function test_nonFirstHolder_withdraws_cappedAt100Percent() public {
        helper.setIMV((INITIAL_IMV * 150) / 100);
        vm.prank(HOLDER2);
        migration.withdraw();

        helper.setIMV((INITIAL_IMV * 250) / 100);
        vm.prank(HOLDER2);
        migration.withdraw();

        assertEq(token.balanceOf(HOLDER2), BAL2);
        assertEq(migration.withdrawnOf(HOLDER2), BAL2);
    }

    function test_cannotWithdrawTwiceBeyondAllowed() public {
        helper.setIMV((INITIAL_IMV * 150) / 100);
        vm.prank(HOLDER2);
        migration.withdraw();

        vm.prank(HOLDER2);
        vm.expectRevert(abi.encodeWithSignature("NothingToWithdraw()"));
        migration.withdraw();
    }

    function test_cannotWithdrawAfterMigrationEnd() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(HOLDER1);
        vm.expectRevert(abi.encodeWithSignature("MigrationEnded()"));
        migration.withdraw();
    }

    function test_setBalances_onlyOwner() public {
        // --- Declare and populate holders & balances here too ---
        address[] memory holders = new address[](2);
        holders[0] = HOLDER1;

        uint256[] memory balances = new uint256[](2);
        balances[0] = BAL1 * 2;
        // ---------------------------------------------------------

        // non‑owner should revert with OZ’s own message
        vm.prank(HOLDER2);
        vm.expectRevert();
        migration.setBalances(holders, balances);

        // owner can reset
        migration.setBalances(holders, balances);
        assertEq(migration.initialBalanceOf(HOLDER1), BAL1 * 2);
    }

    function test_recoverERC20() public {
        token.mint(address(migration), 5e18);
        uint256 before = token.balanceOf(address(this));

        migration.recoverERC20(address(token));
        assertEq(token.balanceOf(address(this)), before + 5e18);
    }
}
