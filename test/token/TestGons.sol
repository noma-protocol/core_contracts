// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "../../src/libraries/SafeMath.sol";
import "../../src/types/ERC20Permit.sol";

contract TestGons is ERC20Permit {
    using SafeMath for uint256;

    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 1_000 * 10**18;
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
    uint256 private constant MAX_SUPPLY = ~uint128(0);
    
    uint256 internal INDEX; // Index Gons - tracks rebase growth
    
    address private someContract;
    uint256 private _gonsPerFragment;

    mapping(address => uint256) private _gonBalances;
    mapping(address => uint256) public debtBalances;
    mapping(address => mapping(address => uint256)) private _allowedValue;

    event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 scalingFactor);

    constructor () ERC20("Staked Gons", "sGons", 18)  ERC20Permit("Gons") {
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
    }

    function setIndex(uint256 _index) external {
        require(INDEX == 0, "Cannot set INDEX again");
        INDEX = gonsForBalance(_index);
    }

    function initialize(address _someContract) external {
        someContract = _someContract;
        _gonBalances[_someContract] = TOTAL_GONS;
    }

    function rebase(uint256 profit_) public returns (uint256) {
        uint256 rebaseAmount;
        uint256 circulatingSupply_ = circulatingSupply();
        if (profit_ == 0) {
            return _totalSupply;
        } else if (circulatingSupply_ > 0) {
            rebaseAmount = profit_.mul(_totalSupply).div(circulatingSupply_);
        } else {
            rebaseAmount = profit_;
        }

        _totalSupply = _totalSupply.add(rebaseAmount);

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
        return _totalSupply;
    }

    function transfer(address to, uint256 value) public override(ERC20) returns (bool) {
        uint256 gonValue = value.mul(_gonsPerFragment);

        _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);

        require(balanceOf(msg.sender) >= debtBalances[msg.sender], "Debt: cannot transfer amount");
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override(ERC20) returns (bool) {
        _allowedValue[from][msg.sender] = _allowedValue[from][msg.sender].sub(value);
        emit Approval(from, msg.sender, _allowedValue[from][msg.sender]);

        uint256 gonValue = gonsForBalance(value);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);

        require(balanceOf(from) >= debtBalances[from], "Debt: cannot transfer amount");
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public override(ERC20) returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _approve(msg.sender, spender, _allowedValue[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        uint256 oldValue = _allowedValue[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _approve(msg.sender, spender, 0);
        } else {
            _approve(msg.sender, spender, oldValue.sub(subtractedValue));
        }
        return true;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _gonBalances[account] / _gonsPerFragment;
    }

    function gonsForBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(_gonsPerFragment);
    }

    function balanceForGons(uint256 gons) public view returns (uint256) {
        return gons / _gonsPerFragment;
    }    

    function index() public view returns (uint256) {
        return balanceForGons(INDEX);
    }

    // some contract contract holds excess TOK
    function circulatingSupply() public view returns (uint256) {
        return
            _totalSupply.sub(balanceOf(someContract));
    }
}