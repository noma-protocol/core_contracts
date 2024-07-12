

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {TickMath} from '@uniswap/v3-core/libraries/TickMath.sol';

import {BaseVault} from "./vault/BaseVault.sol";
 
import {MockNomaToken} from "./token/MockNomaToken.sol";
import {Conversions} from "./libraries/Conversions.sol";
import {Utils} from "./libraries/Utils.sol";
import {feeTier, tickSpacing, LiquidityPosition, LiquidityType, TokenInfo} from "./Types.sol";
import {Uniswap} from "./libraries/Uniswap.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockWETH} from "../src/token/MockWETH.sol";

import {Diamond} from "./Diamond.sol";
import {DiamondInit} from "./init/DiamondInit.sol";
import {OwnershipFacet} from "./facets/OwnershipFacet.sol";
import {DiamondCutFacet} from "./facets/DiamondCutFacet.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {IFacet} from "./interfaces/IFacet.sol";
import {IDiamond} from "./interfaces/IDiamond.sol";

interface IWETH {
    function deposit() external payable;
    function depositTo(address receiver) external payable;
    function transfer(address to, uint value) external returns (bool);
    function mintTo(address to, uint256 amount) external;
}

interface IVaultUpgrade {
    function doUpgradeStart(address diamond, address _vaultUpgradeFinalize) external;
    function doUpgradeFinalize(address diamond) external;
}

