// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// ███╗   ██╗ ██████╗ ███╗   ███╗ █████╗                               
// ████╗  ██║██╔═══██╗████╗ ████║██╔══██╗                              
// ██╔██╗ ██║██║   ██║██╔████╔██║███████║                              
// ██║╚██╗██║██║   ██║██║╚██╔╝██║██╔══██║                              
// ██║ ╚████║╚██████╔╝██║ ╚═╝ ██║██║  ██║                              
// ╚═╝  ╚═══╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝                              
                                                                    
// ██████╗ ██████╗  ██████╗ ████████╗ ██████╗  ██████╗ ██████╗ ██╗     
// ██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝██╔═══██╗██╔════╝██╔═══██╗██║     
// ██████╔╝██████╔╝██║   ██║   ██║   ██║   ██║██║     ██║   ██║██║     
// ██╔═══╝ ██╔══██╗██║   ██║   ██║   ██║   ██║██║     ██║   ██║██║     
// ██║     ██║  ██║╚██████╔╝   ██║   ╚██████╔╝╚██████╗╚██████╔╝███████╗
// ╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝  ╚═════╝ ╚═════╝ ╚══════╝
//
// Contract: NomaDividends.sol
// Author: 0xsufi@noma.money
// Copyright Noma Protocol 2024/2026

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Resolver} from "../Resolver.sol";
import {MultiTokenDividends} from "../libraries/MultiTokenDividends.sol";
import {Utils} from "../libraries/Utils.sol";
import {VaultDescription} from "../types/Types.sol";

interface INomaFactory {
    function getVaultsRepository(address vault) external view returns (VaultDescription memory);
}

