// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {IDeployer} from "../interfaces/IDeployer.sol";
import {LiquidityOps} from "../libraries/LiquidityOps.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Conversions} from "../libraries/Conversions.sol";
import {Utils} from "../libraries/Utils.sol";
import {Uniswap} from "../libraries/Uniswap.sol";
import {IVault} from "../interfaces/IVault.sol";
import {TickMath} from 'v3-core/libraries/TickMath.sol';
import {DecimalMath} from "../libraries/DecimalMath.sol";
import {LiquidityDeployer} from "../libraries/LiquidityDeployer.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    ProtocolAddresses,
    RewardParams,
    LiquidityInternalPars
} from "../types/Types.sol";

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface IRewardsCalculator {
    function calculateRewards(RewardParams memory params) external pure returns (uint256);
}

// Custom errors
error NotInitialized();
error LiquidityRatioOutOfRange();
error StakingContractNotSet();
error Unauthorized();
error NoStakingRewards();
error StakingNotEnabled();

/**
 * @title StakingVault
 * @notice A contract for managing staking rewards and distributing them to stakers.
 * @dev This contract extends the `BaseVault` contract and provides functionality for minting and distributing staking rewards.
 */
contract StakingVault is BaseVault {
    using SafeERC20 for IERC20;

    /**
     * @notice Mints and distributes staking rewards to the staking contract.
     * @param addresses The protocol addresses.
     */
    function mintAndDistributeRewards(ProtocolAddresses memory addresses) public onlyInternalCalls {
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }

        if (_v.stakingContract == address(0)) {
            revert StakingContractNotSet();
        }

        if (!_v.stakingEnabled) {
            return;
        }

        LiquidityPosition[3] memory positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];

        uint256 excessReservesToken1 = IModelHelper(modelHelper())
        .getExcessReserveBalance(
            address(_v.pool),
            address(this),
            false
        );

        uint256 totalStaked = IERC20(_v.tokenInfo.token0).balanceOf(_v.stakingContract);

        uint256 intrinsicMinimumValue = IModelHelper(modelHelper())
        .getIntrinsicMinimumValue(address(this));

        uint256 circulatingSupply = IModelHelper(modelHelper())
        .getCirculatingSupply(
            addresses.pool, 
            address(this)
        );

        uint256 toMintEth = 
        IRewardsCalculator(rewardsCalculator()).
        calculateRewards(
            RewardParams(
                excessReservesToken1,
                circulatingSupply,
                totalStaked
            )
        ); 

        uint256 toMint = DecimalMath.divideDecimal(toMintEth, intrinsicMinimumValue);

        if (toMint > 0) {        
            IVault(address(this)).mintTokens(address(this), toMint);

            address teamMultisig = IVault(address(this)).teamMultiSig();
            uint256 inflation = toMint * IVault(address(this)).getProtocolParameters().inflationFee / 100;
            
            if (inflation > 0) {
                if (teamMultisig != address(0)) {
                    IERC20(IUniswapV3Pool(addresses.pool).token0())
                    .safeTransfer(
                        teamMultisig, 
                        inflation
                    );
                    toMint -= inflation;
                }
                if (_v.manager != address(0)) {
                    IERC20(IUniswapV3Pool(addresses.pool).token0())
                    .safeTransfer(
                        _v.manager, 
                        inflation
                    );
                    toMint -= inflation;
                }
            }

            // Update total minted (OKS)
            _v.totalMinted += toMint;

            // Transfer to staking contract
            IERC20(_v.tokenInfo.token0).transfer(_v.stakingContract, toMint);

            // Call notifyRewardAmount 
            IStakingRewards(_v.stakingContract).notifyRewardAmount(toMint);  

            // Send tokens to Floor
            (,, uint256 floorToken0Balance, uint256 floorToken1Balance) = IModelHelper(modelHelper())
            .getUnderlyingBalances(address(_v.pool), address(this), LiquidityType.Floor);
            
            Uniswap.collect(address(_v.pool), address(this), _v.floorPosition.lowerTick, _v.floorPosition.upperTick);         
            LiquidityDeployer.reDeployFloor(
                address(_v.pool), 
                address(this), 
                floorToken0Balance, 
                floorToken1Balance + toMintEth, 
                positions
            );

        } else {
            revert NoStakingRewards();
        }
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
        return _v.resolver
        .requireAndGetAddress("RewardsCalculator", "No rewards calculator");
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
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards((address,address,address,address,address,address))"))); 
        selectors[1] = bytes4(keccak256(bytes("setStakingContract(address)")));
        selectors[2] = bytes4(keccak256(bytes("getStakingContract()")));
        selectors[3] = bytes4(keccak256(bytes("stakingEnabled()")));
        return selectors;
    }
}