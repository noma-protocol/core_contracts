// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { IDOHelper } from  "../../test/IDO_Helper/IDOHelper.sol";
import { Utils } from  "../../src/libraries/Utils.sol";
import {AuxVault} from  "../../src/vault/AuxVault.sol";
import {IDOHelper} from  "../../test/IDO_Helper/IDOHelper.sol";
import {LiquidityType} from "../../src/types/Types.sol";
import {Conversions} from  "../../src/libraries/Conversions.sol"; 
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IAmphorToken {
    function balanceOf(address account) external view returns (uint256);
    function mintTo(address to, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
}

struct ContractAddressesJson {
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

contract SellAll is Script {
    // Command to deploy:
    // forge script script/Deploy.s.sol --rpc-url=<RPC_URL> --broadcast --slow

    // Get environment variables.
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    // Constants
    address WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
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

        IDOHelper idoManager = IDOHelper(idoManager);
        IAmphorToken amphor = IAmphorToken(nomaToken);

        // address implementationAddress = idoManager.implementationAddress();
        // address proxyAddress = idoManager.proxyAddress();

        // console.log("implementation address", implementationAddress);
        // console.log("proxy address", proxyAddress);

        AuxVault vault = AuxVault(address(idoManager.vault()));

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(vault.pool()).slot0();
        uint8 totalTrades = 1;
        

        uint256 tokenBalance = amphor.balanceOf(deployer);

        uint256 tokenBalanceBefore = amphor.balanceOf(address(deployer));
        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
        uint256 salePrice = spotPrice + (spotPrice * 1 / 100);

        console.log("Token balance is: %s", tokenBalance);

        for (uint i = 0; i < totalTrades; i++) {
            (sqrtRatioX96,,,,,,) = IUniswapV3Pool(vault.pool()).slot0();
            spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);
            salePrice = spotPrice - (spotPrice * 5 / 1000);

            uint256 amount = tokenBalance / totalTrades;

            amphor.transfer(address(idoManager), amount); 

            console.log("Amount is: %s", amount);
            if (amount > 0) {
                idoManager.sellTokens(salePrice, amount, address(deployer));
            }
         }
        
        uint256 presaleContractBalance = amphor.balanceOf(0xdB1EBD287fC4eDCc26D1e5C076C26687b62a88e8);

        console.log("Presale contract balance is: %s", presaleContractBalance);

        uint256 poolBalance = amphor.balanceOf(address(vault.pool()));

        uint256 idoManagerBalance = amphor.balanceOf(address(idoManager));

        console.log("IDO Manager balance is: %s", idoManagerBalance);

        console.log("Pool balance is: %s", poolBalance);

        VmSafe.Log[] memory entries = vm.getRecordedLogs();
        console.log("Entries: %s", entries.length);

        vm.stopBroadcast();
    }

}