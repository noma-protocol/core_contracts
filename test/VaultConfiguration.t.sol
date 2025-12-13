// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { NomaFactory } from "../src/factory/NomaFactory.sol";
import { TestResolver } from "./resolver/Resolver.sol";
import { DeployerFactory } from "../src/factory/DeployerFactory.sol";
import { ExtFactory } from "../src/factory/ExtFactory.sol";
import { EtchVault } from "../src/vault/deploy/EtchVault.sol";
import { TokenFactory } from "../src/factory/TokenFactory.sol";
import { VaultInit } from "../src/vault/init/VaultInit.sol";
import {
    VaultUpgrade,
    VaultUpgradeStep1 as OriginalVaultUpgradeStep1,
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
    ExistingDeployData,
    Decimals,
    LiquidityPosition,
    VaultInfo
} from "../src/types/Types.sol";
import "../src/libraries/Utils.sol";
import { ModelHelper } from "../src/model/Helper.sol";
import { AdaptiveSupply } from "../src/controllers/supply/AdaptiveSupply.sol";
import { PresaleFactory } from "../src/factory/PresaleFactory.sol";
import { IVault } from "../src/interfaces/IVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";

struct ContractInfo {
    string name;
    address addr;
}

interface IVaultConfiguration {
    function stakingEnabled() external view returns (bool);
    function getStakingContract() external view returns (address);
    function initialized() external view returns (bool);
    function shift() external;
    function slide() external;
    function borrow(uint256 borrowAmount, uint256 duration) external;
    function getPositions() external view returns (LiquidityPosition[3] memory);
}

interface IStaking {
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
}

