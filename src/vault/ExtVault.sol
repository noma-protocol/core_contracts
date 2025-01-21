// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IModelHelper } from "../interfaces/IModelHelper.sol";
import { IDeployer } from "../interfaces/IDeployer.sol";
import { LiquidityOps } from "../libraries/LiquidityOps.sol";
import {
    LiquidityStructureParameters,
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
    function rollLoan(address who) external;
}

contract ExtVault {

    function borrow(
        address who,
        uint256 borrowAmount
    ) external {
        ILendingVault(address(this))
        .borrowFromFloor(
            who,
            borrowAmount,
            30 days
        );
    }

    function payback(
        address who
    ) external {
        ILendingVault(address(this))
        .paybackLoan(
            who
        );
    }

    function roll(
        address who
    ) external {
        ILendingVault(address(this))
        .rollLoan(
            who
        );
    }

    function shift() public {

        LiquidityPosition[3] memory positions = IVault(address(this)).getPositions();
        ProtocolAddresses memory addresses = IVault(address(this)).getProtocolAddresses();

        LiquidityOps.shift(
            addresses,
            positions
        );

        IStakingVault(address(this)).mintAndDistributeRewards(addresses);
    }    

    function slide() public  {

        LiquidityPosition[3] memory positions = IVault(address(this)).getPositions();
        ProtocolAddresses memory addresses = IVault(address(this)).getProtocolAddresses();

        LiquidityOps.slide(
            addresses,
            positions
        );
    }

    function getFunctionSelectors() external pure  returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = bytes4(keccak256(bytes("shift()")));
        selectors[1] = bytes4(keccak256(bytes("slide()")));  
        selectors[2] = bytes4(keccak256(bytes("borrow(address,uint256)")));  
        selectors[3] = bytes4(keccak256(bytes("payback(address)")));
        selectors[4] = bytes4(keccak256(bytes("roll(address)")));              
        return selectors;
    }
}