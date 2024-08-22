// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IsNomaToken is IERC20 {
    function rebase(uint256 supplyDelta) external;
    function circulatingSupply() external view returns (uint256);
    function mint(address _recipient, uint256 _amount) external;
    function burnFor(address from, uint256 value) external returns (bool);
}
