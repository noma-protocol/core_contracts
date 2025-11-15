// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultStorage } from "../libraries/LibAppStorage.sol";
import { ProtocolParameters, LiquidityPosition } from "../types/Types.sol";
import { Utils } from "../libraries/Utils.sol";
import { IModelHelper } from "../interfaces/IModelHelper.sol";
import { IDeployer } from "../interfaces/IDeployer.sol";
import { LiquidityType, ProtocolAddresses, LiquidityInternalPars, ReferralEntity } from "../types/Types.sol";
import { DeployHelper } from "../libraries/DeployHelper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Uniswap } from "../libraries/Uniswap.sol";
import { IVault } from "../interfaces/IVault.sol";
import { DecimalMath } from "../libraries/DecimalMath.sol";
import { Conversions } from "../libraries/Conversions.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { LiquidityDeployer } from "../libraries/LiquidityDeployer.sol";
import { LiquidityOps } from "../libraries/LiquidityOps.sol";
import {IAddressResolver} from "../interfaces/IAddressResolver.sol";

interface INomaFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface ILendingVault {
    function loanLTV(address who) external view returns (uint256 ltv1e18);
    function vaultSelfRepayLoans(uint256 fundsToPull,uint256 start,uint256 limit) external returns (uint256 totalLoans, uint256 collateralToReturn);
}

error NotAuthorized();
error OnlyInternalCalls();
error NotInitialized();
error NoLiquidity();

event LoanRepaidOnBehalf(address indexed who, uint256 amount, uint256 collateralReleased);

/**
 * @title AuxVault
 * @notice A contract for vault auxiliary public functions.
 * @dev n/a.
 */
