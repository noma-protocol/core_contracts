// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {BaseVault} from "../src/vault/BaseVault.sol";
import {IQuoterV2} from "./Quoter/IQuoterV2.sol";

struct ContractAddressesJson {
    address Factory;
    address IDOHelper;
    address ModelHelper;
    address Proxy;
}

interface IDOManager {
    function vault() external view returns (BaseVault);
    function buyTokens(uint256 price, uint256 amount, address receiver) external;
    function sellTokens(uint256 price, uint256 amount, address receiver) external;
    function modelHelper() external view returns (address);
}

contract TestQuoter is Test {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.envAddress("DEPLOYER");

    address payable idoManager;
    address vaultAddress;
    address quoterV2 = 0x78D78E420Da98ad378D7799bE8f4AF69033EB077;
    IUniswapV3Pool pool;

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
        
        // Extract addresses from JSON
        idoManager = payable(addresses.IDOHelper);
        
        IDOManager managerContract = IDOManager(idoManager);
        require(address(managerContract) != address(0), "Manager contract address is zero");
        
        vaultAddress = address(managerContract.vault());

        console.log("Vault address is: ", vaultAddress);   

        pool = IUniswapV3Pool(IVault(vaultAddress).pool());  
    }

    function testQuoteExactOutput() public {
        address token0 = pool.token0();
        address token1 = pool.token1();

        bytes memory swapPath = _encodePath(
            token0,
            token1,
            3000
        );

       (uint256 quote,,,) = IQuoterV2(quoterV2).quoteExactOutput(swapPath, 1e18);

        console.log("Quote for 1 token0 to token1: ", quote);
    }

    function testQuoteExactInput() public {
        address token0 = pool.token0();
        address token1 = pool.token1();

        bytes memory swapPath = _encodePath(
            token1,
            token0,
            3000
        );

       (uint256 quote,,,) = IQuoterV2(quoterV2).quoteExactInput(swapPath, 1e18);

        console.log("Quote for 1 token0 to token1: ", quote);
    }

    /// @notice Encode a single‐hop Uniswap V3 swap path
    /// @param tokenIn  address of the input token
    /// @param tokenOut address of the output token
    /// @param fee      pool fee, in hundredths of a bip (e.g. 500 = 0.05%, 3000 = 0.3%)
    /// @return path     the abi-packed path bytes ready for exactInput calls
    function _encodePath(
        address tokenIn,
        address tokenOut,
        uint24  fee
    ) internal pure returns (bytes memory path) {
        return abi.encodePacked(tokenIn, fee, tokenOut);
    }

    /**
     * @notice Uniswap v3 callback function, called back on pool.swap
     */
    function uniswapV3SwapCallback(
        int256 amount0Delta, 
        int256 amount1Delta, 
        bytes calldata data
    ) external {
        require(msg.sender == address(pool), "Callback caller not pool");

    }
}