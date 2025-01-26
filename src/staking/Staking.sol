// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Utils} from "../libraries/Utils.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IsNomaToken.sol";
import "../interfaces/IVault.sol";

contract Staking {
    using SafeERC20 for IERC20;
    using SafeERC20 for IsNomaToken;

    struct Epoch {
        uint256 number; // since inception
        uint256 end; // timestamp
        uint256 distribute; // amount
    }

    struct Claim {
        uint256 deposit; // if forfeiting
        uint256 gons; // staked balance
        uint256 expiry; // end of warmup period
        bool lock; // prevents malicious delays for claim
    }

    IERC20 public NOMA;
    IsNomaToken public sNOMA;
    
    address public authority;
    address public vault;

    Epoch public epoch;

    mapping(uint256 => Epoch) public epochs;
    
    uint256 public totalRewards;
    uint256 public totalEpochs;

    mapping(address => Claim) public infos;

    error StakingNotEnabled();
    error InvalidParameters();
    error NotEnoughBalance();
    error InvalidReward();
    error OnlyVault();

    constructor(    
        address _noma,
        address _sNoma,
        address _vault
    ) {
        NOMA = IERC20(_noma);
        sNOMA = IsNomaToken(_sNoma);
        vault = _vault;
        
        // Initialize first epoch with distribute 0
        epoch = Epoch({
            number: 1,
            end: 0,
            distribute: 0
        });

        epochs[totalEpochs] = epoch;
        totalEpochs++;
    }

    function stake(
        address _to,
        uint256 _amount
    ) external {
        if (_amount == 0 || _to == address(0)) {
            revert InvalidParameters();
        }

        if (IVault(vault).stakingEnabled() == false) {
            revert StakingNotEnabled();
        }

        NOMA.safeTransferFrom(_to, address(this), _amount);
        sNOMA.mint(_to, _amount);

    }

    function unstake(
        address _from
    ) external {
        if (_from == address(0)) {
            revert InvalidParameters();
        }

        if (IVault(vault).stakingEnabled() == false) {
            revert StakingNotEnabled();
        }
        
        uint256 balance = sNOMA.balanceOf(_from);

        if (balance == 0) {
            revert NotEnoughBalance();
        }

        if (NOMA.balanceOf(address(this)) < balance) {
            revert NotEnoughBalance();
        }

        sNOMA.burnFor(_from, balance);
        NOMA.safeTransfer(_from, balance);

    }  

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
            // require(_reward > 0, "epoch > 1, invalid reward");
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
    }

    modifier onlyVault() {
        if (msg.sender != vault && msg.sender != address(this)) {
            revert OnlyVault();
        }
        _;
    }
}
