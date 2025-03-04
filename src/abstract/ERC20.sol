// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Abstract ERC20 Implementation
/// @notice A base ERC20 contract that conforms to the IERC20 interface, with additional customization capabilities.
/// @dev This contract includes internal functions for minting, burning, and transferring tokens.

abstract contract ERC20 is IERC20 {
    /// @dev Interface identifier for ERC20Token using ERC1820.
    
    /// The keccak256 hash of ERC20Token is aea199e31a596269b42cdafd93407f14436db6e4cad65417994c2eb37381e05a
    bytes32 private constant ERC20TOKEN_ERC1820_INTERFACE_ID = keccak256("ERC20Token");

    /// @dev Maps addresses to their respective token balances.
    mapping(address => uint256) internal _balances;

    /// @dev Maps an owner address to a spender address and the allowance given.
    mapping(address => mapping(address => uint256)) internal _allowances;

    /// @dev Total supply of the token.
    uint256 internal _totalSupply;

    /// @dev Name of the token.
    string internal _name;

    /// @dev Symbol of the token.
    string internal _symbol;

    /// @dev Number of decimals used by the token.
    uint8 internal immutable _decimals;

    /// @notice Constructs the ERC20 token.
    /// @param name_ The name of the token.
    /// @param symbol_ The symbol of the token.
    /// @param decimals_ The number of decimals for the token.
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    /// @notice Returns the name of the token.
    /// @return The name of the token.
    function name() public view returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token.
    /// @return The symbol of the token.
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the number of decimals used by the token.
    /// @return The number of decimals.
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    /// @notice Returns the total supply of the token.
    /// @return The total supply.
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /// @notice Returns the balance of a specific account.
    /// @param account The address of the account.
    /// @return The balance of the account.
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    /// @notice Transfers tokens to a recipient.
    /// @param recipient The address of the recipient.
    /// @param amount The amount of tokens to transfer.
    /// @return A boolean indicating success.
    function transfer(address recipient, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /// @notice Returns the remaining tokens a spender is allowed to spend on behalf of the owner.
    /// @param owner The address of the token owner.
    /// @param spender The address of the spender.
    /// @return The remaining allowance.
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @notice Approves a spender to transfer up to a specific amount of tokens on behalf of the caller.
    /// @param spender The address of the spender.
    /// @param amount The amount of tokens to approve.
    /// @return A boolean indicating success.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers tokens on behalf of the owner to a recipient.
    /// @param sender The address of the token sender.
    /// @param recipient The address of the token recipient.
    /// @param amount The amount of tokens to transfer.
    /// @return A boolean indicating success.
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender] - amount
        );
        return true;
    }

    /// @notice Increases the allowance for a spender.
    /// @param spender The address of the spender.
    /// @param addedValue The additional amount to approve.
    /// @return A boolean indicating success.
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    /// @notice Decreases the allowance for a spender.
    /// @param spender The address of the spender.
    /// @param subtractedValue The amount to reduce from the approved allowance.
    /// @return A boolean indicating success.
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender] - subtractedValue
        );
        return true;
    }

    /// @dev Transfers tokens between addresses.
    /// @param sender The address of the sender.
    /// @param recipient The address of the recipient.
    /// @param amount The amount of tokens to transfer.
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    /// @dev Mints new tokens to an account.
    /// @param account The address of the recipient.
    /// @param amount The amount of tokens to mint.
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    /// @dev Burns tokens from an account.
    /// @param account The address of the account.
    /// @param amount The amount of tokens to burn.
    /// @dev Burns tokens from an account.
    /// @param account The address of the account.
    /// @param amount The amount of tokens to burn.
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _burnAll(address account) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];        
        _balances[account] = 0;
        _totalSupply -= accountBalance;

        emit Transfer(account, address(0), accountBalance);
    }



    /// @dev Approves a spender to transfer tokens on behalf of an owner.
    /// @param owner The address of the token owner.
    /// @param spender The address of the spender.
    /// @param amount The amount of tokens to approve.
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /// @dev Hook that is called before any transfer of tokens. Can be overridden.
    /// @param from_ The address transferring tokens.
    /// @param to_ The address receiving tokens.
    /// @param amount_ The amount of tokens being transferred.
    function _beforeTokenTransfer(
        address from_,
        address to_,
        uint256 amount_
    ) internal virtual {}
}
