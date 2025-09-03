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
  import {PresaleDeployParams, PresaleProtocolParams, LivePresaleParams, SwapParams} from "../types/Types.sol";

  interface IVault {
      function afterPresale() external;
  }

  interface IPresale {
      function buyTokens(uint256 price, uint256 amount, address receiver) external payable;
  }

  interface IFactory {
      function teamMultiSig() external view returns (address);
      function owner() external view returns (address);
  }

  /**
   * @title Presale Contract
   * @notice Manages the presale process and interfaces with the Bootstrap contract, including a referral system.
   */
  contract Presale is pAsset, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Address of the vault contract.  
    address public vaultAddress;

    /// @notice Soft cap for the presale in ETH.
    uint256 public softCap;

    /// @notice Hard cap for the presale in ETH.
    uint256 public hardCap;

    /// @notice Initial price of the token in ETH.
    uint256 public initialPrice;

    /// @notice Total supply of the token to be launched.
    uint256 public launchSupply;

    /// @notice Percentage of the liquidity assigned to floor position.
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

    /// @notice Referral percentage 
    uint256 public referralPercentage;

    /// @notice Tracks all contributors.
    address[] public contributors;
    
    /// @notice Struct to hold token information.
    address public deployer;

    /// @notice Factory address for the presale.
    address public factory; 

    /// @notice Migration contract address, if applicable.
    address public migrationContract;

    /// @notice Tracks if an address has already been added as a contributor.
    mapping(address => bool) public isContributor;

    uint256 public totalRaised;      // net: deposits minus any emergency refunds
    uint256 public totalDeposited;   // gross: sum of all deposits ever received

    /// @dev Stores token information
    TokenInfo private tokenInfo;

    /// @notice Parameters for the presale protocol.
    PresaleProtocolParams public protocolParams;

    int24 public tickSpacing;

    uint256 public MIN_CONTRIBUTION;
    uint256 public MAX_CONTRIBUTION;
    uint256 public teamFeePct;

    bool public emergencyWithdrawalFlag;
    bool private locked;

    /// @notice Events
    event Deposit(address indexed user, uint256 amount, bytes32 indexed referralCode);
    event ReferralPaid(bytes32 indexed referralCode, uint256 amount);
    event Finalized(
        uint256 totalRaised,
        uint256 feeTaken,
        uint256 contributionAmount,
        uint256 slippagePriceX96
    );
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
    error InvalidHardCap();
    error InvalidSoftCap();
    error EmergencyWithdrawalNotEnabled();
    error NoReentrantCalls();
    error NotAuthorized();
    error OnlyFactoryOwner();

    constructor(
        address _factory,
        PresaleDeployParams memory params,
        PresaleProtocolParams memory _protocolParams
    ) 
    pAsset(params.name, params.symbol, params.decimals) 
    Ownable(params.deployer) {
        
        deployer = params.deployer;
        vaultAddress = params.vaultAddress;
        pool = IUniswapV3Pool(params.pool);
        softCap = params.softCap;
        initialPrice = params.initialPrice;
        deadline = block.timestamp + params.deadline;
        tickSpacing = params.tickSpacing;
        launchSupply = params.totalSupply;
        floorPercentage = params.floorPercentage;
        protocolParams = _protocolParams;
        referralPercentage = _protocolParams.referralPercentage;
        factory = _factory;
        teamFeePct = _protocolParams.teamFee;

        uint256 launchSupplyDecimals = IERC20Metadata(pool.token0()).decimals(); 
        uint256 initialPriceDecimals = 18; 

        uint256 normalizedLaunchSupply = launchSupply * (10 ** (18 - launchSupplyDecimals));
        uint256 normalizedInitialPrice = initialPrice * (10 ** (18 - initialPriceDecimals));

        hardCap = (
            (
            normalizedLaunchSupply * normalizedInitialPrice
            ) / 1e18
        ) * params.floorPercentage / 100;

        if (softCap > hardCap * _protocolParams.maxSoftCap / 100) revert InvalidParameters();
        if (softCap > hardCap) revert InvalidHardCap();

        tokenInfo = TokenInfo({
            token0: pool.token0(),
            token1: pool.token1()
        });

        MIN_CONTRIBUTION = hardCap / _protocolParams.minContributionRatio;
        MAX_CONTRIBUTION = hardCap / _protocolParams.maxContributionRatio;

        // Set default values for flags
        emergencyWithdrawalFlag = true;
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
function deposit(bytes32 referralCode) external payable lock {
    if (hasExpired()) revert PresaleEnded();
    if (finalized) revert AlreadyFinalized();
    if (msg.value == 0) revert InvalidParameters();

    // Prevent self-referrals by checking if the referral code is the sender's own code
    if (referralCode != bytes32(0) && referralCode == keccak256(abi.encodePacked(msg.sender))) {
        revert InvalidParameters();
    }

    if (migrationContract == address(0)) {
        if (msg.value < MIN_CONTRIBUTION || msg.value > MAX_CONTRIBUTION) revert InvalidParameters();
    }

    uint256 balance = address(this).balance;
    if (balance > hardCap) revert HardCapExceeded();

    // Track contributions
    contributions[msg.sender] += msg.value;
    totalDeposited += msg.value;
    totalRaised    += msg.value;


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
    function finalize() external lock {
        if (finalized) revert AlreadyFinalized();

        bool expired = hasExpired();
        bool reachedSoftCap = address(this).balance >= softCap;

        if (!expired) {
            // before deadline: only allow if soft cap reached AND caller is owner
            if (!reachedSoftCap) revert PresaleOngoing();
            if (msg.sender != owner()) revert NotAuthorized();
        }
        // if expired: permissionless (no caller restriction)

        // 1) load & validate parameters
        PresaleProtocolParams memory p = protocolParams;
        uint256 pct = p.presalePercentage;
        if (pct == 0 || pct > 100) revert InvalidParameters();

        // 2) compute amounts
        uint256 raisedBalance      = address(this).balance;
        uint256 feeTaken           = (raisedBalance * pct) / 100;
        uint256 contributionAmount = migrationContract != address(0) ? raisedBalance : raisedBalance - feeTaken;

        // 3) enforce soft-cap after fee
        uint256 requiredAfterFee = migrationContract != address(0)
            ? softCap
            : (softCap * (100 - pct)) / 100;
        if (contributionAmount < requiredAfterFee) revert SoftCapNotMet();

        // 4) mark finalized before external calls
        finalized = true;

        // 5) deploy liquidity and wrap
        IVault(vaultAddress).afterPresale();
        IWETH(tokenInfo.token1).deposit{value: contributionAmount}();

        // 6) compute slippage-adjusted price
        (uint160 sqrt0,,,,,,) = pool.slot0();
        uint256 spotPriceX96 = Conversions.sqrtPriceX96ToPrice(sqrt0, 18);
        uint256 slippagePriceX96 = spotPriceX96 + (spotPriceX96 * 5) / 1000;

        // 7) swap with a limit order at slippagePriceX96
        Uniswap.swap(
            SwapParams({
                poolAddress:   address(pool),
                receiver:      address(this),
                token0:        tokenInfo.token0,
                token1:        tokenInfo.token1,
                basePriceX96:  Conversions.priceToSqrtPriceX96(int256(slippagePriceX96), tickSpacing, 18),
                amountToSwap:  contributionAmount,
                slippageTolerance: 1,
                zeroForOne:    false,
                isLimitOrder:  true
            })
        );

        // 8) emit + payouts
        emit Finalized(raisedBalance, feeTaken, contributionAmount, slippagePriceX96);
        _payReferrals();
        _withdrawExcessEth();
    }

    /**
    * @notice Pays out referral fees after finalization.
    */
    function _payReferrals() internal {
        if (!finalized) revert NotFinalized();

        for (uint256 i = 0; i < contributors.length; i++) {
            bytes32 referralCode = Utils.generateReferralCode(contributors[i]);
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

    function withdraw() external lock {
    if (!finalized) revert NotFinalized();

    // Check if pAsset balance is greater than 0
    uint256 balance = balanceOf(msg.sender);

    if (balance == 0) revert NoContributionsToWithdraw();

    // Burn p-assets
    _burn(msg.sender, balance);

    address token0 = pool.token0();

    // Account for slippage due to floor tick width (max 1.5%)
    uint256 minAmountOut = (balance * 985) / 1000;

    // Get the available balance of token0 in the contract
    uint256 availableBalance = IERC20(token0).balanceOf(address(this));

    // Ensure the available balance meets the minimum required amount
    uint256 amountToTransfer = minAmountOut;

    if (availableBalance < amountToTransfer) {
        amountToTransfer = availableBalance;
    }

    bool isMigration = migrationContract != address(0);

    if (isMigration) {
        IERC20(token0).safeTransfer(migrationContract, amountToTransfer);
    } else {
        IERC20(token0).safeTransfer(msg.sender, amountToTransfer);
    }

    emit TokensWithdrawn(msg.sender, amountToTransfer);
    }

    /**
    * @notice Allows contributors to withdraw funds if the presale is unsuccessful.
    * Contributors must burn their p-assets first.
    * Withdrawal can only occur 30 days after the presale deadline.
    */
    function emergencyWithdrawal() external emergencyWithdrawalEnabled lock {
        if (finalized) revert AlreadyFinalized();
        if (block.timestamp < deadline + 30 days) revert WithdrawNotAllowedYet();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoContributionsToWithdraw();

        // Burn p-assets equivalent to the contribution amount
        uint256 pAssetAmount = (amount * 1e18) / initialPrice;
        _burn(msg.sender, pAssetAmount);

        contributions[msg.sender] = 0;
        totalRaised -= amount; 
        payable(msg.sender).transfer(amount);

        emit TokenBurned(msg.sender, pAssetAmount);
    }

    /**
    * @notice Allows the owner to withdraw excess ETH and tokens after finalization.
    */
    function withdrawExcess() external onlyOwner {
        _withdrawExcessEth();
        _withdrawExcessTokens();
    }

    function _withdrawExcessEth() internal {
    if (!finalized) revert NotFinalized();

    uint256 balance = address(this).balance;
        
    // calculate fee
    uint256 fee = (balance * teamFeePct) / 100;

    address teamMultiSig = IFactory(factory).teamMultiSig();

    if (teamMultiSig != address(0)) {
        // transfer fee to team multisig
        payable(teamMultiSig).transfer(fee);
    }
    payable(owner()).transfer(balance - fee);
    }

    /**
    * @notice Withdraws any excess tokens from the contract after finalization.
    * This is used to withdraw any tokens that were not sold during the presale.
    */
    function _withdrawExcessTokens() internal {
        if (!finalized) revert NotFinalized();

        address token0 = pool.token0();
        uint256 token0Balance = IERC20(token0).balanceOf(address(this));
        if (token0Balance > 0) {
            IERC20(token0).safeTransfer(vaultAddress, token0Balance);
        }
    }

    /**
    * @notice Sets the emergency withdrawal flag.
    * @param flag True to enable emergency withdrawals, false to disable.
    */
    function setEmergencyWithdrawalFlag(bool flag) external authorized {
        emergencyWithdrawalFlag = flag;
    }

    /**
    * @notice Sets the migration contract address.
    * @param _migrationContract Address of the migration contract.
    */
    function setMigrationContract(address _migrationContract) external isFactoryOwner {
    migrationContract = _migrationContract;
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
            if (Utils.generateReferralCode(contributors[i]) == referralCode) {
                count++;
            }
        }
        return count;
    }

    function canFinalize() external view returns (bool allowed, bool ownerOnly) {
        if (finalized) return (false, false);

        // Validate params like finalize()
        uint256 pct = protocolParams.presalePercentage;
        if (pct == 0 || pct > 100) return (false, false);

        // Mirror the after-fee softcap check used in finalize()
        uint256 raisedBalance = address(this).balance;
        uint256 contributionAmount = migrationContract != address(0)
            ? raisedBalance
            : raisedBalance - (raisedBalance * pct) / 100;

        uint256 requiredAfterFee = migrationContract != address(0)
            ? softCap
            : (softCap * (100 - pct)) / 100;

        bool meetsAfterFeeSoftCap = contributionAmount >= requiredAfterFee;
        if (!meetsAfterFeeSoftCap) return (false, false);

        bool expired = hasExpired();

        // Before deadline: owner-only (early finalize on soft cap)
        if (!expired) {
            return (true, true); // allowed, but owner-only right now
        }

        // After deadline: permissionless
        return (true, false);
    }

    function getTimeLeft() external view returns (uint256) {
        if (block.timestamp > deadline) return 0;
        return deadline - block.timestamp;
    }

    function hasExpired() public view returns (bool) {
        return block.timestamp > deadline;
    }

    function getCurrentTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function getPresaleParams() external view returns (LivePresaleParams memory) {
        return LivePresaleParams({
            softCap: softCap,
            hardCap: hardCap,
            initialPrice: initialPrice,
            deadline: deadline,
            launchSupply: launchSupply,
            deployer: deployer
        });
    }

    modifier emergencyWithdrawalEnabled () {
        if (!emergencyWithdrawalFlag) revert EmergencyWithdrawalNotEnabled();
        _;
    }

    modifier isFactoryOwner() {
        if (msg.sender != IFactory(factory).owner()) revert OnlyFactoryOwner();
        _;
    }

    modifier authorized() {
        if (msg.sender != owner() && msg.sender != IFactory(factory).owner()) revert NotAuthorized();
        _;
    }

    // Modifier to prevent reentrancy
    modifier lock() {
        if (locked) revert NoReentrantCalls();
        locked = true;
        _;
        locked = false;
    }
  }
