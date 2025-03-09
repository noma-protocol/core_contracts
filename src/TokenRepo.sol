// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITokenRepo {
    function transfer(address token, address to, uint256 amount) external;
}

contract TokenRepo {

    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function transfer(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

}