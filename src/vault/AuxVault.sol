// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultStorage } from "../libraries/LibAppStorage.sol";
import { Utils } from "../libraries/Utils.sol";
import { 
    LiquidityType, 
    LiquidityPosition,
    ProtocolAddresses, 
    LiquidityInternalPars, 
    ReferralEntity, 
    ProtocolParameters, 
    CreatorFacingParameters 
} from "../types/Types.sol";
// import { DeployHelper } from "../libraries/DeployHelper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Uniswap } from "../libraries/Uniswap.sol";
import { IVault } from "../interfaces/IVault.sol";
import { Conversions } from "../libraries/Conversions.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { LiquidityOps } from "../libraries/LiquidityOps.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";
import {Conversions} from "../libraries/Conversions.sol";
import "../libraries/TickMathExtra.sol";

interface INomaFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
    function recoverERC20(address token, address to) external;
}

interface ILendingVault {
    function loanLTV(address who) external view returns (uint256 ltv1e18);
    function vaultSelfRepayLoans(uint256 fundsToPull,uint256 start,uint256 limit) external returns (uint256 totalLoans, uint256 collateralToReturn);
}

interface IVaultExt {
    function mintTokens(address to, uint256 amount) external returns (bool);
}

error NotAuthorized();
error OnlyInternalCalls();
error NotInitialized();
error NoLiquidity();
error CallbackCaller();
error InsufficientBalance();

event LoanRepaidOnBehalf(address indexed who, uint256 amount, uint256 collateralReleased);

/**
 * @title AuxVault
 * @notice A contract for vault auxiliary public functions.
 * @dev n/a.
 */
