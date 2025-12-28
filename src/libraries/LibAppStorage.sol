

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { 
    TokenInfo, 
    LiquidityPosition, 
    LoanPosition, 
    ProtocolParameters,
    ReferralEntity
}  from "../types/Types.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";

/**
 * @notice Storage structure for vault state.
 */
struct VaultStorage {
    // Vault state
    address factory;
    address manager;
    IAddressResolver resolver;

    // Setup state
    bool isLendingSetup; // @deprecated - unused, kept for storage layout compatibility
    bool isStakingSetup;
    bool isAdvancedConfEnabled;

    // Loans
    address[] loanAddresses;
    uint256 totalLoans;
    uint256 collateralAmount;
    uint8 loanFee;    
    uint256 totalInterest;
    mapping(address => LoanPosition) loanPositions;
    mapping(address => uint256) totalLoansPerUser;

    // Protocol configuration
    ProtocolParameters protocolParameters;
    bool initialized;
    bool stakingEnabled; 

    // Protocol addresses
    address deployerContract;
    address modelHelper;
    address stakingContract;
    address presaleContract;
    address proxyAddress; // @deprecated - unused, kept for storage layout compatibility
    address adaptiveSupplyController;
    address tokenRepo;
    address vNOMAContract;
    address orchestrator;
    address sToken;

    // Liquidity positions
    LiquidityPosition  floorPosition;
    LiquidityPosition  anchorPosition;
    LiquidityPosition  discoveryPosition;
    
    // Staking rewards
    uint256 totalMinted;
    uint256 timeLastMinted;
    
    // Token information
    TokenInfo tokenInfo;

    // Uniswap pool information
    uint24 feeTier; // @deprecated - unused, kept for storage layout compatibility
    int24 tickSpacing;
    IUniswapV3Pool pool;

    // Uniswap Fees
    uint256 feesAccumulatorToken0;
    uint256 feesAccumulatorToken1;

    // Team & Creator Fees
    uint256 totalTeamFees;
    uint256 totalCreatorFees;

    // Referral information
    mapping(bytes8 => ReferralEntity) referrals;

    // Per vault lock state
    mapping(address => bool) isLocked;
}


/**
 * @notice Library for accessing storage.
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
