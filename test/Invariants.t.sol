// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {Deployer} from "../src/Deployer.sol";
import {BaseVault} from  "../src/vault/BaseVault.sol";
import {AmphorToken} from  "../src/token/AmphorToken.sol";
import {ModelHelper} from  "../src/model/Helper.sol";
import {Underlying } from  "../src/libraries/Underlying.sol";
import {LiquidityType, LiquidityPosition} from "../src/Types.sol";
import {DecimalMath} from "../src/libraries/DecimalMath.sol";
import {Conversions} from "../src/libraries/Conversions.sol";
 
interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IDOManager {
    function vault() external view returns (BaseVault);
    function buyTokens(uint256 price, uint256 amount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
}

interface IVault {
    function getPositions() external view returns (LiquidityPosition[3] memory);
    function shift() external;
    function slide() external;
}
 
contract Invariants is Test {
    // Get environment variables.
    address feeTo = vm.envAddress("FEE_TO");
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");
    bytes32 salt = keccak256(bytes(vm.envString("SALT")));

    // Constants
    address WETH = 0xdA07fdA01Fd20c2aaC600067dD87539944926547;
    
    // Protocol addresses
    address payable idoManager = payable(0x755fFe71D79c5D9778ED83C5c775ED2A6F15aa28);
    address nomaToken = 0xA4907FdC7D04aF3475722f622C6F002a4cA48F24;
    address deployerContract = 0x63EE25fF279a4948fbd2024A19c522b269E57881;
    address modelHelperContract = 0xc29D94a7e45299ff976398ddE03Aa5979B023148;

    AmphorToken private noma;
    ModelHelper private modelHelper;

    function setUp() public {
        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");

        noma = AmphorToken(nomaToken);
        require(address(noma) != address(0), "Noma token address is zero");
        
        modelHelper = ModelHelper(modelHelperContract);
    }


    function testCirculatingSupply() public {     
        IDOManager managerContract = IDOManager(idoManager);

        BaseVault vault = managerContract.vault();
        address pool = address(vault.pool());

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));

        console.log("Circulating supply is: ", circulatingSupply);
    }

    function testTotalSupply() public {
        IDOManager managerContract = IDOManager(idoManager);

        vm.recordLogs();
        vm.startBroadcast(privateKey);

        uint256 totalSupply = noma.totalSupply();
        console.log("Total supply is %s", totalSupply);

        assertEq(totalSupply, 100_000_000e18, "Total supply is not correct");

        vm.stopBroadcast();
    }

    function testCirculatingSupplyMatchesBalances() public {
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 2;
        uint256 tradeAmount = 0.005 ether;

        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            managerContract.buyTokens(spotPrice, tradeAmount, address(this));
        }
        
        uint256 tokenBalanceAfter = noma.balanceOf(address(this));
        console.log("Token balance after buying is %s", tokenBalanceAfter);

        uint256 circulatingSupplyAfter = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyAfter);

        assertEq(tokenBalanceAfter + 3, circulatingSupplyAfter, "Circulating supply does not match bought tokens");
    }
    
    function testBuyTokens() public {
        vm.recordLogs();
        vm.startBroadcast(privateKey);
        
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();

        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice;

        uint8 numTrades = 200;
        uint256 tradeAmount = 0.005 ether;
        
        IWETH(WETH).deposit{ value:  tradeAmount * numTrades}();
        IWETH(WETH).transfer(idoManager, tradeAmount * numTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(deployer));

        for (uint i = 0; i < numTrades; i++) {
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);

            managerContract.buyTokens(spotPrice, tradeAmount, address(deployer));
            uint256 tokenBalanceAfter = noma.balanceOf(address(deployer));
            
            uint256 receivedAmount = tokenBalanceAfter > tokenBalanceBefore 
                ? tokenBalanceAfter - tokenBalanceBefore
                : 0;

            console.log("Traded %s Ethereum, received %s tokens", (i + 1) * tradeAmount, receivedAmount);

        }
        vm.stopBroadcast();
    }

    function testSellTokens() public {
        vm.recordLogs();
        vm.startBroadcast(privateKey);

        IDOManager managerContract = IDOManager(idoManager);

        BaseVault vault = managerContract.vault();
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Spot price is: ", spotPrice);

        uint8 totalTradesBuy = 24;
        uint256 tradeAmountWETH = 2 ether;

        IWETH(WETH).deposit{ value:  tradeAmountWETH * totalTradesBuy}();
        IWETH(WETH).transfer(idoManager, tradeAmountWETH * totalTradesBuy);

        uint256 tokenBalanceBefore = noma.balanceOf(address(deployer));
        console.log("Token balance before buying is %s", tokenBalanceBefore);

        for (uint i = 0; i < totalTradesBuy; i++) {
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            if (i >= 4) {
                spotPrice = spotPrice + (spotPrice * i / 100);
            }
            managerContract.buyTokens(spotPrice, tradeAmountWETH, address(deployer));

        }

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Spot price is: ", spotPrice);

        uint256 tokenBalanceBeforeSelling = noma.balanceOf(address(deployer));
        console.log("Token balance before selling is %s", tokenBalanceBeforeSelling);

        noma.transfer(idoManager, tokenBalanceBeforeSelling);

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        managerContract.sellTokens(spotPrice - (spotPrice * 15/100), tokenBalanceBeforeSelling, address(deployer));

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        console.log("Spot price is: ", spotPrice);

        vm.stopBroadcast();
    }

    function testLargePurchaseTriggerShift() public {
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 100;
        uint256 tradeAmount = 1 ether;

        IWETH(WETH).deposit{ value: 100 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 tokenBalanceBefore = noma.balanceOf(address(this));
        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            if (i >= 4) {
                spotPrice = spotPrice + (spotPrice * i / 100);
            }
            managerContract.buyTokens(spotPrice, tradeAmount, address(this));
        }
        
        uint256 nextFloorPrice = getNextFloorPrice(pool, address(vault));
        console.log("Next floor price is: ", nextFloorPrice);

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio < 0.98e18) {
            console.log("Attempt to shift positions");
            vault.shift();
            nextFloorPrice = getNextFloorPrice(pool, address(vault));
            console.log("Next floor price (after shift) is: ", nextFloorPrice);
            solvencyInvariant();
        } else {
            revert("No shift triggered");
        }
    }

    function testShiftAboveThreshold() public {
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();

        address pool = address(vault.pool());        
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 2;
        uint256 tradeAmount = 0.005 ether;

        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            managerContract.buyTokens(spotPrice, tradeAmount, address(deployer));
        }

        uint256 nextFloorPrice = getNextFloorPrice(pool, address(vault));
        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio > 0.98e18) {

            console.log("Attempt to shift positions");
            // custom error AboveThreshold()"
            vm.expectRevert(bytes4(0xe40aeaf5));
            vault.shift();
            solvencyInvariant();
        }  
        
    }
    
    function testShiftBelowThreshold() public {
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();

        address pool = address(vault.pool());        
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 5;
        uint256 tradeAmount = 0.05 ether;

        IWETH(WETH).deposit{ value: 10 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        for (uint i = 0; i < totalTrades; i++) {
            managerContract.buyTokens(spotPrice, tradeAmount, address(deployer));
        }

        LiquidityPosition[3] memory positions = vault.getPositions();

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, address(vault), positions[1]);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, address(vault), positions[0]);

        uint256 nextFloorPrice = DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
        console.log("Next floor price is: ", nextFloorPrice);

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio < 0.98e18) {
            console.log("Attempt to shift positions");
            vault.shift();
            nextFloorPrice = getNextFloorPrice(pool, address(vault));
            console.log("Next floor price (after shift) is: ", nextFloorPrice);     
            require(nextFloorPrice > 0.98e18, "Next floor price is below threshold");  
        }  
    }
    
    function testSlide() public {
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();
        address pool = address(vault.pool());

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
        uint8 totalTrades = 100;
        uint256 tradeAmount = 1 ether;

        IWETH(WETH).deposit{ value: 100 ether }();
        IWETH(WETH).transfer(idoManager, tradeAmount * totalTrades);

        uint256 circulatingSupplyBefore = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupplyBefore);

        for (uint i = 0; i < totalTrades; i++) {
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);
            if (i >= 4) {
                spotPrice = spotPrice + (spotPrice * i / 100);
            }
            managerContract.buyTokens(spotPrice, tradeAmount, address(this));
        }

        uint256 liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));

        if (liquidityRatio < 0.98e18) {
            console.log("Attempt to shift positions");
            vault.shift();
        }  

        uint256 tokenBalanceBeforeSelling = noma.balanceOf(address(this));
        console.log("Token balance before selling is %s", tokenBalanceBeforeSelling);

        noma.transfer(idoManager, tokenBalanceBeforeSelling);

        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtPriceX96, 18);

        managerContract.sellTokens(
            spotPrice - (spotPrice * 15/100), 
            tokenBalanceBeforeSelling, 
            address(deployer)
        );

        liquidityRatio = modelHelper.getLiquidityRatio(pool, address(vault));
        console.log("Liquidity ratio is: ", liquidityRatio);

        if (liquidityRatio > 1.2e18) {
            console.log("Attempt to slide positions");
            vault.slide();
            solvencyInvariant();
        } else {
            revert("No slide triggered");
        
        }

    }

    function getNextFloorPrice(address pool, address vault) public view returns (uint256) {
        LiquidityPosition[3] memory positions = IVault(vault).getPositions();
        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, vault);
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, vault, positions[1]);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, vault, positions[0]);

        return DecimalMath.divideDecimal(floorBalance, circulatingSupply > anchorCapacity ? circulatingSupply - anchorCapacity : circulatingSupply);
    }

    function solvencyInvariant() public view {
        IDOManager managerContract = IDOManager(idoManager);
        BaseVault vault = managerContract.vault();
        address pool = address(vault.pool());

        // To guarantee solvency, Noma ensures that capacity > circulating supply each liquidity is deployed.

        uint256 circulatingSupply = modelHelper.getCirculatingSupply(pool, address(vault));
        console.log("Circulating supply is: ", circulatingSupply);

        LiquidityPosition[3] memory positions = vault.getPositions();
        uint256 anchorCapacity = modelHelper.getPositionCapacity(pool, address(vault), positions[1]);
        (,,,uint256 floorBalance) = Underlying.getUnderlyingBalances(pool, address(vault), positions[0]);

        require(anchorCapacity + floorBalance > circulatingSupply, "Insolvency invariant failed");
    }

    function testSolvencyInvariant() public {
        solvencyInvariant();
    }

    function getPositions(address vault) public view returns (LiquidityPosition[3] memory) {
        return IVault(vault).getPositions();
    }
    
}

library Utils {
    function testLessThan(uint256 a, uint256 b) public {
        // Use require to assert 'a' is less than 'b' with a custom error message
        require(a <= b, "Value 'a' should be less than 'b'.");
    } 
    
    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }    
}