contract AuxVault {
    using SafeERC20 for IERC20;

    VaultStorage internal _v;

    function _handleV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta
    ) internal {
        if (msg.sender != address(_v.pool)) revert CallbackCaller();

        // No tokens owed → nothing to do
        if (amount0Delta <= 0 && amount1Delta <= 0) {
            return;
        }

        if (amount0Delta > 0) {
            uint256 balance0 = IERC20(_v.tokenInfo.token0).balanceOf(address(this));
            if (balance0 <  uint256(amount0Delta)) {
                _mintTokens(address(this),  uint256(amount0Delta));
            }
            // [C-02 FIX] Use SafeERC20
            IERC20(_v.tokenInfo.token0).safeTransfer(msg.sender, uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            uint256 bal1 = IERC20(_v.tokenInfo.token1).balanceOf(address(this));
            if (bal1 < uint256(amount1Delta)) revert InsufficientBalance();
            // [C-02 FIX] Use SafeERC20
            IERC20(_v.tokenInfo.token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        _handleV3SwapCallback(amount0Delta, amount1Delta);
    }

    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        _handleV3SwapCallback(amount0Delta, amount1Delta);
    }

    /**
     * @notice Mints new tokens and distributes them to the specified address.
     * @param to The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mintTokens(
        address to,
        uint256 amount
    ) public onlyInternalCalls returns (bool) {
        
        return _mintTokens(to, amount);
    }

    function _mintTokens(
        address to,
        uint256 amount
    ) internal returns (bool) {
        
        _v.timeLastMinted = block.timestamp;

        INomaFactory(_v.factory)
        .mintTokens(
            to,
            amount
        );

        return true;
    }

    /**
     * @notice Burns tokens from the vault.
     * @param amount The amount of tokens to burn.
     */
    function burnTokens(
        uint256 amount
    ) public onlyInternalCalls {

        IERC20(_v.pool.token0()).approve(address(_v.factory), amount);

        INomaFactory(_v.factory)
        .burnFor(
            address(this),
            amount
        );
    }

    function fixInbalance(
        address pool,
        uint160 sqrtPriceX96,
        uint256 amount
    ) public onlyInternalCalls {
        bool isOverLimit = Conversions.isNearMaxSqrtPrice(sqrtPriceX96);

        if (isOverLimit) {
            IUniswapV3Pool(pool).swap(
                address(this),
                true,
                int256(amount),
                TickMath.MIN_SQRT_RATIO + 1,
                ""
            );
        }
    }

    function _setFees(
        LiquidityPosition[3] memory positions
    ) internal {

        (
            uint256 feesPosition0Token0,
            uint256 feesPosition0Token1, 
            uint256 feesPosition1Token0, 
            uint256 feesPosition1Token1
        ) = LiquidityOps._calculateFees(address(this), address(_v.pool), positions);

        IVault(address(this)).setFees(
            feesPosition0Token0, 
            feesPosition0Token1
        );

        IVault(address(this)).setFees(
            feesPosition1Token0, 
            feesPosition1Token1
        );
        
    }

    /**
     * @notice Triggers self repayment of qualified loans.
     */
    function selfRepayLoans(
        uint256 amountToPull, 
        uint256 start, 
        uint256 limit
    ) public onlyManagerOrMultiSig {

        (uint256 collateralToReturn, uint256 totalRepaid) = 
        ILendingVault(address(this)).vaultSelfRepayLoans(amountToPull, start, limit);

        emit LoanRepaidOnBehalf(msg.sender, totalRepaid, collateralToReturn);
    }

    /**
    * @notice Allows creators to update only the subset of protocol parameters
    * that are explicitly creator-facing, leaving the rest unchanged.
    */
    function setProtocolParametersCreator(
        CreatorFacingParameters memory cp
    ) public onlyManager {
        ProtocolParameters storage p = _v.protocolParameters;

        // ✅ always allowed
        p.lowBalanceThresholdFactor  = cp.lowBalanceThresholdFactor;
        p.highBalanceThresholdFactor = cp.highBalanceThresholdFactor;
        p.halfStep                   = cp.halfStep;

        // 🔒 privileged: only if advanced config is enabled
        if (_v.isAdvancedConfEnabled) {
            p.discoveryBips        = cp.discoveryBips;
            p.shiftAnchorUpperBips = cp.shiftAnchorUpperBips;
            p.slideAnchorUpperBips = cp.slideAnchorUpperBips;

            p.inflationFee         = cp.inflationFee;
            p.loanFee              = cp.loanFee;
            p.selfRepayLtvTreshold = cp.selfRepayLtvTreshold;

            p.shiftRatio           = cp.shiftRatio;
        }
    }

    
    function setManager(address manager) public onlyManagerOrMultiSig {
        _v.manager = manager;
    }

    function setAdvancedConf(bool flag) public onlyMultiSig {
        _v.isAdvancedConfEnabled = flag;
    }
    
    function recoverERC20(address token, address to) public onlyMultiSig {
        if (to != INomaFactory(_v.factory).teamMultiSig()) revert NotAuthorized();

        IStakingRewards(_v.stakingContract).recoverERC20(token, to);
    }

    function getReferralEntity(address who) public view returns (ReferralEntity memory) {
        // Get referral code directly as bytes8
        bytes8 code = Utils.getReferralCode(who);

        if (code == bytes8(0)) {
            return ReferralEntity({
                code: bytes8(0),
                totalReferred: 0
            });
        }

        return _v.referrals[code];
    }

    /**
     * @notice Retrieves the time since the last mint operation.
     * @return The time since the last mint operation.
     */
    function getTimeSinceLastMint() public view returns (uint256) {
        return block.timestamp - _v.timeLastMinted;
    }

    /**
     * @notice Retrieves the address of the team multisig.
     * @return The address of the team multisig.
     */
    function teamMultiSig() public view returns (address) {
        return INomaFactory(_v.factory).teamMultiSig();
    }


    /**
     * @notice Retrieves the Uniswap V3 pool contract.
     * @return The Uniswap V3 pool contract.
     */
    function pool() public view returns (IUniswapV3Pool) {
        return _v.pool;
    }

    /**
     * @notice Retrieves the accumulated fees.
     * @return The accumulated fees for token0 and token1.
     */
    function getAccumulatedFees() public view returns (uint256, uint256) {
        return (_v.feesAccumulatorToken0, _v.feesAccumulatorToken1);
    }

    function setModelHelper(address modelHelper) public onlyMultiSig {
        _v.modelHelper = modelHelper;
    }   
    
    /**
     * @notice Sets or updates a referral entity.
     * @param code The referral code.
     * @param amount The amount to add to the total referred.
     */
    function setReferralEntity(
        bytes8 code, 
        uint256 amount
    ) public onlyAuthorizedContracts {
        uint256 totalReferred = _v.referrals[code].totalReferred;

        _v.referrals[code] = ReferralEntity({
            code: code,
            totalReferred: (totalReferred + amount)
        });
    }

    /**
     * @notice Sets the accumulated fees for token0 and token1.
     * @param _feesAccumulatedToken0 The accumulated fees for token0.
     * @param _feesAccumulatedToken1 The accumulated fees for token1.
     */
    function setFees(
        uint256 _feesAccumulatedToken0, 
        uint256 _feesAccumulatedToken1
    ) public onlyInternalCalls {
        _v.feesAccumulatorToken0 += _feesAccumulatedToken0;
        _v.feesAccumulatorToken1 += _feesAccumulatedToken1;
    }

    /**
     * @notice Updates the liquidity positions in the vault.
     * @param positions The new liquidity positions.
     */
    function updatePositions(LiquidityPosition[3] memory positions) public onlyInternalCalls {
        if (!_v.initialized) revert NotInitialized();             
        if (positions[0].liquidity == 0 /*|| positions[1].liquidity == 0 || positions[2].liquidity == 0*/) revert NoLiquidity();
        
        _updatePositions(positions);
    }

    /**
     * @notice Internal function to update the liquidity positions.
     * @param positions The new liquidity positions.
     */
    function _updatePositions(LiquidityPosition[3] memory positions) internal {   
        _v.floorPosition = positions[0];
        _v.anchorPosition = positions[1];
        _v.discoveryPosition = positions[2];
    }

    function setProtocolParameters(
        ProtocolParameters memory protocolParameters
    ) public onlyMultiSig {
        _v.protocolParameters = protocolParameters;
    }

    function consumeReferral(bytes8 code, uint256 amount) external {
        if (msg.sender != vToken()) revert NotAuthorized();

        uint256 bal = _v.referrals[code].totalReferred;
        if (amount > bal) amount = bal; // or revert
        unchecked {
            _v.referrals[code].totalReferred = bal - amount;
        }
    }

    /**
     * @notice Retrieves the address of the exchange helper.
     * @return The address of the contract.
     */
    function exchangeHelper() public view returns (address) {
        IAddressResolver resolver = _v.resolver;
        address _exchangeHelper = resolver
        .getVaultAddress(
            address(this), 
            Utils.stringToBytes32("ExchangeHelper")
        );
        if (_exchangeHelper == address(0)) {
            _exchangeHelper = resolver
                .requireAndGetAddress(
                    Utils.stringToBytes32("ExchangeHelper"), 
                    "no ExchangeHelper"
                );
        }
        return _exchangeHelper;
    }

 

    /**
     * @notice Retrieves the address of the vToken contract.
     * @return The address of the contract.
     */
    function vToken() public view returns (address) {
        IAddressResolver resolver = _v.resolver;
        address _vToken = resolver
        .getVaultAddress(
            address(this), 
            Utils.stringToBytes32("vToken")
        );
        return _vToken;
    }

    function getTotalCreatorEarnings() public view returns (uint256) {
        return _v.totalCreatorFees;
    }

    function getTotalTeamEarnings() public view returns (uint256) {
        return _v.totalTeamFees;
    }

    /**
     * @notice Modifier to restrict access to the authorized manager.`
     */
    modifier authorized() {
        if (msg.sender != _v.manager) revert NotAuthorized();
        _;
    }

    modifier onlyMultiSig() {
        if (msg.sender != INomaFactory(_v.factory).teamMultiSig()) {
            revert NotAuthorized();
        }
        _;        
    }

     modifier onlyManager() {
        if (msg.sender != _v.manager) {
            revert NotAuthorized();
        }
        _;
    }   

    modifier onlyManagerOrMultiSig() {
        address multiSig = INomaFactory(_v.factory).teamMultiSig();
        if (msg.sender != _v.manager && msg.sender != multiSig) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @notice Modifier to restrict access to internal calls.
     */
    modifier onlyInternalCalls() {
        if (msg.sender != _v.factory && msg.sender != address(this)) revert OnlyInternalCalls();
        _;        
    }

    modifier onlyAuthorizedContracts() {
        if (msg.sender != exchangeHelper() && msg.sender != vToken()) revert NotAuthorized();
        _;        
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](22);
        selectors[0] = bytes4(keccak256(bytes("teamMultiSig()")));
        selectors[1] = bytes4(keccak256(bytes("getTimeSinceLastMint()")));
        selectors[2] = bytes4(keccak256(bytes("getAccumulatedFees()")));
        selectors[3] = bytes4(keccak256(bytes("pool()")));
        selectors[4] = bytes4(
            keccak256(
                bytes("setProtocolParameters((uint8,uint8,uint8,uint16[2],uint256,uint256,int24,int24,int24,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,(uint8,uint8),uint256))")
            )
        );      
        selectors[5] = bytes4(keccak256(bytes("setManager(address)")));
        selectors[6] = bytes4(keccak256(bytes("setModelHelper(address)")));
        selectors[7] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256,int24,uint8)[3])")));
        selectors[8] = bytes4(keccak256(bytes("mintTokens(address,uint256)")));
        selectors[9] = bytes4(keccak256(bytes("burnTokens(uint256)")));
        selectors[10] = bytes4(keccak256(bytes("setReferralEntity(bytes8,uint256)")));
        selectors[11] = bytes4(keccak256(bytes("getReferralEntity(address)")));
        selectors[12] = bytes4(keccak256(bytes("setProtocolParametersCreator((int24,int24,int24,uint256,uint256,uint256,uint256,uint256,uint256,uint256))")));
        selectors[13] = bytes4(keccak256(bytes("getTotalCreatorEarnings()")));
        selectors[14] = bytes4(keccak256(bytes("getTotalTeamEarnings()")));
        selectors[15] = bytes4(keccak256(bytes("setFees(uint256,uint256)")));
        selectors[16] = bytes4(keccak256(bytes("fixInbalance(address,uint160,uint256)")));
        selectors[17] = bytes4(keccak256(bytes("uniswapV3SwapCallback(int256,int256,bytes)")));
        selectors[18] = bytes4(keccak256(bytes("pancakeV3SwapCallback(int256,int256,bytes)")));
        selectors[19] = bytes4(keccak256(bytes("recoverERC20(address,address)")));
        selectors[20] = bytes4(keccak256(bytes("setAdvancedConf(bool)")));
        selectors[21] = bytes4(keccak256(bytes("consumeReferral(bytes8,uint256)")));

        return selectors; 
    }
}        
