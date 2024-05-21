// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/auth/Owned.sol";

contract MockWETH is Owned {
    string public name = "Mock WETH";
    string public symbol = "mWETH";
    uint8 public decimals = 18;

    event Approval(address indexed sender, address indexed who, uint256 amount);
    event Transfer(address indexed sender, address indexed receiver, uint256 amount);
    event Deposit(address indexed receiver, uint256 amount);
    event Withdrawal(address indexed sender, uint256 amount);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(address deployer) Owned(msg.sender) {
        balanceOf[deployer] = 1_000_000 ether;
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function depositTo(address receiver) external payable {
        balanceOf[receiver] += msg.value;
        emit Deposit(receiver, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }

    function mintTo(address to, uint256 amount) external onlyOwner {
        balanceOf[to] += amount;
        emit Deposit(to, amount);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address who, uint256 amount) public returns (bool) {
        allowance[msg.sender][who] = amount;
        emit Approval(msg.sender, who, amount);
        return true;
    }

    function transfer(address receiver, uint256 amount) public returns (bool) {
        return transferFrom(msg.sender, receiver, amount);
    }

    function transferFrom(address sender, address receiver, uint256 amount)
        public
        returns (bool)
    {
        require(balanceOf[sender] >= amount, "Insufficient balance");

        if (sender != msg.sender && allowance[sender][msg.sender] != type(uint256).max) {
            require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");
            allowance[sender][msg.sender] -= amount;
        }

        balanceOf[sender] -= amount;
        balanceOf[receiver] += amount;

        emit Transfer(sender, receiver, amount);

        return true;
    }

    fallback() external payable {
        deposit();
    }

    receive() external payable {
        deposit();
    }

}
