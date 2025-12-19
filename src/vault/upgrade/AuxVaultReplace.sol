// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { VaultStorage } from "../../libraries/LibAppStorage.sol";
import { ProtocolParameters, LiquidityPosition } from "../../types/Types.sol";
import { Utils } from "../../libraries/Utils.sol";
import "../../errors/Errors.sol";

interface INomaFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

/**
 * @title AuxVault
 * @notice A contract for vault auxiliary public functions.
 * @dev n/a.
 */
contract AuxVault {
    VaultStorage internal _v;

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
        // LiquidityPosition struct: (int24 lowerTick, int24 upperTick, uint128 liquidity, uint256 price, int24 tickSpacing, uint8 liquidityType)
        selectors[0] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256,int24,uint8)[3])")));
        return selectors;
    }
}