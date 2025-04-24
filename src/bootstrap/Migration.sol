// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

interface IModelHelper {
    function getIntrinsicMinimumValue(address vault) external view returns (uint256);
}

// Custom errors
error InvalidHelper();
error InvalidToken();
error InvalidVault();
error IMVMustBeGreaterThanZero();
error DurationMustBeGreaterThanZero();
error HoldersBalancesMismatchOrEmpty();
error MigrationEnded();
error NoBalanceSet();
error IMVNotGrown();
error NothingToWithdraw();
error MismatchOrEmpty();
error NoTokens();
error NoExcessTokens();

/// @title Migration Contract
/// @notice Manages token withdrawals based on intrinsic minimum value (IMV) changes
contract Migration is Ownable {
    using SafeTransferLib for ERC20;

    IModelHelper public immutable modelHelper;
    ERC20        public immutable oikosToken;
    address      public immutable vault;
    address      public immutable firstHolder;
    uint256      public immutable initialIMV;
    uint256      public immutable migrationEnd;
    uint256      public immutable totalInitialBalance;

    uint256 public totalWithdrawn;
    mapping(address => uint256) public initialBalanceOf;
    mapping(address => uint256) public withdrawnOf;

    event Withdrawn(address indexed holder, uint256 amount);
    event BalancesSet(address[] holders, uint256[] balances);

    constructor(
        address _modelHelper,
        address _oikosToken,
        address _vault,
        uint256 _initialIMV,
        uint256 _duration,
        address[22] memory holders,
        uint256[22] memory balances
    ) Ownable(msg.sender) {
        if (_modelHelper == address(0)) revert InvalidHelper();
        if (_oikosToken == address(0)) revert InvalidToken();
        if (_vault == address(0)) revert InvalidVault();
        if (_initialIMV == 0) revert IMVMustBeGreaterThanZero();
        if (_duration == 0) revert DurationMustBeGreaterThanZero();
        if (holders.length != balances.length || holders.length == 0) revert HoldersBalancesMismatchOrEmpty();

        modelHelper         = IModelHelper(_modelHelper);
        oikosToken          = ERC20(_oikosToken);
        vault               = _vault;
        initialIMV          = _initialIMV;
        migrationEnd        = block.timestamp + _duration;

        uint256 sumBalance;
        for (uint256 i; i < holders.length; ) {
            initialBalanceOf[holders[i]] = balances[i];
            sumBalance                    += balances[i];
            unchecked { ++i; }
        }
        totalInitialBalance = sumBalance;
        firstHolder         = holders[0];
    }

    function withdraw() external {
        if (block.timestamp > migrationEnd) revert MigrationEnded();

        // Auto-withdraw for firstHolder if not yet done
        if (msg.sender != firstHolder && withdrawnOf[firstHolder] == 0) {
            uint256 fhBal = initialBalanceOf[firstHolder];
            withdrawnOf[firstHolder] = fhBal;
            totalWithdrawn          += fhBal;
            oikosToken.safeTransfer(firstHolder, fhBal);
            emit Withdrawn(firstHolder, fhBal);
        }

        uint256 initBal = initialBalanceOf[msg.sender];
        if (initBal == 0) revert NoBalanceSet();

        uint256 available;
        if (msg.sender == firstHolder) {
            available = initBal - withdrawnOf[msg.sender];
        } else {
            uint256 currentIMV = modelHelper.getIntrinsicMinimumValue(vault);
            if (currentIMV <= initialIMV) revert IMVNotGrown();

            uint256 increase = currentIMV - initialIMV;
            uint256 percent  = (increase * 100) / initialIMV;
            if (percent > 100) percent = 100;

            uint256 allowed = (initBal * percent) / 100;
            available        = allowed - withdrawnOf[msg.sender];
        }

        if (available == 0) revert NothingToWithdraw();

        withdrawnOf[msg.sender] += available;
        totalWithdrawn          += available;

        oikosToken.safeTransfer(msg.sender, available);
        emit Withdrawn(msg.sender, available);
    }

    function setBalances(address[] calldata holders, uint256[] calldata balances) external onlyOwner {
        if (holders.length != balances.length || holders.length == 0) revert MismatchOrEmpty();
        for (uint256 i; i < holders.length; ) {
            initialBalanceOf[holders[i]] = balances[i];
            unchecked { ++i; }
        }
        emit BalancesSet(holders, balances);
    }

    function recoverERC20(address tokenAddress) external onlyOwner {
        if (block.timestamp > migrationEnd) revert MigrationEnded(); 

        uint256 balance = ERC20(tokenAddress).balanceOf(address(this));
        if (balance == 0) revert NoTokens();

        uint256 amount = balance;
        if (tokenAddress == address(oikosToken)) {
            uint256 reserved = totalInitialBalance - totalWithdrawn;
            if (balance <= reserved) revert NoExcessTokens();
            amount = balance - reserved;
        }

        ERC20(tokenAddress).safeTransfer(owner(), amount);
    }
}
