// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IsOikosToken} from "../interfaces/IsOikosToken.sol";
import {IVault} from "../interfaces/IVault.sol";
import {Utils} from "../libraries/Utils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Staking
 * @notice A contract for staking OKS tokens and earning rewards.
 */
contract Staking {
    using SafeERC20 for IERC20;
    using SafeERC20 for IsOikosToken;

    /**
     * @notice Struct representing an epoch.
     * @param number The epoch number since inception.
     * @param end The timestamp when the epoch ends.
     * @param distribute The amount of rewards distributed in this epoch.
     */
    struct Epoch {
        uint256 number;     // since inception
        uint256 end;        // timestamp
        uint256 distribute; // amount
    }

    // State variables
    IERC20 public OKS; // The OKS token contract.
    IsOikosToken public sOKS; // The staked OKS token contract.
    
    address public authority; // The address with authority over the contract.
    address public vault; // The address of the vault contract.

    Epoch public epoch; // The current epoch.

    mapping(uint256 => Epoch) public epochs; // Mapping of epoch numbers to Epoch structs.
    
    uint256 public totalRewards; // Total rewards distributed.
    uint256 public totalEpochs; // Total number of epochs.
    uint256 public totalStaked; // Total amount of OKS staked.

    // Mapping to track staked amounts per user
    mapping(address => uint256) private stakedBalances;

    // Mapping to track the last operation timestamp for each user
    mapping(address => uint256) public lastOperationTimestamp;

    // Mapping to track the epoch number when a user first staked
    mapping(address => uint256) public stakedEpochs;

    // Lock-in period in epochs (e.g., 1 for one epoch)
    uint256 public lockInEpochs = 1;

    // Custom errors
    error StakingNotEnabled();
    error InvalidParameters();
    error NotEnoughBalance(uint256 currentBalance);
    error InvalidReward();
    error OnlyVault();
    error CustomError();
    error CooldownNotElapsed();
    error LockInPeriodNotElapsed();

    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event NotifiedReward(uint256 reward);

    /**
     * @notice Constructor to initialize the Staking contract.
     * @param _oikos The address of the OKS token.
     * @param _sOikos The address of the staked OKS token.
     * @param _vault The address of the vault contract.
     */
    constructor(    
        address _oikos,
        address _sOikos,
        address _vault
    ) {
        OKS = IERC20(_oikos);
        sOKS = IsOikosToken(_sOikos);
        vault = _vault;
        
        sOKS.initialize(address(this));

        // Initialize first epoch with distribute 0
        epoch = Epoch({
            number: 1,
            end: 0,
            distribute: 0
        });

        totalStaked = 0;
        epochs[totalEpochs] = epoch;
        totalEpochs++;
    }

    /**
    * @notice Allows a user to stake OKS tokens.
    * @param _amount The amount of OKS tokens to stake.
    */
    function stake(uint256 _amount) public {
        if (_amount == 0) {
            revert InvalidParameters();
        }

        if (IVault(vault).stakingEnabled() == false) {
            revert StakingNotEnabled();
        }
        
        // Ensure 3 days have passed since the user's last stake/unstake operation
        if (block.timestamp < lastOperationTimestamp[msg.sender] + 3 days) {
            revert CooldownNotElapsed();
        }
        
        // Update the last operation timestamp for the user
        lastOperationTimestamp[msg.sender] = block.timestamp;
        
        // Transfer OKS tokens from the user to the staking contract
        OKS.transferFrom(msg.sender, address(this), _amount);

        // Mint rebase-adjusted sOKS to the staker
        sOKS.mint(msg.sender, _amount);
        
        // Track the originally staked amount and the epoch number when staked
        stakedBalances[msg.sender] += _amount;
        totalStaked += _amount;
        stakedEpochs[msg.sender] = epoch.number;

        emit Staked(msg.sender, _amount);
    }

    /**
    * @notice Allows a user to unstake their OKS tokens.
    */
    function unstake() external {
        if (IVault(vault).stakingEnabled() == false) {
            revert StakingNotEnabled();
        }

        // Check if the user's tokens are locked in the lock-in period
        if (epoch.number < stakedEpochs[msg.sender] + lockInEpochs) {
            revert LockInPeriodNotElapsed();
        }

        uint256 balance = Math.min(sOKS.balanceOf(msg.sender), OKS.balanceOf(address(this)));

        if (balance == 0) {
            revert NotEnoughBalance(0);
        }

        if (OKS.balanceOf(address(this)) < balance) {
            revert NotEnoughBalance(balance); 
        }

        sOKS.burn(sOKS.balanceOf(msg.sender), msg.sender);
        OKS.safeTransfer(msg.sender, balance);

        totalStaked -= stakedBalances[msg.sender];
        stakedBalances[msg.sender] = 0;

        emit Unstaked(msg.sender, balance);
    }

    /**
     * @notice Notifies the contract of a new reward amount and starts a new epoch.
     * @param _reward The amount of rewards to distribute.
     */
    function notifyRewardAmount(uint256 _reward) public onlyVault {
        if (_reward == type(uint256).max) {
            revert InvalidReward();
        }

        if (IVault(vault).stakingEnabled() == false) {
            revert StakingNotEnabled();
        }

        // Mark end of current epoch
        epoch.end = block.timestamp;
        epochs[totalEpochs] = epoch;

        // Increment totalEpochs before starting a new epoch
        totalEpochs++;

        // Set the distribute amount for the current epoch
        epoch.distribute = _reward;

        // Start new epoch with the updated epoch number
        epoch = Epoch({
            number: totalEpochs,
            end: 0,
            distribute: 0
        });

        // Update total rewards and rebase sOKS
        sOKS.rebase(_reward);
        totalRewards += _reward;

        emit NotifiedReward(_reward);
    }

    /**
    * @notice Returns the originally staked amount of OKS for a user.
   * @param _user The address of the staker.
   * @return The originally staked amount of OKS.
    */
    function stakedBalance(address _user) external view returns (uint256) {
        return stakedBalances[_user];
    }

    /**
     * @notice Modifier to restrict access to the vault or the contract itself.
     */
    modifier onlyVault() {
        if (msg.sender != vault && msg.sender != address(this)) {
            revert OnlyVault();
        }
        _;
    }
}