

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { 
    TokenInfo, 
    LiquidityPosition, 
    LoanPosition, 
    LiquidityStructureParameters
}  from "../types/Types.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";

/**
 * @notice Storage structure for vault-related information.
 */
struct VaultStorage {
    // Vault state
    address factory;

    LiquidityStructureParameters liquidityStructureParameters;

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
    uint256 timeLastMinted;
    
    // Token information
    TokenInfo tokenInfo;

    // Uniswap pool information
    uint24 feeTier;
    int24 tickSpacing;

    // Protocol addresses
    address deployerContract;
    address modelHelper;
    address stakingContract;
    address proxyAddress;
    address adaptiveSupplyController;
    
    IUniswapV3Pool pool;
    IAddressResolver resolver;

    // Uniswap Fees
    uint256 feesAccumulatorToken0;
    uint256 feesAccumulatorToken1;

    // System parameters
    bool initialized;
    bool stakingEnabled; 
    // uint256 lastLiquidityRatio;
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
}
