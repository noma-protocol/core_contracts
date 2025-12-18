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
import {LiquidityDeployerMin} from "../libraries/LiquidityDeployerMin.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import "../errors/Errors.sol";

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

interface ILendingVault {
    function vaultSelfRepayLoans(uint256 fundsToPull, uint256 start, uint256 limit) external returns (uint256 eligibleCount, uint256 totalRepaid, uint256 nextIndex);
}

interface INomaDividends {
    function distribute(address rewardToken, uint256 amount) external;
}

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
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }
        if (_v.stakingContract == address(0)) revert StakingContractNotSet();
        if (!_v.stakingEnabled) return;

        // 1) calculate base mint amounts
        (
            uint256 toMintEth, 
            uint256 toMint, 
            uint256 selfRepayingLoansEth
        ) = _calculateMint(addresses);

        (,uint256 totalRepaid,) = ILendingVault(address(this))
        .vaultSelfRepayLoans(
            selfRepayingLoansEth,
            0,
            0
        );

        if (toMint > 0) {
            bool ret = IVault(address(this)).mintTokens(address(this), toMint);
            address dd = dividendDistributor();
            if (ret) {
                // 3) distribute fees, returns post-fee amount
                (
                    uint256 postFee, 
                    uint256 protocolFee
                ) = _distributeInflationFees(
                    caller,
                    addresses.pool,
                    toMint
                );
                _v.totalMinted += postFee;

                if (protocolFee > 0 && dd != address(0)) {
                    IERC20(IUniswapV3Pool(addresses.pool).token0())
                    .approve(
                        dd,
                        protocolFee
                    );
                    INomaDividends(dd)
                    .distribute(
                        IUniswapV3Pool(addresses.pool).token0(),
                        protocolFee
                    );
                }

                // 4) send to staking & notify
                _notifyStaking(postFee);

                // // 5) redeploy floor liquidity
                _redeployFloor(addresses.pool, toMintEth);            
            }            
        }
    }

    function _calculateMint(
        ProtocolAddresses memory addresses
    ) internal view 
    returns (
        uint256 toMintEth, 
        uint256 toMint, 
        uint256 selfRepayingLoansEth
    ) {
        IVault v = IVault(address(this));

        // fetch data
        uint256 excessReserves = IModelHelper(modelHelper())
            .getExcessReserveBalance(
                address(_v.pool),
                address(this),
                false
            );

        selfRepayingLoansEth = excessReserves * (2 * v.getProtocolParameters().inflationFee) / 100; 
        excessReserves -= selfRepayingLoansEth;

        uint256 totalStaked = IERC20(_v.tokenInfo.token0)
            .balanceOf(_v.stakingContract);

        uint256 imv = IModelHelper(modelHelper())
            .getIntrinsicMinimumValue(address(this));

        uint256 circulating = IModelHelper(modelHelper())
            .getCirculatingSupply(
                addresses.pool,
                address(this), 
                false
            );

        toMintEth = IRewardsCalculator(rewardsCalculator())
            .calculateRewards(
                RewardParams(excessReserves, circulating, totalStaked)
            );
            
        toMint = DecimalMath.divideDecimal(toMintEth, imv);
    }


    function _distributeInflationFees(
        address caller,
        address poolAddr,
        uint256 toMint
    ) internal returns (uint256 remain, uint256 protocolFee) {
        IVault v = IVault(address(this));
        uint256 inflationFeePct = v.getProtocolParameters().inflationFee; // e.g. 5 means 5%
        
        // vNOMA share set to inflation fee for now
        uint256 vNomaShare = (toMint * inflationFeePct) / 100;

        address teamMultisig = v.teamMultiSig();
        
        uint256 baseAfterVnoma = toMint - vNomaShare;
        uint256 inflation = (baseAfterVnoma * inflationFeePct) / 100;

        if (inflation == 0) {
            if (_v.vNOMAContract != address(0)) {
                IERC20(IUniswapV3Pool(poolAddr).token0()).safeTransfer(_v.vNOMAContract, vNomaShare);
            }
            return (baseAfterVnoma, 0); // all else remains
        }

        // 1.25% caller fee out of inflation
        uint256 callerFee = (inflation * 125) / 10_000;
        uint256 remAfterCaller = inflation - callerFee;

        // split remaining inflation pot equally between team + creator
        protocolFee = remAfterCaller / 2;
        uint256 creatorFee = remAfterCaller - protocolFee;

        // Caller
        _pay(IUniswapV3Pool(poolAddr).token0(), caller, callerFee);

        // Team
        if (protocolFee > 0 && teamMultisig != address(0)) {
            if (dividendDistributor() == address(0)) {
                _pay(IUniswapV3Pool(poolAddr).token0(), teamMultisig, protocolFee);
                _v.totalTeamFees += protocolFee;
                // do this to avoid double distribution
                protocolFee = 0; 
            }
        }

        // Creator / manager
        if (creatorFee > 0 && _v.manager != address(0)) {
            _pay(IUniswapV3Pool(poolAddr).token0(), _v.manager, creatorFee);
            _v.totalCreatorFees += creatorFee;
        }

        // vToken share (or fallback to team)
        if (vNomaShare > 0) {
            address vTokenAddr = vToken();
            address recipient = vTokenAddr != address(0) ? vTokenAddr : teamMultisig;
            _pay(IUniswapV3Pool(poolAddr).token0(), recipient, vNomaShare);
        }
       
        // remain is the base minus inflation 
        remain = baseAfterVnoma - inflation;
    }

    function _pay(
        address token,
        address to,
        uint256 amount
    ) internal {
        if (to != address(0) && amount > 0) {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function _notifyStaking(uint256 amount) internal {
        // [C-02 FIX] Use SafeERC20
        IERC20(_v.tokenInfo.token0).safeTransfer(
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
        (,,uint256 floor0,uint256 floor1) = IModelHelper(modelHelper())
        .getUnderlyingBalances(
            poolAddr,
            address(this),
            LiquidityType.Floor
        );
            
        Uniswap
        .collect(
            poolAddr,
            address(this),
            _v.floorPosition.lowerTick,
            _v.floorPosition.upperTick
        );

        LiquidityDeployerMin
        .reDeployFloor(
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
    // function _collectLiquidity(
    //     LiquidityPosition[3] memory positions,
    //     ProtocolAddresses memory addresses
    // ) internal {
    //     for (uint256 i = 0; i < positions.length; i++) {
    //         Uniswap.collect(
    //             addresses.pool, 
    //             address(this), 
    //             positions[i].lowerTick, 
    //             positions[i].upperTick
    //         );          
    //     }
    // }

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
     * @notice Retrieves the address of the vToken contract.
     * @return The address of the contract.
     */
    function vToken() internal view returns (address) {
        IAddressResolver resolver = _v.resolver;
        address _vToken = resolver
        .getVaultAddress(
            address(this), 
            Utils.stringToBytes32("vToken")
        );
        return _vToken;
    }

    /**
     * @notice Retrieves the address of the dividend distributor contract.
     * @return The address of the contract.
     */
    function dividendDistributor() public view returns (address) {
        IAddressResolver resolver = _v.resolver;
        address _dd = resolver
        .getAddress(
            Utils.stringToBytes32("DividendDistributor")
        );
        return _dd;
    }    

    /**
     * @notice Sets the staking contract address.
     * @param _stakingContract The address of the staking contract.
     */
    function setStakingContract(address _stakingContract) external onlyManager {
        _v.stakingContract = _stakingContract;
    }

    /**
     * @notice Checks if staking is enabled.
     * @return True if staking is enabled, false otherwise.
     */
    function stakingEnabled() external view returns (bool) {
        return _v.stakingEnabled;
    }

    function getVNOMAContract() external view returns (address) {
        return _v.vNOMAContract;
    }

    function setvNOMAContract(address _vNOMAContract) external onlyManager() {
        _v.vNOMAContract = _vNOMAContract;
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
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards(address,(address,address,address,address,address,address,address))"))); 
        selectors[1] = bytes4(keccak256(bytes("setStakingContract(address)")));
        selectors[2] = bytes4(keccak256(bytes("stakingEnabled()")));
        selectors[3] = bytes4(keccak256(bytes("setvNOMAContract(address)")));
        selectors[4] = bytes4(keccak256(bytes("getVNOMAContract()")));
        return selectors;
    }
}