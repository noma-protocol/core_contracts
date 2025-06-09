// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IVault.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {OikosToken} from  "../src/token/OikosToken.sol";
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
    function buyTokens(uint256 price, uint256 amount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
    function modelHelper() external view returns (address);
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

    OikosToken private noma;
    ModelHelper private modelHelper;

    address WBNB = 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;

    function setUp() public {
        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);

        string memory networkId = "1337";
        // Parse the data for network ID `1337`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Model Helper Address:", addresses.ModelHelper);

        // Extract addresses from JSON
        idoManager = payable(addresses.IDOHelper);
        nomaToken = addresses.Proxy;
        modelHelperContract = addresses.ModelHelper;
        
        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        noma = OikosToken(nomaToken);
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
        vm.stopPrank();

        uint256 allowance = token0.allowance(deployer, vaultAddress);
        uint256 balanceBeforeToken0 = token0.balanceOf(deployer);
        uint256 balanceBeforeToken1 = token1.balanceOf(deployer);

        vm.prank(deployer);
        vault.borrow(borrowAmount, duration);

        uint256 fees = calculateLoanFees(borrowAmount, duration);

        assertEq(token1.balanceOf(deployer) - balanceBeforeToken1, borrowAmount - fees);
        assertLt(token0.balanceOf(deployer), balanceBeforeToken0);
    }

    function testPaybackLoan() public {
        testBorrow();

        uint256 borrowAmount = 1 ether;

        // Pay back part of the loan
        vm.prank(deployer);
        token1.approve(vaultAddress, MAX_INT);

        vm.prank(deployer);
        IWETH(WBNB).deposit{ value: borrowAmount}();

        uint256 token1Balance = token1.balanceOf(deployer);
        console.log("Token1 balance before payback is: ", token1Balance);
        
        vm.prank(deployer);
        vault.payback(borrowAmount);
 
        assertEq(token1Balance - borrowAmount, token1.balanceOf(deployer));
    }    

    function testRollLoan() public {
        uint256 borrowAmount = 5 ether;
        uint256 duration = 30 days;
        uint256 newDuration = 30 days;

        vm.prank(deployer);
        token0.approve(vaultAddress, MAX_INT);

        // Borrow first
        vm.prank(deployer);
        vault.borrow(borrowAmount, duration);
        
        uint256 balanceBeforePaybackToken1 = token1.balanceOf(deployer);
        uint256 balanceBeforePaybackToken0 = token0.balanceOf(deployer);

        // trigger shift
        testLargePurchaseTriggerShift();

        // Pay back part of the loan
        vm.prank(deployer);
        token1.approve(vaultAddress, MAX_INT);

        vm.prank(deployer);
        vault.roll(newDuration);

        // check if the loan amount is deducted from the user's balance
        // assertEq(balanceBeforePaybackToken1 - token1.balanceOf(deployer), borrowAmount);
        // // check if the borrowed amount is reduced by the payback amount
        assertLt(balanceBeforePaybackToken0, token0.balanceOf(deployer));

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
        AuxVault vault = AuxVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        uint16 totalTrades = 50;
        uint256 tradeAmount = 2 ether;

        IWETH(WBNB).deposit{ value: (tradeAmount * totalTrades)}();
        IWETH(WBNB).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            purchasePrice = spotPrice + (spotPrice * i / 100);
            if (i >= 4) {
                spotPrice =  purchasePrice;
            }
            managerContract.buyTokens(spotPrice, tradeAmount, deployer);
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
            solvency();
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

    function getNextFloorPrice(address pool, address vault) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault);
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

    function solvency() public view {
        IDOManager managerContract = IDOManager(idoManager);
        AuxVault vault = AuxVault(address(managerContract.vault()));
        address pool = address(vault.pool());

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupply);

        uint256 intrinsicMinimumValue = modelHelper.getIntrinsicMinimumValue(address(vault));
        
        LiquidityPosition[3] memory positions =  AuxVault(address(vault)).getPositions();

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
