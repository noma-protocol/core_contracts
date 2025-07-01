// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultStorage } from "../libraries/LibAppStorage.sol";
import { ProtocolParameters, LiquidityPosition } from "../types/Types.sol";
import { Utils } from "../libraries/Utils.sol";
import { IModelHelper } from "../interfaces/IModelHelper.sol";
import { IDeployer } from "../interfaces/IDeployer.sol";
import { LiquidityType, ProtocolAddresses, LiquidityInternalPars } from "../types/Types.sol";
import { DeployHelper } from "../libraries/DeployHelper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Uniswap } from "../libraries/Uniswap.sol";
import { LiquidityOps } from "../libraries/LiquidityOps.sol";
import { IVault } from "../interfaces/IVault.sol";
import { DecimalMath } from "../libraries/DecimalMath.sol";
import { Conversions } from "../libraries/Conversions.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";

interface IOikosFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

error NotAuthorized();
error OnlyInternalCalls();
error NotInitialized();
error NoLiquidity();

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
    ) public onlyInternalCalls {
        
        _v.timeLastMinted = block.timestamp;

        IOikosFactory(_v.factory)
        .mintTokens(
            to,
            amount
        );
    }

    /**
     * @notice Burns tokens from the vault.
     * @param amount The amount of tokens to burn.
     */
    function burnTokens(
        uint256 amount
    ) public onlyInternalCalls {

        IERC20(_v.pool.token0()).approve(address(_v.factory), amount);
        IOikosFactory(_v.factory)
        .burnFor(
            address(this),
            amount
        );
    }
    
    function bumpFloor(
        uint256 reserveAmount
    ) public onlyManagerOrMultiSig {
        if (!_v.initialized) revert NotInitialized();

        (,,, uint256 floorToken1Balance) = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(
            address(_v.pool), 
            address(this), 
            LiquidityType.Floor
        );

        (,,, uint256 anchorToken1Balance) = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(
            address(_v.pool), 
            address(this), 
            LiquidityType.Anchor
        );

        LiquidityPosition[3] memory positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];

        _setFees(positions);

        // Collect floor liquidity
        Uniswap.collect(
            address(_v.pool),
            address(this), 
            positions[0].lowerTick, 
            positions[0].upperTick
        ); 

        // Collect anchor liquidity
        Uniswap.collect(
            address(_v.pool),
            address(this), 
            positions[1].lowerTick, 
            positions[1].upperTick
        );

        uint256 circulatingSupply = IVault(address(this)).getCirculatingSupply(address(_v.pool), address(this));

        uint256 targetFloorPrice = DecimalMath.divideDecimal(
            floorToken1Balance + reserveAmount, 
            circulatingSupply
        );

        if (address(this).balance >= floorToken1Balance + reserveAmount) {
            IERC20(
                IUniswapV3Pool(_v.pool).token1()
            ).safeTransfer(
                _v.deployerContract, 
                floorToken1Balance + reserveAmount
            );
        }

        LiquidityPosition[3] memory newPositions = [
            positions[0], 
            positions[1], 
            positions[2]
        ];

        newPositions[0] = IDeployer(_v.deployerContract) 
        .shiftFloor(
            address(_v.pool), 
            address(this), 
            Conversions
            .sqrtPriceX96ToPrice(
                Conversions
                .tickToSqrtPriceX96(
                    positions[0].upperTick
                ), 
            IERC20Metadata(
                IUniswapV3Pool(_v.pool).token1()
            ).decimals()
            ), 
            targetFloorPrice,
            floorToken1Balance + reserveAmount,
            floorToken1Balance,
            positions[0]
        );

        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(_v.pool).slot0();

        // Deploy new anchor position
        newPositions[1] = LiquidityOps
        .reDeploy(
            ProtocolAddresses({
                pool: address(_v.pool),
                modelHelper: _v.modelHelper,
                vault: address(this),
                deployer: _v.deployerContract,
                presaleContract: _v.presaleContract,
                adaptiveSupplyController: _v.adaptiveSupplyController
            }),
            LiquidityInternalPars({
                lowerTick: newPositions[0].upperTick,
                upperTick: Utils.addBipsToTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96), 
                    IVault(address(this))
                    .getProtocolParameters().shiftAnchorUpperBips,
                    IERC20Metadata(
                        IUniswapV3Pool(_v.pool).token1()
                    ).decimals(),
                    positions[0].tickSpacing
                ),
                amount1ToDeploy: anchorToken1Balance - reserveAmount,
                liquidityType: LiquidityType.Anchor
            }),
            true
        );

        IVault(address(this))
        .updatePositions(
            newPositions
        ); 
    }

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
        IOikosFactory(
            _v.factory
        ).deferredDeploy(
            deployer
        );
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
        return IOikosFactory(_v.factory).teamMultiSig();
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
     * @notice Modifier to restrict access to the authorized manager.`
     */
    modifier authorized() {
        if (msg.sender != _v.manager) revert NotAuthorized();
        _;
    }

    modifier onlyManagerOrMultiSig() {
        if (msg.sender != _v.manager && msg.sender != IOikosFactory(_v.factory).teamMultiSig()) {
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

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = bytes4(keccak256(bytes("teamMultiSig()")));
        selectors[1] = bytes4(keccak256(bytes("getProtocolParameters()")));  
        selectors[2] = bytes4(keccak256(bytes("getTimeSinceLastMint()")));
        selectors[3] = bytes4(keccak256(bytes("getAccumulatedFees()")));
        selectors[4] = bytes4(keccak256(bytes("pool()")));
        selectors[5] = bytes4(keccak256(bytes("getPositions()")));
        selectors[6] = bytes4(keccak256(bytes("afterPresale()")));
        selectors[7] = bytes4(keccak256(bytes("setProtocolParameters((uint8,uint8,uint8,uint16[2],uint256,uint256,int24,int24,int24,uint256,uint256,uint256,uint256,uint256,uint256))")));
        selectors[8] = bytes4(keccak256(bytes("setManager(address)")));
        selectors[9] = bytes4(keccak256(bytes("setModelHelper(address)")));
        selectors[10] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256,int24)[3])")));
        selectors[11] = bytes4(keccak256(bytes("mintTokens(address,uint256)")));
        selectors[12] = bytes4(keccak256(bytes("burnTokens(uint256)")));
        selectors[13] = bytes4(keccak256(bytes("bumpFloor(uint256)")));
        return selectors;
    }
}        
