// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVault} from "../../src/interfaces/IVault.sol";
import {IModelHelper} from "../../src/interfaces/IModelHelper.sol";
import {IsNomaToken} from "../../src/interfaces/IsNomaToken.sol";
import {NomaToken} from "../../src/token/NomaToken.sol";
import {GonsToken} from "../../src/token/Gons.sol";
import {
    LiquidityPosition,
    LiquidityType,
    VaultInfo,
    ProtocolAddresses
} from "../../src/types/Types.sol";
import {DecimalMath} from "../../src/libraries/DecimalMath.sol";
import {Underlying} from "../../src/libraries/Underlying.sol";

interface IStaking {
    function NOMA() external view returns (IERC20);
    function sNOMA() external view returns (IsNomaToken);
    function vault() external view returns (address);
    function totalStaked() external view returns (uint256);
    function totalRewards() external view returns (uint256);
    function totalEpochs() external view returns (uint256);
    function stakedBalance(address user) external view returns (uint256);
    function lastOperationTimestamp(address user) external view returns (uint256);
    function stakedEpochs(address user) external view returns (uint256);
    function lockInEpochs() external view returns (uint256);
    function stake(uint256 amount) external;
    function unstake() external;
    function notifyRewardAmount(uint256 reward) external;
    function epoch() external view returns (uint256 number, uint256 end, uint256 distribute);
}

interface IIDOHelper {
    function vault() external view returns (address);
    function buyTokens(uint256 price, uint256 amount, uint256 minAmount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
}

interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * @title FuzzBase
 * @notice Base contract for Foundry invariant testing - reads addresses from JSON like existing tests
 */
abstract contract FuzzBase is Test {
    using stdJson for string;

    // Environment config
    uint256 public privateKey;
    address public deployer;
    bool public isMainnet;
    string public networkId;

    // Protocol contracts
    IVault public vault;
    IUniswapV3Pool public pool;
    IModelHelper public modelHelper;
    NomaToken public nomaToken;
    IsNomaToken public sNOMA;
    GonsToken public gonsToken;
    IStaking public staking;
    IIDOHelper public idoHelper;
    IWETH public weth;

    // Token addresses
    address public token0;
    address public token1;

    // Network-specific addresses
    address constant WMON_MAINNET = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant WMON_TESTNET = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;

    // Fuzzing actors
    address[] public actors;
    uint256 public constant NUM_ACTORS = 10;

    // State tracking
    uint256 public initialTotalSupply;
    uint256 public initialCollateral;
    uint256 public feesToken0Baseline;
    uint256 public feesToken1Baseline;

    function setUp() public virtual {
        _loadEnvironment();
        _loadDeployedAddresses();
        _setupActors();
        _recordInitialState();
    }

    /**
     * @notice Load environment variables like existing tests
     */
    function _loadEnvironment() internal {
        privateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.envAddress("DEPLOYER");
        isMainnet = vm.envOr("DEPLOY_FLAG_MAINNET", false);
        networkId = "1337"; // Local fork

        // Set WETH based on network
        weth = IWETH(isMainnet ? WMON_MAINNET : WMON_TESTNET);
    }

    /**
     * @notice Load deployed addresses from JSON file (same as existing tests)
     */
    function _loadDeployedAddresses() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");
        string memory json = vm.readFile(path);

        // Parse addresses from JSON
        address idoHelperAddr = vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper"));
        address modelHelperAddr = vm.parseJsonAddress(json, string.concat(".", networkId, ".ModelHelper"));

        require(idoHelperAddr != address(0), "IDOHelper not found in JSON");
        require(modelHelperAddr != address(0), "ModelHelper not found in JSON");

        // Set IDO Helper and derive vault
        idoHelper = IIDOHelper(idoHelperAddr);
        modelHelper = IModelHelper(modelHelperAddr);

        // Get vault from IDO Helper
        address vaultAddr = idoHelper.vault();
        require(vaultAddr != address(0), "Vault address is zero");

        vault = IVault(vaultAddr);
        pool = vault.pool();

        // Get token addresses
        token0 = pool.token0();
        token1 = pool.token1();

        // Set NOMA token (token0)
        nomaToken = NomaToken(token0);

        // Get staking info from vault
        VaultInfo memory info = vault.getVaultInfo();
        if (info.stakingContract != address(0)) {
            staking = IStaking(info.stakingContract);
            sNOMA = staking.sNOMA();
            gonsToken = GonsToken(address(sNOMA));
        }

        // Log loaded addresses
        console.log("Loaded addresses:");
        console.log("  IDOHelper:", idoHelperAddr);
        console.log("  Vault:", vaultAddr);
        console.log("  Pool:", address(pool));
        console.log("  Token0 (NOMA):", token0);
        console.log("  Staking:", info.stakingContract);
    }

