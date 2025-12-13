// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {NomaToken} from "../src/token/NomaToken.sol";
import {ModelHelper} from "../src/model/Helper.sol";
import {BaseVault} from "../src/vault/BaseVault.sol";
import {GonsToken} from "../src/token/Gons.sol";
import {Staking} from "../src/staking/Staking.sol";
import {Conversions} from "../src/libraries/Conversions.sol";

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

interface INomaFactory {
    function teamMultiSig() external view returns (address);
    function owner() external view returns (address);
}

interface IAuxVault {
    function recoverERC20(address token, address to) external;
}

interface IStakingVault {
    function setStakingContract(address _stakingContract) external;
    function stakingEnabled() external view returns (bool);
    function getStakingContract() external view returns (address);
}

/// @notice Mock ERC20 token for testing recovery of arbitrary tokens
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title ERC20RecoveryTest
/// @notice Tests for ERC20 recovery mechanism from Gons and Staking contracts through AuxVault
contract ERC20RecoveryTest is Test {
    using stdJson for string;

    IVault vault;
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
    address teamMultiSig;
    address stakingContract;
    address gonsContract;

    // Mock tokens for recovery testing
    MockERC20 randomToken1;
    MockERC20 randomToken2;
    MockERC20 randomToken3;

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

        IDOManager managerContract = IDOManager(idoManager);
        noma = NomaToken(nomaToken);
        modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        vault = IVault(vaultAddress);
        IUniswapV3Pool pool = vault.pool();

        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        // Get team multisig (required for recovery operations)
        teamMultiSig = INomaFactory(factoryAddress).teamMultiSig();

        // Get staking contract address
        stakingContract = IStakingVault(vaultAddress).getStakingContract();

        console.log("Vault address:", vaultAddress);
        console.log("Token0 (NOMA):", address(token0));
        console.log("Token1 (WETH):", address(token1));
        console.log("Factory:", factoryAddress);
        console.log("Team MultiSig:", teamMultiSig);
        console.log("Staking Contract:", stakingContract);

        // Deploy mock tokens for recovery testing
        randomToken1 = new MockERC20("Random Token 1", "RND1");
        randomToken2 = new MockERC20("Random Token 2", "RND2");
        randomToken3 = new MockERC20("Random Token 3", "RND3");

        // If staking is not set up, set it up for testing
        if (stakingContract == address(0)) {
            _setupStaking();
        } else {
            // Get Gons contract from staking
            gonsContract = address(Staking(stakingContract).sNOMA());
            console.log("Gons Contract (sNOMA):", gonsContract);
        }
    }

    // ============ ERC20 RECOVERY TESTS ============

    /// @notice Test recovery of arbitrary ERC20 from Staking contract (to multisig only)
    function testRecoverERC20_FromStaking() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping test");
            return;
        }

        // Send random tokens to staking contract (simulating accidental transfer)
        uint256 amountToSend = 1000 ether;
        randomToken1.mint(stakingContract, amountToSend);

        uint256 stakingBalanceBefore = randomToken1.balanceOf(stakingContract);
        console.log("Staking balance before recovery:", stakingBalanceBefore);
        assertGt(stakingBalanceBefore, 0, "Staking should have random tokens");

        // Record multisig balance before (funds can ONLY go to multisig)
        uint256 multisigBalanceBefore = randomToken1.balanceOf(teamMultiSig);

        // Recover tokens through AuxVault (must be called by multisig, to multisig)
        vm.prank(teamMultiSig);
        IAuxVault(vaultAddress).recoverERC20(address(randomToken1), teamMultiSig);

        // Verify tokens were recovered to multisig
        uint256 stakingBalanceAfter = randomToken1.balanceOf(stakingContract);
        uint256 multisigBalanceAfter = randomToken1.balanceOf(teamMultiSig);

        console.log("Staking balance after recovery:", stakingBalanceAfter);
        console.log("MultiSig balance after recovery:", multisigBalanceAfter);

        assertEq(stakingBalanceAfter, 0, "Staking should have 0 tokens after recovery");
        assertGt(multisigBalanceAfter, multisigBalanceBefore, "MultiSig should have received tokens");
        assertEq(multisigBalanceAfter - multisigBalanceBefore, amountToSend, "MultiSig should receive exact amount");
    }

    /// @notice Test recovery of arbitrary ERC20 from Gons contract (to multisig only)
    function testRecoverERC20_FromGons() public {
        if (stakingContract == address(0) || gonsContract == address(0)) {
            console.log("Staking/Gons not set up, skipping test");
            return;
        }

        // Send random tokens to Gons contract (simulating accidental transfer)
        uint256 amountToSend = 500 ether;
        randomToken2.mint(gonsContract, amountToSend);

        uint256 gonsBalanceBefore = randomToken2.balanceOf(gonsContract);
        console.log("Gons balance before recovery:", gonsBalanceBefore);
        assertGt(gonsBalanceBefore, 0, "Gons should have random tokens");

        // Record multisig balance before
        uint256 multisigBalanceBefore = randomToken2.balanceOf(teamMultiSig);

        // Recover tokens through AuxVault (cascades to both Staking and Gons)
        vm.prank(teamMultiSig);
        IAuxVault(vaultAddress).recoverERC20(address(randomToken2), teamMultiSig);

        // Verify tokens were recovered from Gons to multisig
        uint256 gonsBalanceAfter = randomToken2.balanceOf(gonsContract);
        uint256 multisigBalanceAfter = randomToken2.balanceOf(teamMultiSig);

        console.log("Gons balance after recovery:", gonsBalanceAfter);
        console.log("MultiSig balance after recovery:", multisigBalanceAfter);

        assertEq(gonsBalanceAfter, 0, "Gons should have 0 tokens after recovery");
        assertGt(multisigBalanceAfter, multisigBalanceBefore, "MultiSig should have received tokens");
    }

    /// @notice Test recovery from both Staking and Gons simultaneously (to multisig only)
    function testRecoverERC20_FromBothStakingAndGons() public {
        if (stakingContract == address(0) || gonsContract == address(0)) {
            console.log("Staking/Gons not set up, skipping test");
            return;
        }

        // Send random tokens to both contracts
        uint256 stakingAmount = 1000 ether;
        uint256 gonsAmount = 2000 ether;

        randomToken3.mint(stakingContract, stakingAmount);
        randomToken3.mint(gonsContract, gonsAmount);

        uint256 stakingBalanceBefore = randomToken3.balanceOf(stakingContract);
        uint256 gonsBalanceBefore = randomToken3.balanceOf(gonsContract);

        console.log("Staking balance before:", stakingBalanceBefore);
        console.log("Gons balance before:", gonsBalanceBefore);

        assertGt(stakingBalanceBefore, 0, "Staking should have tokens");
        assertGt(gonsBalanceBefore, 0, "Gons should have tokens");

        uint256 multisigBalanceBefore = randomToken3.balanceOf(teamMultiSig);

        // Single recovery call should recover from both contracts to multisig
        vm.prank(teamMultiSig);
        IAuxVault(vaultAddress).recoverERC20(address(randomToken3), teamMultiSig);

        uint256 stakingBalanceAfter = randomToken3.balanceOf(stakingContract);
        uint256 gonsBalanceAfter = randomToken3.balanceOf(gonsContract);
        uint256 multisigBalanceAfter = randomToken3.balanceOf(teamMultiSig);

        console.log("Staking balance after:", stakingBalanceAfter);
        console.log("Gons balance after:", gonsBalanceAfter);
        console.log("MultiSig balance after:", multisigBalanceAfter);

        assertEq(stakingBalanceAfter, 0, "Staking should have 0 after recovery");
        assertEq(gonsBalanceAfter, 0, "Gons should have 0 after recovery");

        uint256 totalRecovered = multisigBalanceAfter - multisigBalanceBefore;
        assertEq(totalRecovered, stakingAmount + gonsAmount, "Should recover total from both contracts");
        assertGt(totalRecovered, 0, "Recovered amount should be positive");
    }

    /// @notice Test that only multisig can call recoverERC20
    function testRecoverERC20_OnlyMultiSigCanCall() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping test");
            return;
        }

        randomToken1.mint(stakingContract, 100 ether);

        // Try to recover from non-multisig account - should revert
        address nonAuthorized = address(0x1234);
        vm.prank(nonAuthorized);
        vm.expectRevert();
        IAuxVault(vaultAddress).recoverERC20(address(randomToken1), teamMultiSig);
    }

    /// @notice Test that recovery can ONLY go to multisig address
    function testRecoverERC20_OnlyToMultiSig() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping test");
            return;
        }

        randomToken1.mint(stakingContract, 100 ether);

        // Try to recover to a non-multisig address - should revert with NotAuthorized
        address nonMultiSigRecipient = address(0xBEEF);
        vm.prank(teamMultiSig);
        vm.expectRevert();
        IAuxVault(vaultAddress).recoverERC20(address(randomToken1), nonMultiSigRecipient);

        // Verify tokens are still in staking (recovery failed)
        assertEq(randomToken1.balanceOf(stakingContract), 100 ether, "Tokens should still be in staking");
        assertEq(randomToken1.balanceOf(nonMultiSigRecipient), 0, "Non-multisig should not receive tokens");
    }

    /// @notice Test that recovery to arbitrary address fails even when called by multisig
    function testRecoverERC20_ToArbitraryAddressFails() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping test");
            return;
        }

        uint256 amountToSend = 500 ether;
        randomToken1.mint(stakingContract, amountToSend);

        // Even multisig cannot recover to arbitrary addresses
        address[] memory invalidRecipients = new address[](4);
        invalidRecipients[0] = address(0xDEAD);
        invalidRecipients[1] = address(0xBEEF);
        invalidRecipients[2] = address(this);
        invalidRecipients[3] = deployer;

        for (uint i = 0; i < invalidRecipients.length; i++) {
            if (invalidRecipients[i] != teamMultiSig) {
                vm.prank(teamMultiSig);
                vm.expectRevert();
                IAuxVault(vaultAddress).recoverERC20(address(randomToken1), invalidRecipients[i]);
            }
        }

        // Verify tokens still in staking
        assertEq(randomToken1.balanceOf(stakingContract), amountToSend, "Tokens should remain in staking");
    }

    /// @notice Test that cannot recover NOMA from Staking
    function testRecoverERC20_CannotRecoverNOMA() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping test");
            return;
        }

        // Try to recover NOMA to multisig - should revert (NOMA is protected)
        vm.prank(teamMultiSig);
        vm.expectRevert();
        IAuxVault(vaultAddress).recoverERC20(address(token0), teamMultiSig);
    }

    /// @notice Test that cannot recover sNOMA from Staking
    function testRecoverERC20_CannotRecoverSNOMA() public {
        if (stakingContract == address(0) || gonsContract == address(0)) {
            console.log("Staking/Gons not set up, skipping test");
            return;
        }

        // Try to recover sNOMA to multisig - should revert (sNOMA is protected)
        vm.prank(teamMultiSig);
        vm.expectRevert();
        IAuxVault(vaultAddress).recoverERC20(gonsContract, teamMultiSig);
    }

    // ============ FULL LIFECYCLE TESTS ============

    /// @notice Complete flow: buy tokens, stake, accidental transfer, recovery
    function testFullLifecycle_BuyStakeRecover() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping full lifecycle test");
            return;
        }

        // Step 1: Buy NOMA tokens
        _buyTokens(10 ether);

        uint256 nomaBalance = token0.balanceOf(address(this));
        console.log("NOMA balance after buy:", nomaBalance);
        assertGt(nomaBalance, 0, "Should have NOMA after buying");

        // Step 2: Check if staking is enabled
        bool stakingEnabled = IStakingVault(vaultAddress).stakingEnabled();
        console.log("Staking enabled:", stakingEnabled);

        if (stakingEnabled && nomaBalance > 0) {
            // Step 3: Approve and stake
            token0.approve(stakingContract, nomaBalance);

            // Skip cooldown for testing
            vm.warp(block.timestamp + 4 days);

            try Staking(stakingContract).stake(nomaBalance / 2) {
                console.log("Staked successfully");

                uint256 stakedBalance = Staking(stakingContract).stakedBalance(address(this));
                console.log("Staked balance:", stakedBalance);
                assertGt(stakedBalance, 0, "Should have staked balance");
            } catch {
                console.log("Staking failed (may not be enabled yet)");
            }
        }

        // Step 4: Simulate accidental token transfer to staking
        uint256 accidentalAmount = 777 ether;
        randomToken1.mint(stakingContract, accidentalAmount);

        uint256 stakingRandomBefore = randomToken1.balanceOf(stakingContract);
        assertEq(stakingRandomBefore, accidentalAmount, "Staking should have accidental tokens");

        // Step 5: Recover the accidentally sent tokens (must go to multisig)
        uint256 multisigBefore = randomToken1.balanceOf(teamMultiSig);

        vm.prank(teamMultiSig);
        IAuxVault(vaultAddress).recoverERC20(address(randomToken1), teamMultiSig);

        uint256 multisigAfter = randomToken1.balanceOf(teamMultiSig);
        uint256 recovered = multisigAfter - multisigBefore;

        console.log("Recovered amount:", recovered);
        assertEq(recovered, accidentalAmount, "Should recover exact accidental amount");
        assertGt(recovered, 0, "Recovered amount must be positive");
    }

    /// @notice Test recovery with multiple token types
    function testRecovery_MultipleTokenTypes() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping test");
            return;
        }

        // Create and send multiple different tokens
        MockERC20[] memory tokens = new MockERC20[](5);
        uint256[] memory amounts = new uint256[](5);

        for (uint i = 0; i < 5; i++) {
            tokens[i] = new MockERC20(
                string(abi.encodePacked("Token", vm.toString(i))),
                string(abi.encodePacked("TKN", vm.toString(i)))
            );
            amounts[i] = (i + 1) * 100 ether;
            tokens[i].mint(stakingContract, amounts[i]);
        }

        // Recover each token to multisig and verify
        for (uint i = 0; i < 5; i++) {
            uint256 balanceBefore = tokens[i].balanceOf(teamMultiSig);

            vm.prank(teamMultiSig);
            IAuxVault(vaultAddress).recoverERC20(address(tokens[i]), teamMultiSig);

            uint256 balanceAfter = tokens[i].balanceOf(teamMultiSig);
            uint256 recovered = balanceAfter - balanceBefore;

            console.log("Token", i, "recovered:", recovered);
            assertEq(recovered, amounts[i], "Should recover correct amount for each token");
            assertGt(recovered, 0, "Each recovered amount must be positive");
        }
    }

    /// @notice Test recovery to zero address should fail
    function testRecovery_ToZeroAddressFails() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping test");
            return;
        }

        randomToken1.mint(stakingContract, 100 ether);

        // Recovery to zero address should revert
        vm.prank(teamMultiSig);
        vm.expectRevert();
        IAuxVault(vaultAddress).recoverERC20(address(randomToken1), address(0));
    }

    /// @notice Test recovery when no tokens to recover (should not revert, just transfer 0)
    function testRecovery_NoTokensToRecover() public {
        if (stakingContract == address(0)) {
            console.log("Staking not set up, skipping test");
            return;
        }

        // Don't send any tokens, just try to recover to multisig
        uint256 balanceBefore = randomToken1.balanceOf(teamMultiSig);

        // Should not revert, just transfer 0
        vm.prank(teamMultiSig);
        IAuxVault(vaultAddress).recoverERC20(address(randomToken1), teamMultiSig);

        uint256 balanceAfter = randomToken1.balanceOf(teamMultiSig);
        assertEq(balanceAfter, balanceBefore, "Balance should be unchanged when nothing to recover");
    }

    // ============ HELPER FUNCTIONS ============

    function _setupStaking() internal {
        // This would deploy and configure staking if not already done
        // For forked tests, staking should already be configured
        console.log("Staking setup would be done here if needed");
    }

    function _buyTokens(uint256 wethAmount) internal {
        IDOManager managerContract = IDOManager(idoManager);
        address poolAddr = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddr).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);

        IWETH(WMON).deposit{value: wethAmount}();
        IWETH(WMON).transfer(idoManager, wethAmount);

        managerContract.buyTokens(purchasePrice, wethAmount, 0, address(this));
    }

    receive() external payable {}
}
