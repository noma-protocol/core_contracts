// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultStorage } from "../../libraries/LibAppStorage.sol";
import { ProtocolParameters, LiquidityPosition } from "../../types/Types.sol";
import { Utils } from "../../libraries/Utils.sol";
import { IModelHelper } from "../../interfaces/IModelHelper.sol";
import { IDeployer } from "../../interfaces/IDeployer.sol";
import { LiquidityType } from "../../types/Types.sol";
import { DeployHelper } from "../../libraries/DeployHelper.sol";

interface INomaFactory {
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
contract AuxVaultAdd {
    VaultStorage internal _v;

    function restoreLiquidityPriv() public {
        if (!_v.initialized) revert NotInitialized();
        // Restore liquidity logic can be added here
        
        uint256 circulatingSupply = IModelHelper(_v.modelHelper)
        .getCirculatingSupply(
            address(_v.pool),
            address(this)
        ); 

        (,,, uint256 floorToken1Balance) = IModelHelper(_v.modelHelper)
        .getUnderlyingBalances(
            address(_v.pool), 
            address(this), 
            LiquidityType.Floor
        );

        uint256 newFloorPrice = IDeployer(_v.deployerContract)
        .computeNewFloorPrice(
            0,
            floorToken1Balance,
            circulatingSupply,
            [
                _v.floorPosition, 
                _v.anchorPosition, 
                _v.discoveryPosition
            ]
        );

        (LiquidityPosition memory newFloor, ) =  DeployHelper
        .deployFloor(
            _v.pool,
            address(this), 
            newFloorPrice, 
            0,
            _v.tickSpacing
        );

        _updatePositions([
            newFloor,
            _v.anchorPosition,
            _v.discoveryPosition
        ]);
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
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("restoreLiquidityPriv()")));
        return selectors;
    }
}