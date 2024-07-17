

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TokenInfo, LiquidityPosition, LoanPosition } from "../Types.sol";
/**
 * @notice Storage structure for token-related information.
 */
struct TokenStorage {
    uint256 initialized;
    uint256 totalSupply;
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowances;
    mapping(address => uint256) nonces;
}

/**
 * @notice Storage structure for vault-related information.
 */
struct VaultStorage {
    LiquidityPosition  floorPosition;
    LiquidityPosition  anchorPosition;
    LiquidityPosition  discoveryPosition;

    mapping(address => LoanPosition) loanPositions;
    mapping(address => uint256) totalLoansPerUser;
    address[] loanAddresses;

    uint256 totalLoans;

    TokenInfo tokenInfo;
    
    address deployerContract;
    address modelHelper;
    address stakingContract;
    address proxyAddress;
    address escrowContract;

    IUniswapV3Pool pool;

    uint256 feesAccumulatorToken0;
    uint256 feesAccumulatorToken1;
    uint256 collateralAmount;

    bool initialized; 
    uint256 lastLiquidityRatio;
}

/**
 * @notice Library for accessing token-related storage.
 */
library LibAppStorage {
    /**
     * @notice Get the token storage.
     * @return ts The token storage.
     */
    function tokenStorage() internal pure returns (TokenStorage storage ts) {
        assembly {
            ts.slot := keccak256(add(0x20, "noma.money.tokenstorage"), 32)
        }
    }

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
