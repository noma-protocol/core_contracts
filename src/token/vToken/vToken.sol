// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAddressResolver} from "../../interfaces/IAddressResolver.sol";
import {ReferralEntity} from "../../types/Types.sol";

interface IVault {
    function getReferralEntity(address who) external view returns (ReferralEntity memory);
    function setReferralEntity(bytes8 code, uint256 amount) external; 
}

error Unauthorized();
error InvalidAddress();
error NothingToMint();

contract vToken is ERC20 {

    IAddressResolver public resolver;
    address public vault;

    constructor(
        address _resolver,
        address _vaultAddress,
        string memory _name, 
        string memory _symbol
    ) ERC20(_name, _symbol) {
        resolver = IAddressResolver(_resolver);
        vault = _vaultAddress;
    }

    // Non-transferable: only mint/burn are allowed.
    function _update(address from, address to, uint256 value) internal override {
        // allow mint (from=0) and burn (to=0), block transfers
        require(from == address(0) || to == address(0), "vNOMA: non-transferable");
        super._update(from, to, value);
    }

    /// @notice Mint vTokens against your referral balance.
    /// @param to Recipient (or zero to mint to msg.sender)
    /// @param amount Amount to mint. If zero, mints ALL available.
    function mint(address to, uint256 amount) external {
        if (vault == address(0)) revert InvalidAddress();

        // Fetch caller's referral balance/entity
        ReferralEntity memory referralEntity = 
        IVault(vault).getReferralEntity(msg.sender);
        
        uint256 available = referralEntity.totalReferred;
        if (available == 0) revert NothingToMint();

        // amount==0 -> mint all; otherwise cap to available
        uint256 toMint = amount == 0 ? available : (amount > available ? available : amount);
        if (toMint == 0) revert NothingToMint();

        address mintRecipient = to == address(0) ? msg.sender : to;

        // Mint only what's requested/capped
        _mint(mintRecipient, toMint);

        // Preserve remaining balance: subtract only what was minted
        uint256 remaining = available - toMint;
        IVault(vault).setReferralEntity(referralEntity.code, remaining);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setVault(address newVault) external {
        if (newVault == address(0)) revert InvalidAddress();
        if (msg.sender != resolver.owner()) revert Unauthorized();
        vault = newVault;
    }
}
