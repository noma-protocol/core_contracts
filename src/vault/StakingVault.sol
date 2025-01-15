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
import "../libraries/LiquidityDeployer.sol";

import {
    LiquidityPosition, 
    LiquidityType,
    ProtocolAddresses,
    LiquidityStructureParameters
} from "../types/Types.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address receiver, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
}

interface IStakingRewards {
    function notifyRewardAmount(uint256 reward) external;
}

contract StakingVault is BaseVault {

    //TODO move this to LibAppStorage
    uint256 public constant BASE_VALUE = 100e18;

    function calculateMintAmount(int256 currentLiquidityRatio, uint256 excessTokens) public view returns (uint256) {
        return _calculateMintAmont(currentLiquidityRatio, excessTokens);
    }

    function _calculateMintAmont(int256 currentLiquidityRatio, uint256 excessTokens) internal view returns (uint256) {
        require(currentLiquidityRatio >= -1e18 && currentLiquidityRatio <= 1e18 * 10, "currentLiquidityRatio out of range");

        uint256 stakedBalance = IERC20(_v.pool.token0()).balanceOf(_v.stakingContract);
        
        uint256 BASE_VALUE = 100e18;
        uint256 SCALING_FACTOR = 1e12; // New scaling factor

        uint256 adjustedRatio = BASE_VALUE - uint256(currentLiquidityRatio);
        uint256 mintAmount = (adjustedRatio * excessTokens * SCALING_FACTOR) / 1e18;

        return mintAmount;
    }

    function mintAndDistributeRewards(ProtocolAddresses memory addresses) public {
        require(msg.sender == address(this), "StakeVault: unauthorized");

        LiquidityPosition[3] memory positions = [
            _v.floorPosition, 
            _v.anchorPosition, 
            _v.discoveryPosition
        ];

        uint256 excessReservesToken1 = IModelHelper(_v.modelHelper)
        .getExcessReserveBalance(
            address(_v.pool),
            addresses.vault,
            false
        );

        uint256 currentLiquidityRatio = IModelHelper(_v.modelHelper)
        .getLiquidityRatio(address(_v.pool), addresses.vault);
        
        uint256 toMintScaledToken1 = _calculateMintAmont(int256(currentLiquidityRatio), excessReservesToken1);

        uint256 intrinsicMinimumValue = IModelHelper(_v.modelHelper)
        .getIntrinsicMinimumValue(addresses.vault) * 1e18;

        uint256 toMintConverted = DecimalMath.divideDecimal(toMintScaledToken1, intrinsicMinimumValue);
        
        if (toMintConverted == 0) {
            return;
        } 
        
        require(_v.stakingContract != address(0), "StakeVault: staking contract not set");
        
        IERC20(_v.tokenInfo.token0).approve(_v.stakingContract, toMintConverted);
        mintTokens(_v.stakingContract, toMintConverted);

        // Update total minted (NOMA)
        _v.totalMinted += toMintConverted;

        // Call notifyRewardAmount 
        IStakingRewards(_v.stakingContract).notifyRewardAmount(toMintConverted);  

        // Send tokens to Floor
        _sendToken1ToFloor(positions, addresses, toMintConverted);
    }

    function _sendToken1ToFloor(
        LiquidityPosition[3] memory positions, 
        ProtocolAddresses memory addresses,
        uint256 toMint
    ) internal {

        (,,, uint256 floorToken1Balance) = IModelHelper(addresses.modelHelper)
        .getUnderlyingBalances(
            addresses.pool, 
            address(this), 
            LiquidityType.Floor
        );

        {
            uint256 anchorCapacity = IModelHelper(addresses.modelHelper)
            .getPositionCapacity(
                addresses.pool, 
                addresses.vault, 
                positions[1],
                LiquidityType.Anchor
            );

            (
                uint256 circulatingSupply,,,
            ) = LiquidityOps.getVaulData(addresses);

            uint256 newFloorPrice = IDeployer(addresses.deployer)
            .computeNewFloorPrice(
                addresses.pool,
                toMint,
                floorToken1Balance,
                circulatingSupply,
                anchorCapacity,
                positions
            );

            uint256 currentFloorPrice = Conversions
            .sqrtPriceX96ToPrice(
                Conversions
                .tickToSqrtPriceX96(
                    positions[0].upperTick
                ), 
            18);
            
            // Bump floor if necessary
            if (newFloorPrice > currentFloorPrice) {
                _shiftPositions(
                    positions, 
                    addresses, 
                    newFloorPrice, 
                    toMint, 
                    floorToken1Balance
                );
            }  
        }        
    }

    function _shiftPositions(
        LiquidityPosition[3] memory positions, 
        ProtocolAddresses memory addresses,
        uint256 newFloorPrice,
        uint256 toMint,
        uint256 floorToken1Balance
    ) internal {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(addresses.pool).slot0();
        
        ( , uint256 anchorToken1Balance, 
            uint256 discoveryToken1Balance,
        ) = LiquidityOps.getVaulData(addresses);

        // Collect floor liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[0].lowerTick, 
            positions[0].upperTick
        ); 

        // Collect discovery liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[2].lowerTick, 
            positions[2].upperTick
        );

        // Collect anchor liquidity
        Uniswap.collect(
            addresses.pool, 
            address(this), 
            positions[1].lowerTick, 
            positions[1].upperTick
        ); 

        if (floorToken1Balance + toMint > floorToken1Balance) {
            ERC20(IUniswapV3Pool(addresses.pool).token1()).transfer(
                addresses.deployer, 
                floorToken1Balance + toMint
            );
        }

        {
            positions[0] = IDeployer(addresses.deployer) 
            .shiftFloor(
                addresses.pool, 
                addresses.vault, 
                Conversions
                .sqrtPriceX96ToPrice(
                    Conversions
                    .tickToSqrtPriceX96(
                        positions[0].upperTick
                    ), 
                18), 
                newFloorPrice,
                floorToken1Balance + toMint,
                floorToken1Balance,
                positions[0]
            );   

            // Deploy new anchor position
            positions[1] = LiquidityOps
            .reDeploy(
                addresses,
                positions[0].upperTick,                
                Utils.nearestUsableTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96)      
                ),
                (anchorToken1Balance + discoveryToken1Balance) - toMint, 
                LiquidityType.Anchor
            );

            positions[2] = LiquidityOps
            .reDeploy(
                addresses,
                Utils.nearestUsableTick(
                    Utils.addBipsToTick(positions[1].upperTick, 150)
                ),
                Utils.nearestUsableTick(
                    TickMath.getTickAtSqrtRatio(sqrtRatioX96) * 3     
                ),                
                0,
                LiquidityType.Discovery 
            ); 

            IVault(addresses.vault).updatePositions(positions);  

            IModelHelper(_v.modelHelper)
            .enforceSolvencyInvariant(address(this));   
        }
    }

    function liquidityStructureParameters() public view returns 
    (LiquidityStructureParameters memory ) {
        return _v.liquidityStructureParameters;
    }

    function setStakingContract(address _stakingContract) external onlyManager {
        _v.stakingContract = _stakingContract;
    }

    function getFunctionSelectors() external pure  override returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = bytes4(keccak256(bytes("mintAndDistributeRewards((address,address,address,address,address))"))); 
        selectors[1] = bytes4(keccak256(bytes("liquidityStructureParameters()")));  
        selectors[2] = bytes4(keccak256(bytes("setStakingContract(address)")));
        return selectors;
    }
}