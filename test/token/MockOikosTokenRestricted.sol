// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MockOikosTokenRestricted is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    mapping(address => bool) public allowedPools;

    address uniswapPool = 0x4aBda2052f7E91eED7C2b6A6e6191E4db22463b0;

    function initialize(address owner, address deployer, uint256 totalSupply) initializer public {
        __ERC20_init("Test Amphor", "tAMPH");
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        _mint(deployer, totalSupply);
        _addAllowedPool(uniswapPool);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() public pure returns (string memory) {
        return "2";
    }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("eip1967.proxy.implementation");
    }

    function transfer(address recipient, uint256 amount) public override onlyUniswapV3(msg.sender, recipient) returns (bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override onlyUniswapV3(sender, recipient) returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    function addAllowedPool(address pool) external onlyOwner {
        _addAllowedPool(pool);
    }

    function _addAllowedPool(address pool) internal  {
        allowedPools[pool] = true;
    }

    function removeAllowedPool(address pool) external onlyOwner {
        allowedPools[pool] = false;
    }
    
    modifier onlyUniswapV3(address sender, address recipient) {
        require(
            allowedPools[sender] && recipient == msg.sender|| allowedPools[recipient] && sender == msg.sender,
            "Token can only be transferred via Uniswap V3"
        );
        _;
    }
}
