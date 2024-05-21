// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";

contract MockNomaTokenV2 is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    mapping(address => bool) public allowedPools;

    function initialize(address deployer, uint256 totalSupply) initializer public {
        __ERC20_init("Test Noma V2", "tNOMA");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() public pure returns (string memory) {
        return "V2";
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
        allowedPools[pool] = true;
    }

    function removeAllowedPool(address pool) external onlyOwner {
        allowedPools[pool] = false;
    }
    
    modifier onlyUniswapV3(address sender, address recipient) {
        require(
            allowedPools[sender] || allowedPools[recipient],
            "Token can only be transferred via Uniswap V3"
        );
        _;
    }
}