/// @title NomaDividends
/// @notice Distribute arbitrary ERC20 dividends to holders of a "shares" token (NOMA, sNOMA, etc.)
/// @dev Uses MultiTokenDividends for index math. The shares token MUST call
///      `onSharesTransferHook` in its `_beforeTokenTransfer` / `_update` so rewards
///      are accrued on every balance change.
///
///      Rewards accrue non-linearly into a "raw" claimable balance via index math.
///      When a user calls `claim` (or `claimAll`), the current raw claimable amount
///      is locked into a 6-month linear vesting tranche. Later, the user calls
///      `withdrawVested` / `withdrawAllVested` to actually receive tokens.
contract NomaDividends {
    using SafeERC20 for IERC20;
    using MultiTokenDividends for MultiTokenDividends.State;

    // ============================================================
    //                         CONFIG
    // ============================================================

    /// @notice Vesting duration for all dividend tranches: 6 months.
    uint64 public constant VESTING_DURATION = 180 days;

    // ============================================================
    //                         STATE
    // ============================================================

    /// @notice The token whose holders receive dividends (e.g., NOMA or sNOMA).
    IERC20 public sharesToken;

    /// @notice Whether auto-withdraw of vested rewards on transfer is enabled.
    bool public autoClaimOnTransfer = true;

    /// @notice Address resolver and factory references (immutable for cheaper reads).
    Resolver public immutable resolver;
    INomaFactory public immutable factory;

    /// @dev Core dividends state (per reward token) from MultiTokenDividends.
    MultiTokenDividends.State private _state;

    /// @dev List of all reward tokens ever used (for iterating in hooks).
    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    mapping(address => uint256) public totalDistributed;

    /// @notice Fixed owner (no transfer), stored as immutable for cheap reads.
    address public immutable owner;

    // ---------------------- VESTING / ESCROW ---------------------

    /// @notice Linear vesting tranche per user per reward token.
    /// @dev Packed into 2 storage slots: amount+claimed, start+padding.
    struct VestingEntry {
        uint128 amount;   // total amount in this tranche
        uint128 claimed;  // amount already withdrawn from this tranche
        uint64  start;    // vesting start timestamp for this tranche
    }

    /// @dev user => rewardToken => vesting entries (tranches)
    mapping(address => mapping(address => VestingEntry[])) private _vestingEntries;

    // ============================================================
    //                         EVENTS
    // ============================================================

    event RewardTokenAdded(address indexed token);
    event Distributed(address indexed rewardToken, uint256 amount, uint256 totalShares);
    event Locked(address indexed user, address indexed rewardToken, uint256 amount, uint64 start);
    event Claimed(address indexed user, address indexed rewardToken, uint256 amount);
    event AutoClaimOnTransferChanged(bool enabled);

    // ============================================================
    //                         ERRORS
    // ============================================================

    error InvalidRewardToken();
    error ZeroAmount();
    error NoShares();
    error OnlyVaultsError();
    error NotSharesToken();
    error NotOwner();

    // ============================================================
    //                       CONSTRUCTOR
    // ============================================================

    constructor(address factoryAddress, address resolverAddress) {
        resolver = Resolver(resolverAddress);
        factory  = INomaFactory(factoryAddress);
        owner    = msg.sender;
    }

    // ============================================================
    //                   ADMIN / OWNER FUNCTIONS
    // ============================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Sets the shares token from the resolver's "NomaToken" entry.
    function setSharesToken() external onlyOwner {
        address nomaTokenAddress = resolver.requireAndGetAddress(
            Utils.stringToBytes32("NomaToken"),
            "no NomaToken"
        );
        if (nomaTokenAddress != address(0)) {
            sharesToken = IERC20(nomaTokenAddress);
        }
    }

    /// @notice Enable or disable auto-withdraw of vested rewards on transfers.
    function setAutoClaimOnTransfer(bool enabled) external onlyOwner {
        autoClaimOnTransfer = enabled;
        emit AutoClaimOnTransferChanged(enabled);
    }

    // ============================================================
    //                   REWARD DISTRIBUTION
    // ============================================================

    /// @notice Distribute `amount` of `rewardToken` to all current shares holders.
    /// @dev Caller must have approved this contract to spend `amount` of `rewardToken`.
    function distribute(address rewardToken, uint256 amount) external onlyVaults {
        IERC20 sharesToken_ = sharesToken;
        if (address(sharesToken_) == address(0)) return;
        if (rewardToken == address(0)) revert InvalidRewardToken();
        if (amount == 0) revert ZeroAmount();

        uint256 totalShares = sharesToken_.totalSupply();
        if (totalShares == 0) revert NoShares();

        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        if (!isRewardToken[rewardToken]) {
            isRewardToken[rewardToken] = true;
            rewardTokens.push(rewardToken);
            emit RewardTokenAdded(rewardToken);
        }

        totalDistributed[rewardToken] += amount;
        _state.distribute(rewardToken, amount, totalShares);

        emit Distributed(rewardToken, amount, totalShares);
    }

    // ============================================================
    //                HOOK FROM SHARES TOKEN
    // ============================================================

    /// @notice Called by the shares token in its hook BEFORE balances change.
    /// @dev Accrues index-based rewards for `from` & `to` based on current balances,
    ///      then optionally auto-withdraws already-vested amounts from existing tranches.
    function onSharesTransferHook(address from, address to)
        external
        onlySharesToken
    {
        address[] storage rewardTokens_ = rewardTokens;
        uint256 len = rewardTokens_.length;
        if (len == 0) return;

        IERC20 sharesToken_ = sharesToken;

        // accrue for `from`
        if (from != address(0)) {
            uint256 fromShares = sharesToken_.balanceOf(from);
            for (uint256 i; i < len; ) {
                _state.accrueForUser(rewardTokens_[i], from, fromShares);
                unchecked { ++i; }
            }
            if (autoClaimOnTransfer) {
                _withdrawAllVestedFor(from);
            }
        }

        // accrue for `to`
        if (to != address(0)) {
            uint256 toShares = sharesToken_.balanceOf(to);
            for (uint256 i; i < len; ) {
                _state.accrueForUser(rewardTokens_[i], to, toShares);
                unchecked { ++i; }
            }
            if (autoClaimOnTransfer) {
                _withdrawAllVestedFor(to);
            }
        }
    }

    // ============================================================
    //                     VIEW FUNCTIONS
    // ============================================================

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function getTotalDistributed(address rewardToken) external view returns (uint256) {
        return totalDistributed[rewardToken];
    }

    /// @notice Return all vesting entries (tranches) for `msg.sender` and a given reward token.
    function getVestingEntries(address rewardToken) external view returns (VestingEntry[] memory) {
        VestingEntry[] storage entries = _vestingEntries[msg.sender][rewardToken];
        uint256 len = entries.length;
        VestingEntry[] memory out = new VestingEntry[](len);
        for (uint256 i; i < len; ) {
            out[i] = entries[i];
            unchecked { ++i; }
        }
        return out;
    }

    /// @notice View raw (non-vested) claimable amount for a user & token based on index math.
    /// @dev This is the amount that would be locked into a vesting tranche if the user calls `claim`.
    function claimableRaw(address rewardToken, address user) external view returns (uint256) {
        MultiTokenDividends.RewardData storage rd = _state.rewards[rewardToken];

        uint256 userShares = sharesToken.balanceOf(user);
        if (userShares == 0) {
            return rd.accrued[user];
        }

        uint256 userIdx = rd.userIndex[user];
        if (userIdx == 0) {
            return rd.accrued[user];
        }

        uint256 delta = rd.index - userIdx;
        if (delta == 0) {
            return rd.accrued[user];
        }

        uint256 earned = (userShares * delta) / MultiTokenDividends.getPrecision();
        return rd.accrued[user] + earned;
    }

    /// @notice View vested (but not yet withdrawn) amount over all tranches for a user & token.
    function claimable(address rewardToken, address user) external view returns (uint256) {
        return _releasableView(user, rewardToken);
    }

    // ============================================================
    //                   LOCK (CREATE VESTING)
    // ============================================================

    /// @notice Lock current raw claimable amount of `rewardToken` into a 6-month vesting tranche.
    /// @dev Does NOT transfer tokens to the user. Use `withdrawVested` later.
    function claim(address rewardToken) external {
        address user = msg.sender;
        IERC20 sharesToken_ = sharesToken;

        uint256 userShares = sharesToken_.balanceOf(user);
        _state.accrueForUser(rewardToken, user, userShares);

        uint256 amount = _state.takeAccrued(rewardToken, user);
        if (amount != 0) {
            uint64 start = uint64(block.timestamp);
            _vestingEntries[user][rewardToken].push(
                VestingEntry({
                    amount:  uint128(amount),
                    claimed: 0,
                    start:   start
                })
            );
            emit Locked(user, rewardToken, amount, start);
        }
    }

    /// @notice Lock current raw claimable amounts of ALL reward tokens into 6-month vesting tranches.
    function claimAll() external {
        address user = msg.sender;
        address[] storage rewardTokens_ = rewardTokens;
        uint256 lenTokens = rewardTokens_.length;
        if (lenTokens == 0) return;

        IERC20 sharesToken_ = sharesToken;
        uint256 userShares = sharesToken_.balanceOf(user);
        uint64 start = uint64(block.timestamp);

        for (uint256 i; i < lenTokens; ) {
            address rt = rewardTokens_[i];

            _state.accrueForUser(rt, user, userShares);
            uint256 amount = _state.takeAccrued(rt, user);
            if (amount != 0) {
                _vestingEntries[user][rt].push(
                    VestingEntry({
                        amount:  uint128(amount),
                        claimed: 0,
                        start:   start
                    })
                );
                emit Locked(user, rt, amount, start);
            }

            unchecked { ++i; }
        }
    }

    // ============================================================
    //                WITHDRAW VESTED (ACTUAL PAYOUT)
    // ============================================================

    /// @notice Withdraw vested portion of a specific reward token.
    function withdrawVested(address rewardToken) external {
        address user = msg.sender;
        uint256 amount = _withdrawVested(user, rewardToken);
        if (amount != 0) {
            IERC20(rewardToken).safeTransfer(user, amount);
            emit Claimed(user, rewardToken, amount);
        }
    }

    /// @notice Withdraw vested portions of all reward tokens.
    function withdrawAllVested() external {
        _withdrawAllVestedFor(msg.sender);
    }

    // ============================================================
    //                     INTERNAL HELPERS
    // ============================================================

    /// @dev Withdraw all vested reward tokens for `user` over all reward tokens.
    function _withdrawAllVestedFor(address user) internal {
        address[] storage rewardTokens_ = rewardTokens;
        uint256 lenTokens = rewardTokens_.length;
        if (lenTokens == 0 || user == address(0)) return;

        for (uint256 i; i < lenTokens; ) {
            address rt = rewardTokens_[i];

            uint256 amount = _withdrawVested(user, rt);
            if (amount != 0) {
                IERC20(rt).safeTransfer(user, amount);
                emit Claimed(user, rt, amount);
            }

            unchecked { ++i; }
        }
    }

    /// @dev Computes the vested amount for a single tranche (not net of claimed).
    function _vestedAmount(uint128 amount, uint64 start, uint256 ts) internal pure returns (uint256) {
        if (start == 0 || ts <= start) return 0;

        unchecked {
            uint256 elapsed = ts - start;
            if (elapsed >= VESTING_DURATION) {
                return amount;
            }
            return (uint256(amount) * elapsed) / VESTING_DURATION;
        }
    }

    /// @dev View-only: releasable (vested - claimed) amount over all tranches.
    function _releasableView(address user, address rewardToken) internal view returns (uint256 total) {
        VestingEntry[] storage entries = _vestingEntries[user][rewardToken];
        uint256 len = entries.length;
        uint256 ts = block.timestamp;

        for (uint256 i; i < len; ) {
            VestingEntry storage e = entries[i];
            uint128 claimed = e.claimed;
            uint256 vested = _vestedAmount(e.amount, e.start, ts);
            if (vested > claimed) {
                total += (vested - claimed);
            }
            unchecked { ++i; }
        }
    }

    /// @dev Mutating version: mark vested amounts as claimed and return total withdrawn.
    function _withdrawVested(address user, address rewardToken) internal returns (uint256 total) {
        VestingEntry[] storage entries = _vestingEntries[user][rewardToken];
        uint256 len = entries.length;
        uint256 ts = block.timestamp;

        for (uint256 i; i < len; ) {
            VestingEntry storage e = entries[i];
            uint128 claimed = e.claimed;
            uint256 vested = _vestedAmount(e.amount, e.start, ts);

            if (vested > claimed) {
                uint256 claimableInTranche = vested - claimed;
                e.claimed = uint128(vested);
                total += claimableInTranche;
            }

            unchecked { ++i; }
        }
    }

    // ============================================================
    //                RESOLVER / FACTORY HELPERS
    // ============================================================

    /// @dev Only the sharesToken is allowed to call certain entry points (transfer hook).
    modifier onlySharesToken() {
        if (msg.sender != address(sharesToken)) revert NotSharesToken();
        _;
    }

    /// @dev Only known vaults (from factory registry) can call certain functions (e.g. distribute).
    modifier onlyVaults() {
        VaultDescription memory vaultDesc = factory.getVaultsRepository(msg.sender);
        if (vaultDesc.vault != msg.sender) revert OnlyVaultsError();
        _;
    }
}
