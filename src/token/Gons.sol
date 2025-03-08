// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20, ERC20Permit} from "../abstract/ERC20Permit.sol";
import {Utils} from "../libraries/Utils.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract GonsToken is ERC20Permit {

    bool public initialized;
    address public stakingContract;

    uint256 public rebaseIndex = 1e18; // Scaling factor for rebases
    mapping(address => mapping(address => uint256)) private _allowedFragments;

    event LogRebase(uint256 totalSupply);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    error RebaseFailed();
    error InvalidAddress();
    error InvalidAmount();
    error AlreadyInitialized();
    error NotInitialized();
    error Unauthorized();

    constructor(address _authority) ERC20("Staked Gons", "sGons", 18) ERC20Permit("Gons") {}

    function initialize(address _stakingContract) external {
        if (initialized) {
            revert AlreadyInitialized();
        }
        if (_stakingContract == address(0)) {
            revert InvalidAddress();
        }
        stakingContract = _stakingContract;
        initialized = true;
    }

    function rebase(uint256 supplyDelta) public {
        if (!initialized) {
            revert NotInitialized();
        }

        uint256 totalShares = super.totalSupply();
        if (totalShares == 0) {
            return; 
        }

        uint256 increase = (supplyDelta * 1e18) / totalShares;
        rebaseIndex = rebaseIndex + increase;

        uint256 actualMintAmount = (totalShares * increase) / 1e18;  // Prevent precision drift
        mint(stakingContract, actualMintAmount);

        if (_totalSupply != super.totalSupply()) {
            revert RebaseFailed();
        }

        emit LogRebase(super.totalSupply());
    }

    function balanceOf(address account) public view override returns (uint256) {
        return (super.balanceOf(account) * rebaseIndex) / 1e18;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        require(balanceOf(msg.sender) >= value, "Insufficient balance");
        uint256 adjustedValue = (value * 1e18) / rebaseIndex;
        _transfer(msg.sender, to, adjustedValue);
        return true;
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        return _allowedFragments[owner_][spender];
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        require(_allowedFragments[from][msg.sender] >= value, "Allowance exceeded");
        require(balanceOf(from) >= value, "Insufficient balance");

        uint256 adjustedValue = (value * 1e18) / rebaseIndex;
        _allowedFragments[from][msg.sender] -= value;
        _transfer(from, to, adjustedValue);

        return true;
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _allowedFragments[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] -= subtractedValue;
        }
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    function gonsForBalance(uint256 amount) public view returns (uint256) {
        return (amount * 1e18) / rebaseIndex;
    }

    function balanceForGons(uint256 gons) public view returns (uint256) {
        return (gons * rebaseIndex) / 1e18;
    }

    function circulatingSupply() public view returns (uint256) {
        return super.totalSupply();
    }

    function mint(address to, uint256 amount) public {
        if (amount == 0) {
            revert InvalidAmount();
        }

        // Use mulDiv to avoid precision loss
        uint256 adjustedAmount = Math.mulDiv(amount, 1e18, rebaseIndex);
        _mint(to, adjustedAmount);

        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function burnFor(address from) public {
        uint256 balance = balanceOf(from);
        _burnAll(from);
        emit Burn(from, balance);
        emit Transfer(from, address(0), balance);
    }

    modifier onlyStakingContract() {
        if (msg.sender != stakingContract) {
            revert Unauthorized();
        }
        _;
    }
}
