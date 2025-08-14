// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Utils} from "../libraries/Utils.sol";
import {Uniswap} from "../libraries/Uniswap.sol";
import {IVault} from "../interfaces/IVault.sol";
import {DecimalMath} from "../libraries/DecimalMath.sol";
import {LiquidityDeployer} from "../libraries/LiquidityDeployer.sol";

import {
    LiquidityType,
    LiquidityPosition,
    ProtocolAddresses,
    RewardParams
} from "../types/Types.sol";

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface IRewardsCalculator {
    function calculateRewards(RewardParams memory params) external pure returns (uint256);
}

// Custom errors
error StakingContractNotSet();
error Unauthorized();
error NoStakingRewards();

/**
 * @title StakingVault
 * @notice A contract for managing staking rewards and distributing them to stakers.
 * @dev This contract extends the `BaseVault` contract and provides functionality for minting and distributing staking rewards.
 */
contract StakingVault is BaseVault {
    using SafeERC20 for IERC20;
    /**
     * @notice Mints and distributes staking rewards to the staking contract.
     * @param caller    entity to receive caller fee
     * @param addresses protocol addresses struct
     */
    function mintAndDistributeRewards(
        address caller,
        ProtocolAddresses memory addresses
    ) public onlyInternalCalls {
        require(msg.sender == address(this), "Unauthorized");
        if (_v.stakingContract == address(0)) revert StakingContractNotSet();
        if (!_v.stakingEnabled) return;

        // 1) calculate base mint amounts
        (uint256 toMintEth, uint256 toMint) = _calculateMint(addresses);
        if (toMint == 0) revert NoStakingRewards();

        // 2) mint
        bool ret = IVault(address(this)).mintTokens(address(this), toMint);

        // 3) distribute fees, returns post-fee amount
        uint256 postFee = _distributeInflationFees(
            caller,
            addresses.pool,
            toMint
        );
        _v.totalMinted += postFee;

        // 4) send to staking & notify
        _notifyStaking(postFee);

        // 5) redeploy floor liquidity
        _redeployFloor(addresses.pool, toMintEth);
    }

    function _calculateMint(
        ProtocolAddresses memory addresses
    ) internal view returns (uint256 toMintEth, uint256 toMint) {
        // fetch data
        uint256 excessReserves = IModelHelper(modelHelper())
            .getExcessReserveBalance(
                address(_v.pool),
                address(this),
                false
            );
        uint256 totalStaked = IERC20(_v.tokenInfo.token0)
            .balanceOf(_v.stakingContract);
        uint256 intrinsicMin = IModelHelper(modelHelper())
            .getIntrinsicMinimumValue(address(this));
        uint256 circulating = IModelHelper(modelHelper())
            .getCirculatingSupply(
                addresses.pool,
                address(this)
            );

        toMintEth = IRewardsCalculator(rewardsCalculator())
            .calculateRewards(
                RewardParams(excessReserves, circulating, totalStaked)
            );
        toMint = DecimalMath.divideDecimal(toMintEth, intrinsicMin);
    }


    function _distributeInflationFees(
        address caller,
        address poolAddr,
        uint256 toMint
    ) internal returns (uint256 remain) {
        uint256 inflationFee = IVault(address(this))
            .getProtocolParameters()
            .inflationFee;
        address teamMultisig = IVault(address(this)).teamMultiSig();

        uint256 inflation = (toMint * inflationFee) / 100;
        if (inflation == 0) return toMint;

        // 1.25% caller fee
        uint256 callerFee = (inflation * 125) / 10_000;
        // remaining after caller
        uint256 rem = inflation - callerFee;
        // split team/creator
        uint256 teamFee = rem / 2;
        uint256 creatorFee = rem - teamFee;

        address token0 = IUniswapV3Pool(poolAddr).token0();
        if (caller != address(0)) {
            IERC20(token0).safeTransfer(caller, callerFee);
        }
        if (teamMultisig != address(0)) {
            IERC20(token0).safeTransfer(teamMultisig, teamFee);
        }
        if (_v.manager != address(0)) {
            IERC20(token0).safeTransfer(_v.manager, creatorFee);
        }

        remain = toMint - inflation;
    }

    function _notifyStaking(uint256 amount) internal {
        IERC20(_v.tokenInfo.token0).transfer(
            _v.stakingContract,
            amount
        );
        IStakingRewards(_v.stakingContract)
            .notifyRewardAmount(amount);
    }

    function _redeployFloor(
        address poolAddr,
        uint256 toMintEth
    ) internal {
        // collect existing liquidity & balances
        (
            ,
            ,
            uint256 floor0,
            uint256 floor1
        ) = IModelHelper(modelHelper())
        .getUnderlyingBalances(
            poolAddr,
            address(this),
            LiquidityType.Floor
        );
            
        Uniswap.collect(
            poolAddr,
            address(this),
            _v.floorPosition.lowerTick,
            _v.floorPosition.upperTick
        );

        LiquidityDeployer.reDeployFloor(
            poolAddr,
            address(this),
            floor0,
            floor1 + toMintEth,
            [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition]
        );
    }
    
    /**
     * @notice Collects liquidity from all positions.
     * @param positions The current liquidity positions.
     * @param addresses The protocol addresses.
     */
    function _collectLiquidity(
        LiquidityPosition[3] memory positions,
        ProtocolAddresses memory addresses
    ) internal {
        // Collect floor liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[0].lowerTick, 
            positions[0].upperTick
        );

        // Collect discovery liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[2].lowerTick, 
            positions[2].upperTick
        );

        // Collect anchor liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[1].lowerTick, 
            positions[1].upperTick
        );
    }

    /**
     * @notice Transfers excess balance to the deployer.
     * @param addresses The protocol addresses.
     * @param totalAmount The total amount to transfer.
     */
    function _transferExcessBalance(ProtocolAddresses memory addresses, uint256 totalAmount) internal {
        IERC20 token1 = IERC20(IUniswapV3Pool(addresses.pool).token1());
        token1.safeTransfer(addresses.deployer, totalAmount);
    }

    /**
     * @notice Retrieves the address of the rewards calculator.
     * @return The address of the rewards calculator.
     */
    function rewardsCalculator() public view returns (address) {
        address _rewardsCalculator = _v.resolver
        .getVaultAddress(
            address(this), 
            Utils.stringToBytes32("RewardsCalculator")
        );
        if (_rewardsCalculator == address(0)) {
            _rewardsCalculator = _v.resolver
            .requireAndGetAddress(
                "RewardsCalculator", 
                "No rewards calculator"
            );
        }
        return _rewardsCalculator;
    }

    /**
     * @notice Sets the staking contract address.
     * @param _stakingContract The address of the staking contract.
     */
    function setStakingContract(address _stakingContract) external onlyManager {
        _v.stakingContract = _stakingContract;
    }

    /**
     * @notice Retrieves the staking contract address.
     * @return The address of the staking contract.
     */
    function getStakingContract() external view returns (address) {
        return _v.stakingContract;
    }

    /**
     * @notice Checks if staking is enabled.
     * @return True if staking is enabled, false otherwise.
     */
    function stakingEnabled() external view returns (bool) {
        return _v.stakingEnabled;
    }

    /**
     * @notice Modifier to restrict access to the manager.
     */
    modifier onlyManager() {
        if (msg.sender != _v.manager) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards(address,(address,address,address,address,address,address))"))); 
        selectors[1] = bytes4(keccak256(bytes("setStakingContract(address)")));
        selectors[2] = bytes4(keccak256(bytes("getStakingContract()")));
        selectors[3] = bytes4(keccak256(bytes("stakingEnabled()")));
        return selectors;
    }
}