/// @notice Mock WETH/WMON token for testing
contract MockWMON {
    string public name = "Wrapped MON";
    string public symbol = "WMON";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @title VaultConfigurationTest
/// @notice Tests that vault functions require configureVault to be called after deployVault
/// @dev These tests require a forked environment with Uniswap V3 contracts deployed.
///      Run with: forge test --match-path test/VaultConfiguration.t.sol --fork-url $RPC_URL
contract VaultConfigurationTest is Test {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bool isMainnet = vm.envOr("DEPLOY_FLAG_MAINNET", false);

    address user = address(0xBEEF);

    NomaFactory nomaFactory;
    TestResolver resolver;
    EtchVault etchVault;
    VaultUpgrade vaultUpgrade;
    ModelHelper modelHelper;
    AdaptiveSupply adaptiveSupply;
    TokenFactory tokenFactory;
    MockWMON mockWMON;

    // Mainnet addresses
    address constant WMON_MAINNET = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant UNISWAP_FACTORY_MAINNET = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address constant PANCAKESWAP_FACTORY_MAINNET = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    // Testnet addresses
    address constant WMON_TESTNET = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address constant UNISWAP_FACTORY_TESTNET = 0x961235a9020B05C44DF1026D956D1F4D78014276;
    address constant PANCAKESWAP_FACTORY_TESTNET = 0x3b7838D96Fc18AD1972aFa17574686be79C50040;
    // Select based on environment
    address WMON;
    address testWMON;
    address private uniswapFactory;
    address private pancakeSwapFactory;

    ContractInfo[] private expectedAddressesInResolver;

    function setUp() public {
        // Set addresses based on mainnet/testnet flag
        WMON = isMainnet ? WMON_MAINNET : WMON_TESTNET;
        uniswapFactory = isMainnet ? UNISWAP_FACTORY_MAINNET : UNISWAP_FACTORY_TESTNET;
        pancakeSwapFactory = isMainnet ? PANCAKESWAP_FACTORY_MAINNET : PANCAKESWAP_FACTORY_TESTNET;

        vm.prank(deployer);

        // Mock WMON
        mockWMON = new MockWMON();
        testWMON = address(mockWMON);

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
        PresaleFactory presaleFactory = new PresaleFactory(address(resolver));

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

        expectedAddressesInResolver.push(
            ContractInfo("NomaFactory", address(nomaFactory))
        );

        vm.prank(deployer);
        etchVault = new EtchVault(address(nomaFactory), address(resolver));
        vaultUpgrade = new VaultUpgrade(deployer, address(nomaFactory));

        // VaultStep1 adds BaseVault (used by preDeployVault)
        VaultInit vaultStep1 = new VaultInit(deployer, address(nomaFactory));

        // VaultUpgradeStep1 adds StakingVault (used by configureVault)
        // This is different from VaultStep1!
        OriginalVaultUpgradeStep1 vaultUpgradeStep1 = new OriginalVaultUpgradeStep1(deployer, address(nomaFactory));

        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer, address(nomaFactory));
        VaultUpgradeStep3 vaultUpgradeStep3 = new VaultUpgradeStep3(deployer, address(nomaFactory));
        VaultUpgradeStep4 vaultUpgradeStep4 = new VaultUpgradeStep4(deployer, address(nomaFactory));
        VaultUpgradeStep5 vaultUpgradeStep5 = new VaultUpgradeStep5(deployer, address(nomaFactory));

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgrade", address(vaultUpgrade))
        );

        // VaultStep1 is used by preDeployVault - adds BaseVault
        expectedAddressesInResolver.push(
            ContractInfo("VaultStep1", address(vaultStep1))
        );

        // VaultUpgradeStep1 is used by configureVault - adds StakingVault
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

        // Use real WMON address (test requires fork)
        expectedAddressesInResolver.push(
            ContractInfo("WMON", WMON)
        );

        vm.prank(deployer);
        configureResolver();

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
            25e16,      // presalePremium (25%)
            1_250,      // self repaying loan ltv treshold
            0.5e18,     // Adaptive supply curve half step
            2,          // Skim ratio
            Decimals(6, 18), // Decimals (minDecimals, maxDecimals)
            1e14        // basePriceDecimals
        );

        vm.prank(deployer);
        nomaFactory.setProtocolParameters(_params);
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

    function _deployVaultOnly() internal returns (address vault, address pool, address proxy) {
        VaultDeployParams memory vaultDeployParams =
        VaultDeployParams(
            "Test Token",
            "TEST",
            18,
            100_000_000e18,
            200_000_000e18,
            1e18,
            0,
            WMON,  // Use real WMON (test requires fork)
            3000,
            0,
            true,
            true
        );

        PresaleUserParams memory presaleParams =
        PresaleUserParams(
            100e18,
            90 days
        );

        vm.prank(deployer);
        (vault, pool, proxy) = nomaFactory.deployVault(
            presaleParams,
            vaultDeployParams,
            ExistingDeployData({
                pool: address(0),
                token0: address(0)
            })
        );
    }

    function _deployAndConfigureVault() internal returns (address vault, address pool, address proxy) {
        (vault, pool, proxy) = _deployVaultOnly();

        vm.prank(deployer);
        nomaFactory.configureVault(vault, 0);
    }

    // ============ TESTS: BEFORE configureVault ============

    /// @notice Test that stakingContract is not set before configureVault
    function testBeforeConfig_StakingContractNotSet() public {
        (address vault,,) = _deployVaultOnly();

        address stakingContract = IVaultConfiguration(vault).getStakingContract();
        assertEq(stakingContract, address(0), "Staking contract should be address(0) before configureVault");
    }

    /// @notice Test that stakingEnabled() doesn't exist before configureVault
    function testBeforeConfig_StakingNotEnabled() public {
        (address vault,,) = _deployVaultOnly();

        // stakingEnabled() function doesn't exist in diamond before configureVault
        vm.expectRevert("Diamond: Function does not exist");
        IVaultConfiguration(vault).stakingEnabled();
    }

    /// @notice Test that vault is not initialized before configureVault
    function testBeforeConfig_NotInitialized() public {
        (address vault,,) = _deployVaultOnly();

        // Check initialized state through vault info
        VaultInfo memory info = IVault(vault).getVaultInfo();
        assertFalse(info.initialized, "Vault should not be initialized before configureVault");
    }

    /// @notice Test that shift reverts before configureVault (NotInitialized)
    function testBeforeConfig_ShiftReverts() public {
        (address vault,,) = _deployVaultOnly();

        // Shift should revert because vault is not initialized
        vm.expectRevert();
        IVaultConfiguration(vault).shift();
    }

    /// @notice Test that slide reverts before configureVault (NotInitialized)
    function testBeforeConfig_SlideReverts() public {
        (address vault,,) = _deployVaultOnly();

        // Slide should revert because vault is not initialized
        vm.expectRevert();
        IVaultConfiguration(vault).slide();
    }

    /// @notice Test that borrow reverts before configureVault
    function testBeforeConfig_BorrowReverts() public {
        (address vault,,) = _deployVaultOnly();

        // Get some tokens first (would need to buy through presale/IDO)
        // For this test, we just verify it reverts
        vm.prank(user);
        vm.expectRevert();
        IVaultConfiguration(vault).borrow(1 ether, 30 days);
    }

    // ============ TESTS: AFTER configureVault ============

    /// @notice Test that stakingContract is set after configureVault
    function testAfterConfig_StakingContractSet() public {
        (address vault,,) = _deployAndConfigureVault();

        address stakingContract = IVaultConfiguration(vault).getStakingContract();
        assertTrue(stakingContract != address(0), "Staking contract should be set after configureVault");
        console.log("Staking contract:", stakingContract);
    }

    /// @notice Test that staking is enabled after configureVault
    function testAfterConfig_StakingEnabled() public {
        (address vault,,) = _deployAndConfigureVault();

        bool stakingEnabled = IVaultConfiguration(vault).stakingEnabled();
        assertTrue(stakingEnabled, "Staking should be enabled after configureVault");
    }

    /// @notice Test that vault is initialized after configureVault
    function testAfterConfig_Initialized() public {
        (address vault,,) = _deployAndConfigureVault();

        VaultInfo memory info = IVault(vault).getVaultInfo();
        assertTrue(info.initialized, "Vault should be initialized after configureVault");
    }

    /// @notice Test that floor position has liquidity after configureVault
    function testAfterConfig_FloorPositionHasLiquidity() public {
        (address vault,,) = _deployAndConfigureVault();

        LiquidityPosition[3] memory positions = IVaultConfiguration(vault).getPositions();
        LiquidityPosition memory floorPos = positions[0];
        assertGt(floorPos.liquidity, 0, "Floor position should have liquidity after configureVault");
        console.log("Floor liquidity:", floorPos.liquidity);
    }

    // ============ TESTS: configureVault AUTHORIZATION ============

    /// @notice Test that only deployer can call configureVault
    function testConfigureVault_OnlyDeployer() public {
        (address vault,,) = _deployVaultOnly();

        // Non-deployer should not be able to call configureVault
        vm.prank(user);
        vm.expectRevert();
        nomaFactory.configureVault(vault, 0);
    }

    /// @notice Test that configureVault can only be called once
    function testConfigureVault_OnlyOnce() public {
        (address vault,,) = _deployAndConfigureVault();

        // Second call should revert (already initialized)
        vm.prank(deployer);
        vm.expectRevert();
        nomaFactory.configureVault(vault, 0);
    }

    // ============ TESTS: FULL FLOW ============

    /// @notice Test complete flow: deploy -> verify not working -> configure -> verify working
    function testFullFlow_DeployConfigureVerify() public {
        // Step 1: Deploy vault
        (address vault, address pool,) = _deployVaultOnly();

        console.log("Step 1: Vault deployed at", vault);
        console.log("Pool:", pool);

        // Step 2: Verify functions don't exist before configureVault
        // stakingEnabled() doesn't exist in diamond yet
        (bool success,) = vault.staticcall(abi.encodeWithSignature("stakingEnabled()"));
        assertFalse(success, "stakingEnabled() should not exist before config");

        // getStakingContract() should return address(0) if it exists
        address stakingContract = IVaultConfiguration(vault).getStakingContract();
        assertEq(stakingContract, address(0), "Staking contract should be 0 before config");

        console.log("Step 2: Verified vault is not configured");

        // Step 3: Configure vault
        vm.prank(deployer);
        nomaFactory.configureVault(vault, 0);

        console.log("Step 3: Vault configured");

        // Step 4: Verify functions now work
        assertTrue(IVaultConfiguration(vault).stakingEnabled(), "Staking should be enabled after config");
        assertTrue(IVaultConfiguration(vault).getStakingContract() != address(0), "Staking contract should be set after config");

        VaultInfo memory infoAfter = IVault(vault).getVaultInfo();
        assertTrue(infoAfter.initialized, "Should be initialized after config");

        // Verify liquidity positions are set
        LiquidityPosition[3] memory positions = IVaultConfiguration(vault).getPositions();
        LiquidityPosition memory floorPos = positions[0];
        assertGt(floorPos.liquidity, 0, "Floor should have liquidity after config");

        console.log("Step 4: Verified vault is fully configured");
        console.log("  - Staking enabled:", IVaultConfiguration(vault).stakingEnabled());
        console.log("  - Staking contract:", IVaultConfiguration(vault).getStakingContract());
        console.log("  - Floor liquidity:", floorPos.liquidity);
    }

    receive() external payable {}
}
