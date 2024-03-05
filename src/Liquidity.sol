// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './libraries/TransferHelper.sol';
import './interfaces/INonFungiblePositionManager.sol';
import './base/PeripheryImmutableState.sol';

import './base/LiquidityManagement.sol';
import './libraries/ABDKMath64x64.sol';
import './libraries/SafeMath.sol';

address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant POOL = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;

address constant POOL_B = 0xba6F08ADb52BAdC392d803E70d48c8071734131E;

IUniswapV3Pool constant pool = IUniswapV3Pool(POOL);
IUniswapV3Pool constant pool_b = IUniswapV3Pool(POOL_B);

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint amount) external;
}


contract UniswapV3Liquidity is IERC721Receiver {
    using SafeMath for uint256;

    IERC20 private constant dai = IERC20(DAI);
    IWETH private constant weth = IWETH(WETH);

    // using ABDKMath64x64 for int24;
    //int24 private constant MIN_TICK = -887272;
    //int24 private constant MAX_TICK = -MIN_TICK;

    uint public totalTokens = 0;
    int24 private constant TICK_SPACING = 60;


    INonfungiblePositionManager public nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    address public NFT_ADDRESS  = address(nonfungiblePositionManager);
    mapping(uint256 => INonfungiblePositionManager.TokenPosition) public positions;

    event PositionMinted(
        uint amount0,
        uint amount1,
        uint128 liquidity,
        uint tokenId,
        int24 currentTick
        // int56 tickCumulativeInside, 
        // uint160 secondsPerLiquidityInsideX128, 
        // uint32 secondsInside,
    );

    event LiquidityAdded(uint amount0, uint amount1, uint128 liquidity, uint tokenId);
    event FeesCollected(uint amount0, uint amount1);
    event RemoveLiquidity(uint256 availableLiquidity, uint256 amount0, uint256 amount1, bytes32 positionKey);
    event LiquidityRemoved(uint amount0, uint amount1);

    modifier isApprovedOrOwner(uint256 tokenId) {
        address owner = IERC721(NFT_ADDRESS).ownerOf(tokenId);
        bool isApprovedForAll = IERC721(NFT_ADDRESS).isApprovedForAll(owner, msg.sender);
        if (
            msg.sender != owner &&
            !isApprovedForAll &&
            IERC721(NFT_ADDRESS).getApproved(tokenId) != msg.sender
        ) revert("not owner");
        _;
    }

    function priceToTick(uint256 price) public pure returns (int24 tick_) {
        tick_ = TickMath.getTickAtSqrtRatio(
        uint160(
            int160(
            ABDKMath64x64.sqrt(int128(int256(price << 64))) <<
            (FixedPoint96.RESOLUTION - 64)
            )
        )
        );
    }

    function getCurrentTick() public view returns (uint160 sqrtPriceX96, int24 currentTick) {
        (sqrtPriceX96, currentTick, , , , , ) = pool.slot0();
    }

    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function mintNewPositionSingleTick(
        int24 MIN_TICK, 
        uint amount0ToAdd,
        uint amount1ToAdd,
        address tokenA,
        address tokenB
    )
        external
        returns (
            // int56 tickCumulativeInside,
            // uint160 secondsPerLiquidityInsideX128,
            // uint32 secondsInside,
            uint tokenId,
            uint128 liquidity,
            uint amount0,
            uint amount1
        )
    {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amount0ToAdd);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amount1ToAdd);

        IERC20(tokenA).approve(address(nonfungiblePositionManager), amount0ToAdd);
        IERC20(tokenB).approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: tokenA,
                token1: tokenB,
                fee: 3000,
                tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
                tickUpper: ((MIN_TICK / TICK_SPACING + 1) * TICK_SPACING),
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0, //amount0ToAdd.sub(amount0ToAdd.div(2))
                amount1Min: 0, //amount1ToAdd.sub(amount1ToAdd.div(2))
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(
            params
        );

        if (amount0 < amount0ToAdd) {
            IERC20(tokenA).approve(address(nonfungiblePositionManager), 0);
            uint refund0 = amount0ToAdd - amount0;
            IERC20(tokenA).transfer(msg.sender, refund0);
        }
        if (amount1 < amount1ToAdd) {
            IERC20(tokenB).approve(address(nonfungiblePositionManager), 0);
            uint refund1 = amount1ToAdd - amount1;
            IERC20(tokenB).transfer(msg.sender, refund1);
        }

        // (tickCumulativeInside, secondsPerLiquidityInsideX128, secondsInside) = pool
        //     .snapshotCumulativesInside(params.tickLower, params.tickUpper);

        (, int24 currentTick, , , , , ) = pool.slot0();

        INonfungiblePositionManager.TokenPosition storage currentPosition = positions[totalTokens++];

        currentPosition.pool = POOL; 
        currentPosition.lowerTick = params.tickLower;
        currentPosition.upperTick = params.tickUpper;

        IERC721(NFT_ADDRESS).approve(msg.sender, tokenId);
        
        emit LiquidityAdded(amount0, amount1, liquidity, tokenId);
        emit PositionMinted(amount0, amount1, liquidity, tokenId, currentTick);
        // emit PositionMinted(amount0, amount1, liquidity, tokenId, tickCumulativeInside, secondsPerLiquidityInsideX128, secondsInside, currentTick);

    }

    function mintNewPositionRange(
        int24 MIN_TICK, 
        uint amount0ToAdd,
        uint amount1ToAdd,
        address tokenA,
        address tokenB
    )
        external
        returns (
            uint tokenId,
            uint128 liquidity,
            uint amount0,
            uint amount1
        )
    {
        IERC20(tokenA).transferFrom(msg.sender, address(this), amount0ToAdd);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amount1ToAdd);

        IERC20(tokenA).approve(address(nonfungiblePositionManager), amount0ToAdd);
        IERC20(tokenB).approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: tokenA,
                token1: tokenB,
                fee: 3000,
                tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
                tickUpper: (-MIN_TICK / TICK_SPACING) * TICK_SPACING,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0, //amount0ToAdd.sub(amount0ToAdd.div(2))
                amount1Min: 0, //amount1ToAdd.sub(amount1ToAdd.div(2))
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(
            params
        );

        if (amount0 < amount0ToAdd) {
            IERC20(tokenA).approve(address(nonfungiblePositionManager), 0);
            uint refund0 = amount0ToAdd - amount0;
            IERC20(tokenA).transfer(msg.sender, refund0);
        }
        if (amount1 < amount1ToAdd) {
            IERC20(tokenB).approve(address(nonfungiblePositionManager), 0);
            uint refund1 = amount1ToAdd - amount1;
            IERC20(tokenB).transfer(msg.sender, refund1);
        }
        
        (, int24 currentTick, , , , , ) = pool.slot0();

        INonfungiblePositionManager.TokenPosition storage currentPosition = positions[totalTokens++];

        currentPosition.pool = POOL; 
        currentPosition.lowerTick = params.tickLower;
        currentPosition.upperTick = params.tickUpper;

        IERC721(NFT_ADDRESS).approve(msg.sender, tokenId);
        
        emit LiquidityAdded(amount0, amount1, liquidity, tokenId);
        // emit PositionMinted(amount0, amount1, liquidity, tokenId, tickCumulativeInside, secondsPerLiquidityInsideX128, secondsInside, currentTick);
    }

    function mint(
        INonfungiblePositionManager.MintParams memory params
    )
        external
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside,
            uint tokenId,
            uint128 liquidity,
            uint amount0,
            uint amount1
        )
    {
        dai.transferFrom(msg.sender, address(this), params.amount0Desired);
        weth.transferFrom(msg.sender, address(this), params.amount1Desired);

        dai.approve(address(nonfungiblePositionManager), params.amount0Desired);
        weth.approve(address(nonfungiblePositionManager), params.amount1Desired);

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(
            params
        );

        if (amount0 < params.amount0Desired) {
            dai.approve(address(nonfungiblePositionManager), 0);
            uint refund0 = params.amount0Desired - amount0;
            dai.transfer(msg.sender, refund0);
        }
        if (amount1 < params.amount1Desired) {
            weth.approve(address(nonfungiblePositionManager), 0);
            uint refund1 = params.amount1Desired - amount1;
            weth.transfer(msg.sender, refund1);
        }

        (tickCumulativeInside, secondsPerLiquidityInsideX128, secondsInside) = pool
            .snapshotCumulativesInside(params.tickLower, params.tickUpper);

        (, int24 currentTick, , , , , ) = pool.slot0();

        INonfungiblePositionManager.TokenPosition storage currentPosition = positions[totalTokens++];

        currentPosition.pool = POOL; 
        currentPosition.lowerTick = params.tickLower;
        currentPosition.upperTick = params.tickUpper;
        
        emit LiquidityAdded(amount0, amount1, liquidity, tokenId);
        // emit PositionMinted(amount0, amount1, liquidity, tokenId, tickCumulativeInside, secondsPerLiquidityInsideX128, secondsInside, currentTick);
    }

    function collectAllFees(uint tokenId)
        external
        returns (uint amount0, uint amount1)
    {
        INonfungiblePositionManager.CollectParams  memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(
            params
        );
        emit FeesCollected(amount0, amount1);
    }

    function increaseLiquidityCurrentRange(
        uint tokenId,
        uint amount0ToAdd,
        uint amount1ToAdd
    )
        external
        returns (
            uint128 liquidity,
            uint amount0,
            uint amount1
        )
    {
        dai.transferFrom(msg.sender, address(this), amount0ToAdd);
        weth.transferFrom(msg.sender, address(this), amount1ToAdd);

        dai.approve(address(nonfungiblePositionManager), amount0ToAdd);
        weth.approve(address(nonfungiblePositionManager), amount1ToAdd);

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(
            params
        );
    }

    // function decreaseLiquidityCurrentRange(uint tokenId, uint128 liquidity)
    //     external
    //     returns (uint amount0, uint amount1)
    // {
    //     INonfungiblePositionManager.DecreaseLiquidityParams
    //         memory params = INonfungiblePositionManager.DecreaseLiquidityParams({
    //             tokenId: tokenId,
    //             liquidity: liquidity,
    //             amount0Min: 0,
    //             amount1Min: 0,
    //             deadline: block.timestamp
    //         });

    //     (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
    //         params
    //     );
    // }

    // function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams memory params)
    //     external
    //     isApprovedOrOwner(params.tokenId)
    //     returns (uint amount0, uint amount1)
    // {
    //     // INonfungiblePositionManager.DecreaseLiquidityParams
    //     //     memory myPars = INonfungiblePositionManager.DecreaseLiquidityParams({
    //     //         tokenId: params.tokenId,
    //     //         liquidity: params.liquidity,
    //     //         amount0Min: 0,
    //     //         amount1Min: 0,
    //     //         deadline: block.timestamp
    //     //     });

    //     // (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
    //     //     myPars
    //     // );
    // }

    function decreaseLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    )
        external
        isApprovedOrOwner(params.tokenId)
        payable
        returns (uint amount0, uint amount1)
    {
        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
        emit LiquidityRemoved(amount0, amount1);
    }

    // function removeLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams memory params)
    //     external
    //     isApprovedOrOwner(params.tokenId)
    //     returns (uint amount0, uint amount1)
    // {
    //     // INonfungiblePositionManager.DecreaseLiquidityParams
    //     //     memory myPars = INonfungiblePositionManager.DecreaseLiquidityParams({
    //     //         tokenId: params.tokenId,
    //     //         liquidity: params.liquidity,
    //     //         amount0Min: 0,
    //     //         amount1Min: 0,
    //     //         deadline: block.timestamp
    //     //     });

    //     // (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
    //     //     myPars
    //     // );
    // }

    function removeLiquidity(
        uint tokenId, 
        uint128 liquidity
    )
        public
        isApprovedOrOwner(tokenId)
        returns (uint256 amount0, uint256 amount1)
    {
        INonfungiblePositionManager.TokenPosition memory tokenPosition = positions[tokenId];
        require(tokenPosition.pool != address(0), "Position not set");
        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);
        bytes32 positionKey = poolPositionKey(tokenPosition);

        (uint128 availableLiquidity, , , , ) = pool.positions(
            poolPositionKey(tokenPosition)
        );

        require(availableLiquidity >= liquidity, "Not enough liquidity!");
        (amount0, amount1) = pool.burn(
            tokenPosition.lowerTick,
            tokenPosition.upperTick,
            liquidity
        );

        emit RemoveLiquidity(availableLiquidity, amount0, amount1, positionKey);

    }


    /*
        Returns position ID within a pool
    */
    function poolPositionKey(INonfungiblePositionManager.TokenPosition memory position)
        internal
        view
        returns (bytes32 key)
    {
        key = keccak256(
            abi.encodePacked(
                address(this),
                position.lowerTick,
                position.upperTick
            )
        );
    }

    /*
        Returns position ID within the NFT manager
    */
    function positionKey(INonfungiblePositionManager.TokenPosition memory position)
        internal
        pure
        returns (bytes32 key)
    {
        key = keccak256(
            abi.encodePacked(
                address(position.pool),
                position.lowerTick,
                position.upperTick
            )
        );
    }   



}
