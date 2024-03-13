// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";


contract AmphorToken is ERC20, Owned {
    
  constructor(address deployer, uint256 supply) 
  ERC20("Amphor", "AMPHR", 18) 
  Owned(msg.sender) {
    _mint(deployer, supply);
  }

  function mintTo(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function renounceOwnership() external onlyOwner {
    transferOwnership(address(0));
  }
}