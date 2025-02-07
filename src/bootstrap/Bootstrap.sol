// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {Conversions} from "../libraries/Conversions.sol";
import {Uniswap} from "../libraries/Uniswap.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {VaultDeployParams, TokenInfo} from "../types/Types.sol";

interface INomaFactory {
    function deployVault(VaultDeployParams memory _params) external returns (address, address, address);
}

interface IWETH {
    function deposit() external payable;
}

/**
 * @title Bootstrap Contract
 * @notice This contract handles the deployment of vaults, token purchases, and interactions with Uniswap pools.
 */
contract Bootstrap {
    using SafeERC20 for IERC20;

    /// @notice Address of the presale contract.
    address public presaleContract;

    /// @notice Address of the migration contract.
    address public migrationContract;

    /// @notice Reference to the Noma Factory contract.
    INomaFactory public nomaFactory;

    /// @notice Reference to the Uniswap v3 pool.
    IUniswapV3Pool public pool;

    /// @dev Stores token information for the Uniswap pool.
    TokenInfo private tokenInfo;

    /// @dev Address of the WETH token.
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    int24 public tickSpacing;

    /// @dev Custom errors for better gas efficiency.
    error OnlyPresaleContract();
    error CallbackCaller();
    error PoolNotSet();
    error InvalidReceiver();
    error InvalidAddress();

    /**
     * @notice Initializes the Bootstrap contract.
     * @param _nomafactory Address of the Noma Factory contract.
     * @param _presaleContract Address of the presale contract.
     * @param _migrationContract Address of the migration contract.
     */
    constructor (
        address _nomafactory, 
        address _presaleContract,
        address _migrationContract,
        address _pool,
        int24 _tickSpacing
    ) {
        nomaFactory = INomaFactory(_nomafactory);
        presaleContract = _presaleContract;
        migrationContract = _migrationContract;
        tickSpacing = _tickSpacing;
        pool = IUniswapV3Pool(_pool);
    }

    /**
     * @notice Ensures the function can only be called by the presale contract.
     */
    modifier onlyPresale() {
        if (msg.sender != presaleContract) revert OnlyPresaleContract();
        _;
    }
}
