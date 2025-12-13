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
    ProtocolParameters,
    CreatorFacingParameters,
    ExistingDeployData,
    Decimals
} from "../src/types/Types.sol";
import "../src/libraries/Utils.sol";
import { ModelHelper } from "../src/model/Helper.sol";
import { AdaptiveSupply } from "../src/controllers/supply/AdaptiveSupply.sol";
import { PresaleFactory } from "../src/factory/PresaleFactory.sol";
import { IVault } from "../src/interfaces/IVault.sol";

struct ContractInfo {
    string name;
    address addr;
}

/// @notice Interface for AuxVault privileged parameter functions
interface IAuxVault {
    function setProtocolParametersCreator(CreatorFacingParameters memory cp) external;
    function setAdvancedConf(bool flag) external;
    function setManager(address manager) external;
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

/// @title PrivilegedParametersTest
/// @notice Tests for privileged vs non-privileged CreatorFacingParameters in AuxVault
/// @dev These tests require a forked environment with Uniswap V3 contracts deployed.
///      Run with: forge test --match-path test/PrivilegedParameters.t.sol --fork-url $RPC_URL
///
///      These tests verify that:
///      - Non-privileged parameters (lowBalanceThresholdFactor, highBalanceThresholdFactor, halfStep)
///        can always be updated by the manager
///      - Privileged parameters (discoveryBips, shiftAnchorUpperBips, slideAnchorUpperBips,
///        inflationFee, loanFee, selfRepayLtvTreshold, shiftRatio) are only updated when
///        isAdvancedConfEnabled is true
///      - Only multisig can toggle isAdvancedConfEnabled via setAdvancedConf()
///      - Only manager can call setProtocolParametersCreator()
contract PrivilegedParametersTest is Test {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    address user = address(0xBEEF);
    address multisig;

    NomaFactory nomaFactory;
    TestResolver resolver;
    EtchVault etchVault;
    VaultUpgrade vaultUpgrade;
    ModelHelper modelHelper;
    AdaptiveSupply adaptiveSupply;
    TokenFactory tokenFactory;
    MockWMON mockWMON;

    // Constants mainnet (used with fork) or mock (local testing)
    address WMON;  // Will be set to mock in setUp
    address private uniswapFactory = 0x204FAca1764B154221e35c0d20aBb3c525710498;
    address private pancakeSwapFactory = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

    ContractInfo[] private expectedAddressesInResolver;

    // Initial protocol parameters for comparison
    ProtocolParameters initialParams;

    function setUp() public {
        vm.prank(deployer);

        // Mock WMON - use mock for local testing
        mockWMON = new MockWMON();
        WMON = address(mockWMON);

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

        // Set a separate multisig address (different from deployer) to properly test authorization
        multisig = address(0xDEAD);
        vm.prank(deployer);  // deployer is current multisig (factory default)
        nomaFactory.setMultiSigAddress(multisig);

        expectedAddressesInResolver.push(
            ContractInfo("NomaFactory", address(nomaFactory))
        );

        vm.prank(deployer);
        etchVault = new EtchVault(address(nomaFactory), address(resolver));
        vaultUpgrade = new VaultUpgrade(deployer, address(nomaFactory));

        // VaultStep1 adds BaseVault (used by preDeployVault)
        VaultInit vaultStep1 = new VaultInit(deployer, address(nomaFactory));

        // VaultUpgradeStep1 adds StakingVault (used by configureVault)
        OriginalVaultUpgradeStep1 vaultUpgradeStep1 = new OriginalVaultUpgradeStep1(deployer, address(nomaFactory));

        VaultUpgradeStep2 vaultUpgradeStep2 = new VaultUpgradeStep2(deployer, address(nomaFactory));
        VaultUpgradeStep3 vaultUpgradeStep3 = new VaultUpgradeStep3(deployer, address(nomaFactory));
        VaultUpgradeStep4 vaultUpgradeStep4 = new VaultUpgradeStep4(deployer, address(nomaFactory));
        VaultUpgradeStep5 vaultUpgradeStep5 = new VaultUpgradeStep5(deployer, address(nomaFactory));

        expectedAddressesInResolver.push(
            ContractInfo("VaultUpgrade", address(vaultUpgrade))
        );

        expectedAddressesInResolver.push(
            ContractInfo("VaultStep1", address(vaultStep1))
        );

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

        expectedAddressesInResolver.push(
            ContractInfo("WMON", WMON)
        );

        vm.prank(deployer);
        configureResolver();

        // Set initial protocol parameters
        initialParams = ProtocolParameters(
            10,         // Floor percentage of total supply
            5,          // Anchor percentage of total supply
            3,          // IDO price multiplier
            [uint16(200), uint16(500)], // Floor bips
            90e16,      // Shift liquidity ratio (shiftRatio)
            120e16,     // Slide liquidity ratio
            25000,      // Discovery deploy bips (discoveryBips)
            10,         // shiftAnchorUpperBips
            300,        // slideAnchorUpperBips
            100,        // lowBalanceThresholdFactor
            100,        // highBalanceThresholdFactor
            5e15,       // inflationFee
            25,         // loanFee
            27,         // maxLoanUtilization
            0.01e18,    // deployFee (ETH)
            25e16,      // presalePremium (25%)
            1_250,      // selfRepayLtvTreshold
            0.5e18,     // Adaptive supply curve half step (halfStep)
            2,          // Skim ratio
            Decimals(6, 18), // Decimals (minDecimals, maxDecimals)
            1e14        // basePriceDecimals
        );

        vm.prank(deployer);
        nomaFactory.setProtocolParameters(initialParams);
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

    function _deployAndConfigureVault() internal returns (address vault, address pool, address proxy) {
        VaultDeployParams memory vaultDeployParams =
        VaultDeployParams(
            "Test Token",
            "TEST",
            18,
            100_000_000e18,
            200_000_000e18,
            1e18,
            0,
            WMON,
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

        vm.prank(deployer);
        nomaFactory.configureVault(vault, 0);
    }

    function _getDefaultCreatorFacingParams() internal view returns (CreatorFacingParameters memory) {
        // Return default params matching the initial protocol parameters
        return CreatorFacingParameters({
            discoveryBips: 25000,
            shiftAnchorUpperBips: 10,
            slideAnchorUpperBips: 300,
            lowBalanceThresholdFactor: 100,
            highBalanceThresholdFactor: 100,
            inflationFee: 5e15,
            loanFee: 25,
            selfRepayLtvTreshold: 1_250,
            halfStep: 0.5e18,
            shiftRatio: 90e16
        });
    }

    // ============ TESTS: NON-PRIVILEGED PARAMETERS ============

    /// @notice Test that non-privileged parameters can be updated by manager when advanced config is disabled
    function testNonPrivilegedParams_UpdateableByManager() public {
        (address vault,,) = _deployAndConfigureVault();

        // Get initial parameters
        ProtocolParameters memory paramsBefore = IVault(vault).getProtocolParameters();

        // Create new parameters with only non-privileged fields changed
        CreatorFacingParameters memory newParams = _getDefaultCreatorFacingParams();
        newParams.lowBalanceThresholdFactor = 200;   // Changed
        newParams.highBalanceThresholdFactor = 250;  // Changed
        newParams.halfStep = 1e18;                   // Changed

        // Manager (deployer) updates parameters - advanced config is disabled by default
        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        // Verify non-privileged parameters were updated
        ProtocolParameters memory paramsAfter = IVault(vault).getProtocolParameters();

        assertEq(paramsAfter.lowBalanceThresholdFactor, 200, "lowBalanceThresholdFactor should be updated");
        assertEq(paramsAfter.highBalanceThresholdFactor, 250, "highBalanceThresholdFactor should be updated");
        assertEq(paramsAfter.halfStep, 1e18, "halfStep should be updated");

        // Verify privileged parameters remained unchanged
        assertEq(paramsAfter.discoveryBips, paramsBefore.discoveryBips, "discoveryBips should not change");
        assertEq(paramsAfter.shiftAnchorUpperBips, paramsBefore.shiftAnchorUpperBips, "shiftAnchorUpperBips should not change");
        assertEq(paramsAfter.slideAnchorUpperBips, paramsBefore.slideAnchorUpperBips, "slideAnchorUpperBips should not change");
        assertEq(paramsAfter.inflationFee, paramsBefore.inflationFee, "inflationFee should not change");
        assertEq(paramsAfter.loanFee, paramsBefore.loanFee, "loanFee should not change");
        assertEq(paramsAfter.selfRepayLtvTreshold, paramsBefore.selfRepayLtvTreshold, "selfRepayLtvTreshold should not change");
        assertEq(paramsAfter.shiftRatio, paramsBefore.shiftRatio, "shiftRatio should not change");
    }

    // ============ TESTS: PRIVILEGED PARAMETERS WHEN DISABLED ============

    /// @notice Test that privileged parameters are ignored when advanced config is disabled
    function testPrivilegedParams_IgnoredWhenDisabled() public {
        (address vault,,) = _deployAndConfigureVault();

        // Get initial parameters
        ProtocolParameters memory paramsBefore = IVault(vault).getProtocolParameters();

        // Try to update privileged parameters (with advanced config disabled)
        CreatorFacingParameters memory newParams = _getDefaultCreatorFacingParams();
        newParams.discoveryBips = 50000;          // Privileged - should be ignored
        newParams.shiftAnchorUpperBips = 50;      // Privileged - should be ignored
        newParams.slideAnchorUpperBips = 500;     // Privileged - should be ignored
        newParams.inflationFee = 10e15;           // Privileged - should be ignored
        newParams.loanFee = 50;                   // Privileged - should be ignored
        newParams.selfRepayLtvTreshold = 2_500;   // Privileged - should be ignored
        newParams.shiftRatio = 95e16;             // Privileged - should be ignored

        // Manager updates parameters - advanced config is disabled
        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        // Verify privileged parameters were NOT updated
        ProtocolParameters memory paramsAfter = IVault(vault).getProtocolParameters();

        assertEq(paramsAfter.discoveryBips, paramsBefore.discoveryBips, "discoveryBips should not be updated when disabled");
        assertEq(paramsAfter.shiftAnchorUpperBips, paramsBefore.shiftAnchorUpperBips, "shiftAnchorUpperBips should not be updated when disabled");
        assertEq(paramsAfter.slideAnchorUpperBips, paramsBefore.slideAnchorUpperBips, "slideAnchorUpperBips should not be updated when disabled");
        assertEq(paramsAfter.inflationFee, paramsBefore.inflationFee, "inflationFee should not be updated when disabled");
        assertEq(paramsAfter.loanFee, paramsBefore.loanFee, "loanFee should not be updated when disabled");
        assertEq(paramsAfter.selfRepayLtvTreshold, paramsBefore.selfRepayLtvTreshold, "selfRepayLtvTreshold should not be updated when disabled");
        assertEq(paramsAfter.shiftRatio, paramsBefore.shiftRatio, "shiftRatio should not be updated when disabled");
    }

    // ============ TESTS: PRIVILEGED PARAMETERS WHEN ENABLED ============

    /// @notice Test that privileged parameters can be updated when advanced config is enabled
    function testPrivilegedParams_UpdateableWhenEnabled() public {
        (address vault,,) = _deployAndConfigureVault();

        // Enable advanced config (only multisig can do this)
        vm.prank(multisig);
        IAuxVault(vault).setAdvancedConf(true);

        // Update privileged parameters
        CreatorFacingParameters memory newParams = CreatorFacingParameters({
            discoveryBips: 50000,          // Privileged
            shiftAnchorUpperBips: 50,      // Privileged
            slideAnchorUpperBips: 500,     // Privileged
            lowBalanceThresholdFactor: 200, // Non-privileged
            highBalanceThresholdFactor: 250, // Non-privileged
            inflationFee: 10e15,           // Privileged
            loanFee: 50,                   // Privileged
            selfRepayLtvTreshold: 2_500,   // Privileged
            halfStep: 1e18,                // Non-privileged
            shiftRatio: 95e16              // Privileged
        });

        // Manager updates parameters - advanced config is now enabled
        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        // Verify ALL parameters were updated
        ProtocolParameters memory paramsAfter = IVault(vault).getProtocolParameters();

        // Non-privileged
        assertEq(paramsAfter.lowBalanceThresholdFactor, 200, "lowBalanceThresholdFactor should be updated");
        assertEq(paramsAfter.highBalanceThresholdFactor, 250, "highBalanceThresholdFactor should be updated");
        assertEq(paramsAfter.halfStep, 1e18, "halfStep should be updated");

        // Privileged
        assertEq(paramsAfter.discoveryBips, 50000, "discoveryBips should be updated when enabled");
        assertEq(paramsAfter.shiftAnchorUpperBips, 50, "shiftAnchorUpperBips should be updated when enabled");
        assertEq(paramsAfter.slideAnchorUpperBips, 500, "slideAnchorUpperBips should be updated when enabled");
        assertEq(paramsAfter.inflationFee, 10e15, "inflationFee should be updated when enabled");
        assertEq(paramsAfter.loanFee, 50, "loanFee should be updated when enabled");
        assertEq(paramsAfter.selfRepayLtvTreshold, 2_500, "selfRepayLtvTreshold should be updated when enabled");
        assertEq(paramsAfter.shiftRatio, 95e16, "shiftRatio should be updated when enabled");
    }

    // ============ TESTS: setAdvancedConf AUTHORIZATION ============

    /// @notice Test that only multisig can call setAdvancedConf
    function testSetAdvancedConf_OnlyMultiSig() public {
        (address vault,,) = _deployAndConfigureVault();

        // Non-multisig (regular user) should not be able to enable advanced config
        vm.prank(user);
        vm.expectRevert();
        IAuxVault(vault).setAdvancedConf(true);

        // Manager (deployer) is different from multisig in this test setup
        // Manager should not be able to enable advanced config
        vm.prank(deployer);
        vm.expectRevert();
        IAuxVault(vault).setAdvancedConf(true);

        // Only multisig can enable advanced config
        vm.prank(multisig);
        IAuxVault(vault).setAdvancedConf(true);
        // No revert means success
    }

    /// @notice Test that multisig can toggle advanced config on and off
    function testSetAdvancedConf_Toggle() public {
        (address vault,,) = _deployAndConfigureVault();

        // Get initial privileged parameter values
        ProtocolParameters memory initialProtocolParams = IVault(vault).getProtocolParameters();
        // Verify initial value is as expected from protocol parameters
        assertEq(initialProtocolParams.discoveryBips, 25000, "Initial discoveryBips should be 25000");

        // Enable advanced config
        vm.prank(multisig);
        IAuxVault(vault).setAdvancedConf(true);

        // Update privileged parameter
        CreatorFacingParameters memory newParams = _getDefaultCreatorFacingParams();
        newParams.discoveryBips = 60000;

        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        // Verify it was updated
        ProtocolParameters memory paramsAfterEnable = IVault(vault).getProtocolParameters();
        assertEq(paramsAfterEnable.discoveryBips, 60000, "discoveryBips should be updated when enabled");

        // Disable advanced config
        vm.prank(multisig);
        IAuxVault(vault).setAdvancedConf(false);

        // Try to update privileged parameter again
        newParams.discoveryBips = 70000;

        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        // Verify it was NOT updated (should stay at 60000)
        ProtocolParameters memory paramsAfterDisable = IVault(vault).getProtocolParameters();
        assertEq(paramsAfterDisable.discoveryBips, 60000, "discoveryBips should not change when disabled");
    }

    // ============ TESTS: setProtocolParametersCreator AUTHORIZATION ============

    /// @notice Test that only manager can call setProtocolParametersCreator
    function testSetProtocolParametersCreator_OnlyManager() public {
        (address vault,,) = _deployAndConfigureVault();

        CreatorFacingParameters memory newParams = _getDefaultCreatorFacingParams();
        newParams.lowBalanceThresholdFactor = 300;

        // Non-manager (regular user) should not be able to update parameters
        vm.prank(user);
        vm.expectRevert();
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        // Manager (deployer) can update parameters
        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(newParams);
        // No revert means success

        // Verify it was updated
        ProtocolParameters memory paramsAfter = IVault(vault).getProtocolParameters();
        assertEq(paramsAfter.lowBalanceThresholdFactor, 300, "Manager should be able to update non-privileged params");
    }

    /// @notice Test that manager can be changed and new manager can update parameters
    function testSetManager_NewManagerCanUpdateParams() public {
        (address vault,,) = _deployAndConfigureVault();

        address newManager = address(0xCAFE);

        // Change manager (can be done by manager or multisig)
        vm.prank(deployer);
        IAuxVault(vault).setManager(newManager);

        // Old manager (deployer) should no longer be able to update parameters
        CreatorFacingParameters memory newParams = _getDefaultCreatorFacingParams();
        newParams.lowBalanceThresholdFactor = 400;

        vm.prank(deployer);
        vm.expectRevert();
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        // New manager can update parameters
        vm.prank(newManager);
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        // Verify it was updated
        ProtocolParameters memory paramsAfter = IVault(vault).getProtocolParameters();
        assertEq(paramsAfter.lowBalanceThresholdFactor, 400, "New manager should be able to update params");
    }

    // ============ TESTS: EDGE CASES ============

    /// @notice Test updating only non-privileged params when trying to update all params with advanced config disabled
    function testMixedParams_OnlyNonPrivilegedUpdated() public {
        (address vault,,) = _deployAndConfigureVault();

        ProtocolParameters memory paramsBefore = IVault(vault).getProtocolParameters();

        // Try to update ALL parameters (both privileged and non-privileged)
        CreatorFacingParameters memory newParams = CreatorFacingParameters({
            discoveryBips: 99999,               // Privileged - should be ignored
            shiftAnchorUpperBips: 999,          // Privileged - should be ignored
            slideAnchorUpperBips: 999,          // Privileged - should be ignored
            lowBalanceThresholdFactor: 999,     // Non-privileged - should be updated
            highBalanceThresholdFactor: 888,    // Non-privileged - should be updated
            inflationFee: 99e15,                // Privileged - should be ignored
            loanFee: 99,                        // Privileged - should be ignored
            selfRepayLtvTreshold: 9999,         // Privileged - should be ignored
            halfStep: 2e18,                     // Non-privileged - should be updated
            shiftRatio: 99e16                   // Privileged - should be ignored
        });

        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(newParams);

        ProtocolParameters memory paramsAfter = IVault(vault).getProtocolParameters();

        // Non-privileged should be updated
        assertEq(paramsAfter.lowBalanceThresholdFactor, 999, "lowBalanceThresholdFactor should be updated");
        assertEq(paramsAfter.highBalanceThresholdFactor, 888, "highBalanceThresholdFactor should be updated");
        assertEq(paramsAfter.halfStep, 2e18, "halfStep should be updated");

        // Privileged should remain unchanged
        assertEq(paramsAfter.discoveryBips, paramsBefore.discoveryBips, "discoveryBips should remain unchanged");
        assertEq(paramsAfter.shiftAnchorUpperBips, paramsBefore.shiftAnchorUpperBips, "shiftAnchorUpperBips should remain unchanged");
        assertEq(paramsAfter.slideAnchorUpperBips, paramsBefore.slideAnchorUpperBips, "slideAnchorUpperBips should remain unchanged");
        assertEq(paramsAfter.inflationFee, paramsBefore.inflationFee, "inflationFee should remain unchanged");
        assertEq(paramsAfter.loanFee, paramsBefore.loanFee, "loanFee should remain unchanged");
        assertEq(paramsAfter.selfRepayLtvTreshold, paramsBefore.selfRepayLtvTreshold, "selfRepayLtvTreshold should remain unchanged");
        assertEq(paramsAfter.shiftRatio, paramsBefore.shiftRatio, "shiftRatio should remain unchanged");
    }

    /// @notice Test that enabling advanced config allows all privileged params to be updated individually
    function testPrivilegedParams_IndividualUpdate() public {
        (address vault,,) = _deployAndConfigureVault();

        // Enable advanced config
        vm.prank(multisig);
        IAuxVault(vault).setAdvancedConf(true);

        // Test updating each privileged parameter individually
        CreatorFacingParameters memory params = _getDefaultCreatorFacingParams();

        // Update discoveryBips only
        params.discoveryBips = 30000;
        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(params);

        ProtocolParameters memory result = IVault(vault).getProtocolParameters();
        assertEq(result.discoveryBips, 30000, "discoveryBips should be updated");

        // Update shiftRatio only
        params.shiftRatio = 85e16;
        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(params);

        result = IVault(vault).getProtocolParameters();
        assertEq(result.shiftRatio, 85e16, "shiftRatio should be updated");

        // Update inflationFee only
        params.inflationFee = 7e15;
        vm.prank(deployer);
        IAuxVault(vault).setProtocolParametersCreator(params);

        result = IVault(vault).getProtocolParameters();
        assertEq(result.inflationFee, 7e15, "inflationFee should be updated");
    }

    receive() external payable {}
}
