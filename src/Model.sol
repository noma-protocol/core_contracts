// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Vault} from "./Vault.sol";
import {DecimalMath} from "./libraries/DecimalMath.sol";
import {LiquidityHelper} from "./libraries/LiquidityHelper.sol";

import {LiquidityPosition} from "./Types.sol";

contract Model {

    ERC20 public token0;
    Vault public vault;

    constructor(address _token0, address _vault) {
        token0 = ERC20(_token0);
        vault = Vault(_vault);
    }

    function checkCapacityInvariant() public view returns (bool) {

        uint256 inVault = getInVault();
        uint256 totalCapacity = getTotalCapacityToken0();

        return inVault + totalCapacity > getFloating();
    }

    function getUnderlyingBalancesToken1(
        LiquidityPosition memory position
    ) public view returns (uint256, uint256) {

        (uint256 amount0Current, uint256 amount1Current) = LiquidityHelper
            .getUnderlyingBalances(vault.pool(), position);

        return (amount0Current, amount1Current);
    }

    function getTotalToken0InLiquidity() public view returns (uint256) {

        (,,,, uint256 inAnchor,,) =
            vault.getAnchorPosition();

        (,,,, uint256 InDiscovery,,) =
            vault.getDiscoveryPosition();
        
        return inAnchor + InDiscovery;
    }

    function getTotalCapacityToken0() public view returns (uint256) {

        (,,,uint256 floorPrice,, uint256 amount1UpperBoundFloor,) =
            vault.getFloorPosition();

        uint amount0LowerBoundFloor = DecimalMath
            .divideDecimalRound(amount1UpperBoundFloor, floorPrice);

        (,,,, uint256 amount0LowerBoundAnchor,,) =
            vault.getAnchorPosition();

        (,,,, uint256 amount0LowerBoundDiscovery,,) =
            vault.getDiscoveryPosition();

        return (
            amount0LowerBoundFloor + 
            amount0LowerBoundAnchor + 
            0
        );

    }

    function getFloating() public view returns (uint256) {

        uint256 inVault = getInVault();
        uint256 totalToken0InLiquidity = getTotalToken0InLiquidity();

        return token0.totalSupply() - inVault -  totalToken0InLiquidity;
    }

    function getInVaultAndTotalCapacity() public view returns (uint256, uint256) {
        uint256 inVault = getInVault();
        uint256 totalCapacity = getTotalCapacityToken0();
        return (inVault, totalCapacity);
    }

    function getInVault() public view returns (uint256) {
        return token0.balanceOf(address(vault));
    }

}