    /**
     * @notice Setup fuzzing actors with initial balances
     */
    function _setupActors() internal {
        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            address actor = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(actor);

            // Fund actors with ETH
            vm.deal(actor, 100 ether);
        }
    }

    /**
     * @notice Record initial protocol state
     */
    function _recordInitialState() internal {
        if (address(nomaToken) != address(0)) {
            initialTotalSupply = nomaToken.totalSupply();
        }
        if (address(vault) != address(0)) {
            initialCollateral = vault.getCollateralAmount();
            (feesToken0Baseline, feesToken1Baseline) = vault.getAccumulatedFees();
        }
    }

    /**
     * @notice Get actor by index
     */
    function _getActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /**
     * @notice Fund actor with WETH
     */
    function _fundWithWETH(address actor, uint256 amount) internal {
        vm.deal(address(this), amount);
        weth.deposit{value: amount}();
        weth.transfer(actor, amount);
    }

    /**
     * @notice Fund actor with NOMA tokens
     */
    function _fundWithNOMA(address actor, uint256 amount) internal {
        // Try to transfer from deployer or IDO helper
        uint256 balance = nomaToken.balanceOf(address(idoHelper));
        if (balance >= amount) {
            vm.prank(address(idoHelper));
            nomaToken.transfer(actor, amount);
        }
    }

    // ==================== INVARIANT HELPERS ====================

    /**
     * @notice Check solvency invariant
     */
    function _checkSolvency() public view returns (bool, string memory) {
        if (address(vault) == address(0) || address(modelHelper) == address(0)) {
            return (true, "Not initialized");
        }

        address poolAddr = address(pool);
        address vaultAddr = address(vault);

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(poolAddr, vaultAddr, false);
        if (circulatingSupply == 0) return (true, "No circulating supply");

        uint256 imv = modelHelper.getIntrinsicMinimumValue(vaultAddr);
        if (imv == 0) return (true, "No IMV");

        LiquidityPosition[3] memory positions = vault.getPositions();

        uint256 anchorCapacity = modelHelper.getPositionCapacity(
            poolAddr,
            vaultAddr,
            positions[1],
            LiquidityType.Anchor
        );

        (,,, uint256 floorBalance) = modelHelper.getUnderlyingBalances(
            poolAddr,
            vaultAddr,
            LiquidityType.Floor
        );

        uint256 floorCapacity = DecimalMath.divideDecimal(floorBalance, imv);
        uint256 totalCapacity = anchorCapacity + floorCapacity;

        if (totalCapacity >= circulatingSupply) {
            return (true, "Solvent");
        } else {
            return (false, string.concat(
                "Insolvent: capacity=", vm.toString(totalCapacity),
                " < circulating=", vm.toString(circulatingSupply)
            ));
        }
    }

    /**
     * @notice Check position validity
     */
    function _checkPositions() public view returns (bool, string memory) {
        if (address(vault) == address(0)) return (true, "Not initialized");

        LiquidityPosition[3] memory positions = vault.getPositions();

        if (positions[0].liquidity == 0) return (false, "Floor has no liquidity");
        if (positions[1].liquidity == 0) return (false, "Anchor has no liquidity");
        if (positions[2].liquidity == 0) return (false, "Discovery has no liquidity");

        if (positions[0].upperTick != positions[1].lowerTick) {
            return (false, "Positions not contiguous");
        }

        return (true, "Valid");
    }

    receive() external payable {}
}
