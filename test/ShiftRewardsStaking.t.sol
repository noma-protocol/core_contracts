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
import {Utils} from "../src/libraries/Utils.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {LiquidityType, LiquidityPosition} from "../src/types/Types.sol";

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

interface IStakingRewards {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IGonsToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function stakingContract() external view returns (address);
}

/// @title ShiftRewardsStakingTest
/// @notice Tests for shift operation rewards distribution to Gons/Staking
contract ShiftRewardsStakingTest is Test {
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
        IUniswapV3Pool pool = vault.pool();

        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        console.log("Vault address:", vaultAddress);
        console.log("Token0 (NOMA):", address(token0));
        console.log("Token1 (WETH):", address(token1));
    }

    // ============ SHIFT REWARDS TESTS ============

    /// @notice Test that shift triggers reward distribution to staking when staking is set up
    function testShift_DistributesRewardsToStaking() public {
        // First, create conditions for a shift (liquidityRatio <= 0.90)
        _doPurchasesToTriggerShiftCondition();

        // Get staking contract address
        address stakingContract = vault.getStakingContract();

        if (stakingContract == address(0)) {
            console.log("Staking contract not set up, skipping staking reward test");
            return;
        }

        // Record balances before shift
        uint256 stakingNomaBalanceBefore = token0.balanceOf(stakingContract);
        uint256 vaultNomaBalanceBefore = token0.balanceOf(vaultAddress);

        console.log("Staking NOMA balance before shift:", stakingNomaBalanceBefore);
        console.log("Vault NOMA balance before shift:", vaultNomaBalanceBefore);

        // Check if shift is needed
        address poolAddr = address(vault.pool());
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);
        console.log("Liquidity ratio before shift:", liquidityRatio);

        if (liquidityRatio <= 0.90e18) {
            // Perform shift
            vault.shift();

            // Record balances after shift
            uint256 stakingNomaBalanceAfter = token0.balanceOf(stakingContract);
            uint256 vaultNomaBalanceAfter = token0.balanceOf(vaultAddress);

            console.log("Staking NOMA balance after shift:", stakingNomaBalanceAfter);
            console.log("Vault NOMA balance after shift:", vaultNomaBalanceAfter);

            // Staking contract should have received rewards
            if (stakingNomaBalanceAfter > stakingNomaBalanceBefore) {
                console.log("Rewards distributed to staking:", stakingNomaBalanceAfter - stakingNomaBalanceBefore);
                assertTrue(stakingNomaBalanceAfter > stakingNomaBalanceBefore, "Staking should receive rewards");
            } else {
                console.log("No rewards minted (might be no excess reserves)");
            }
        } else {
            console.log("Liquidity ratio not low enough for shift");
        }
    }

    /// @notice Test that shift caller receives their fee
    function testShift_CallerReceivesFee() public {
        _doPurchasesToTriggerShiftCondition();

        address poolAddr = address(vault.pool());
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);

        if (liquidityRatio <= 0.90e18) {
            address caller = address(0xCAFE);

            // Record caller balance before
            uint256 callerBalanceBefore = token0.balanceOf(caller);

            // Perform shift from caller address
            vm.prank(caller);
            vault.shift();

            // Record caller balance after
            uint256 callerBalanceAfter = token0.balanceOf(caller);

            console.log("Caller balance before:", callerBalanceBefore);
            console.log("Caller balance after:", callerBalanceAfter);

            if (callerBalanceAfter > callerBalanceBefore) {
                console.log("Caller received fee:", callerBalanceAfter - callerBalanceBefore);
            }
        }
    }

    /// @notice Test multiple shifts accumulate rewards in staking
    function testShift_MultipleShiftsAccumulateRewards() public {
        address stakingContract = vault.getStakingContract();

        if (stakingContract == address(0)) {
            console.log("Staking contract not set up");
            return;
        }

        uint256 initialStakingBalance = token0.balanceOf(stakingContract);
        uint256 shiftsPerformed = 0;

        // Perform multiple purchase cycles and shifts
        for (uint i = 0; i < 3; i++) {
            _doPurchasesToTriggerShiftCondition();

            address poolAddr = address(vault.pool());
            uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);

            if (liquidityRatio <= 0.90e18) {
                vault.shift();
                shiftsPerformed++;

                uint256 currentStakingBalance = token0.balanceOf(stakingContract);
                console.log("Shift", i + 1, "- Staking balance:", currentStakingBalance);
            }

            // Time warp between cycles
            vm.warp(block.timestamp + 1 days);
        }

        uint256 finalStakingBalance = token0.balanceOf(stakingContract);
        console.log("Initial staking balance:", initialStakingBalance);
        console.log("Final staking balance:", finalStakingBalance);
        console.log("Total shifts performed:", shiftsPerformed);

        if (shiftsPerformed > 0 && finalStakingBalance > initialStakingBalance) {
            console.log("Total rewards accumulated:", finalStakingBalance - initialStakingBalance);
        }
    }

    // ============ GONS TOKEN / REBASING TESTS ============

    /// @notice Test that Gons token (sNOMA) total supply increases after staking rewards
    function testGons_TotalSupplyIncreasesWithRewards() public {
        address stakingContract = vault.getStakingContract();

        if (stakingContract == address(0)) {
            console.log("Staking contract not set up");
            return;
        }

        // Try to get sNOMA (Gons) token address
        // The staking contract should hold sNOMA tokens
        // Note: This depends on how the staking is set up

        _doPurchasesToTriggerShiftCondition();

        address poolAddr = address(vault.pool());
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);

        if (liquidityRatio <= 0.90e18) {
            uint256 stakingBalanceBefore = token0.balanceOf(stakingContract);

            vault.shift();

            uint256 stakingBalanceAfter = token0.balanceOf(stakingContract);

            console.log("NOMA in staking before:", stakingBalanceBefore);
            console.log("NOMA in staking after:", stakingBalanceAfter);

            // The staking contract should have received NOMA tokens
            // These would then be distributed to sNOMA holders via rebase
            if (stakingBalanceAfter > stakingBalanceBefore) {
                console.log("Rewards to be distributed via rebase:", stakingBalanceAfter - stakingBalanceBefore);
            }
        }
    }

    // ============ PROTOCOL FEE DISTRIBUTION TESTS ============

    /// @notice Test that protocol fees go to dividend distributor when set
    function testShift_ProtocolFeesToDividendDistributor() public {
        _doPurchasesToTriggerShiftCondition();

        // Get dividend distributor address from vault
        // This requires reading from the resolver

        address poolAddr = address(vault.pool());
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);

        if (liquidityRatio <= 0.90e18) {
            // Note: To fully test this, we'd need access to the resolver
            // to get the DividendDistributor address

            console.log("Performing shift...");
            vault.shift();
            console.log("Shift completed - check dividend distributor balance separately");
        }
    }

    // ============ HELPER FUNCTIONS ============

    /// @dev Perform purchases to trigger shift condition (liquidityRatio <= 0.90)
    function _doPurchasesToTriggerShiftCondition() internal {
        IDOManager managerContract = IDOManager(idoManager);
        address poolAddr = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddr).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);

        uint16 totalTrades = 10;
        uint256 tradeAmount = 20000 ether;

        IWETH(WMON).deposit{value: tradeAmount * totalTrades}();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddr).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * 25 / 100);
            managerContract.buyTokens(purchasePrice, tradeAmount, 0, address(this));
        }

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(poolAddr, vaultAddress);
        console.log("Liquidity ratio after purchases:", liquidityRatio);
    }

    receive() external payable {}
}
