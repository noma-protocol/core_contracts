// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStaking {
    function stake(address _to, uint256 _amount) external;
}
contract sNomaToken is ERC20 {
    uint256 public scalingFactor;

    IERC20 public nomaToken;

    address public initializer;
    address public stakingContract;

    event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 scalingFactor);
    event Wrapped(address indexed user, uint256 nomaAmount, uint256 sNomaAmount);
    event Unwrapped(address indexed user, uint256 sNomaAmount, uint256 nomaAmount);

    constructor(address _initializer, address _nomaToken) ERC20("Staked Noma", "sNOMA") {
        nomaToken = IERC20(_nomaToken);
        initializer = _initializer;
        scalingFactor = 1e18; // Initial scaling factor set to 1.0 in 18 decimals
    }

    function initialize(address _stakingContract) external {
        require(msg.sender == initializer, "Initializer: caller is not initializer");
        require(_stakingContract != address(0), "Staking");
        stakingContract = _stakingContract;
        initializer = address(0);
    }

    function rebase(uint256 profit) external {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            // Handle case where total supply is zero to avoid division by zero
            scalingFactor += profit * 1e18;
        } else {
            uint256 rebaseAmount = profit * 1e18 / totalSupply;
            scalingFactor += rebaseAmount;
        }

        _mint(address(this), profit);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account) * scalingFactor / 1e18;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint256 scaledAmount = amount * 1e18 / scalingFactor;
        return super.transfer(recipient, scaledAmount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 scaledAmount = amount * 1e18 / scalingFactor;
        return super.transferFrom(sender, recipient, scaledAmount);
    }

    function mint(address account, uint256 amount) external {
        uint256 scaledAmount = amount * 1e18 / scalingFactor;
        _mint(account, scaledAmount);
    }
}
