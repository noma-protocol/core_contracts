// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseVault} from "../BaseVault.sol";
import {IModelHelper} from "../../interfaces/IModelHelper.sol";
import {DecimalMath} from "../../libraries/DecimalMath.sol";
import {Uniswap} from "../../libraries/Uniswap.sol";
import {LiquidityDeployer} from "../../libraries/LiquidityDeployer.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {ITokenRepo} from "../../TokenRepo.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    LoanPosition
} from "../../types/Types.sol";

interface INomaFactory {
    function deferredDeploy(address deployer) external;
    function mintTokens(address to, uint256 amount) external;
    function burnFor(address from, uint256 amount) external;
    function teamMultiSig() external view returns (address);
}

// Custom errors
error NotInitialized();
error InsufficientLoanAmount();
error InvalidDuration();
error InsufficientFloorBalance();
error NoActiveLoan();
error ActiveLoan();
error LoanExpired();
error InsufficientCollateral();
error CantRollLoan();
error NoLiquidity();
error OnlyVault();
error InvalidRepayAmount();
error InvalidParams();
error NotPermitted();

/**
 * @title LendingVault
 * @notice A contract for managing lending and borrowing functionality within a vault.
 * @dev This contract extends the `BaseVault` contract and provides functionality for borrowing, repaying loans, and managing collateral.
 */
contract LendingVaultRemove is BaseVault {
    using SafeERC20 for IERC20;

    /**
     * @notice Updates the liquidity positions in the vault.
     * @param _positions The new liquidity positions.
     */
    function updatePositions(LiquidityPosition[3] memory _positions) public onlyInternalCalls {
        if (!_v.initialized) revert NotInitialized();             
        // if (_positions[0].liquidity == 0 || _positions[1].liquidity == 0 || _positions[2].liquidity == 0) revert NoLiquidity();
        
        _updatePositions(_positions);
    }

    /**
     * @notice Internal function to update the liquidity positions.
     * @param _positions The new liquidity positions.
     */
    function _updatePositions(LiquidityPosition[3] memory _positions) internal {   
        // if (_positions[0].liquidity == 0 || _positions[1].liquidity == 0 || _positions[2].liquidity == 0) revert NoLiquidity();

        _v.floorPosition = _positions[0];
        _v.anchorPosition = _positions[1];
        _v.discoveryPosition = _positions[2];
    }
    

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("updatePositions((int24,int24,uint128,uint256,int24)[3])")));

        return selectors;
    }
}