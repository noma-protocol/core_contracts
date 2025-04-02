// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../src/controllers/supply/AdaptiveSupply.sol";
import {ModelHelper} from  "../../src/model/Helper.sol";
import {BaseVault} from "../../src/vault/BaseVault.sol";

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

contract AdaptiveMintTest is Test {
    AdaptiveSupply adaptiveMint;
    
    address payable idoManager;
    address nomaToken;
    address modelHelperContract;
    address vaultAddress;

    function setUp() public {
        adaptiveMint = new AdaptiveSupply();

        // Define the file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy_helper/out/out.json");

        // Read the JSON file
        string memory json = vm.readFile(path);

        string memory networkId = "56";
        // Parse the data for network ID `56`
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
        
        ModelHelper modelHelper = ModelHelper(modelHelperContract);
        vaultAddress = address(managerContract.vault());

        console.log("Vault address is: ", vaultAddress);          
    }

    function testLowVolatility() public returns (uint256) {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 7 days;      // Example time elapsed

        vm.prank(vaultAddress);
        uint256 mintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 2e18, 1e18);

        emit log_named_uint("Mint Amount (Low Volatility)", mintAmount);
        assertGt(mintAmount, 0, "Mint amount should be greater than 0 for low volatility");

        return mintAmount;
    }

    function testNormalVolatility() public returns (uint256) {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 7 days;      // Example time elapsed

        vm.prank(vaultAddress);
        uint256 mintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 4e18, 1e18);

        uint256 toMintLowVolatility = testLowVolatility();

        emit log_named_uint("Mint Amount (Normal Volatility)", mintAmount);

        assertGt(mintAmount, 0, "Mint amount should be greater than 0 for normal volatility");
        assertLt(toMintLowVolatility, mintAmount, "Mint amount should be more than low volatility");

        return mintAmount;
    }

    function testMediumVolatility() public returns (uint256) {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 1 days;      // Example time elapsed

        vm.prank(vaultAddress);
        uint256 mintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 6e18, 1e18);

        uint256 toMintNormalVolatility = testNormalVolatility();

        emit log_named_uint("Mint Amount (Medium Volatility)", mintAmount);

        assertGt(mintAmount, 0, "Mint amount should be greater than 0 for medium volatility");
        assertLt(toMintNormalVolatility, mintAmount, "Mint amount should be more than normal volatility");

        return mintAmount;
    }

    function testHighVolatility() public {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 12 hours;    // Example time elapsed

        vm.prank(vaultAddress);
        uint256 mintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 10e18, 1e18);

        uint256 toMintMediumVolatility = testMediumVolatility();

        emit log_named_uint("Mint Amount (High Volatility)", mintAmount);

        assertGt(mintAmount, 0, "Mint amount should be greater than 0 for high volatility");
        assertLt(toMintMediumVolatility, mintAmount, "Mint amount should be more than medium volatility");
    }

    function testRewardLogic() public {
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 14 days;     // Example time elapsed

        vm.prank(vaultAddress);
        uint256 lowMint = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 2e18, 1e18);
        vm.prank(vaultAddress);
        uint256 normalMint = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed - 2 days, 4e18, 1e18);
        vm.prank(vaultAddress);
        uint256 mediumMint = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed - 3 days, 6e18, 1e18);
        vm.prank(vaultAddress);
        uint256 highMint = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed - 1 weeks, 10e18, 1e18);
        
        emit log_named_uint("Mint Amount (Low Volatility)", lowMint);
        emit log_named_uint("Mint Amount (Normal Volatility)", normalMint);
        emit log_named_uint("Mint Amount (Medium Volatility)", mediumMint);
        emit log_named_uint("Mint Amount (High Volatility)", highMint);

        assertLt(lowMint, normalMint, "Low volatility mint should be smaller than normal");
        assertLt(normalMint, mediumMint, "Normal volatility mint should be smaller than medium");
        assertLt(mediumMint, highMint, "Medium volatility mint should be smaller than high");
    }


    function testMintAmountsIncreaseLinearly() public {
    
        uint256 increaseFactor = 1_000; // Example increase factor
        uint256 deltaSupply = 1_000 ether; // Example delta supply
        uint256 timeElapsed = 14 days;     // Example time elapsed

        vm.prank(vaultAddress);
        uint256 firstMintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 2e18, 1e18);

        console.log("First Mint Amount: ", firstMintAmount);

        emit log_named_uint("Mint Amount (Low Volatility)", firstMintAmount);

        deltaSupply = deltaSupply * increaseFactor; 

        //assert that firstMintAmount is less than 10% of deltaSupply
        assertLt(firstMintAmount, deltaSupply / 10, "First mint amount should be less than 10% of delta supply");

        vm.prank(vaultAddress);
        uint256 secondMintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 2e18, 1e18);
    
        console.log("Second Mint Amount: ", secondMintAmount);

        emit log_named_uint("Mint Amount (Low Volatility)", secondMintAmount);

        //assert that secondMintAmount is less than 10% of deltaSupply
        assertLt(secondMintAmount, deltaSupply / 10, "Second mint amount should be less than 10% of delta supply");

        // Assert that the second mint amount is approximately equal to the first mint amount multiplied by increaseFactor
        uint256 expectedAmount = firstMintAmount * increaseFactor;
        uint256 tolerance = 1e18; // 1 token tolerance
        assertApproxEqAbs(secondMintAmount, expectedAmount, tolerance, "Mint amount should scale linearly with delta supply");

        // Repeat all tests above for 30 days

        timeElapsed = 30 days; // Example time elapsed
        vm.prank(vaultAddress);
        uint256 thirdMintAmount = adaptiveMint.computeMintAmount(deltaSupply, timeElapsed, 2e18, 1e18);
        console.log("Third Mint Amount: ", thirdMintAmount);

        emit log_named_uint("Mint Amount (Low Volatility)", thirdMintAmount);

        //assert that thirdMintAmount is less than 10% of deltaSupply
        assertLt(thirdMintAmount, deltaSupply / 10, "Third mint amount should be less than 10% of delta supply");

        //assert that thirdMintAmount is less than 10% of deltaSupply
        assertLt(thirdMintAmount, deltaSupply / 10, "Third mint amount should be less than 10% of delta supply");
        // Assert that the third mint amount is approximately equal to the first mint amount multiplied by increaseFactor

        expectedAmount = firstMintAmount * increaseFactor;
        assertApproxEqAbs(thirdMintAmount, expectedAmount, tolerance, "Mint amount should scale linearly with delta supply");
        
        //assert that thirdMintAmount is less than 10% of deltaSupply
        assertLt(thirdMintAmount, deltaSupply / 10, "Third mint amount should be less than 10% of delta supply");

        //assert that thirdMintAmount is less than 10% of deltaSupply
        assertLt(thirdMintAmount, deltaSupply / 10, "Third mint amount should be less than 10% of delta supply");

        // Assert that the third mint amount is approximately equal to the first mint amount multiplied by increaseFactor
        expectedAmount = firstMintAmount * increaseFactor;
        assertApproxEqAbs(thirdMintAmount, expectedAmount, tolerance, "Mint amount should scale linearly with delta supply");

        //assert that thirdMintAmount is less than 10% of deltaSupply
        assertLt(thirdMintAmount, deltaSupply / 10, "Third mint amount should be less than 10% of delta supply");

        //assert that thirdMintAmount is less than 10% of deltaSupply
        assertLt(thirdMintAmount, deltaSupply / 10, "Third mint amount should be less than 10% of delta supply");

        // Assert that the third mint amount is approximately equal to the first mint amount multiplied by increaseFactor
        expectedAmount = firstMintAmount * increaseFactor;
        assertApproxEqAbs(thirdMintAmount, expectedAmount, tolerance, "Mint amount should scale linearly with delta supply");

        //assert that thirdMintAmount is less than 10% of deltaSupply
        assertLt(thirdMintAmount, deltaSupply / 10, "Third mint amount should be less than 10% of delta supply");

        //assert that thirdMintAmount is less than 10% of deltaSupply
        assertLt(thirdMintAmount, deltaSupply / 10, "Third mint amount should be less than 10% of delta supply");

        // Assert that the third mint amount is approximately equal to the first mint amount multiplied by increaseFactor
        expectedAmount = firstMintAmount * increaseFactor;

        assertApproxEqAbs(thirdMintAmount, expectedAmount, tolerance, "Mint amount should scale linearly with delta supply");
    }


}
