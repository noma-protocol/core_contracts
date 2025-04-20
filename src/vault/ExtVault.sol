// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LiquidityOps } from "../libraries/LiquidityOps.sol";
import {
    LiquidityPosition, 
    ProtocolAddresses
} from "../types/Types.sol";

import { IVault } from "../interfaces/IVault.sol";
import { IAddressResolver } from "../interfaces/IAddressResolver.sol";
import { VaultStorage } from "../libraries/LibAppStorage.sol";

interface IStakingVault {
    function mintAndDistributeRewards(address caller, ProtocolAddresses memory addresses) external;
}

interface ILendingVault {
    function borrowFromFloor(address who, uint256 borrowAmount, uint256 duration) external;
    function paybackLoan(address who, uint256 amount) external;
    function rollLoan(address who, uint256 newDuration) external;
    function addCollateral(address who, uint256 amount) external;
    function defaultLoans() external;
}

// Events
event Borrow(address indexed who, uint256 borrowAmount, uint256 duration);
event Payback(address indexed who);
event RollLoan(address indexed who);
event Shift();
event Slide();
event DefaultLoans();

error Locked();

/**
 * @title ExtVault
 * @notice A contract for vault external functions.
 * @dev n/a.
 */
contract ExtVault {
    VaultStorage internal _v;

    /**
     * @notice Allows a user to borrow tokens from the vault's floor liquidity.
     * @param borrowAmount The amount of tokens to borrow.
     * @param duration The duration of the loan.
     */
    function borrow(
        uint256 borrowAmount,
        uint256 duration
    ) external lock {
        ILendingVault(address(this))
        .borrowFromFloor(
            msg.sender,
            borrowAmount,
            duration
        );

        emit Borrow(msg.sender, borrowAmount, duration);
    }

    /**
     * @notice Allows anybody to default expired loans.
     */
    function defaultLoans() external lock {
        ILendingVault(address(this))
        .defaultLoans();

        emit DefaultLoans();
    }

    /**
     * @notice Allows a user to pay back a loan.
     */
    function payback(uint256 amount) external lock {
        ILendingVault(address(this))
        .paybackLoan(msg.sender, amount);

        emit Payback(msg.sender);
    }

    /**
     * @notice Allows a user to roll over a loan.
     */
    function roll(
        uint256 newDuration
    ) external lock {
        ILendingVault(address(this))
        .rollLoan(
            msg.sender,
            newDuration
        );

        emit RollLoan(msg.sender);
    }

    /**
     * @notice Allows a user to add collateral to their loan.
     * @param amount The amount of collateral to add.
     */
    function addCollateral(
        uint256 amount
    ) external lock {
        ILendingVault(address(this))
        .addCollateral(msg.sender, amount);
    }


    /**
     * @notice Shifts the liquidity positions in the vault.
     * @dev This function adjusts the liquidity positions and distributes staking rewards.
     * @dev It also pays rewards to the caller.
     */
    function shift() public lock {

        LiquidityPosition[3] memory positions = IVault(address(this)).getPositions();
        ProtocolAddresses memory addresses = IVault(address(this)).getProtocolAddresses();

        LiquidityOps.shift(
            addresses,
            positions
        );

        IStakingVault(address(this)).mintAndDistributeRewards(msg.sender, addresses);
        
        emit Shift();
    }    

    /**
     * @notice Slides the liquidity positions in the vault.
     * @dev This function adjusts the liquidity positions without distributing staking rewards.
     */
    function slide() public lock {

        LiquidityPosition[3] memory positions = IVault(address(this)).getPositions();
        ProtocolAddresses memory addresses = IVault(address(this)).getProtocolAddresses();

        LiquidityOps.slide(
            addresses,
            positions
        );

        emit Slide();
    }

    /// @dev Reentrancy lock modifier.
    modifier lock() {
        if (_v.isLocked[address(this)]) revert Locked();
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
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = bytes4(keccak256(bytes("shift()")));
        selectors[1] = bytes4(keccak256(bytes("slide()")));  
        selectors[2] = bytes4(keccak256(bytes("borrow(uint256,uint256)")));  
        selectors[3] = bytes4(keccak256(bytes("payback(uint256)")));
        selectors[4] = bytes4(keccak256(bytes("roll(uint256)")));  
        selectors[5] = bytes4(keccak256(bytes("addCollateral(uint256)")));           
        selectors[6] = bytes4(keccak256(bytes("defaultLoans()"))); 
        return selectors;
    }
}