contract AuxVault {
    using SafeERC20 for IERC20;

    VaultStorage internal _v;

    /**
     * @notice Mints new tokens and distributes them to the specified address.
     * @param to The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mintTokens(
        address to,
        uint256 amount
    ) public onlyInternalCalls returns (bool) {
        
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
    
    // function bumpRewards(uint256 bnbAmount) public onlyManagerOrMultiSig {
    //     if (!_v.initialized) revert NotInitialized();
        
    //     LiquidityPosition[3] memory positions = [
    //         _v.floorPosition, 
    //         _v.anchorPosition, 
    //         _v.discoveryPosition
    //     ];

    //     (,,uint256 floorToken0Balance, uint256 floorToken1Balance) = IModelHelper(_v.modelHelper)
    //     .getUnderlyingBalances(
    //         address(_v.pool), 
    //         address(this), 
    //         LiquidityType.Floor
    //     );

    //     (,,, uint256 anchorToken1Balance) = IModelHelper(_v.modelHelper)
    //     .getUnderlyingBalances(
    //         address(_v.pool), 
    //         address(this), 
    //         LiquidityType.Anchor
    //     );

    //     // Collect fees from the pool
    //     Uniswap.collect(
    //         address(_v.pool),
    //         address(this), 
    //         positions[0].lowerTick, 
    //         positions[0].upperTick
    //     );

    //     // Collect anchor liquidity
    //     Uniswap.collect(
    //         address(_v.pool),
    //         address(this), 
    //         positions[1].lowerTick, 
    //         positions[1].upperTick
    //     );

    //     _v.timeLastMinted = block.timestamp;

    //     uint256 imv = IModelHelper(_v.modelHelper)
    //     .getIntrinsicMinimumValue(address(this));
        
    //     INomaFactory(_v.factory)
    //     .mintTokens(
    //         address(this),
    //         DecimalMath.divideDecimal(
    //         bnbAmount, 
    //         imv
    //     )
    //     );
        
    //     if (_v.stakingContract == address(0)) {
    //         revert NotInitialized();
    //     }

    //     IERC20(_v.tokenInfo.token0).transfer(
    //         _v.stakingContract,
    //         DecimalMath.divideDecimal(
    //         bnbAmount, 
    //         imv
    //     )
    //     );

    //     IStakingRewards(_v.stakingContract)
    //         .notifyRewardAmount(
    //         DecimalMath.divideDecimal(
    //             bnbAmount, 
    //             imv
    //         )
    //     );     

    //     LiquidityPosition memory newFloorPos = LiquidityDeployer
    //     .reDeployFloor(
    //         address(_v.pool), 
    //         address(this), 
    //         floorToken0Balance, 
    //         floorToken1Balance + bnbAmount, 
    //         positions
    //     );     

    //     (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(_v.pool).slot0();
                  
    //     // Deploy new anchor position
    //     LiquidityPosition memory newAnchorPos = LiquidityOps
    //     .reDeploy(
    //         ProtocolAddresses({
    //             pool: address(_v.pool),
    //             modelHelper: _v.modelHelper,
    //             vault: address(this),
    //             deployer: _v.deployerContract,
    //             presaleContract: _v.presaleContract,
    //             adaptiveSupplyController: _v.adaptiveSupplyController
    //         }),
    //         LiquidityInternalPars({
    //             lowerTick: positions[0].upperTick,
    //             upperTick: Utils.addBipsToTick(
    //                 TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
    //                 IVault(address(this))
    //                 .getProtocolParameters().shiftAnchorUpperBips,
    //                 IERC20Metadata(
    //                     IUniswapV3Pool(_v.pool).token1()
    //                 ).decimals(),
    //                 positions[0].tickSpacing
    //             ),
    //             amount1ToDeploy: anchorToken1Balance - bnbAmount,
    //             liquidityType: LiquidityType.Anchor
    //         }),
    //         true
    //     );

    //     positions = [
    //         newFloorPos, 
    //         newAnchorPos, 
    //         positions[2]
    //     ];

    //     _updatePositions(positions);
    //     IModelHelper(_v.modelHelper).enforceSolvencyInvariant(address(this));

    // }

    function _setFees(
        LiquidityPosition[3] memory positions
    ) internal {

        (
            uint256 feesPosition0Token0,
            uint256 feesPosition0Token1, 
            uint256 feesPosition1Token0, 
            uint256 feesPosition1Token1
            ) = LiquidityOps._calculateFees(address(_v.pool), positions);

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
     * @notice Handles the post-presale actions.
     */
    function afterPresale() public  {
        if (msg.sender != _v.presaleContract) revert NotAuthorized();
        address deployer = _v.resolver.requireAndGetAddress(
            Utils.stringToBytes32("Deployer"), 
            "no Deployer"
        );
        INomaFactory(
            _v.factory
        ).deferredDeploy(
            deployer
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

    function setProtocolParameters(
        ProtocolParameters memory protocolParameters
    ) public onlyManagerOrMultiSig {
        _v.protocolParameters = protocolParameters;
    }

    function setManager(address manager) public onlyManagerOrMultiSig {
        _v.manager = manager;
    }

    /**
     * @notice Retrieves the current liquidity positions.
     * @return positions The current liquidity positions.
     */
    function getPositions() public view
    returns (LiquidityPosition[3] memory positions) {
        positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];
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
     * @notice Retrieves the protocol parameters.
     * @return The protocol parameters.
     */
    function getProtocolParameters() public view returns 
    (ProtocolParameters memory ) {
        return _v.protocolParameters;
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

    function setModelHelper(address modelHelper) public onlyManagerOrMultiSig {
        _v.modelHelper = modelHelper;
    }   

    /**
     * @notice Updates the liquidity positions in the vault.
     * @param _positions The new liquidity positions.
     */
    function updatePositions(LiquidityPosition[3] memory _positions) public onlyInternalCalls {
        if (!_v.initialized) revert NotInitialized();             
        
        _updatePositions(_positions);
    }
    
    /**
     * @notice Internal function to update the liquidity positions.
     * @param _positions The new liquidity positions.
     */
    function _updatePositions(LiquidityPosition[3] memory _positions) internal {   
        _v.floorPosition = _positions[0];
        _v.anchorPosition = _positions[1];
        _v.discoveryPosition = _positions[2];
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

    /**
     * @notice Modifier to restrict access to the authorized manager.`
     */
    modifier authorized() {
        if (msg.sender != _v.manager) revert NotAuthorized();
        _;
    }

    modifier onlyManagerOrMultiSig() {
        if (msg.sender != _v.manager && msg.sender != INomaFactory(_v.factory).teamMultiSig()) {
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
        bytes4[] memory selectors = new bytes4[](15);
        selectors[0] = bytes4(keccak256(bytes("teamMultiSig()")));
        selectors[1] = bytes4(keccak256(bytes("getProtocolParameters()")));  
        selectors[2] = bytes4(keccak256(bytes("getTimeSinceLastMint()")));
        selectors[3] = bytes4(keccak256(bytes("getAccumulatedFees()")));
        selectors[4] = bytes4(keccak256(bytes("pool()")));
        selectors[5] = bytes4(keccak256(bytes("getPositions()")));
        selectors[6] = bytes4(keccak256(bytes("afterPresale()")));
        selectors[7] = bytes4(keccak256(bytes("setProtocolParameters((uint8,uint8,uint8,uint16[2],uint256,uint256,int24,int24,int24,uint256,uint256,uint256,uint256,uint256,uint256,uint256))")));
        selectors[8] = bytes4(keccak256(bytes("setManager(address)")));
        selectors[9] = bytes4(keccak256(bytes("setModelHelper(address)")));
        selectors[10] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256,int24)[3])")));
        selectors[11] = bytes4(keccak256(bytes("mintTokens(address,uint256)")));
        selectors[12] = bytes4(keccak256(bytes("burnTokens(uint256)")));
        // selectors[13] = bytes4(keccak256(bytes("bumpRewards(uint256)")));
        selectors[13] = bytes4(keccak256(bytes("setReferralEntity(bytes8,uint256)")));
        selectors[14] = bytes4(keccak256(bytes("getReferralEntity(address)")));
        // selectors[15] = bytes4(keccak256(bytes("selfRepayLoans(uint256,uint256,uint256)")));
        return selectors;
    }
}        
