// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import {BaseVault} from "./BaseVault.sol";
import {IModelHelper} from "../interfaces/IModelHelper.sol";
import {IDeployer} from "../interfaces/IDeployer.sol";
import {LiquidityOps} from "../libraries/LiquidityOps.sol";

import "../libraries/Conversions.sol";
import "../libraries/DecimalMath.sol";
import "../libraries/Utils.sol";
import "../libraries/Uniswap.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    ProtocolAddresses
} from "../Types.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address receiver, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

interface IVault {
    function updatePositions(LiquidityPosition[3] memory newPositions) external;
    function setFees(uint256 _feesAccumulatedToken0, uint256 _feesAccumulatedToken1) external;
}

contract ExtVault is BaseVault {

    function shift() public {
        require(_v.initialized, "not initialized");

        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];

        ProtocolAddresses memory addresses = ProtocolAddresses({
            pool: address(_v.pool),
            vault: address(this),
            deployer: _v.deployerContract,
            modelHelper: _v.modelHelper
        });

        LiquidityOps.shift(
            addresses,
            positions
        );

        // IExtVault(address(this)).mintAndDistributeRewards(addresses);
    }    

    function slide() public  {
        require(_v.initialized, "not initialized");

        LiquidityPosition[3] memory positions = [_v.floorPosition, _v.anchorPosition, _v.discoveryPosition];
        LiquidityOps
        .slide(
            ProtocolAddresses({
                pool: address(_v.pool),
                vault: address(this),
                deployer: _v.deployerContract,
                modelHelper: _v.modelHelper
            }),
            positions
        );
    }

    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256(bytes("shift()")));
        selectors[1] = bytes4(keccak256(bytes("slide()")));          
        return selectors;
    }
}