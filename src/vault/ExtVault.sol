// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {BaseVault} from "./BaseVault.sol";

contract ExtVault is BaseVault {

    function test() public view returns (uint256) {
        return 1;
    }

    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256(bytes("test()")));
        return selectors;
    }
}