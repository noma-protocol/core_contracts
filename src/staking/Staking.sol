// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IsNomaToken} from "../interfaces/IsNomaToken.sol";
import {IVault} from "../interfaces/IVault.sol";
import {Utils} from "../libraries/Utils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
/**
 * @title Staking
 * @notice A contract for staking NOMA tokens and earning rewards.
 */
contract Staking {
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

    // Custom errors
    error StakingNotEnabled();
    error InvalidParameters();
    error NotEnoughBalance();
    error InvalidReward();
    error OnlyVault();
    error CustomError();

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
    * @param _to The address to which the staked tokens will be credited.
    * @param _amount The amount of NOMA tokens to stake.
    */
    function stake(address _to, uint256 _amount) public {
        if (_amount == 0) {
            revert InvalidParameters();
        }

        if (IVault(vault).stakingEnabled() == false) {
            revert StakingNotEnabled();
        }

        // Transfer NOMA tokens from the user to the staking contract
        NOMA.transferFrom(msg.sender, address(this), _amount);

        // Mint rebase-adjusted sNOMA to the staker
        // sNOMA.mint(_to, (_amount * 1e18) / sNOMA.rebaseIndex());
        sNOMA.mint(_to, _amount);
        // Track the originally staked amount
        stakedBalances[msg.sender] += _amount;
        totalStaked += _amount;

        emit Staked(msg.sender, _amount);
    }

    
    /**
    * @notice Allows a user to unstake their NOMA tokens.
    * @param _from The address from which the staked tokens will be withdrawn.
    */
    function unstake(
        address _from
    ) external {
        if (_from == address(0)) {
            revert InvalidParameters();
        }

        if (IVault(vault).stakingEnabled() == false) {
            revert StakingNotEnabled();
        }
        
        uint256 balance = Math.min(sNOMA.balanceOf(_from), NOMA.balanceOf(address(this)));

        if (balance == 0) {
            revert NotEnoughBalance();
        }

        if (NOMA.balanceOf(address(this)) < balance) {
            revert(
                string(
                    abi.encodePacked(
                        "unstake : ", 
                        Utils._uint2str(uint256(NOMA.balanceOf(address(this))))
                    )
                )
            );
            revert NotEnoughBalance();
        }

        sNOMA.burn(sNOMA.balanceOf(_from), _from);
        NOMA.safeTransfer(_from, balance);

        totalStaked -= stakedBalances[_from];
        stakedBalances[_from] = 0;

        emit Unstaked(_from, balance);
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

        _reward = totalEpochs == 1 ? epoch.distribute : _reward;
        
        // Save current epoch with the reward distributed
        if (totalEpochs > 1) {
            if (_reward == 0) {
                revert InvalidReward();
            }
            epoch.distribute = _reward;
        }

        epoch.end = block.timestamp;
        epochs[totalEpochs] = epoch;

        // Start new epoch
        epoch = Epoch({
            number: totalEpochs,
            end: 0,
            distribute: 0
        });

        if (totalEpochs > 1 && _reward > 0) {
            sNOMA.rebase(_reward); 
            totalRewards += _reward;           
        } 
        
        totalEpochs++;
    
        emit NotifiedReward(_reward);
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