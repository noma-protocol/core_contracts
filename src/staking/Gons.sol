// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeMath} from "../libraries/SafeMath.sol";
import {ERC20, ERC20Permit} from "../abstract/ERC20Permit.sol";

error AlreadyInitialized();
error InvalidAmount();
error InvalidAddress();

contract GonsToken is ERC20Permit {
    // PLEASE READ BEFORE CHANGING ANY ACCOUNTING OR MATH
    // Anytime there is division, there is a risk of numerical instability from rounding errors. In
    // order to minimize this risk, we adhere to the following guidelines:
    // 1) The conversion rate adopted is the number of gons that equals 1 fragment.
    //    The inverse rate must not be used--TOTAL_GONS is always the numerator and _totalSupply is
    //    always the denominator. (i.e. If you want to convert gons to fragments instead of
    //    multiplying by the inverse rate, you should divide by the normal rate)
    // 2) Gon balances converted into Fragments are always rounded down (truncated).
    //
    // We make the following guarantees:
    // - If address 'A' transfers x Fragments to address 'B'. A's resulting external balance will
    //   be decreased by precisely x Fragments, and B's external balance will be precisely
    //   increased by x Fragments.
    //
    // We do not guarantee that the sum of all balances equals the result of calling totalSupply().
    // This is because, for any conversion function 'f()' that has non-zero rounding error,
    // f(x0) + f(x1) + ... + f(xn) is not always equal to f(x0 + x1 + ... xn).
    using SafeMath for uint256;
    
    event LogRebase(uint256 totalSupply);
    event Mint(address indexed to, uint256 amount);

    uint256 private constant DECIMALS = 18;
    uint256 private constant MAX_UINT256 = ~uint256(0);
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 3.025 * 10**6 * 10**DECIMALS;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint256 private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

    uint256 private _gonsPerFragment;
    mapping(address => uint256) private _gonBalances;

    address public stakingContract;
    
    // This is denominated in Fragments, because the gons-fragments conversion might change before it's fully paid.
    mapping (address => mapping (address => uint256)) private _allowedFragments;

    constructor(address _authority) ERC20("Staked Noma", "sNOMA", 18) ERC20Permit("Staked Noma") {
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[_authority] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        emit Transfer(address(0x0), _authority, _totalSupply);
    }

    /**
     * @dev Initializes the contract by setting the staking contract address and transferring the total supply.
     * @param _stakingContract The address of the staking contract.
     */
    function initialize(address _stakingContract) external  {
        if (stakingContract != address(0)) {
            revert AlreadyInitialized();
        }
        stakingContract = _stakingContract;
        transfer(stakingContract, _totalSupply);
    }

    /**
     * @dev Mints new tokens and assigns them to the specified address.
     * @param to The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        if (amount == 0) {
            revert InvalidAmount();
        }

        uint256 gonAmount = amount.mul(_gonsPerFragment);
        _totalSupply = _totalSupply.add(amount);
        _gonBalances[to] = _gonBalances[to].add(gonAmount);

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
    }

    /**
    * @dev Notifies Fragments contract about a new rebase cycle.
    * @param supplyDelta The number of new fragment tokens to add into circulation via expansion.
    */
    function rebase(uint256 supplyDelta)
        public
    {
        if (supplyDelta == 0) {
            emit LogRebase(_totalSupply);
        }

        _totalSupply = _totalSupply.add(supplyDelta);

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        // From this point forward, _gonsPerFragment is taken as the source of truth.
        // We recalculate a new _totalSupply to be in agreement with the _gonsPerFragment
        // conversion rate.
        // This means our applied supplyDelta can deviate from the requested supplyDelta,
        // but this deviation is guaranteed to be < (_totalSupply^2)/(TOTAL_GONS - _totalSupply).
        
        // In the case of _totalSupply <= MAX_UINT128 (our current supply cap), this
        // deviation is guaranteed to be < 1, so we can omit this step. If the supply cap is
        // ever increased, it must be re-included.
        // _totalSupply = TOTAL_GONS.div(_gonsPerFragment)

        emit LogRebase(_totalSupply);
    }

    /**
    * @dev Burns a specific amount of tokens from the target address and decrements allowance.
    * @param from The address which you want to burn tokens from.
    * @param value The amount of token to be burned.
    * @return A boolean that indicates if the operation was successful.
    */
    function burnFor(address from, uint256 value) public returns (bool) {

        if (from == address(0)) {
            revert InvalidAddress();
        }

        if (value > balanceOf(from)) {
            revert InvalidAmount();
        }

        if (value > allowance(from, msg.sender)) {
            revert InvalidAmount();
        }
        
        uint256 gonValue = value.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _totalSupply = _totalSupply.sub(value);
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        _allowedFragments[from][msg.sender] = _allowedFragments[from][msg.sender].sub(value);

        emit Transfer(from, address(0), value);
        return true;
    }

    /**
     * @return The total number of fragments.
     */
    function totalSupply()
        public
        view
        override
        returns (uint256)
    {
        return _totalSupply;
    }

    /**
     * @param who The address to query.
     * @return The balance of the specified address.
     */
    function balanceOf(address who)
        public
        view
        override
        returns (uint256)
    {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    /**
     * @dev Transfer tokens to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */
    function transfer(address to, uint256 value)
        public
        override
        returns (bool)
    {
        uint256 gonValue = value.mul(_gonsPerFragment);
        _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        emit Transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @dev Function to check the amount of tokens that an owner has allowed to a spender.
     * @param owner_ The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @return The number of tokens still available for the spender.
     */
    function allowance(address owner_, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowedFragments[owner_][spender];
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param from The address you want to send tokens from.
     * @param to The address you want to transfer to.
     * @param value The amount of tokens to be transferred.
     */
    function transferFrom(address from, address to, uint256 value)
        public
        override
        returns (bool)
    {
        _allowedFragments[from][msg.sender] = _allowedFragments[from][msg.sender].sub(value);

        uint256 gonValue = value.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);

        emit Transfer(from, to, value);
        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of
     * msg.sender. This method is included for ERC20 compatibility.
     * increaseAllowance and decreaseAllowance should be used instead.
     * Changing an allowance with this method brings the risk that someone may transfer both
     * the old and the new allowance - if they are both greater than zero - if a transfer
     * transaction is mined before the later approve() call is mined.
     *
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint256 value)
        public
        override
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner has allowed to a spender.
     * This method should be used instead of approve() to avoid the double approval vulnerability
     * described above.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        public
        override
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] =
            _allowedFragments[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to a spender.
     *
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public 
        override
        returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(subtractedValue);
        }
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Converts a fragment balance to the corresponding gon balance.
     * @param amount The fragment balance to convert.
     * @return The corresponding gon balance.
     */
    function gonsForBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(_gonsPerFragment);
    }
    
    /**
     * @dev Converts a gon balance to the corresponding fragment balance.
     * @param gons The gon balance to convert.
     * @return The corresponding fragment balance.
     */
    function balanceForGons(uint256 gons) public view returns (uint256) {
        return gons.div(_gonsPerFragment);
    }

    /**
     * @dev Calculates the circulating supply of tokens.
     * @return The circulating supply, excluding tokens held at address(0).
     */
    function circulatingSupply() public view returns (uint256) {
        return balanceOf(address(this)) - balanceOf(address(0));
    }
}