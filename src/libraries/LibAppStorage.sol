

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TokenInfo, LiquidityPosition, LoanPosition, VaultDescription } from "../types/Types.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Deployer } from "../Deployer.sol";


/**
 * @notice Storage structure for factory-related information.
 */
struct NomaFactoryStorage {
    IAddressResolver resolver;
    Deployer deployer;
    address deploymentFactory;
    address extFactory;
    address authority;
    address uniswapV3Factory;
    uint256 totalVaults;
    EnumerableSet.AddressSet deployers;
    mapping(address => EnumerableSet.AddressSet) _vaults;
    mapping(address => VaultDescription) vaultsRepository;
}

/**
 * @notice Storage structure for vault-related information.
 */
struct VaultStorage {
    // Vault information
    address factory;

    // Liquidity positions
    LiquidityPosition  floorPosition;
    LiquidityPosition  anchorPosition;
    LiquidityPosition  discoveryPosition;

    // Loans
    mapping(address => LoanPosition) loanPositions;
    mapping(address => uint256) totalLoansPerUser;
    address[] loanAddresses;
    uint256 totalLoans;
    uint256 collateralAmount;

    // Staking rewards
    uint256 totalMinted;

    // Token information
    TokenInfo tokenInfo;

    // Protocol addresses
    address deployerContract;
    address modelHelper;
    address stakingContract;
    address proxyAddress;
    address escrowContract;

    IUniswapV3Pool pool;

    // Uniswap Fees
    uint256 feesAccumulatorToken0;
    uint256 feesAccumulatorToken1;

    // System parameters
    bool initialized; 
    uint256 lastLiquidityRatio;
}


/**
 * @notice Library for accessing token-related storage.
 */
library LibAppStorage {
    /**
     * @notice Get the vault storage.
     * @return vs The vault storage.
     */
    function vaultStorage() internal pure returns (VaultStorage storage vs) {
        assembly {
            vs.slot := keccak256(add(0x20, "noma.money.vaultstorage"), 32)
        }
    }

    /**
     * @notice Get the factory storage.
     * @return fs The factory storage.
     */
    function factoryStorage() internal pure returns (NomaFactoryStorage storage fs) {
        assembly {
            fs.slot := keccak256(add(0x20, "noma.money.factorystorage"), 32)
        }
    }

}
