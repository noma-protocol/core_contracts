// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {pAsset} from "./token/pAsset.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Conversions} from "../libraries/Conversions.sol";
import {Uniswap} from "../libraries/Uniswap.sol";
import {TokenInfo} from "../types/Types.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {Utils} from "../libraries/Utils.sol";
import {DecimalMath} from "../libraries/DecimalMath.sol";

import {PresaleDeployParams, PresaleProtocolParams, LivePresaleParams} from "../types/Types.sol";

interface IVault {
    function afterPresale() external;
}

interface IPresale {
    function buyTokens(uint256 price, uint256 amount, address receiver) external payable;
}

/**
 * @title Presale Contract
 * @notice Manages the presale process and interfaces with the Bootstrap contract, including a referral system.
 */
contract Presale is pAsset, Ownable {
    using SafeERC20 for IERC20;
    
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public vaultAddress;

    /// @notice Soft cap for the presale in ETH.
    uint256 public softCap;

    uint256 public hardCap;

    /// @notice Initial price of the token in ETH.
    uint256 public initialPrice;

    uint256 public launchSupply;

    uint256 public floorPercentage;

    /// @notice Interface to the Uniswap v3 pool.
    IUniswapV3Pool public pool;

    /// @notice Deadline for the presale.
    uint256 public deadline;

    /// @notice Tracks whether the presale is finalized.
    bool public finalized;

    /// @notice Tracks ETH contributions per address.
    mapping(address => uint256) public contributions;

    /// @notice Tracks referral earnings using referral codes.
    mapping(bytes32 => uint256) public referralEarnings;

    /// @notice Referral percentage (3%).
    uint256 public constant referralPercentage = 3;

    /// @notice Tracks all contributors.
    address[] public contributors;

    /// @notice Tracks if an address has already been added as a contributor.
    mapping(address => bool) public isContributor;

    /// @dev Stores token information
    TokenInfo private tokenInfo;

    PresaleProtocolParams public protocolParams;

    int24 public tickSpacing;

    uint256 public MIN_CONTRIBUTION;
    uint256 public MAX_CONTRIBUTION;

    /// @notice Events
    event Deposit(address indexed user, uint256 amount, bytes32 indexed referralCode);
    event ReferralPaid(bytes32 indexed referralCode, uint256 amount);
    event Finalized();
    event TokenBurned(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed user, uint256 amount);
    
    /// @dev Custom errors
    error NotFinalized();
    error AlreadyFinalized();
    error PresaleOngoing();
    error PresaleEnded();
    error WithdrawNotAllowedYet();
    error SoftCapNotMet();
    error HardCapExceeded();
    error NoContributionsToWithdraw();
    error CallbackCaller();
    error InvalidParameters();

    constructor(
        PresaleDeployParams memory params,
        PresaleProtocolParams memory protocolParams
    ) 
    pAsset(params.name, params.symbol, params.decimals) 
    Ownable(params.deployer) {

        vaultAddress = params.vaultAddress;
        pool = IUniswapV3Pool(params.pool);
        softCap = params.softCap;
        initialPrice = params.initialPrice;
        deadline = params.deadline;
        tickSpacing = params.tickSpacing;
        launchSupply = params.totalSupply;
        floorPercentage = params.floorPercentage;
        protocolParams = protocolParams;
        referralPercentage = protocolParams.referralPercentage;
        hardCap = ((launchSupply * floorPercentage) / 100) / ((initialPrice * 80 / 100) / 1e18);
        
        uint256 token0Decimals = IERC20Metadata(pool.token0()).decimals();
        uint256 floorToken1Amount = ((launchSupply * floorPercentage / 100) / initialPrice) * 10 ** token0Decimals;

        if (softCap > (floorToken1Amount * protocolParams.maxSoftCap)) revert InvalidParameters();
        if (softCap < (floorToken1Amount * 5/100)) revert InvalidParameters();

        tokenInfo = TokenInfo({
            token0: pool.token0(),
            token1: pool.token1()
        });

        MIN_CONTRIBUTION = hardCap / protocolParams.minContributionRatio;
        MAX_CONTRIBUTION = hardCap / protocolParams.maxContributionRatio;
    }

    /**
     * @notice Callback function for Uniswap v3 swaps.
     * @param amount0Delta Change in token0 balance.
     * @param amount1Delta Change in token1 balance.
     * @param data Additional data for the callback.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external
    {
        if (msg.sender != address(pool)) revert CallbackCaller();

        if (amount0Delta > 0) {
           IERC20(tokenInfo.token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(tokenInfo.token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /**
     * @notice Allows users to contribute ETH to the presale.
     * @param referralCode Referral code used for this deposit (optional).
     */
    function deposit(bytes32 referralCode) external payable {
        // if (block.timestamp > deadline) revert PresaleEnded();
        if (finalized) revert AlreadyFinalized();

        // if (msg.value < MIN_CONTRIBUTION || msg.value > MAX_CONTRIBUTION) revert InvalidParameters();
        
        uint256 balance = address(this).balance;

        if (balance > hardCap) revert HardCapExceeded();

        // Track contributions
        contributions[msg.sender] += msg.value;

        // Mint p-assets based on ETH deposited at the presale price
        uint256 amountToMint = (msg.value * 1e18) / initialPrice;
        _mint(msg.sender, amountToMint);

        // Add to contributors array if not already added
        if (!isContributor[msg.sender]) {
            contributors.push(msg.sender);
            isContributor[msg.sender] = true;
        }

        // Handle referrals
        if (referralCode != bytes32(0)) {
            uint256 referralFee = (msg.value * referralPercentage) / 100;
            referralEarnings[referralCode] += referralFee;
        }
        
        emit Deposit(msg.sender, msg.value, referralCode);
    }

    /**
     * @notice Finalizes the presale and buys tokens.
     */
    function finalize() external {
        if (finalized) revert AlreadyFinalized();
        // if (block.timestamp < deadline) revert PresaleOngoing();

        uint256 totalAmount = address(this).balance;
        uint256 amount = totalAmount - (totalAmount * protocolParams.presalePercentage);

        if (amount < softCap) revert SoftCapNotMet();

        // Deploy liquidity to the vault
        IVault(vaultAddress).afterPresale();

        // Deposit WETH
        IWETH(tokenInfo.token1).deposit{value: amount}();

        uint8 decimals = IERC20Metadata(tokenInfo.token0).decimals();
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        uint256 spotPrice = Conversions.sqrtPriceX96ToPrice(sqrtRatioX96, 18);

        // Slippage due to floor tick width (0.5%)
        uint256 purchasePrice = spotPrice + (spotPrice * 5/1000);

        Uniswap.swap(
            address(pool),
            address(this),
            tokenInfo.token0,
            tokenInfo.token1,
            Conversions.priceToSqrtPriceX96(
                int256(purchasePrice), 
                tickSpacing, 
                decimals
            ),
            amount - (amount * protocolParams.presalePercentage),
            false,
            true
        );

        finalized = true;

        emit Finalized();
    }

    /**
     * @notice Pays out referral fees after finalization.
     */
    function payReferrals() external {
        if (!finalized) revert NotFinalized();

        for (uint256 i = 0; i < contributors.length; i++) {
            bytes32 referralCode = generateReferralCode(contributors[i]);
            uint256 fee = referralEarnings[referralCode];
            if (fee > 0) {
                referralEarnings[referralCode] = 0;

                // Derive referrer address directly from referral code
                address referrer = address(uint160(uint256(referralCode)));
                if (referrer != address(0)) {
                    payable(referrer).transfer(fee);
                    emit ReferralPaid(referralCode, fee);
                }
            }
        }
    }

    function withdraw() external {
        if (!finalized) revert NotFinalized();

        // Check if pAsset balance is greater than 0
        uint256 balance = balanceOf[msg.sender];

        if (balance == 0) revert NoContributionsToWithdraw();

        // Burn p-assets
        _burn(msg.sender, balance);

        address token0 = pool.token0();

        // Account for slippage due to floor tick width (0.5%)
        uint256 minAmountOut = (balance * 995) / 1000; 

        // Get the available balance of token0 in the contract
        uint256 availableBalance = IERC20(token0).balanceOf(address(this));

        // Ensure the available balance meets the minimum required amount
        require(availableBalance >= minAmountOut, "Insufficient liquidity for withdrawal");

        // Transfer tokens to the user
        IERC20(token0).safeTransfer(msg.sender, availableBalance);

        emit TokensWithdrawn(msg.sender, availableBalance);
    }  

    /**
     * @notice Allows contributors to withdraw funds if the presale is unsuccessful.
     * Contributors must burn their p-assets first.
     * Withdrawal can only occur 30 days after the presale deadline.
     */
    function emergencyWithdrawal() external {
        if (finalized) revert PresaleOngoing();
        if (block.timestamp < deadline + 30 days) revert WithdrawNotAllowedYet();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoContributionsToWithdraw();

        // Burn p-assets equivalent to the contribution amount
        uint256 pAssetAmount = (amount * 1e18) / initialPrice;
        _burn(msg.sender, pAssetAmount);

        contributions[msg.sender] = 0;
        payable(msg.sender).transfer(amount);

        emit TokenBurned(msg.sender, pAssetAmount);
    }

    /**
     * @notice Allows the owner to withdraw excess ETH and tokens after finalization.
     */
    function withdrawExcess() external onlyOwner {
        if (!finalized) revert NotFinalized();

        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);

        address token0 = pool.token0();
        uint256 token0Balance = IERC20(token0).balanceOf(address(this));
        if (token0Balance > 0) {
            IERC20(token0).safeTransfer(owner(), token0Balance);
        }
    }

    /**
     * @notice Generates a referral code based on an address.
     * @param user Address to generate a referral code for.
     * @return Referral code.
     */
    function generateReferralCode(address user) public pure returns (bytes32) {
        return bytes32(uint256(uint160(user)));
    }

    // ==================== New Functions ====================

    /**
     * @notice Returns the total ETH raised during the presale.
     * @return Total ETH raised.
     */
    function getTotalRaised() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Returns the total number of participants in the presale.
     * @return Total number of participants.
     */
    function getParticipantCount() external view returns (uint256) {
        return contributors.length;
    }

    /**
     * @notice Checks if the soft cap has been reached.
     * @return True if the soft cap has been reached, false otherwise.
     */
    function softCapReached() external view returns (bool) {
        return address(this).balance >= softCap;
    }

    /**
     * @notice Returns the total ETH raised through a specific referral code.
     * @param referralCode The referral code to check.
     * @return Total ETH raised through the referral code.
     */
    function getTotalReferredByCode(bytes32 referralCode) external view returns (uint256) {
        return referralEarnings[referralCode];
    }

    /**
     * @notice Returns the number of users who used a specific referral code.
     * @param referralCode The referral code to check.
     * @return Number of users who used the referral code.
     */
    function getReferralUserCount(bytes32 referralCode) external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < contributors.length; i++) {
            if (generateReferralCode(contributors[i]) == referralCode) {
                count++;
            }
        }
        return count;
    }

    function getPresaleParams() external view returns (LivePresaleParams memory) {
        return LivePresaleParams({
            softCap: softCap,
            initialPrice: initialPrice,
            deadline: deadline,
            launchSupply: launchSupply
        });
    }
    modifier onlyInternalCalls() {
        require(msg.sender == address(this), "Only internal calls allowed");
        _;
    }
}