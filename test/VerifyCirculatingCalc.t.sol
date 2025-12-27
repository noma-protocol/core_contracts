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
import {Underlying} from "../src/libraries/Underlying.sol";
import {LiquidityType, LiquidityPosition, ProtocolAddresses} from "../src/types/Types.sol";

interface IDOManager {
    function vault() external view returns (BaseVault);
}

/// @title VerifyCirculatingCalc
/// @notice Manually verify the circulating supply calculation
contract VerifyCirculatingCalcTest is Test {
    using stdJson for string;

    IVault vault;
    NomaToken noma;
    ModelHelper modelHelper;

    bool isMainnet = vm.envOr("DEPLOY_FLAG_MAINNET", false);
    address constant WMON_MAINNET = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address constant WMON_TESTNET = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address WMON;
    address payable idoManager;
    address vaultAddress;
    address pool;
    address stakingContract;

    function setUp() public {
        WMON = isMainnet ? WMON_MAINNET : WMON_TESTNET;
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        address nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));

        IDOManager managerContract = IDOManager(idoManager);
        noma = NomaToken(nomaToken);
        vaultAddress = address(managerContract.vault());

        ProtocolAddresses memory protocolAddrs = IVault(vaultAddress).getProtocolAddresses();
        modelHelper = ModelHelper(protocolAddrs.modelHelper);

        vault = IVault(vaultAddress);
        pool = address(vault.pool());
        stakingContract = vault.getStakingContract();
    }

    function testManualCirculatingCalc() public view {
        console.log("\n=== Manual Circulating Supply Calculation ===\n");

        LiquidityPosition[3] memory positions = vault.getPositions();

        // Get values exactly as getCirculatingSupply does
        uint256 totalSupply = ERC20(address(IUniswapV3Pool(pool).token0())).totalSupply();

        (,, uint256 amount0CurrentFloor, ) = Underlying.getUnderlyingBalances(pool, vaultAddress, positions[0]);
        (,, uint256 amount0CurrentAnchor, ) = Underlying.getUnderlyingBalances(pool, vaultAddress, positions[1]);
        (,, uint256 amount0CurrentDiscovery, ) = Underlying.getUnderlyingBalances(pool, vaultAddress, positions[2]);

        uint256 protocolUnusedBalanceToken0 = ERC20(address(IUniswapV3Pool(pool).token0())).balanceOf(vaultAddress);

        uint256 collateralAmount = vault.getCollateralAmount();

        // Get fees (simplified - just the floor position for now)
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        console.log("=== Components ===");
        console.log("totalSupply:               ", totalSupply);
        console.log("amount0CurrentFloor:       ", amount0CurrentFloor);
        console.log("amount0CurrentAnchor:      ", amount0CurrentAnchor);
        console.log("amount0CurrentDiscovery:   ", amount0CurrentDiscovery);
        console.log("protocolUnusedBalanceToken0:", protocolUnusedBalanceToken0);
        console.log("collateralAmount:          ", collateralAmount);
        console.log("stakingContract:           ", stakingContract);

        if (stakingContract != address(0)) {
            uint256 stakingBalance = ERC20(address(IUniswapV3Pool(pool).token0())).balanceOf(stakingContract);
            console.log("stakingBalance:            ", stakingBalance);
        }

        // Manual calculation (without fees for simplicity)
        uint256 subtracted = amount0CurrentFloor + amount0CurrentAnchor + amount0CurrentDiscovery + protocolUnusedBalanceToken0 + collateralAmount;
        uint256 manualCirculating = totalSupply - subtracted;

        console.log("\n=== Calculation ===");
        console.log("Total subtracted (no fees/staking):", subtracted);
        console.log("Manual circulating:                ", manualCirculating);

        // Get the actual value from ModelHelper
        uint256 helperCirculating = modelHelper.getCirculatingSupply(pool, vaultAddress, false);
        console.log("ModelHelper circulating:           ", helperCirculating);

        // Check the difference
        if (manualCirculating > helperCirculating) {
            console.log("Difference (manual > helper):     ", manualCirculating - helperCirculating);
            console.log("This is likely the fees being subtracted");
        } else if (helperCirculating > manualCirculating) {
            console.log("Difference (helper > manual):     ", helperCirculating - manualCirculating);
            console.log("*** SOMETHING IS NOT BEING SUBTRACTED ***");
        }

        // Let's also check: what if we include staking?
        uint256 helperCirculatingWithStaking = modelHelper.getCirculatingSupply(pool, vaultAddress, true);
        console.log("\nWith staking included:");
        console.log("ModelHelper circulating (staked):  ", helperCirculatingWithStaking);

        if (stakingContract != address(0)) {
            uint256 stakingBalance = ERC20(address(IUniswapV3Pool(pool).token0())).balanceOf(stakingContract);
            console.log("Expected diff (staking balance):  ", stakingBalance);
            console.log("Actual diff:                      ", helperCirculating - helperCirculatingWithStaking);
        }
    }

    receive() external payable {}
}
