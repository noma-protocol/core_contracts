// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IModelHelper } from "../../src/interfaces/IModelHelper.sol";
import { IDeployer } from "../../src/interfaces/IDeployer.sol";
import { LiquidityOps } from "../../src/libraries/LiquidityOps.sol";

import {
    LiquidityPosition, 
    ProtocolAddresses,
    LiquidityStructureParameters
} from "../../src/types/Types.sol";

interface IStakingVault {
    function mintAndDistributeRewards(ProtocolAddresses memory addresses) external;
}

interface IVault {
    function getPositions() external view returns (LiquidityPosition[3] memory positions);
    function getProtocolAddresses() external view returns (ProtocolAddresses memory addresses);
    function liquidityStructureParameters() external view returns (LiquidityStructureParameters memory _params);
}

contract ExtVaultUpgraded {

    error DisabledFunction();
    
    function extraFunction() public pure {
        revert DisabledFunction();
    }

    function getFunctionSelectors() external pure  returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);      
        selectors[0] = bytes4(keccak256(bytes("extraFunction()")));
        return selectors;
    }
}