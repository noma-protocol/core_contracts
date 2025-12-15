// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVault} from "../../src/interfaces/IVault.sol";
import {IModelHelper} from "../../src/interfaces/IModelHelper.sol";
import {IsNomaToken} from "../../src/interfaces/IsNomaToken.sol";
import {NomaToken} from "../../src/token/NomaToken.sol";
import {
    LiquidityPosition,
    LiquidityType,
    VaultInfo,
    TokenInfo,
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

    struct Epoch {
        uint256 number;
        uint256 end;
        uint256 distribute;
    }
    function epoch() external view returns (uint256 number, uint256 end, uint256 distribute);
}

interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IIDOHelper {
    function vault() external view returns (address);
    function buyTokens(uint256 price, uint256 amount, uint256 minAmount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
}

interface ITokenRepo {
    function transferToRecipient(address token, address to, uint256 amount) external;
    function owner() external view returns (address);
}

/**
 * @title FuzzSetup
 * @notice Base contract for fuzzing harnesses that connects to deployed contracts on fork
 * @dev Auto-initializes from deployed addresses on forked chain (localhost:8545)
 */
abstract contract FuzzSetup {
    // Core protocol contracts
    IVault public vault;
    IUniswapV3Pool public pool;
    IModelHelper public modelHelper;
    NomaToken public nomaToken;
    IsNomaToken public sNOMA;
    IStaking public staking;
    ITokenRepo public tokenRepo;
    IWETH public weth;
    IIDOHelper public idoHelper;

    // Token addresses
    address public token0;
    address public token1;

    // Actors for multi-user fuzzing
    address[] public actors;
    uint256 public constant NUM_ACTORS = 10;

    // Protocol state tracking
    uint256 public initialTotalSupply;
    uint256 public initialCollateral;
    uint256 public feesToken0Baseline;
    uint256 public feesToken1Baseline;

    // Flag to track initialization
    bool public initialized;

    // ============ DEPLOYED ADDRESSES (from deploy_helper/out/out.json network 1337) ============
    // Update these after each deployment!
    address constant IDO_HELPER = 0x9e2a27D131Cd058e3F335d3E19588aB42141a7eE;
    address constant MODEL_HELPER = 0xF3b32Ce81364dfa3f5A3FC4Dea921cB22bB88a40;
    address constant EXCHANGE_HELPER = 0x2385c19769008181AFD99B5775BE5e877f0Ff70a;
    address constant NOMA_PROXY = 0x387aad63ce4A689647c8E15beC800a45BFD59Bf6;
    address constant FACTORY = 0xA2839bA831284Ea6567B8a6Ab3BA02aaE2b3f147;
    address constant RESOLVER = 0x488eBfab208ADFBf97f98579EC694B82664d6e6B;

    // WETH/WMON address (testnet)
    address constant WETH_ADDRESS = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;

    // Hevm cheatcodes interface for Echidna/Medusa
    address constant HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    constructor() {
        _initializeFromFork();
        _setupActors();
        _recordInitialState();
    }

    /**
     * @notice Initialize contracts from forked chain using hardcoded addresses
     * @dev Automatically derives vault and other addresses from IDOHelper
     */
    function _initializeFromFork() internal virtual {
        // Set WETH
        weth = IWETH(WETH_ADDRESS);

        // Set IDO Helper and derive vault
        idoHelper = IIDOHelper(IDO_HELPER);

        // Get vault address from IDO Helper
        address vaultAddr = idoHelper.vault();
        if (vaultAddr != address(0)) {
            vault = IVault(vaultAddr);
            pool = vault.pool();

            // Get token addresses from pool
            token0 = pool.token0();
            token1 = pool.token1();

            // Set NOMA token (token0)
            nomaToken = NomaToken(token0);

            // Set model helper
            modelHelper = IModelHelper(MODEL_HELPER);

            // Get staking contract from vault
            VaultInfo memory info = vault.getVaultInfo();
            if (info.stakingContract != address(0)) {
                staking = IStaking(info.stakingContract);
                sNOMA = staking.sNOMA();
            }

            // Get protocol addresses for tokenRepo
            ProtocolAddresses memory addrs = vault.getProtocolAddresses();
            // tokenRepo would be accessed via the vault

            initialized = true;
        }
    }

    /**
     * @notice Set vault address and derive all other addresses
     * @param _vault The deployed vault address
     */
    function _setVault(address _vault) internal {
        vault = IVault(_vault);
        pool = vault.pool();

        // Get protocol addresses from vault
        token0 = pool.token0();
        token1 = pool.token1();

        // Get additional addresses
        VaultInfo memory info = vault.getVaultInfo();

        if (info.stakingContract != address(0)) {
            staking = IStaking(info.stakingContract);
            sNOMA = staking.sNOMA();
        }

        nomaToken = NomaToken(token0);

        // Get model helper from protocol addresses
        // modelHelper is typically at a known address
    }

    /**
     * @notice Setup fuzzing actors with funding
     */
    function _setupActors() internal {
        for (uint256 i = 0; i < NUM_ACTORS; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
        }
    }

    /**
     * @notice Record initial protocol state for invariant checking
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
     * @notice Get actor address by index (wraps around)
     */
    function _getActor(uint8 index) internal view returns (address) {
        return actors[index % actors.length];
    }

    /**
     * @notice Bound a value to a range
     */
    function _bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min > max) {
            (min, max) = (max, min);
        }
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }

    /**
     * @notice Fund an actor with ETH
     */
    function _fundWithETH(address actor, uint256 amount) internal {
        // Use hevm.deal or direct transfer
        payable(actor).transfer(amount);
    }

    /**
     * @notice Fund an actor with WETH
     */
    function _fundWithWETH(address actor, uint256 amount) internal {
        weth.deposit{value: amount}();
        weth.transfer(actor, amount);
    }

    /**
     * @notice Calculate solvency - anchorCapacity + floorCapacity vs circulatingSupply
     */
    function _checkSolvency() internal view returns (bool) {
        if (address(vault) == address(0) || address(modelHelper) == address(0)) {
            return true; // Skip if not initialized
        }

        address poolAddr = address(pool);
        address vaultAddr = address(vault);

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(poolAddr, vaultAddr, false);
        if (circulatingSupply == 0) return true;

        uint256 imv = modelHelper.getIntrinsicMinimumValue(vaultAddr);
        if (imv == 0) return true;

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

        return (anchorCapacity + floorCapacity) >= circulatingSupply;
    }

    /**
     * @notice Get all positions
     */
    function _getPositions() internal view returns (LiquidityPosition[3] memory) {
        return vault.getPositions();
    }

    /**
     * @notice Check if positions are valid (non-zero liquidity, contiguous)
     */
    function _positionsValid() internal view returns (bool) {
        if (address(vault) == address(0)) return true;

        LiquidityPosition[3] memory positions = vault.getPositions();

        // All positions should have liquidity > 0
        if (positions[0].liquidity == 0) return false;
        if (positions[1].liquidity == 0) return false;
        if (positions[2].liquidity == 0) return false;

        // Positions should be contiguous: floor.upper == anchor.lower
        if (positions[0].upperTick != positions[1].lowerTick) return false;

        return true;
    }

    // Allow receiving ETH
    receive() external payable {}
}
