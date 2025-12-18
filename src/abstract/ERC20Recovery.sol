
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../errors/Errors.sol";

event RecoveredERC20(address token, address who, uint256 balance);

abstract contract ERC20Recovery {

    function recoverAllERC20(address token, address to)
        internal
    {
        if (to == address(0)) revert ZeroAddress();

        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(to, bal);
        emit RecoveredERC20(token, to, bal);
    }

}