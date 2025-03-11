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
    Migration public migration;
    MockModelHelper public helper;
    DummyERC20 public token;

    address public constant HOLDER1 = address(0x1);
    address public constant HOLDER2 = address(0x2);
    address public constant VAULT   = address(0x3);

    uint256 public constant INITIAL_IMV = 100;
    uint256 public constant DURATION    = 1000;
    uint256 public constant BAL1        = 1_000;
    uint256 public constant BAL2        = 2_000;
    uint256 public constant TOTAL_SUP   = BAL1 + BAL2;
    
    function setUp() public {
        // Deploy mocks and token
        helper = new MockModelHelper();
        helper.setIMV(INITIAL_IMV);

        token  = new DummyERC20();

        // Prepare holders and balances
        address[] memory holders  = new address[](2);
        holders[0] = HOLDER1;
        holders[1] = HOLDER2;

        uint256[] memory balances = new uint256[](2);
        balances[0] = BAL1;
        balances[1] = BAL2;

        // Deploy migration contract
        migration = new Migration(
            address(helper),
            address(token),
            VAULT,
            INITIAL_IMV,
            DURATION,
            holders,
            balances
        );

        // Fund migration contract
        token.mint(address(migration), TOTAL_SUP);
    }

    function test_constructor_setsState() public {
        assertEq(migration.initialIMV(), INITIAL_IMV);
        assertEq(migration.vault(), VAULT);
        assertEq(migration.migrationEnd(), block.timestamp + DURATION);

        // initial balances
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
        vm.expectRevert(bytes("IMV has not grown"));
        migration.withdraw();
    }

    function test_nonFirstHolder_withdrawsAfterIMVIncrease() public {
        // Increase IMV by 50%
        helper.setIMV((INITIAL_IMV * 150) / 100);

        vm.prank(HOLDER2);
        migration.withdraw();

        uint256 expected = (BAL2 * 50) / 100;
        assertEq(token.balanceOf(HOLDER2), expected);
        assertEq(migration.withdrawnOf(HOLDER2), expected);
        assertEq(migration.totalWithdrawn(), BAL1 + expected);
    }

    function test_nonFirstHolder_withdraws_cappedAt100Percent() public {
        // First, withdraw 50%
        helper.setIMV((INITIAL_IMV * 150) / 100);
        vm.prank(HOLDER2);
        migration.withdraw();

        // Then, IMV jumps to 250% (cap at 100%)
        helper.setIMV((INITIAL_IMV * 250) / 100);

        vm.prank(HOLDER2);
        migration.withdraw();

        // Total should now equal full BAL2
        assertEq(token.balanceOf(HOLDER2), BAL2);
        assertEq(migration.withdrawnOf(HOLDER2), BAL2);
    }

    function test_cannotWithdrawTwiceBeyondAllowed() public {
        helper.setIMV((INITIAL_IMV * 150) / 100);
        vm.prank(HOLDER2);
        migration.withdraw();

        // Second withdraw at same IMV should revert
        vm.prank(HOLDER2);
        vm.expectRevert(bytes("Nothing to withdraw"));
        migration.withdraw();
    }

    function test_cannotWithdrawAfterMigrationEnd() public {
        // Warp past end
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(HOLDER1);
        vm.expectRevert(bytes("Migration ended"));
        migration.withdraw();
    }

    function test_setBalances_onlyOwner() public {
        address[] memory holders  = new address[](1);
        holders[0] = HOLDER1;
        uint256[] memory balances = new uint256[](1);
        balances[0] = BAL1 * 2;

        // Non-owner cannot call
        vm.prank(HOLDER2);
        vm.expectRevert("Ownable: caller is not the owner");
        migration.setBalances(holders, balances);

        // Owner can call
        migration.setBalances(holders, balances);
        assertEq(migration.initialBalanceOf(HOLDER1), BAL1 * 2);
    }

    function test_recoverERC20() public {
        // Mint extra tokens to migration
        token.mint(address(migration), 5e18);
        uint256 before = token.balanceOf(address(this));

        migration.recoverERC20(address(token));
        assertEq(token.balanceOf(address(this)), before + 5e18);
    }
}
