// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {NomaToken} from  "../src/token/NomaToken.sol";
import {ModelHelper} from  "../src/model/Helper.sol";
import {BaseVault} from  "../src/vault/BaseVault.sol";
import {AuxVault} from  "../src/vault/AuxVault.sol";
import {Utils} from "../src/libraries/Utils.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
import {Underlying } from  "../src/libraries/Underlying.sol";
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

interface IExtVault {
    function addCollateral(uint256 amount) external;
}

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

contract LendingVaultTest is Test {
    using stdJson for string;

    IVault vault;
    IERC20 token0;
    IERC20 token1;

    uint256 MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 SECONDS_IN_DAY = 86400;

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

        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);
        string memory networkId = "1337";

        // Parse individual fields to avoid struct ordering issues
        idoManager = payable(vm.parseJsonAddress(json, string.concat(".", networkId, ".IDOHelper")));
        nomaToken = vm.parseJsonAddress(json, string.concat(".", networkId, ".Proxy"));
        modelHelperContract = vm.parseJsonAddress(json, string.concat(".", networkId, ".ModelHelper"));

        // Log parsed addresses for verification
        console2.log("Model Helper Address:", modelHelperContract);

        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        noma = NomaToken(nomaToken);
        require(address(noma) != address(0), "Noma token address is zero");
        
        modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        console.log("Vault address is: ", vaultAddress);

        // Initialize the existing vault contract
        vault = IVault(vaultAddress);
        IUniswapV3Pool pool = vault.pool();

        token0 = IERC20(pool.token0());  
        token1 = IERC20(pool.token1());    

        testLargePurchaseTriggerShift();  
    }

    function testBorrow() public {
        uint256 borrowAmount = 1 ether;
        uint256 duration = 30 days;

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);

        uint256 allowance              = token0.allowance(deployer, vaultAddress);
        uint256 balanceBeforeToken0    = token0.balanceOf(deployer);
        uint256 balanceBeforeToken1    = token1.balanceOf(deployer); 

        vm.prank(deployer);
        vault.borrow(borrowAmount, duration);

        uint256 balanceAfterToken0     = token0.balanceOf(deployer);
        uint256 balanceAfterToken1     = token1.balanceOf(deployer);

        // 1) Deployer received token0 from the vault (loan)
        assertGt(balanceAfterToken1, balanceBeforeToken1);

        // uint256 receivedToken0 = balanceAfterToken0 - balanceBeforeToken0;

        // If you have a fee formula, enforce exact amount:
        // uint256 fees = calculateLoanFees(borrowAmount, duration);
        // assertEq(receivedToken0, borrowAmount - fees);

        // 2) (Optional) If token1 is used as collateral, ensure it went down
        // and didn't exceed allowance.
        // This requires approving token1, not token0, as collateral.
        // uint256 spentToken1 = balanceBeforeToken1 - balanceAfterToken1;
        // assertGt(spentToken1, 0);              // some collateral was taken
        // assertLe(spentToken1, allowanceToken1); // did not exceed allowance
    }

    // function testPaybackLoan() public {
    //     testBorrow();

    //     uint256 borrowAmount = 1 ether;

    //     // Pay back part of the loan
    //     vm.prank(deployer);
    //     token1.approve(vaultAddress, MAX_INT);

    //     vm.prank(deployer);
    //     IWETH(WMON).deposit{ value: borrowAmount}();

    //     uint256 token1Balance = token1.balanceOf(deployer);
    //     console.log("Token1 balance before payback is: ", token1Balance);
        
    //     vm.prank(deployer);
    //     vault.payback(borrowAmount);
 
    //     assertEq(token1Balance - borrowAmount, token1.balanceOf(deployer));
    // }    

    function testRollLoan() public {
        uint256 borrowAmount = 1 ether;
        uint256 duration = 30 days;
        uint256 newDuration = 60 days;

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);

        uint256 allowance              = token0.allowance(deployer, vaultAddress);
        uint256 balanceBeforeToken0    = token0.balanceOf(deployer);
        uint256 balanceBeforeToken1    = token1.balanceOf(deployer); 

        vm.prank(deployer);
        vault.borrow(borrowAmount, duration);

        // Add more collateral so that collateralValue > borrowAmount, enabling roll
        // Note: removed testLargePurchaseTriggerShift() call because shift() triggers
        // vaultSelfRepayLoans() which repays the deployer's loan
        uint256 additionalCollateral = 100 ether;
        vm.prank(deployer);
        IExtVault(vaultAddress).addCollateral(additionalCollateral);

        uint256 balanceAfterBorrowToken1 = token1.balanceOf(deployer);

        // After borrow, deployer should have received token1 (minus fees)
        assertGt(balanceAfterBorrowToken1, balanceBeforeToken1, "Should receive token1 from borrow");

        vm.prank(deployer);
        vault.roll(duration);

        uint256 balanceAfterRollToken1 = token1.balanceOf(deployer);

        // After roll, deployer should have received additional token1 (new borrow amount)
        assertGt(balanceAfterRollToken1, balanceAfterBorrowToken1, "Should receive additional token1 from roll");
    }    

    function testRollLoanShouldFail() public {
        uint256 borrowAmount = 5 ether;
        uint256 duration = 30 days;
        uint256 newDuration = 10 days;

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);

        // Borrow first
        vm.prank(deployer);
        vault.borrow(borrowAmount, duration);
        
        uint256 balanceBeforePaybackToken1 = token1.balanceOf(deployer);
        uint256 balanceBeforePaybackToken0 = token0.balanceOf(deployer);

        vm.prank(deployer);

        vm.expectRevert();
        vault.roll(newDuration);
    }
    


    function testRollLoanShouldFailMoreThan30Days() public {
        uint256 borrowAmount = 5 ether;
        uint256 duration = 30 days;
        uint256 newDuration = 90 days;

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);

        // Borrow first
        vm.prank(deployer);
        vault.borrow(borrowAmount, duration);
        
        uint256 balanceBeforePaybackToken1 = token1.balanceOf(deployer);
        uint256 balanceBeforePaybackToken0 = token0.balanceOf(deployer);

        vm.prank(deployer);

        vm.expectRevert();
        vault.roll(newDuration);
    }
    

    function testLargePurchaseTriggerShift() public {
        IDOManager managerContract = IDOManager(idoManager);
        IVault vault = IVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 25 / 100);

        uint16 totalTrades = 10;
        uint256 tradeAmount = 20000 ether;

        IWETH(WMON).deposit{ value: (tradeAmount * totalTrades)}();
        IWETH(WMON).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault), false);
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * 25 / 100);
            // if (i >= 4) {
                spotPrice = purchasePrice;
            // }
            managerContract.buyTokens(spotPrice, tradeAmount, 0, address(this));
        }
        
        uint256 nextFloorPrice = getNextFloorPrice(pool, address(vault));
        console.log("Next floor price is: ", nextFloorPrice);

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio < 0.90e18) {
            console.log("Attempt to shift positions");
            IVault(address(vault)).shift();
            nextFloorPrice = getNextFloorPrice(pool, address(vault));
            console.log("Next floor price (after shift) is: ", nextFloorPrice);
            solvencyInvariant();
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "no shift triggered: ", 
                        Utils._uint2str(liquidityRatio)
                    )
                )
            );
        }
    }
    
    // function testDefaultLoans_ExpiredLoanThenPaybackReverts() public {
    //     uint256 borrowAmount = 1 ether;
    //     uint256 duration = 30 days;

    //     // Approve collateral and borrow
    //     vm.prank(deployer);
    //     token0.approve(vaultAddress, MAX_INT);
    //     vm.prank(deployer);
    //     vault.borrow(borrowAmount, duration);

    //     // Move past due date
    //     vm.warp(block.timestamp + duration + 1);

    //     // Anyone can trigger defaults (if authorization is required, swap to the allowed caller)
    //     vault.defaultLoans();

    //     // Attempt to repay after default should revert
    //     vm.prank(deployer);
    //     token1.approve(vaultAddress, MAX_INT);

    //     vm.prank(deployer);
    //     IWETH(WMON).deposit{ value: borrowAmount }();

    //     vm.prank(deployer);
    //     vm.expectRevert(); // loan should no longer be repayable once defaulted
    //     vault.payback(borrowAmount);
    // }

    // function testDefaultLoans_HealthyLoanUnaffected() public {
    //     uint256 borrowAmount = 1 ether;
    //     uint256 duration = 30 days;

    //     // Approve collateral and borrow
    //     vm.prank(deployer);
    //     token0.approve(vaultAddress, MAX_INT);
    //     vm.prank(deployer);
    //     vault.borrow(borrowAmount, duration);

    //     // Run defaults BEFORE maturity — should be a no-op for this loan
    //     vm.warp(block.timestamp + 1 days);
    //     vault.defaultLoans();

    //     // Repay a partial amount should still succeed
    //     uint256 repay = 0.1 ether;

    //     vm.prank(deployer);
    //     token1.approve(vaultAddress, MAX_INT);

    //     vm.prank(deployer);
    //     IWETH(WMON).deposit{ value: repay }();

    //     uint256 balBefore = token1.balanceOf(deployer);

    //     vm.prank(deployer);
    //     vault.payback(repay);

    //     assertEq(balBefore - repay, token1.balanceOf(deployer), "repay should deduct token1");
    // }

    function getNextFloorPrice(address pool, address vault) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault, false);
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, vault, positions[1], LiquidityType.Anchor);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, vault, positions[0]);

        return DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
    }

    function calculateLoanFees(
        uint256 borrowAmount,
        uint256 duration
    ) internal view returns (uint256 fees) {
        uint256 SECONDS_IN_DAY = 86400;
        // daily rate = 0.027% -> 27 / 100_000
        uint256 daysElapsed = duration / SECONDS_IN_DAY;
        fees = (borrowAmount * 27 * daysElapsed) / 100_000;
    }

    function solvencyInvariant() public view {
        IDOManager managerContract = IDOManager(idoManager);
        AuxVault vault = AuxVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault), false);
        console.log("Circulating supply is: ", circulatingSupply);

        uint256 intrinsicMinimumValue = modelHelper.getIntrinsicMinimumValue(address(vault));
        
        LiquidityPosition[3] memory positions =  BaseVault(address(vault)).getPositions();

        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, address(vault), positions[1], LiquidityType.Anchor);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, address(vault), positions[0]);
        
        uint256 floorCapacity = DecimalMath.divideDecimal(
            floorBalance, 
            intrinsicMinimumValue
        );

        console.log("IMV is: ", intrinsicMinimumValue);
        console.log("Anchor capacity is: ", anchorCapacity);
        console.log("Floor balance is: ", floorBalance);
        console.log("Floor capacity is: ", floorCapacity);
        console.log("Anchor capacity + floor balance is: ", anchorCapacity + floorBalance);
        console.log("Circulating supply is: ", circulatingSupply);

        // To guarantee solvency, Noma ensures that capacity > circulating supply each liquidity is deployed.
        require(anchorCapacity + floorCapacity > circulatingSupply, "Insolvency invariant failed");
    }
}
