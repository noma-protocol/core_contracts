// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MockNomaToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    function initialize(address deployer, uint256 totalSupply) initializer public {
        __ERC20_init("Test Amphor", "tAMPH");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _mint(deployer, totalSupply);
        // super.transferOwnership(address(owner()));
    }

    // function transferOwnership(address _owner) public override onlyOwner {
    //     super.transferOwnership(address(owner()));
    // }

    function _authorizeUpgrade(address newImplementation) internal override /*onlyOwner*/ {}

    function version() public pure returns (string memory) {
        return "1";
    }

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("eip1967.proxy.implementation");
    }

    function setOwner(address _owner) external onlyOwner {
        super.transferOwnership(_owner);
    }

}
