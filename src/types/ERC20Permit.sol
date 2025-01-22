// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./ERC20.sol";

/// @title Counters Library
/// @notice Provides a simple counter that can be incremented, decremented, or queried.
/// @dev Counters are used to manage nonces for the ERC20Permit extension.
library Counters {
    struct Counter {
        uint256 _value; // Default: 0
    }

    /// @notice Returns the current value of the counter.
    /// @param counter The counter to query.
    /// @return The current value of the counter.
    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    /// @notice Increments the value of the counter by 1.
    /// @param counter The counter to increment.
    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    /// @notice Decrements the value of the counter by 1.
    /// @param counter The counter to decrement.
    /// @dev Reverts if the counter is already at zero.
    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }
}

/// @title ERC20Permit
/// @notice An ERC20 extension that allows approvals via signatures, as defined in EIP-2612.
/// @dev This contract allows token holders to approve spenders without needing to hold Ether for gas.
abstract contract ERC20Permit is ERC20, IERC20Permit, EIP712 {
    using Counters for Counters.Counter;

    /// @dev Mapping of owner addresses to their respective nonces for permit signatures.
    mapping(address => Counters.Counter) private _nonces;

    /// @dev The EIP-712 type hash for the permit struct.
    bytes32 private immutable _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice Initializes the EIP-712 domain separator with the token name and version "1".
    /// @param name The name of the ERC20 token, used as the domain separator name.
    constructor(string memory name) EIP712(name, "1") {}

    /// @notice Allows a token owner to approve a spender via an off-chain signature.
    /// @dev The permit function verifies a signed message and sets the spender's allowance.
    /// @param owner The address of the token owner.
    /// @param spender The address of the spender.
    /// @param value The amount of tokens to approve.
    /// @param deadline The expiration time for the permit, in seconds since the Unix epoch.
    /// @param v The recovery byte of the signature.
    /// @param r The first 32 bytes of the signature.
    /// @param s The second 32 bytes of the signature.
    /// @notice Reverts if the signature is invalid or the deadline has passed.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        require(block.timestamp <= deadline, "ERC20Permit: expired deadline");

        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);

        require(signer == owner, "ERC20Permit: invalid signature");

        _approve(owner, spender, value);
    }

    /// @notice Returns the current nonce for an owner.
    /// @dev Nonces are used to ensure each permit signature is unique and cannot be replayed.
    /// @param owner The address of the token owner.
    /// @return The current nonce for the owner.
    function nonces(address owner) public view virtual override returns (uint256) {
        return _nonces[owner].current();
    }

    /// @notice Returns the domain separator for the EIP-712 encoding.
    /// @return The domain separator used in EIP-712 encoding.
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @dev Consumes the current nonce for an owner and increments it.
    /// @param owner The address of the token owner.
    /// @return current The current nonce value before incrementing.
    function _useNonce(address owner) internal virtual returns (uint256 current) {
        Counters.Counter storage nonce = _nonces[owner];
        current = nonce.current();
        nonce.increment();
    }
}
