// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {Conversions} from "./libraries/Conversions.sol";
import {Utils} from "./libraries/Utils.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {Uniswap} from "./libraries/Uniswap.sol";
import {LiquidityHelper} from "./libraries/LiquidityHelper.sol";
import {feeTier, tickSpacing, LiquidityPosition, LiquidityType} from "./Types.sol";

interface IIDOManager {
    function buyTokens(uint256 price, uint256 amount) external;
}

contract Vault is Owned {

    LiquidityPosition public floorPosition;
    LiquidityPosition public anchorPosition;
    LiquidityPosition public discoveryPosition;
    
    mapping(LiquidityType => LiquidityPosition) public positions;

    address public token0;
    address public token1;
    IUniswapV3Pool public pool;

    bool initialized = false; 
    IIDOManager public idoManager;

    constructor(address _pool, address _idoManager) Owned(msg.sender) {
        pool = IUniswapV3Pool(_pool);
        token0 = pool.token0();
        token1 = pool.token1();
        idoManager = IIDOManager(payable(_idoManager));
    }

    /**
     * @notice Uniswap V3 callback function, called back on pool.mint
     */
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data)
        external
    {
        require(msg.sender == address(pool), "callback caller");

        uint256 token0Balance = ERC20(token0).balanceOf(address(this));
        uint256 token1Balance = ERC20(token1).balanceOf(address(this));

        (uint256 code, string memory message) = abi.decode(data, (uint256, string));

        if (token0Balance >= amount0Owed) {

            if (amount0Owed > 0) ERC20(token0).transfer(msg.sender, amount0Owed);
            
            if (code == 0 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                floorPosition.amount0LowerBound = amount0Owed;
            } else if (code == 1 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                anchorPosition.amount0LowerBound = amount0Owed;
            } else if (code == 2 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                discoveryPosition.amount0LowerBound = amount0Owed;
            }
        
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "insufficient token0 balance, owed: ", 
                        Utils._uint2str(amount0Owed)
                        )
                    )
                );
        }

        if (token1Balance >= amount1Owed) {

            if (amount1Owed > 0) ERC20(token1).transfer(msg.sender, amount1Owed);

            if (code == 0 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                floorPosition.amount1UpperBound = amount1Owed;
            } else if (code == 1 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                anchorPosition.amount1UpperBound = amount1Owed;
            } else if (code == 2 && keccak256(abi.encodePacked(message)) == keccak256(abi.encodePacked("mint"))) {
                discoveryPosition.amount1UpperBound = amount1Owed;
            }      

        } else {
            revert(
                string(
                    abi.encodePacked("insufficient token1 balance, owed: ", 
                    Utils._uint2str(amount1Owed)
                    )
                )
            );
        }
    }

    function deployFloor(uint256 _floorPrice, uint256 _anchorBips, uint256 initialOffset) public /*onlyOwner*/ {
        require(!initialized, "already initialized");
         
        uint256 balanceToken1 = ERC20(token1).balanceOf(address(this));
        
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (int24 lowerTick, int24 upperTick) = Conversions.computeSingleTick(_floorPrice, tickSpacing);

        uint256 amount0Max = 0;
        uint256 amount1Max = (balanceToken1 * 80) / 100; // 80% of WETH

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        if (liquidity > 0) {
            Uniswap.mint(pool, lowerTick, upperTick, liquidity, LiquidityType.Floor, false);
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "deployFloor: liquidity is 0, spot price: ", 
                            Utils._uint2str(uint256(sqrtRatioX96)
                        )
                    )
                )
            );             
        }

        floorPosition = LiquidityPosition(
            lowerTick, 
            upperTick, 
            liquidity, 
            Conversions.sqrtPriceX96ToPrice(Conversions.tickToSqrtPriceX96(upperTick), 18),
            floorPosition.amount0LowerBound,
            floorPosition.amount1UpperBound,
            0
        );

        _initAnchor(_anchorBips, initialOffset);
    }

    function _initAnchor(uint256 bips, uint256 offset) internal {

        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        uint256 lowerAnchorPrice = Utils.addBips(floorPosition.price, int256(offset));
        uint256 upperAnchorPrice = Utils.addBips(floorPosition.price, int256(bips));

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeRangeTicks(
            lowerAnchorPrice, 
            upperAnchorPrice, 
            tickSpacing
        );

        uint256 balanceToken0 = ERC20(token0).balanceOf(address(this));
        uint256 balanceToken1 = ERC20(token1).balanceOf(address(this));

        uint256 amount0Max = (balanceToken0 * 5) / 100;
        uint256 amount1Max = balanceToken1;

        uint128 liquidity = LiquidityAmounts
        .getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        if (liquidity > 0) {
            Uniswap.mint(pool, lowerTick, upperTick, liquidity, LiquidityType.Anchor, false);
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "_initAnchor: liquidity is 0, spot price: ", 
                            Utils._uint2str(uint256(sqrtRatioX96)
                        )
                    )
                )
            ); 
        }

        anchorPosition = LiquidityPosition(
            lowerTick, 
            upperTick, 
            liquidity, 
            upperAnchorPrice, 
            anchorPosition.amount0LowerBound, 
            anchorPosition.amount1UpperBound,
            0
        );

        // Do this during init to rise the spot price
        idoManager.buyTokens(Utils.addBips(floorPosition.price, 1500), 10 ether);

        LiquidityHelper.collect(
            pool, 
            anchorPosition
        );
        
        initialized = true;
    }

    function deployAnchor(uint256 bips, uint256 bipsBelowSpot) public {
        require(initialized, "not initialized");

        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        uint256 lowerAnchorPrice = Utils.addBips(Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18), (int256(bipsBelowSpot) * -1));
        uint256 upperAnchorPrice = Utils.addBips(floorPosition.price, int256(bips));
        int24 lowerAnchorTick = Conversions.priceToTick(int256(lowerAnchorPrice), tickSpacing);

        require(
            lowerAnchorTick >= floorPosition.upperTick, 
            string(
                abi.encodePacked(
                    "deployAnchor: invalid anchor, spot price: ", 
                    Utils._uint2str(Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18))
                )
            )
        );

        (int24 lowerTick, int24 upperTick) = (-76500, -73800); 
        // Conversions
        // .computeRangeTicks(
        //     lowerAnchorPrice, 
        //     upperAnchorPrice, 
        //     tickSpacing
        // );

        uint256 balanceToken0 = ERC20(token0).balanceOf(address(this));
        uint256 balanceToken1 = ERC20(token1).balanceOf(address(this));

        uint256 amount0Max = (balanceToken0 * 5) / 100;
        uint256 amount1Max = balanceToken1;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );


        if (liquidity > 0) {
            Uniswap.mint(pool, lowerTick, upperTick, liquidity, LiquidityType.Anchor, false);
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "deployAnchor: liquidity is 0, spot price:  ", 
                            Utils._uint2str(uint256(sqrtRatioX96)
                        )
                    )
                )
            ); 
        }

        anchorPosition = LiquidityPosition(
            lowerTick, 
            upperTick, 
            liquidity, 
            upperAnchorPrice,
            anchorPosition.amount0LowerBound, 
            anchorPosition.amount1UpperBound,
            0
        );

        
        initialized = true;
    }

    function collect(LiquidityType liquidityType) public {
        require(initialized, "not initialized");
        
        LiquidityPosition memory position;

        if (liquidityType == LiquidityType.Floor) {
            position = floorPosition;
        } else if (liquidityType == LiquidityType.Anchor) {
            position = anchorPosition;
        } else if (liquidityType == LiquidityType.Discovery) {
            position = discoveryPosition;
        }
    
        LiquidityHelper.collect(
            pool, 
            position
        );
    }

    function deployDiscovery(uint256 bips) public {
        require(initialized, "not initialized");

        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        uint256 lowerDiscoveryPrice = Conversions.sqrtPriceX96ToPrice(
            Conversions.tickToSqrtPriceX96(anchorPosition.upperTick), 
            18 // decimals hardcoded for now
        );
        
        lowerDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, 50);
        uint256 upperDiscoveryPrice = Utils.addBips(lowerDiscoveryPrice, int256(bips));

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeRangeTicks(
            lowerDiscoveryPrice, 
            upperDiscoveryPrice, 
            tickSpacing
        );

        uint256 balanceToken0 = ERC20(token0).balanceOf(address(this));
        uint256 balanceToken1 = ERC20(token1).balanceOf(address(this));

        uint256 amount0Max = (balanceToken0 * 30) / 100; // 30% of token0 in Discovery
        uint256 amount1Max = 0;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        if (liquidity > 0) {
            Uniswap.mint(pool, lowerTick, upperTick, liquidity, LiquidityType.Discovery, false);
        } else {
            revert(
                string(
                    abi.encodePacked(
                            "deployDiscovery: liquidity is 0, spot price:  ", 
                            Utils._uint2str(uint256(sqrtRatioX96)
                        )
                    )
                )
            ); 
        }  

        idoManager.buyTokens(Utils.addBips(lowerDiscoveryPrice, 500), 20 ether);
        discoveryPosition = LiquidityPosition(
            lowerTick, 
            upperTick, 
            liquidity, 
            upperDiscoveryPrice, 
            discoveryPosition.amount0LowerBound, 
            discoveryPosition.amount1UpperBound,
            0
        );
    }

    function shiftFloor(uint256 bips) public {
        require(initialized, "not initialized");

        LiquidityHelper
        .shiftFloor(
            address(this), 
            pool, 
            floorPosition,
            token1, 
            bips, 
            tickSpacing
        );
    }

    function updatePosition(
        LiquidityPosition memory position, 
        LiquidityType liquidityType
    ) public {
        require(msg.sender == address(this), "cb not allowed");

        if (liquidityType == LiquidityType.Floor) {
            floorPosition = position;
        } else if (liquidityType == LiquidityType.Anchor) {
            anchorPosition = position;
        } else if (liquidityType == LiquidityType.Discovery) {
            discoveryPosition = position;
        }
    }

    function getUnderlyingBalances(LiquidityType liquidityType) public 
    view 
    returns  (uint256 amount0Current, uint256 amount1Current) {
        LiquidityPosition memory position;

        if (liquidityType == LiquidityType.Floor) {
            position = floorPosition;
        } else if (liquidityType == LiquidityType.Anchor) {
            position = anchorPosition;
        } else if (liquidityType == LiquidityType.Discovery) {
            position = discoveryPosition;
        }

        return LiquidityHelper.getUnderlyingBalances(pool, position);
    }

    function getFloorCapacity() public view returns (uint256) {
        return LiquidityHelper.getFloorCapacity(floorPosition);
    }

    function getAnchorPosition() public view 
    returns (int24, int24, uint128, uint256, uint256, uint256, uint256) {
        uint256 amount1 = LiquidityHelper.getAmount1ForLiquidityInPosition(anchorPosition);
        return (
            anchorPosition.lowerTick, 
            anchorPosition.upperTick, 
            anchorPosition.liquidity, 
            anchorPosition.price,
            anchorPosition.amount0LowerBound,
            anchorPosition.amount1UpperBound,
            amount1
        );
    }

    function getFloorPosition() public view 
    returns (int24, int24, uint128, uint256, uint256, uint256, uint256) {
        return (
            floorPosition.lowerTick, 
            floorPosition.upperTick, 
            floorPosition.liquidity, 
            floorPosition.price,
            floorPosition.amount0LowerBound,
            floorPosition.amount1UpperBound,
            0
        );
    }

    function getAmount1RequiredForAnchorTop() public view returns (uint256) {
        
        (,int24 upperTick,,,, uint256 amount1UpperBound, uint256 amount1UpperBoundVirtual) = getAnchorPosition();

        revert(
            string(
                abi.encodePacked(
                    "Amount1 required to reach ", 
                    Utils.intToString(upperTick),
                    " is ",
                    Utils._uint2str(amount1UpperBoundVirtual - amount1UpperBound)
                )
            )
        );
    }

    function getToken0Balance() public view returns (uint256) {
        return ERC20(token0).balanceOf(address(this));
    }

    function getToken1Balance() public view returns (uint256) {
        return ERC20(token1).balanceOf(address(this));
    }
    
    function getFloorPrice() public view returns (uint256) {
        return floorPosition.price;
    }

}