// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LiquidityOps } from "../../libraries/LiquidityOps.sol"; 
import {
    LiquidityPosition, 
    ProtocolAddresses
} from "../../types/Types.sol";

import { IVault } from "../../interfaces/IVault.sol";
import { IAddressResolver } from "../../interfaces/IAddressResolver.sol";
import { VaultStorage } from "../../libraries/LibAppStorage.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LiquidityType, SwapParams} from "../../types/Types.sol";
import {Conversions} from "../../libraries/Conversions.sol";
import "../../errors/Errors.sol";

interface IStakingVault {
    function mintAndDistributeRewards(address caller, ProtocolAddresses memory addresses) external;
}

interface ILendingVault {
    function borrowFromFloor(address who, uint256 borrowAmount, uint256 duration) external;
    function paybackLoan(address who, uint256 amount) external;
    function rollLoan(address who, uint256 newDuration) external;
    function addCollateral(address who, uint256 amount) external;
    function defaultLoans() external returns (uint256 totalBurned, uint256 totalLoans);
}

// Events
event Borrow(address indexed who, uint256 borrowAmount, uint256 duration);
event Payback(address indexed who);
event RollLoan(address indexed who);
event DefaultLoans(uint256 totalBurned, uint256 totalLoans);

event Shift();
event Slide();

/**
 * @title ExtVault
 * @notice A contract for vault external functions.
 * @dev n/a.
 */
contract ExtVaultReplace {
    VaultStorage internal _v;


    function restoreLiquidity() public lock {

    }

    /// @dev Reentrancy lock modifier.
    modifier lock() {
        if (_v.isLocked[address(this)]) revert ReentrantCall();
        _v.isLocked[address(this)] = true;
        _;
        _v.isLocked[address(this)] = false;
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
     // TODO add defaultLoans to selectors
    function getFunctionSelectors() external pure  returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("slide()")));  
        return selectors;
    }
}