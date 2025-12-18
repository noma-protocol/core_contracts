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
// Author: 0xsufi@noma.money
// Copyright Noma Protocol 2025/2026

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Recovery} from "../abstract/ERC20Recovery.sol";
import {IsNomaToken} from "../interfaces/IsNomaToken.sol";
import {IVault} from "../interfaces/IVault.sol";
import {Utils} from "../libraries/Utils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../errors/Errors.sol";

/**
 * @title Staking
 * @notice A contract for staking NOMA tokens and earning rewards.
 */
contract Staking is ReentrancyGuard, ERC20Recovery {
    using SafeERC20 for IERC20;
    using SafeERC20 for IsNomaToken;

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
    IERC20 public NOMA; // The NOMA token contract.
    IsNomaToken public sNOMA; // The staked NOMA token contract.
    
    address public authority; // The address with authority over the contract.
    address public vault; // The address of the vault contract.

    Epoch public epoch; // The current epoch.

    mapping(uint256 => Epoch) public epochs; // Mapping of epoch numbers to Epoch structs.
    
    uint256 public totalRewards; // Total rewards distributed.
    uint256 public totalEpochs; // Total number of epochs.
    uint256 public totalStaked; // Total amount of NOMA staked.

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
     * @param _noma The address of the NOMA token.
     * @param _sNoma The address of the staked NOMA token.
     * @param _vault The address of the vault contract.
     */
    constructor(    
        address _noma,
        address _sNoma,
        address _vault
    ) {
        NOMA = IERC20(_noma);
        sNOMA = IsNomaToken(_sNoma);
        vault = _vault;
        
        sNOMA.initialize(address(this));

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
    * @notice Allows a user to stake NOMA tokens.
    * @param _amount The amount of NOMA tokens to stake.
    */
    function stake(uint256 _amount) external nonReentrant {
        if (_amount == 0) {
            revert InvalidParameters();
        }

        if (IVault(vault).stakingEnabled() == false || epoch.number == 0) {
            revert StakingNotEnabled();
        }
        
        // Ensure 3 days have passed since the user's last stake/unstake operation
        if (block.timestamp < lastOperationTimestamp[msg.sender] + 3 days) {
            revert CooldownNotElapsed();
        }
        
        // Update the last operation timestamp for the user
        lastOperationTimestamp[msg.sender] = block.timestamp;
        
        // Transfer NOMA tokens from the user to the staking contract
        // [C-02 FIX] Use SafeERC20
        NOMA.safeTransferFrom(msg.sender, address(this), _amount);

        // Mint rebase-adjusted sNOMA to the staker
        sNOMA.mint(msg.sender, _amount);
        
        // Track the originally staked amount and the epoch number when staked
        stakedBalances[msg.sender] += _amount;
        totalStaked += _amount;
        stakedEpochs[msg.sender] = epoch.number;

        emit Staked(msg.sender, _amount);
    }

    /**
    * @notice Allows a user to unstake their NOMA tokens.
    */
    function unstake() external nonReentrant {
        if (IVault(vault).stakingEnabled() == false) {
            revert StakingNotEnabled();
        }

        // Check if the user's tokens are locked in the lock-in period
        if (epoch.number < stakedEpochs[msg.sender] + lockInEpochs) {
            revert LockInPeriodNotElapsed();
        }

        uint256 balance = Math.min(sNOMA.balanceOf(msg.sender), NOMA.balanceOf(address(this)));

        if (balance == 0) {
            revert NotEnoughBalance(0);
        }

        if (NOMA.balanceOf(address(this)) < balance) {
            revert NotEnoughBalance(balance); 
        }

        sNOMA.burn(sNOMA.balanceOf(msg.sender), msg.sender);
        NOMA.safeTransfer(msg.sender, balance);

        totalStaked -= stakedBalances[msg.sender];
        stakedBalances[msg.sender] = 0;

        emit Unstaked(msg.sender, balance);
    }

    /**
     * @notice Notifies the contract of a new reward amount and starts a new epoch.
     * @param _reward The amount of rewards to distribute.
     */
    function notifyRewardAmount(uint256 _reward) public onlyVault nonReentrant {
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

        // Update total rewards and rebase sNOMA
        sNOMA.rebase(_reward);
        totalRewards += _reward;

        emit NotifiedReward(_reward);
    }
    
    function recoverERC20(address token, address to) public onlyVault {
        if (token == address(NOMA) || token == address(sNOMA)) revert CannotRecoverTokens();

        recoverAllERC20(token, to);
        sNOMA.recoverERC20(token,to);
    }

    /**
    * @notice Returns the originally staked amount of NOMA for a user.
   * @param _user The address of the staker.
   * @return The originally staked amount of NOMA.
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