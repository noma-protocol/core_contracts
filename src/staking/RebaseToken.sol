// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/SafeMath.sol";

interface IStaking {
    function stake(address _to, uint256 _amount) external;
}

contract RebaseToken is ERC20 {
    using SafeMath for uint256;

    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 1_000 * 10**18;
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
    uint256 private constant MAX_SUPPLY = ~uint128(0);

    uint256 private _totalSupply;
    uint256 private _gonsPerFragment;
    mapping(address => uint256) private _gonBalances;
    mapping(address => mapping(address => uint256)) private _allowedValue;

    IERC20 public nomaToken;
    address public initializer;
    address public stakingContract;
    address public vault;

    event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 scalingFactor);
    event Wrapped(address indexed user, uint256 nomaAmount, uint256 sNomaAmount);
    event Unwrapped(address indexed user, uint256 sNomaAmount, uint256 nomaAmount);

    constructor(address _initializer, address _nomaToken) ERC20("Staked Noma", "sNOMA") {
        nomaToken = IERC20(_nomaToken);
        initializer = _initializer;
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
        _gonBalances[stakingContract] = TOTAL_GONS;
        emit Transfer(address(0x0), stakingContract, _totalSupply);
    }

    function initialize(address _vault, address _stakingContract) external {
        require(msg.sender == initializer, "Initializer: caller is not initializer");
        require(_stakingContract != address(0), "Staking");
        require(_vault != address(0), "Vault");
        stakingContract = _stakingContract;
        vault = _vault;
        initializer = address(0);
        emit Transfer(address(0x0), stakingContract, _totalSupply);
    }

    function rebase(uint256 profit, uint256 epoch) public onlyStakingContract returns (uint256) {
        uint256 rebaseAmount;
        uint256 circulatingSupply = circulatingSupply();
        if (profit == 0) {
            emit LogRebase(epoch, 0, _gonsPerFragment);
            return _totalSupply;
        } else if (circulatingSupply > 0) {
            rebaseAmount = profit.mul(_totalSupply).div(circulatingSupply);
        } else {
            rebaseAmount = profit;
        }

        _totalSupply = _totalSupply.add(rebaseAmount);

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        emit LogRebase(epoch, rebaseAmount, _gonsPerFragment);

        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _gonBalances[account].div(_gonsPerFragment);
    }

    function gonsForBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(_gonsPerFragment);
    }

    function balanceForGons(uint256 gons) public view returns (uint256) {
        return gons.div(_gonsPerFragment);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        uint256 gonValue = value.mul(_gonsPerFragment);
        _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _allowedValue[from][msg.sender] = _allowedValue[from][msg.sender].sub(value);
        emit Approval(from, msg.sender, _allowedValue[from][msg.sender]);

        uint256 gonValue = value.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        _allowedValue[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function mint(address account, uint256 amount) external {
        uint256 gonAmount = amount.mul(_gonsPerFragment);
        _gonBalances[account] = _gonBalances[account].add(gonAmount);
        _totalSupply = _totalSupply.add(amount);
        emit Transfer(address(0), account, amount);
    }

    function gonsPerFragment() public view returns (uint256) {
        return _gonsPerFragment;
    }

    function gonBalances(address account) public view returns (uint256) {
        return _gonBalances[account];
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "RebaseToken: caller is not vault");
        _;
    }

    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "RebaseToken: caller is not staking contract");
        _;
    }

    function circulatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(stakingContract));
    }
}
