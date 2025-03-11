// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

interface IModelHelper {
    function getIntrinsicMinimumValue(address vault) external view returns (uint256);
}

/// @title Migration Contract
/// @notice Manages token withdrawals based on intrinsic minimum value (IMV) changes
contract Migration is Ownable {
    using SafeTransferLib for ERC20;

    /// @notice Helper to fetch IMV values
    IModelHelper public immutable modelHelper;

    /// @notice Token being migrated
    ERC20 public immutable oikosToken;

    /// @notice Vault used for IMV calculations
    address public immutable vault;

    /// @notice The very first holder with special withdrawal rights
    address public immutable firstHolder;

    /// @notice Initial IMV snapshot at migration start
    uint256 public immutable initialIMV;

    /// @notice Timestamp when migration ends
    uint256 public immutable migrationEnd;

    /// @notice Total initial balances sum
    uint256 public immutable totalInitialBalance;

    /// @notice Total withdrawn by all holders
    uint256 public totalWithdrawn;

    /// @notice Records each holder’s starting balance
    mapping(address => uint256) public initialBalanceOf;

    /// @notice Records each holder’s total withdrawn amount
    mapping(address => uint256) public withdrawnOf;

    /// @notice Emitted when a holder withdraws tokens
    event Withdrawn(address indexed holder, uint256 amount);

    /// @notice Emitted when owner resets initial balances
    event BalancesSet(address[] holders, uint256[] balances);

    /// @param _modelHelper  Address of the IMV helper
    /// @param _oikosToken   Address of the Oikos ERC20 token
    /// @param _vault        Vault for IMV queries
    /// @param _initialIMV   IMV snapshot at start
    /// @param _duration     Migration duration in seconds
    /// @param holders       List of holder addresses
    /// @param balances      Corresponding initial balances
    constructor(
        address _modelHelper,
        address _oikosToken,
        address _vault,
        uint256 _initialIMV,
        uint256 _duration,
        address[] memory holders,
        uint256[] memory balances
    ) Ownable(msg.sender) {
        require(_modelHelper != address(0), "Invalid helper");
        require(_oikosToken != address(0), "Invalid token");
        require(_vault != address(0), "Invalid vault");
        require(_initialIMV > 0, "IMV must be > 0");
        require(_duration > 0, "Duration must be > 0");
        require(holders.length == balances.length && holders.length > 0, "Holders/balances mismatch or empty");

        modelHelper = IModelHelper(_modelHelper);
        oikosToken  = ERC20(_oikosToken);
        vault       = _vault;
        initialIMV  = _initialIMV;
        migrationEnd = block.timestamp + _duration;

        // Sum initial balances and set mapping
        uint256 sumBalance;
        for (uint256 i; i < holders.length; ) {
            initialBalanceOf[holders[i]] = balances[i];
            sumBalance += balances[i];
            unchecked { ++i; }
        }
        totalInitialBalance = sumBalance;

        firstHolder = holders[0];
    }

    /// @notice Withdraws allowed tokens based on IMV growth
    function withdraw() external {
        require(block.timestamp <= migrationEnd, "Migration ended");

        // If firstHolder hasn't yet withdrawn, auto-withdraw full balance
        if (msg.sender != firstHolder && withdrawnOf[firstHolder] == 0) {
            uint256 fhBalance = initialBalanceOf[firstHolder];
            withdrawnOf[firstHolder] = fhBalance;
            totalWithdrawn += fhBalance;
            oikosToken.safeTransfer(firstHolder, fhBalance);
            emit Withdrawn(firstHolder, fhBalance);
        }

        uint256 initBal = initialBalanceOf[msg.sender];
        require(initBal > 0, "No balance set");

        uint256 available;

        if (msg.sender == firstHolder) {
            available = initBal - withdrawnOf[msg.sender];
        } else {
            uint256 currentIMV = modelHelper.getIntrinsicMinimumValue(vault);
            require(currentIMV > initialIMV, "IMV has not grown");

            uint256 increase  = currentIMV - initialIMV;
            uint256 percent   = (increase * 100) / initialIMV;
            if (percent > 100) percent = 100;

            uint256 allowed   = (initBal * percent) / 100;
            available = allowed - withdrawnOf[msg.sender];
        }

        require(available > 0, "Nothing to withdraw");
        withdrawnOf[msg.sender] += available;
        totalWithdrawn += available;

        oikosToken.safeTransfer(msg.sender, available);
        emit Withdrawn(msg.sender, available);
    }

    /// @notice Owner can update initial balances for holders
    function setBalances(address[] calldata holders, uint256[] calldata balances) external {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        require(holders.length == balances.length && holders.length > 0, "Mismatch or empty");
        for (uint256 i; i < holders.length; ) {
            initialBalanceOf[holders[i]] = balances[i];
            unchecked { ++i; }
        }
        emit BalancesSet(holders, balances);
    }

    /// @notice Recover tokens accidentally sent to this contract
    /// @param tokenAddress The address of the token to recover
    function recoverERC20(address tokenAddress) external onlyOwner {
        uint256 balance = ERC20(tokenAddress).balanceOf(address(this));
        require(balance > 0, "No tokens");
        uint256 amount;
        if (tokenAddress == address(oikosToken)) {
            uint256 reserved = totalInitialBalance - totalWithdrawn;
            require(balance > reserved, "No excess tokens");
            amount = balance - reserved;
        } else {
            amount = balance;
        }
        ERC20(tokenAddress).safeTransfer(owner(), amount);
    }
}