contract IDOManager is Owned {

    bool private initialized;

    IUniswapV3Pool public pool;

    MockNomaToken private amphorToken;
    MockWETH private mockWeth;

    BaseVault public vault;

    uint256 private totalSupply;
    uint256 private launchSupply;
    address private uniswapFactory;
    address private vaultUpgrade;
    address private vaultUpgradeFinalize;
    address public mockWethAddress;
    address public implementationAddress;
    address public proxyAddress;

    TokenInfo private  tokenInfo;
    address public modelHelper;
    uint256 private IDOPrice;

    LiquidityPosition private IDOPosition;

    Diamond diamond;
    DiamondCutFacet dCutFacet;
    OwnershipFacet ownerF;
    DiamondInit dInit;

    constructor(
        address _deployer,
        address _uniswapFactory, 
        address _modelHelper,
        address _token1,
        uint256 _totalSupply, 
        uint16 _percentageForSale
    ) Owned(_deployer) { 
        require(
            _percentageForSale > 0 && 
            _percentageForSale < 50, 
            "invalid percentage"
        );

        totalSupply = _totalSupply;
        launchSupply = totalSupply * _percentageForSale / 100;   

        // Dev: force desired token order on Uniswap V3
        uint256 nonce = 0;
        MockNomaToken amphorToken;

        // Encode the initialize function call
        bytes memory data = abi.encodeWithSelector(
            amphorToken.initialize.selector,
            // address(this),  // owner address
            address(this),  // Deployer address
            totalSupply     // Initial supply
        );

        do {
            mockWeth = new MockWETH(_deployer);
            amphorToken = new MockNomaToken{salt: bytes32(nonce)}();            
            nonce++;
        } while (address(amphorToken) >= address(mockWeth));

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(amphorToken),
            data
        );      
        
        require(address(amphorToken) < address(mockWeth), "invalid token address");

        implementationAddress = address(amphorToken);
        mockWethAddress = address(mockWeth);
        proxyAddress = address(proxy);

        amphorToken.initialize(address(this), totalSupply);
        MockNomaToken(address(proxy)).setOwner(_deployer);
        // amphorToken.transferOwnership(deployer);
        
        uniswapFactory = _uniswapFactory;
        
        uint256 totalSupplyFromContract = amphorToken.totalSupply();

        require(totalSupplyFromContract == totalSupply, "wrong parameters");
        require(address(proxy) != address(0), "Token deploy failed");

        TokenInfo storage tokenInfo = tokenInfo;
        tokenInfo.token0 = address(proxy);  
        tokenInfo.token1 = address(mockWeth); 
        modelHelper = _modelHelper;

    }

    function initialize(
        uint256 _initPrice, 
        uint256 _IDOPrice, 
        address _vaultUpgrade, 
        address _vaultUpgradeFinalize,
        address _escrowContract,
        address _stakingContract
    ) public onlyOwner {
        require(!initialized, "already initialized");

        IUniswapV3Factory factory = IUniswapV3Factory(uniswapFactory);
        pool = IUniswapV3Pool(
            factory.getPool(tokenInfo.token0, tokenInfo.token1, feeTier)
        );

        if (address(pool) == address(0)) {
            pool = IUniswapV3Pool(
                factory.createPool(tokenInfo.token0, tokenInfo.token1, feeTier)
            );
            IUniswapV3Pool(pool)
            .initialize(
                Conversions.priceToSqrtPriceX96(int256(_initPrice), tickSpacing)
            );
        } 
        
        vaultUpgrade = _vaultUpgrade;
        vaultUpgradeFinalize = _vaultUpgradeFinalize;

        address vaultAddress = _preDeploy();
        vault = BaseVault(vaultAddress);

        IVaultUpgrade(vaultUpgrade).doUpgradeStart(vaultAddress, vaultUpgradeFinalize);
        vault.initialize(owner, address(pool), modelHelper, address(0), proxyAddress, address(0));
        
        IDOPrice = _IDOPrice;
        initialized = true;
    }

    function createIDO(address receiver) public onlyOwner {
        require(initialized, "not initialized");

        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        (int24 lowerTick, int24 upperTick) = Conversions
        .computeSingleTick(IDOPrice, tickSpacing);

        uint256 amount0Max = launchSupply;
        uint256 amount1Max = 0;

        uint128 liquidity = LiquidityAmounts
        .getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Max,
            amount1Max
        );

        // if (liquidity > 0) {
        //     Uniswap.mint(address(pool), address(this), lowerTick, upperTick, liquidity, LiquidityType.Floor, false);
        // } else {
        //     revert("createIDO: liquidity is 0");
        // }

        ERC20(tokenInfo.token0).transfer(receiver, totalSupply);
        //ERC20(tokenInfo.token0).transfer(receiver, totalSupply - launchSupply);
        // IDOPosition = LiquidityPosition(lowerTick, upperTick, liquidity, IDOPrice);
    }

    function _preDeploy()
        internal
        returns (address vault)
    {
        //deploy facets
        dCutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(dCutFacet));
        ownerF = new OwnershipFacet();
        dInit = new DiamondInit();

        //build cut struct
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](3);

        cut[0] = (
            IDiamondCut.FacetCut({
                facetAddress: address(ownerF),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(address(ownerF)).getFunctionSelectors()
            })
        );

        cut[1] = (
            IDiamondCut.FacetCut({
                facetAddress: address(dInit),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(address(dInit)).getFunctionSelectors()
            })
        );

        cut[2] = (
            IDiamondCut.FacetCut({
                facetAddress: address(dCutFacet),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: IFacet(address(dCutFacet)).getFunctionSelectors()
            })
        );

        //upgrade diamond
        IDiamondCut(address(diamond)).diamondCut(cut, address(0x0), "");
        IDiamond(address(diamond)).transferOwnership(vaultUpgrade);

        //Initialization
        DiamondInit(address(diamond)).init();
        vault = address(diamond);
    }

    // Test function
    function buyIDO(uint256 price, uint256 amountToken1, address receiver) public {
        Uniswap.swap(
            address(pool),
            receiver,
            tokenInfo.token0,
            tokenInfo.token1,
            Conversions.priceToSqrtPriceX96(int256(price), tickSpacing),
            amountToken1,
            false,
            false
        );        
    }

    function collectIDOFunds(address receiver) public {
        require(initialized, "not initialized");

        uint256 balanceBeforeSwap = ERC20(tokenInfo.token1).balanceOf(address(this));

        bytes32 IDOPositionId = keccak256(
            abi.encodePacked(
                address(this), 
                IDOPosition.lowerTick, 
                IDOPosition.upperTick
            )
        );

        (uint128 liquidity,,,,) = pool.positions(IDOPositionId);

        if (liquidity > 0) {
            Uniswap.burn(
                address(pool),
                address(this),
                IDOPosition.lowerTick, 
                IDOPosition.upperTick,
                liquidity
            );
        } else {
            revert("collectWETH: liquidity is 0");
        }

        uint256 balanceAfterSwap = ERC20(tokenInfo.token1).balanceOf(address(this));
        require(balanceAfterSwap > balanceBeforeSwap, "no tokens exchanged");
        
        // Send left over token0 to contract owner
        ERC20(tokenInfo.token0).transfer(owner, ERC20(tokenInfo.token0).balanceOf(address(this)));

        // Send token1 to receiver (Deployer contract)
        ERC20(tokenInfo.token1).transfer(receiver, ERC20(tokenInfo.token1).balanceOf(address(this)));
    }

    // Test function
    function buyTokens(uint256 price, uint256 amount, address receiver) public {
        Uniswap.swap(
            address(pool),
            receiver,
            tokenInfo.token0,
            tokenInfo.token1,
            Conversions.priceToSqrtPriceX96(int256(price), tickSpacing),
            amount,
            false,
            false
        );        
    }
 
    function sellTokens(uint256 price, uint256 amount, address receiver) public {
        Uniswap.swap(
            address(pool),
            receiver,
            tokenInfo.token0,
            tokenInfo.token1,
            Conversions.priceToSqrtPriceX96(int256(price), tickSpacing),
            amount,
            true,
            false
        );        
    }

    /**
     * @notice Uniswap V3 callback function, called back on pool.mint
     */
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata _data)
        external
    {
        require(msg.sender == address(pool), "callback caller");

        uint256 token0Balance = ERC20(tokenInfo.token0).balanceOf(address(this));
        uint256 token1Balance = ERC20(tokenInfo.token1).balanceOf(address(this));

        if (token0Balance >= amount0Owed) {
            if (amount0Owed > 0) ERC20(tokenInfo.token0).transfer(msg.sender, amount0Owed);
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
            if (amount1Owed > 0) ERC20(tokenInfo.token1).transfer(msg.sender, amount1Owed);
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

    /**
     * @notice Uniswap v3 callback function, called back on pool.swap
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data )
        external
    {
        require(msg.sender == address(pool), "callback caller");

        if (amount0Delta > 0) {
           ERC20(tokenInfo.token0).transfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(tokenInfo.token1).transfer(msg.sender, uint256(amount1Delta));
        }
    }



    receive() external payable {

        uint256 balanceBefore = ERC20(tokenInfo.token1).balanceOf(address(this));

        IWETH(tokenInfo.token1).deposit{value: msg.value}();

        uint256 balanceAfter = ERC20(tokenInfo.token1).balanceOf(address(this));
        uint256 excessAmount = balanceAfter - balanceBefore;

        ERC20(tokenInfo.token1).transfer(owner, excessAmount);
    }

}