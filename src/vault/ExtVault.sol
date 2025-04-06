// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LiquidityOps } from "../libraries/LiquidityOps.sol";
import {
    LiquidityPosition, 
    ProtocolAddresses
} from "../types/Types.sol";

import { IVault } from "../interfaces/IVault.sol";

interface IStakingVault {
    function mintAndDistributeRewards(ProtocolAddresses memory addresses) external;
}

interface ILendingVault {
    function borrowFromFloor(address who, uint256 borrowAmount, uint256 duration) external;
    function paybackLoan(address who) external;
    function rollLoan(address who, uint256 newDuration) external;
}

// Events
event Borrow(address indexed who, uint256 borrowAmount, uint256 duration);
event Payback(address indexed who);
event RollLoan(address indexed who);
event Shift();
event Slide();

/**
 * @title ExtVault
 * @notice A contract for vault external functions.
 * @dev n/a.
 */
contract ExtVault {

    /**
     * @notice Allows a user to borrow tokens from the vault's floor liquidity.
     * @param borrowAmount The amount of tokens to borrow.
     * @param duration The duration of the loan.
     */
    function borrow(
        uint256 borrowAmount,
        uint256 duration
    ) external {
        ILendingVault(address(this))
        .borrowFromFloor(
            msg.sender,
            borrowAmount,
            duration
        );

        emit Borrow(msg.sender, borrowAmount, duration);
    }

    /**
     * @notice Allows a user to pay back a loan.
     * @param who The address of the borrower.
     */
    function payback(
        address who
    ) external {
        ILendingVault(address(this))
        .paybackLoan(
            who
        );

        emit Payback(who);
    }

    /**
     * @notice Allows a user to roll over a loan.
     * @param who The address of the borrower.
     */
    function roll(
        address who,
        uint256 newDuration
    ) external {
        ILendingVault(address(this))
        .rollLoan(
            who,
            newDuration
        );

        emit RollLoan(who);
    }

    /**
     * @notice Shifts the liquidity positions in the vault.
     * @dev This function adjusts the liquidity positions and distributes staking rewards.
     */
    function shift() public {

        LiquidityPosition[3] memory positions = IVault(address(this)).getPositions();
        ProtocolAddresses memory addresses = IVault(address(this)).getProtocolAddresses();

        LiquidityOps.shift(
            addresses,
            positions
        );

        IStakingVault(address(this)).mintAndDistributeRewards(addresses);
        
        emit Shift();
    }    

    /**
     * @notice Slides the liquidity positions in the vault.
     * @dev This function adjusts the liquidity positions without distributing staking rewards.
     */
    function slide() public  {

        LiquidityPosition[3] memory positions = IVault(address(this)).getPositions();
        ProtocolAddresses memory addresses = IVault(address(this)).getProtocolAddresses();

        LiquidityOps.slide(
            addresses,
            positions
        );

        emit Slide();
    }

    /**
     * @notice Retrieves the function selectors for this contract.
     * @return selectors An array of function selectors.
     */
    function getFunctionSelectors() external pure  returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = bytes4(keccak256(bytes("shift()")));
        selectors[1] = bytes4(keccak256(bytes("slide()")));  
        selectors[2] = bytes4(keccak256(bytes("borrow(address,uint256,uint256)")));  
        selectors[3] = bytes4(keccak256(bytes("payback(address)")));
        selectors[4] = bytes4(keccak256(bytes("roll(address,uint256)")));              
        return selectors;
    }
}