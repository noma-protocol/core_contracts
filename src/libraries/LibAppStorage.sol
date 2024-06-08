

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
    string name;
    string symbol;
    string version;

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
