// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAddressResolver} from "../../interfaces/IAddressResolver.sol";
import {ReferralEntity} from "../../types/Types.sol";
import "../../errors/Errors.sol";

interface IVault {
    function getReferralEntity(address who) external view returns (ReferralEntity memory);
    function setReferralEntity(bytes8 code, uint256 amount) external;
    function consumeReferral(bytes8 code, uint256 amount) external;
}

contract vToken is ERC20 {
    using SafeERC20 for IERC20;

    IAddressResolver public resolver;
    address public vault;

    /// @notice vToken token paid out on redemption
    address public tokenOut;

    /// @notice Exchange rate: how many vToken units are required per 1 vToken
    /// e.g., 1000 means 1000 vToken -> 1 vToken
    uint256 public vPerTokenOut;

    event ExchangeRateUpdated(uint256 vPerTokenOut);
    event Redeemed(address indexed user, address indexed to, uint256 vBurned, uint256 tokenOutOut);

    constructor(
        address _resolver,
        address _vaultAddress,
        address _tokenOutToken,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        if (_resolver == address(0) || _vaultAddress == address(0) || _tokenOutToken == address(0)) {
            revert InvalidAddress();
        }

        resolver = IAddressResolver(_resolver);
        vault = _vaultAddress;
        tokenOut = _tokenOutToken;
        vPerTokenOut = 1000; // initial rate: 1000 vToken -> 1 vToken
        emit ExchangeRateUpdated(vPerTokenOut);
    }

    // Non-transferable: only mint/burn are allowed.
    function _update(address from, address to, uint256 value) internal override {
        // allow mint (from=0) and burn (to=0), block transfers
        if (from != address(0) && to != address(0)) revert NonTransferrable();
        super._update(from, to, value);
    }

    /* ----------------------- Mint from referral balance ---------------------- */

    /// @notice Mint vTokens against your referral balance.
    /// @dev IMPORTANT: Only call consumeReferral, NOT setReferralEntity!
    ///      setReferralEntity ADDS to balance, which would allow infinite minting.
    /// @param to Recipient (or zero to mint to msg.sender)
    /// @param amount Amount to mint. If zero, mints ALL available.
    function mint(address to, uint256 amount) external {
        if (vault == address(0)) revert InvalidAddress();

        ReferralEntity memory referralEntity = IVault(vault).getReferralEntity(msg.sender);
        uint256 available = referralEntity.totalReferred;
        if (available == 0) revert NothingToMint();

        // amount==0 -> mint all; otherwise cap to available
        uint256 toMint = amount == 0 ? available : (amount > available ? available : amount);
        if (toMint == 0) revert NothingToMint();

        address mintRecipient = to == address(0) ? msg.sender : to;

        _mint(mintRecipient, toMint);

        // [CRITICAL FIX] Only call consumeReferral - do NOT call setReferralEntity
        // setReferralEntity ADDS to the balance, which would negate the consumption
        // and allow infinite minting
        IVault(vault).consumeReferral(referralEntity.code, toMint);
    }

    /* ------------------------------ Redemption ------------------------------ */

    /// @notice Redeem an exact vToken amount for vToken at the current rate.
    /// @dev vToken out is floored: tokenOutOut = vAmount / vPerTokenOut.
    ///      User may lose remainder if vAmount is not a multiple of vPerTokenOut.
    function redeemForTokenOut(uint256 vAmount, address to) external {
        if (vAmount == 0) revert ZeroAmount();
        if (vPerTokenOut == 0) revert InvalidRate();
        if (msg.sender != to) revert Unauthorized();
        
        address recipient = to == address(0) ? msg.sender : to;

        // Calculate vToken to send (floor division)
        uint256 tokenOutOut = vAmount / vPerTokenOut;
        if (tokenOutOut == 0) revert ZeroAmount();

        // Burn first (effects) then transfer (interaction)
        _burn(msg.sender, vAmount);

        // Ensure contract has enough vToken
        if (IERC20(tokenOut).balanceOf(address(this)) < tokenOutOut) revert InsufficientTokenOut();

        IERC20(tokenOut).safeTransfer(recipient, tokenOutOut);
        emit Redeemed(msg.sender, recipient, vAmount, tokenOutOut);
    }

    /// @notice Redeem an exact vToken amount; burns exactly (tokenOutAmount * vPerTokenOut) vTokens.
    /// @dev Avoids rounding loss for the user if they want a precise vToken amount.
    function redeemTokenOutExact(uint256 tokenOutAmount, address to) external {
        if (tokenOutAmount == 0) revert ZeroAmount();
        if (vPerTokenOut == 0) revert InvalidRate();

        address recipient = to == address(0) ? msg.sender : to;

        uint256 vToBurn = tokenOutAmount * vPerTokenOut;

        // Burn first
        _burn(msg.sender, vToBurn);

        if (IERC20(tokenOut).balanceOf(address(this)) < tokenOutAmount) revert InsufficientTokenOut();

        IERC20(tokenOut).safeTransfer(recipient, tokenOutAmount);
        emit Redeemed(msg.sender, recipient, vToBurn, tokenOutAmount);
    }

    /// @notice View helper: quotes vToken out for a given vToken amount (floored).
    function quoteTokenOutOut(uint256 vAmount) external view returns (uint256 tokenOutOut) {
        if (vPerTokenOut == 0) return 0;
        return vAmount / vPerTokenOut;
    }

    /// @notice View helper: vTokens required to receive a given vToken amount.
    function quoteVForTokenOut(uint256 tokenOutAmount) external view returns (uint256 vRequired) {
        return tokenOutAmount * vPerTokenOut;
    }

    /* ------------------------------- Admin ops ------------------------------ */

    function setVault(address newVault) external {
        if (newVault == address(0)) revert InvalidAddress();
        if (msg.sender != resolver.owner()) revert Unauthorized();
        vault = newVault;
    }

    /// @notice Update the exchange rate (vToken per 1 vToken).
    function setExchangeRate(uint256 newVPerTokenOut) external {
        if (msg.sender != resolver.owner()) revert Unauthorized();
        if (newVPerTokenOut == 0) revert InvalidRate();
        vPerTokenOut = newVPerTokenOut;
        emit ExchangeRateUpdated(newVPerTokenOut);
    }

    /* ------------------------------- Burn hook ------------------------------ */

    function burn(address from, uint256 amount) external  {
        if (msg.sender != from) revert Unauthorized();
        _burn(from, amount);
    }
}
