// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {IDOHelper} from  "../../test/IDO_Helper/IDOHelper.sol";
import {Utils} from  "../../src/libraries/Utils.sol";
import {Conversions} from  "../../src/libraries/Conversions.sol"; 
import {AuxVault} from  "../../src/vault/AuxVault.sol";
import {IDOHelper} from  "../../test/IDO_Helper/IDOHelper.sol";
import {LiquidityType} from "../../src/types/Types.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

interface IWETH {
    function balanceOf(address owner) external returns (uint256);
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function mintTo(address to, uint256 amount) external;
}

interface IAmphorToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function mintTo(address to, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
}

struct ContractAddressesJson {
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

contract BuyIDO is Script {
    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WMON = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address payable idoManager;
    address nomaToken;
    
    address payable idoManagerAddress = payable(idoManager);

    function run() public {  
        vm.recordLogs();
        vm.startBroadcast(privateKey);
        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);

        string memory networkId = "143";
        // Parse the data for network ID `1337`
        bytes memory data = vm.parseJson(json, string.concat(string("."), networkId));

        // Decode the data into the ContractAddresses struct
        ContractAddressesJson memory addresses = abi.decode(data, (ContractAddressesJson));
        
        // Log parsed addresses for verification
        console2.log("Model Helper Address:", addresses.ModelHelper);

        // Extract addresses from JSON
        idoManager = payable(0x40abA8961F44f548C815dACD1C6f3a96dc5e8579); //payable(addresses.IDOHelper);
        nomaToken = 0x1bC268ba8e6add3A72f2092f04963D43D728FF55; //addresses.Proxy;

        IDOHelper idoManager = IDOHelper(idoManager);
        IAmphorToken amphor = IAmphorToken(nomaToken);

        AuxVault vault = AuxVault(address(idoManager.vault()));

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(vault.pool()).slot0();
        uint8 totalTrades = 15;
        uint256 tradeSize = 5 ether;

        IWETH(WMON).deposit{ value: (totalTrades * tradeSize) }();
        IWETH(WMON).transfer(address(idoManager), (totalTrades * tradeSize));

        uint256 tokenBalanceBefore = amphor.balanceOf(address(deployer));
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
        uint256 purchasePrice = spotPrice + (spotPrice * 1 / 100);

        console.log("Token balance before buying is %s", tokenBalanceBefore);
        console.log("Spot price is %s", spotPrice);
        console.log("Purchase price is %s", purchasePrice);
        
        for (uint i = 0; i < totalTrades; i++) {
            // sample price at each iteration
            (sqrtRatioX96,,,,,,) = IUniswapV3Pool(vault.pool()).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
            purchasePrice = spotPrice + (spotPrice * 1 / 100);

            try idoManager.buyTokens(
                purchasePrice, 
                tradeSize, 
                0, // min amount
                deployer
            ) {
                console.log("Token purchase successful.");
            } catch Error(string memory reason) {
                // Catch revert reason if provided
                console.log("Reverted with reason: %s", reason);
            } catch (bytes memory lowLevelData) {
                // Catch low-level revert
                console.log("Reverted with low-level data: %s", string(lowLevelData));
            }

        }

        uint256 tokenBalanceAfter = amphor.balanceOf(address(deployer));
        uint256 totalSupply = amphor.totalSupply();

        console.log("Token balance after buying is %s", tokenBalanceAfter);
        console.log("Total supply is %s", totalSupply);

        VmSafe.Log[] memory entries = vm.getRecordedLogs();
        console.log("Entries: %s", entries.length);

        vm.stopBroadcast();
    }

}