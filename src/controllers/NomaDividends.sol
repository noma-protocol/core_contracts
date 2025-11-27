// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Resolver} from "../Resolver.sol";
import {MultiTokenDividends} from "../libraries/MultiTokenDividends.sol";
import {Utils} from "../libraries/Utils.sol";
import {VaultDescription} from "../types/Types.sol";

interface INomaFactory {
    function getVaultsRepository(address vault) external view returns (VaultDescription memory);
}

/// @title NomaDividends
/// @notice Distribute arbitrary ERC20 dividends to holders of a "shares" token (NOMA, sNOMA, etc.)
/// @dev Uses MultiTokenDividends library. The "sharesToken" contract
///      should call `onSharesTransferHook` from its `_beforeTokenTransfer` hook
///      so rewards are properly accrued on every balance change.
contract NomaDividends is Ownable {
    using SafeERC20 for IERC20;
    using MultiTokenDividends for MultiTokenDividends.State;

    /// @notice The token whose holders receive dividends (e.g., NOMA or sNOMA).
    IERC20 public sharesToken;

    /// @notice Whether auto-claim on transfer is enabled.
    bool public autoClaimOnTransfer = true;

    //
    Resolver public resolver;
    INomaFactory public factory;

    /// @dev Core dividends state (per reward token).
    MultiTokenDividends.State private _state;

    /// @dev List of all reward tokens ever used (for iterating in hooks).
    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    mapping(address => uint256) public totalDistributed;

    event RewardTokenAdded(address indexed token);
    event Distributed(address indexed rewardToken, uint256 amount, uint256 totalShares);
    event Claimed(address indexed user, address indexed rewardToken, uint256 amount);
    event AutoClaimOnTransferChanged(bool enabled);

    error NotInitialized();
    error InvalidRewardToken();
    error ZeroAmount();
    error NoShares();
    error OnlyVaultsError();

    constructor(address factoryAddress, address resolverAddress) Ownable(msg.sender) {
        resolver = Resolver(resolverAddress);
        factory = INomaFactory(factoryAddress);
    }

    // ============================================================
    //                   ADMIN / OWNER FUNCTIONS
    // ============================================================

    function setSharesToken() external onlyOwner {
        address nomaTokenAddress = NomaToken();
        if (nomaTokenAddress != address(0)) {
            sharesToken = IERC20(NomaToken());
        }
    }

    /// @notice Enable or disable auto-claim on transfers.
    function setAutoClaimOnTransfer(bool enabled) external onlyOwner {
        autoClaimOnTransfer = enabled;
        emit AutoClaimOnTransferChanged(enabled);
    }

    // ============================================================
    //                   REWARD DISTRIBUTION
    // ============================================================

    /// @notice Distribute `amount` of `rewardToken` to all current shares holders.
    /// @dev Caller must have approved this contract to spend `amount` of `rewardToken`.
    function distribute(address rewardToken, uint256 amount) public onlyVaults {
        if (address(sharesToken) == address(0)) return;
        if (rewardToken == address(0)) revert InvalidRewardToken();
        if (amount <= 0) revert ZeroAmount();

        uint256 totalShares = sharesToken.totalSupply();
        if (totalShares <= 0) revert NoShares();

        // Pull tokens in first
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        // Track reward token if new
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

    /// @notice Called by the shares token in its `_beforeTokenTransfer`.
    /// @dev Must be called BEFORE balances change in the shares token.
    ///      We:
    ///        - accrue rewards for `from` & `to` based on their current balances
    ///        - optionally auto-claim their rewards
    function onSharesTransferHook(address from, address to)
        external
        onlySharesToken
    {
        uint256 len = rewardTokens.length;

        // accrue for `from`
        if (from != address(0)) {
            uint256 fromShares = sharesToken.balanceOf(from);
            for (uint256 i = 0; i < len; ++i) {
                _state.accrueForUser(rewardTokens[i], from, fromShares);
            }
            if (autoClaimOnTransfer) {
                _claimAllInternal(from);
            }
        }

        // accrue for `to`
        if (to != address(0)) {
            uint256 toShares = sharesToken.balanceOf(to);
            for (uint256 i = 0; i < len; ++i) {
                _state.accrueForUser(rewardTokens[i], to, toShares);
            }
            if (autoClaimOnTransfer) {
                _claimAllInternal(to);
            }
        }
    }

    // ============================================================
    //                     VIEW FUNCTIONS
    // ============================================================

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /// @notice View claimable amount of a specific reward token for a user.
    function claimable(address rewardToken, address user) external view returns (uint256) {
        // read raw data from the library state
        MultiTokenDividends.RewardData storage rd = _state.rewards[rewardToken];

        uint256 globalIdx = rd.index;
        uint256 userIdx   = rd.userIndex[user];
        uint256 accrued   = rd.accrued[user];
        uint256 userShares = sharesToken.balanceOf(user);

        if (userShares == 0) {
            // no shares, just return whatever is already accrued (usually 0)
            return accrued;
        }

        if (userIdx == 0) {
            // First time we see this user from the contract's perspective.
            // With current semantics, we treat them as "starting now", 
            // so they are NOT entitled to past distributions. So we just
            // return accrued (no extra).
            return accrued;
        }

        uint256 delta = globalIdx - userIdx;
        if (delta == 0) {
            return accrued;
        }

        // Simulate what accrueForUser would do:
        uint256 earned = (userShares * delta) / MultiTokenDividends.getPrecision();
        return accrued + earned;
    }

    function getTotalDistributed(address rewardToken) public view returns (uint256) {
        return totalDistributed[rewardToken];
    }

    // ============================================================
    //                     CLAIM FUNCTIONS
    // ============================================================

    /// @notice Manually claim a specific reward token.
    function claim(address rewardToken) external {
        _accrueAllFor(msg.sender);
        uint256 amount = _state.takeAccrued(rewardToken, msg.sender);
        if (amount > 0) {
            IERC20(rewardToken).safeTransfer(msg.sender, amount);
            emit Claimed(msg.sender, rewardToken, amount);
        }
    }

    /// @notice Manually claim all reward tokens.
    function claimAll() external {
        _accrueAllFor(msg.sender);
        _claimAllInternal(msg.sender);
    }

    // ============================================================
    //                     INTERNAL HELPERS
    // ============================================================

    /// @dev Accrue all rewards for `user` using their current shares balance.
    function _accrueAllFor(address user) internal {
        if (user == address(0)) return;

        uint256 userShares = sharesToken.balanceOf(user);
        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            _state.accrueForUser(rewardTokens[i], user, userShares);
        }
    }

    /// @dev Claim all reward tokens for `user` without doing another accrue.
    function _claimAllInternal(address user) internal {
        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            address rt = rewardTokens[i];
            uint256 amount = _state.takeAccrued(rt, user);
            if (amount > 0) {
                IERC20(rt).safeTransfer(user, amount);
                emit Claimed(user, rt, amount);
            }
        }
    }

    function NomaToken() public view returns (address nomaTokenAddress) {
        nomaTokenAddress = resolver
        .requireAndGetAddress(
            Utils.stringToBytes32("NomaToken"), 
            "no NomaToken"
        );
        return nomaTokenAddress;
    }    

    /// @dev Only the sharesToken is allowed to call certain entry points (transfer hook).
    modifier onlySharesToken() {
        require(msg.sender == address(sharesToken), "Not shares token");
        _;
    }

    modifier onlyVaults() {
        VaultDescription memory vaultDesc = factory.getVaultsRepository(msg.sender);
        if (vaultDesc.vault != msg.sender) revert OnlyVaultsError();
        _;
    }
}
