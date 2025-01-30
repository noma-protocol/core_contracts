// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IModelHelper } from "../../src/interfaces/IModelHelper.sol";
import { IDeployer } from "../../src/interfaces/IDeployer.sol";
import { LiquidityOps } from "../../src/libraries/LiquidityOps.sol";
import { VaultStorage } from "../../src/libraries/LibAppStorage.sol";

import {
    LiquidityPosition, 
    ProtocolAddresses,
    ProtocolParameters
} from "../../src/types/Types.sol";

interface IStakingVault {
    function mintAndDistributeRewards(ProtocolAddresses memory addresses) external;
}

interface IVault {
    function getPositions() external view returns (LiquidityPosition[3] memory positions);
    function getProtocolAddresses() external view returns (ProtocolAddresses memory addresses);
    function protocolParameters() external view returns (ProtocolParameters memory _params);
}

contract ExtVaultUpgraded {
    VaultStorage internal _v;

    error DisabledFunction();

    function shift() public {
        revert DisabledFunction();
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
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256(bytes("shift()")));
        selectors[1] = bytes4(keccak256(bytes("slide()")));          
        return selectors;
    }
}