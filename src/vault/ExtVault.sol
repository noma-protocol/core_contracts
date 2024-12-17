// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IModelHelper } from "../interfaces/IModelHelper.sol";
import { IDeployer } from "../interfaces/IDeployer.sol";
import { LiquidityOps } from "../libraries/LiquidityOps.sol";

import {
    LiquidityPosition, 
    ProtocolAddresses
} from "../types/Types.sol";

interface IStakingVault {
    function mintAndDistributeRewards(ProtocolAddresses memory addresses) external;
}

interface IVault {
    function getPositions() external view returns (LiquidityPosition[3] memory positions);
    function getProtocolAddresses() external view returns (ProtocolAddresses memory addresses);
}

contract ExtVault {

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

        LiquidityOps
        .slide(
            addresses,
            positions
        );
    }

    function getFunctionSelectors() external pure  returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256(bytes("shift()")));
        selectors[1] = bytes4(keccak256(bytes("slide()")));          
        return selectors;
    }
}