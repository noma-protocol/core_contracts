// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SafeMath} from "../libraries/SafeMath.sol";
import {ERC20, ERC20Permit} from "../abstract/ERC20Permit.sol";

/**
 * @title RebaseToken
 * @notice A token contract that supports rebasing and staking functionality.
 * @dev This contract uses a "gons" system to handle rebasing, where the total supply can be adjusted without changing individual balances.
 */
contract RebaseToken is ERC20Permit {
    using SafeMath for uint256;

    // Events
    event LogRebase(uint256 totalSupply); // Emitted when a rebase occurs.
    event Mint(address indexed to, uint256 amount); // Emitted when tokens are minted.

    // Constants
    uint256 private constant DECIMALS = 18; // Number of decimals for the token.
    uint256 private constant MAX_UINT256 = ~uint256(0); // Maximum value for a uint256.
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 3.025 * 10**6 * 10**DECIMALS; // Initial supply of fragments.

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint256 private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

    // State variables
    uint256 private _gonsPerFragment; // Conversion rate between gons and fragments.
    mapping(address => uint256) private _gonBalances; // Balances in gons for each address.

    address public stakingContract; // Address of the staking contract.

    // Mapping of allowances in fragments.
    mapping (address => mapping (address => uint256)) private _allowedFragments;

    /**
     * @notice Constructor to initialize the RebaseToken contract.
     * @param _authority The address that will receive the initial supply of tokens.
     */
    constructor(address _authority) ERC20("Staked Noma", "sNOMA", 18) ERC20Permit("Staked Noma") {
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[_authority] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        emit Transfer(address(0x0), _authority, _totalSupply);
    }

    /**
     * @notice Initializes the staking contract address.
     * @param _stakingContract The address of the staking contract.
     */
    function initialize(address _stakingContract) external  {
        require(stakingContract == address(0), "Already initialized");
        stakingContract = _stakingContract;
        transfer(stakingContract, _totalSupply);
    }

    /**
     * @notice Mints new tokens to the specified address.
     * @param to The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyStakingContract {
        require(amount > 0, "Amount must be greater than 0");

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
     * @notice Notifies the contract about a new rebase cycle.
     * @param supplyDelta The number of new fragment tokens to add into circulation via expansion.
     */
    function rebase(uint256 supplyDelta) public onlyStakingContract {
        if (supplyDelta == 0) {
            emit LogRebase(_totalSupply);
        }

        _totalSupply = _totalSupply.add(supplyDelta);

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        emit LogRebase(_totalSupply);
    }

    /**
     * @notice Burns a specific amount of tokens from the target address and decrements allowance.
     * @param from The address from which to burn tokens.
     * @param value The amount of tokens to burn.
     * @return A boolean indicating if the operation was successful.
     */
    function burnFor(address from, uint256 value) public onlyStakingContract returns (bool) {
        require(from != address(0), "ERC20: burn from the zero address");
        require(value <= balanceOf(from), "ERC20: burn amount exceeds balance");
        require(value <= allowance(from, msg.sender), "ERC20: burn amount exceeds allowance");

        uint256 gonValue = value.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _totalSupply = _totalSupply.sub(value);
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        _allowedFragments[from][msg.sender] = _allowedFragments[from][msg.sender].sub(value);

        emit Transfer(from, address(0), value);
        return true;
    }

    /**
     * @notice Returns the total number of fragments.
     * @return The total supply of tokens.
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
     * @notice Returns the balance of the specified address.
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
     * @notice Transfers tokens to a specified address.
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
     * @notice Returns the amount of tokens that an owner has allowed to a spender.
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
     * @notice Transfers tokens from one address to another.
     * @param from The address to send tokens from.
     * @param to The address to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return True on success, false otherwise.
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
     * @notice Approves the passed address to spend the specified amount of tokens on behalf of msg.sender.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return True on success, false otherwise.
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
     * @notice Increases the allowance of a spender.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     * @return True on success, false otherwise.
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
     * @notice Decreases the allowance of a spender.
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     * @return True on success, false otherwise.
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
     * @notice Converts a fragment amount to gons.
     * @param amount The amount of fragments to convert.
     * @return The equivalent amount in gons.
     */
    function gonsForBalance(uint256 amount) public view returns (uint256) {
        return amount.mul(_gonsPerFragment);
    }

    /**
     * @notice Converts a gons amount to fragments.
     * @param gons The amount of gons to convert.
     * @return The equivalent amount in fragments.
     */
    function balanceForGons(uint256 gons) public view returns (uint256) {
        return gons.div(_gonsPerFragment);
    }

    /**
     * @notice Returns the circulating supply of tokens.
     * @return The circulating supply of tokens.
     */
    function circulatingSupply() public view returns (uint256) {
        return balanceOf(address(this)) - balanceOf(address(0));
    }

    /**
     * @notice Modifier to restrict access to the staking contract.
     */
    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "Only staking contract can call this function");
        _;
    }
}