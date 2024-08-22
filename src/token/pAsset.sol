// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PreNomaToken is ERC20 {
    address public presaleContract;

    constructor() ERC20("Pre Noma Token", "p-NOMA") {
        presaleContract = msg.sender;
        _mint(msg.sender, 25_000_000 * 10**18);
    }

    // function mint(address to, uint256 amount) external {
    //     require(msg.sender == presaleContract, "Only presale contract can mint");
    //     _mint(to, amount);
    // }

    function burn(address from, uint256 amount) external {
        require(msg.sender == presaleContract, "Only presale contract can burn");
        _burn(from, amount);
    }
}

