// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IsNomaToken.sol";


contract sStaking is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IsNomaToken;

    struct Epoch {
        uint256 number; // since inception
        uint256 end; // timestamp
        uint256 distribute; // amount
    }

    IERC20 public immutable NOMA;
    IsNomaToken public immutable sNOMA;

    Epoch public epoch;

    constructor(
        address _noma,
        address _sNoma,
        address _authority
    ) Ownable(_authority) {
        require(_noma != address(0), "Zero address: NOMA");
        NOMA = IERC20(_noma);
        require(_sNoma != address(0), "Zero address: sNOMA");
        sNOMA = IsNomaToken(_sNoma);

        epoch = Epoch({
            number: 1,
            end: 0,
            distribute: 100e18
        });
    }

    function stake(
        address _to,
        uint256 _amount
    ) external {
        NOMA.safeTransferFrom(msg.sender, address(this), _amount);
        sNOMA.mint(_to, _amount);
    }

    function unStake(
        uint256 _amount
    ) external {
        sNOMA.safeTransferFrom(msg.sender, address(this), _amount);
        NOMA.transfer(msg.sender, _amount);
    }
}
