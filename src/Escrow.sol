// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

contract Escrow is Owned {

    address public vault;

    constructor(
        address _modelHelper
    ) Owned(msg.sender) {
        
    }

    function triggerDeposit() public {

    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }


    modifier onlyVault() {
        require(msg.sender == vault, "Escrow: only vault");
        _;
    }
}