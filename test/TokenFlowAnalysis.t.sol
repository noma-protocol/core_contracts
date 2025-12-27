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
import {Conversions} from "../src/libraries/Conversions.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {Underlying} from "../src/libraries/Underlying.sol";
import {LiquidityType, LiquidityPosition, ProtocolAddresses} from "../src/types/Types.sol";

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

/// @title TokenFlowAnalysis
/// @notice Analyzes where tokens go during shift operations
contract TokenFlowAnalysisTest is Test {
    using stdJson for string;

    IVault vault;
    IERC20 token0;
    IERC20 token1;
    NomaToken noma;
    ModelHelper modelHelper;

    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bool isMainnet = vm.envOr("DEPLOY_FLAG_MAINNET", false);

    address constant WMON_MAINNET = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant WMON_TESTNET = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address WMON;
    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;
    address pool;
    address stakingContract;

    IDOManager managerContract;

    function setUp() public {
        WMON = isMainnet ? WMON_MAINNET : WMON_TESTNET;

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));
        modelHelperContract = vm.parseJsonAddress(json, string.concat(".", networkId, ".ModelHelper"));

        managerContract = IDOManager(idoManager);
        noma = NomaToken(nomaToken);
        vaultAddress = address(managerContract.vault());

        ProtocolAddresses memory protocolAddrs = IVault(vaultAddress).getProtocolAddresses();
        modelHelper = ModelHelper(protocolAddrs.modelHelper);

        vault = IVault(vaultAddress);
        IUniswapV3Pool poolContract = vault.pool();
        pool = address(poolContract);

        token0 = IERC20(poolContract.token0());
        token1 = IERC20(poolContract.token1());
        stakingContract = vault.getStakingContract();
    }

    function testAnalyzeTokenDistribution() public view {
        console.log("\n=== Token Distribution Analysis ===\n");

        _logPositionBalances();
        _logOtherBalances();
        _logCapacityCheck();
    }

    function _logPositionBalances() internal view {
        LiquidityPosition[3] memory positions = vault.getPositions();
        uint256 totalSupply = noma.totalSupply();

        // Get underlying balances in each position
        (,, uint256 floorToken0, ) = Underlying.getUnderlyingBalances(pool, vaultAddress, positions[0]);
        (,, uint256 anchorToken0, ) = Underlying.getUnderlyingBalances(pool, vaultAddress, positions[1]);
        (,, uint256 discoveryToken0, ) = Underlying.getUnderlyingBalances(pool, vaultAddress, positions[2]);

        console.log("=== Token0 (NOMA) Distribution ===");
        console.log("Total Supply:          ", totalSupply);
        console.log("");
        console.log("--- In Positions ---");
        console.log("Floor Position:        ", floorToken0);
        console.log("Anchor Position:       ", anchorToken0);
        console.log("Discovery Position:    ", discoveryToken0);
        console.log("Total in Positions:    ", floorToken0 + anchorToken0 + discoveryToken0);
    }

    function _logOtherBalances() internal view {
        uint256 vaultBalance = noma.balanceOf(vaultAddress);
        uint256 poolBalance = noma.balanceOf(pool);
        uint256 stakingBalance = stakingContract != address(0) ? noma.balanceOf(stakingContract) : 0;
        uint256 collateral = vault.getCollateralAmount();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vaultAddress, true);

        console.log("");
        console.log("--- Other Protocol Balances ---");
        console.log("Vault Balance:         ", vaultBalance);
        console.log("Staking Contract:      ", stakingBalance);
        console.log("Collateral:            ", collateral);
        console.log("Pool Balance:          ", poolBalance);
        console.log("");
        console.log("Circulating Supply:    ", circulatingSupply);
    }

    function _logCapacityCheck() internal view {
        LiquidityPosition[3] memory positions = vault.getPositions();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vaultAddress, true);

        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, vaultAddress, positions[1], LiquidityType.Anchor);
        uint256 floorCapacity = modelHelper.getPositionCapacity(pool, vaultAddress, positions[0], LiquidityType.Floor);

        console.log("\n=== Capacity vs Circulating ===");
        console.log("Anchor Capacity:   ", anchorCapacity);
        console.log("Floor Capacity:    ", floorCapacity);
        console.log("Total Capacity:    ", anchorCapacity + floorCapacity);
        console.log("Circulating:       ", circulatingSupply);

        if (anchorCapacity + floorCapacity < circulatingSupply) {
            console.log("*** INSOLVENCY ***");
            console.log("Shortfall:        ", circulatingSupply - (anchorCapacity + floorCapacity));
        }
    }

    function testFindMajorHolders() public view {
        console.log("\n=== Finding Token Holders ===\n");

        uint256 totalSupply = noma.totalSupply();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vaultAddress, true);

        // Check known addresses
        address[] memory knownAddresses = new address[](6);
        string[] memory names = new string[](6);

        knownAddresses[0] = vaultAddress;
        names[0] = "Vault";

        knownAddresses[1] = pool;
        names[1] = "Pool";

        knownAddresses[2] = stakingContract;
        names[2] = "Staking";

        knownAddresses[3] = idoManager;
        names[3] = "IDOManager";

        knownAddresses[4] = deployer;
        names[4] = "Deployer";

        knownAddresses[5] = address(this);
        names[5] = "TestContract";

        console.log("Total Supply:      ", totalSupply);
        console.log("Circulating:       ", circulatingSupply);
        console.log("");

        uint256 totalChecked = 0;
        for (uint i = 0; i < knownAddresses.length; i++) {
            if (knownAddresses[i] != address(0)) {
                uint256 balance = noma.balanceOf(knownAddresses[i]);
                if (balance > 0) {
                    console.log(names[i], ":", balance);
                    totalChecked += balance;
                }
            }
        }

        console.log("");
        console.log("Total in known:    ", totalChecked);
        console.log("Remaining:         ", totalSupply - totalChecked);
    }

    receive() external payable {}
}
