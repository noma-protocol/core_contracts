// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IVNOMA is IERC20 {
    function burnFrom(address account, uint256 amount) external;
}

/**
 * @title VNomaRedeemer
 * @notice Holds NOMA (sent directly to this address) to back redemptions of vNOMA
 *         at a manager-set exchange rate. No explicit deposit function—just fund
 *         by transferring NOMA to the contract.
 *
 * Rate convention: rate = NOMA-per-1-vNOMA scaled by 1e18 (1e18 => 1:1).
 */
contract VNomaRedeemer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20  public immutable noma;
    IVNOMA  public immutable vNoma;

    /// @dev Address allowed to update the exchange rate
    address public manager;

    /// @dev NOMA paid per 1 vNOMA, scaled by 1e18
    uint256 public rate;

    uint256 private constant ONE = 1e18;

    event ManagerUpdated(address indexed oldManager, address indexed newManager);
    event RateUpdated(uint256 oldRate, uint256 newRate);
    event Redeemed(address indexed redeemer, address indexed to, uint256 vAmount, uint256 nomaOut);
    event OwnerWithdraw(address indexed to, uint256 amount);

    error NotManager();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientLiquidity();

    constructor(
        address _noma,
        address _vNoma,
        uint256 _initialRate,
        address _manager,
        address _owner
    ) Ownable(msg.sender) {
        if (_noma == address(0) || _vNoma == address(0) || _manager == address(0) || _owner == address(0)) {
            revert ZeroAddress();
        }
        noma    = IERC20(_noma);
        vNoma   = IVNOMA(_vNoma);
        rate    = _initialRate;
        manager = _manager;
        _transferOwnership(_owner);

        emit ManagerUpdated(address(0), _manager);
        emit RateUpdated(0, _initialRate);
    }

    // ---------------------- Manager / Owner ----------------------

    function setManager(address newManager) external onlyOwner {
        if (newManager == address(0)) revert ZeroAddress();
        emit ManagerUpdated(manager, newManager);
        manager = newManager;
    }

    /// @notice Set vNOMA -> NOMA exchange rate (scaled by 1e18).
    function setRate(uint256 newRate) external {
        if (msg.sender != manager) revert NotManager();
        emit RateUpdated(rate, newRate);
        rate = newRate;
    }

    /// @notice Owner can withdraw NOMA (e.g., rotate inventory).
    function ownerWithdraw(uint256 amount, address to) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        noma.safeTransfer(to, amount);
        emit OwnerWithdraw(to, amount);
    }

    // ---------------------- Redeem flow ----------------------

    /// @notice Preview how much NOMA you’d get for `vAmount` vNOMA.
    function previewRedeem(uint256 vAmount) public view returns (uint256) {
        return (vAmount * rate) / ONE;
    }

    /// @notice Burn `vAmount` vNOMA and receive NOMA at the current rate, sent to `to`.
    /// @dev User must approve this contract to burn via `burnFrom`.
    function redeem(uint256 vAmount, address to) external nonReentrant {
        if (vAmount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();

        // Burn caller's vNOMA
        vNoma.burnFrom(msg.sender, vAmount);

        // Compute payout and check inventory
        uint256 nomaOut = previewRedeem(vAmount);
        if (nomaOut == 0) revert ZeroAmount();
        if (noma.balanceOf(address(this)) < nomaOut) revert InsufficientLiquidity();

        // Pay out NOMA
        noma.safeTransfer(to, nomaOut);

        emit Redeemed(msg.sender, to, vAmount, nomaOut);
    }
}
