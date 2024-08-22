// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { PreNomaToken } from "../token/pAsset.sol";

contract Presale is ReentrancyGuard {
    address public WETH;
    
    struct DepositOperation {
        uint256 tokenAmount;
        uint256 ethAmount;
        bool isETH;
        bool hasVoted;
        bool isEligibleForClaim;  
    }

    mapping(address => DepositOperation) public deposits;
    address[] public depositors;
    
    uint256 public setupTime;
    uint256 public constant EMERGENCY_WINDOW = 48 hours;
    uint256 public votesForEmergencyWithdrawal;
    uint256 public immutable deployTime;

    // Allow anyone to abort presale after `timeLimit` from `deployTime`
    uint256 public constant timeLimit = 2 weeks;

    bool public emergencyWithdrawalActivated;
    
    address public immutable authority;
    uint256 public constant MAX_DEPOSITORS = 1000;
    uint256 public immutable initialPrice = 28000000000000 wei; // 0.000028 ETH
    uint256 public constant IMV = 21000000000000 wei; // 0.000021 ETH
    uint256 public constant TOTAL_TOKENS = 25_000_000 * 1e18; // 25M tokens with 18 decimals
    uint256 public constant TOTAL_RAISE_GOAL = 700 ether;
    uint256 public constant TEAM_ALLOCATION = 2_000_000 * 1e18; // 2M tokens for team allocation

    uint256 public tokensRemaining;
    uint256 public totalRaised;
    uint256 public operationalFunds;

    PreNomaToken public immutable pNOMA;
    
    bytes32 public merkleRoot;
    bool public isFirstRound = true;
    bool public teamAllocationBacked = false;
    bool public active = true;

    event Setup(uint256 timestamp);
    event Deposit(address indexed depositor, uint256 tokenAmount, uint256 ethAmount, bool isETH);
    event EmergencyWithdrawalVote(address indexed voter);
    event EmergencyWithdrawalActivated();
    event EmergencyWithdrawal(address indexed depositor, uint256 ethAmount, bool isETH, uint256 tokenAmount);
    event RoundFinished(uint256 tokensRemaining);
    event NewRoundStarted(uint256 newPrice);
    event ApprovalForPresale(address indexed depositor, uint256 pNOMAAmount);
    event Aborted();
    event TeamAllocationBacked(uint256 ethForTeamAllocation);
    event TokensClaimed(address indexed user, uint256 tokenAmount, uint256 ethAmount);

    error InvalidAuthority(address caller);
    error InvalidCaller();
    error InsufficientOperationalFunds(uint256 requested, uint256 available);
    error MaxDepositorsReached();
    error DepositorAlreadyExists();
    error TokenTransferFailed();
    error SaleNotFinalized();
    error EmergencyWithdrawalNotActivated();
    error PoolAlreadySetup();
    error PoolNotSetup();
    error EmergencyWindowPassed();
    error NoDepositFound(address depositor);
    error AlreadyVoted(address voter);
    error InsufficientETHAmount();
    error ETHSentWithTokenDeposit();
    error AllowanceExceeded();
    error ExceedsMaxTokenAllocation();
    error NotEnoughTokensRemaining();
    error TeamAllocationAlreadyBacked();
    error InsufficientBalance();

    error NotEligibleForClaim(address depositor);
    error TimeLimitNotReached();
    error ETHTransferFailed();

    modifier onlyAuthority() {
        // if (msg.sender != authority) revert InvalidAuthority(msg.sender);
        _;
    }
    
    modifier onlyAfterSetup() {
        if (address(pNOMA) == address(0)) revert PoolNotSetup();
        _;
    }
    
    modifier onlyBeforeEmergencyWithdrawal() {
        if (emergencyWithdrawalActivated) revert EmergencyWithdrawalNotActivated();
        _;
    }
    
    constructor(
        address _authority, 
        address _weth, 
        bytes32 _merkleRoot
    ) {
        if (_authority == address(0)) revert InvalidCaller();
        if (_weth == address(0)) revert InvalidCaller();

        authority = _authority;
        initialPrice = 28000000000000 wei; // 0.000028 ETH
        pNOMA = new PreNomaToken();
        tokensRemaining = TOTAL_TOKENS;
        WETH = _weth;
        merkleRoot = _merkleRoot;
    }
        
    function setup() external onlyAuthority {
        if (WETH == address(0)) revert PoolNotSetup();
        setupTime = block.timestamp;
        emit Setup(setupTime);
    }
    
    function setMerkleRoot(bytes32 _merkleRoot) external onlyAuthority {
        merkleRoot = _merkleRoot;
    }
    
    function depositWithProof(
        uint256 amount,
        uint256 maxTokens,
        bytes32[] calldata merkleProof
    ) external payable {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Invalid merkle proof");

        bool isETH = msg.value > 0;
        if (isETH) {
            if (msg.value != amount) revert InsufficientETHAmount();
        } else {
            if (msg.value > 0) revert ETHSentWithTokenDeposit();
            uint256 allowance = IERC20(WETH).allowance(msg.sender, address(this));
            if (allowance < amount) revert AllowanceExceeded();
        }

        _deposit(amount, maxTokens, isETH);
    }
    
    function _deposit(uint256 ethAmount, uint256 maxTokens, bool isETH) internal {
        if (ethAmount == 0) revert InsufficientETHAmount();
        if (depositors.length >= MAX_DEPOSITORS) revert MaxDepositorsReached();
        if (deposits[msg.sender].ethAmount > 0) revert DepositorAlreadyExists();
        if (!IERC20(WETH).transferFrom(msg.sender, address(this), ethAmount)) revert TokenTransferFailed();

        uint256 tokenPrice = isFirstRound ? initialPrice : (initialPrice * 110 / 100); // 10% premium for second round
        uint256 tokenAmount = (ethAmount * 1e18) / tokenPrice;
        if (tokenAmount > maxTokens) revert ExceedsMaxTokenAllocation();
        if (tokenAmount > tokensRemaining) revert NotEnoughTokensRemaining();
        
        deposits[msg.sender] = DepositOperation({
            tokenAmount: tokenAmount,
            ethAmount: ethAmount,
            isETH: isETH,
            hasVoted: false,
            isEligibleForClaim: false
        });
        depositors.push(msg.sender);
        
        tokensRemaining -= tokenAmount;
        totalRaised += ethAmount;
        
        pNOMA.transfer(msg.sender, tokenAmount);
        
        emit Deposit(msg.sender, tokenAmount, ethAmount, isETH);
        
        if (tokensRemaining == 0 || totalRaised >= TOTAL_RAISE_GOAL) {
            finalizeSale();
        }
    }

    function finalizeSale() public onlyAuthority {
        uint256 imvTotal = (TOTAL_TOKENS * IMV) / 1e18;
        operationalFunds = totalRaised - imvTotal;
        emit RoundFinished(tokensRemaining);
    }

    function backTeamAllocation() external onlyAuthority {
        if (teamAllocationBacked) revert TeamAllocationAlreadyBacked();
        if (totalRaised < TOTAL_RAISE_GOAL) revert SaleNotFinalized();

        uint256 ethForTeamAllocation = (TEAM_ALLOCATION * IMV) / 1e18;
        if (operationalFunds < ethForTeamAllocation) revert InsufficientOperationalFunds(ethForTeamAllocation, operationalFunds);

        operationalFunds -= ethForTeamAllocation;
        teamAllocationBacked = true;

        emit TeamAllocationBacked(ethForTeamAllocation);
    }

    function withdrawOperationalFunds(uint256 amount) external onlyAuthority {
        if (totalRaised < TOTAL_RAISE_GOAL) revert SaleNotFinalized();
        if (amount > operationalFunds) revert InsufficientOperationalFunds(amount, operationalFunds);

        operationalFunds -= amount;
        if (!IERC20(WETH).transfer(authority, amount)) revert TokenTransferFailed();
    }

    function getRemainingETH() public view returns (uint256) {
        if (totalRaised < TOTAL_RAISE_GOAL) {
            return 0;
        }
        return operationalFunds;
    }
    
    function startSecondRound() external onlyAuthority {
        if (!isFirstRound) revert InvalidCaller();
        if (tokensRemaining == 0) revert NotEnoughTokensRemaining();
        isFirstRound = false;
        uint256 newPrice = initialPrice * 110 / 100;
        emit NewRoundStarted(newPrice);
    }   

    // Full updated voteForEmergencyWithdrawal function
    function voteForEmergencyWithdrawal() external onlyAfterSetup onlyBeforeEmergencyWithdrawal {
        if (block.timestamp > setupTime + EMERGENCY_WINDOW) revert EmergencyWindowPassed();
        if (deposits[msg.sender].ethAmount == 0) revert NoDepositFound(msg.sender);
        if (deposits[msg.sender].hasVoted) revert AlreadyVoted(msg.sender);
        
        deposits[msg.sender].hasVoted = true;
        votesForEmergencyWithdrawal++;
        
        emit EmergencyWithdrawalVote(msg.sender);
        
        if (votesForEmergencyWithdrawal > depositors.length / 2) {
            emergencyWithdrawalActivated = true;
            emit EmergencyWithdrawalActivated();
        }
    }

    function executeEmergencyWithdrawal() external nonReentrant {
        if (!emergencyWithdrawalActivated) revert EmergencyWithdrawalNotActivated();
        if (block.timestamp < deployTime + timeLimit) revert TimeLimitNotReached();

        for (uint256 i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            DepositOperation storage deposit = deposits[depositor];

            if (deposit.ethAmount > 0) {
                deposit.isEligibleForClaim = true;
            }
        }

        emergencyWithdrawalActivated = false;
    }

    function claimEmergencyWithdrawal() external nonReentrant {
        DepositOperation storage deposit = deposits[msg.sender];
        
        if (!deposit.isEligibleForClaim) revert NotEligibleForClaim(msg.sender);
        if (deposit.ethAmount == 0) revert NoDepositFound(msg.sender);

        uint256 ethAmount = deposit.ethAmount;
        uint256 tokenAmount = deposit.tokenAmount;

        deposit.ethAmount = 0;
        deposit.tokenAmount = 0;
        deposit.isEligibleForClaim = false;

        if (deposit.isETH) {
            (bool success, ) = msg.sender.call{value: ethAmount}("");
            if (!success) revert ETHTransferFailed();
        } else {
            if (!IERC20(WETH).transfer(msg.sender, ethAmount)) revert TokenTransferFailed();
        }

        PreNomaToken(pNOMA).burn(msg.sender, tokenAmount);

        emit EmergencyWithdrawal(msg.sender, ethAmount, deposit.isETH, tokenAmount);
    }

    function approvePresaleContract() external {
        DepositOperation memory deposit = deposits[msg.sender];
        if (deposit.ethAmount == 0) revert NoDepositFound(msg.sender);
        
        uint256 pNOMAAmount = (deposit.ethAmount * 1e18) / initialPrice;
        pNOMA.approve(address(this), pNOMAAmount);
        
        emit ApprovalForPresale(msg.sender, pNOMAAmount);
    }

    function withdraw() external nonReentrant {
        DepositOperation storage deposit = deposits[msg.sender];
        if (deposit.ethAmount == 0) revert NoDepositFound(msg.sender);
        if (totalRaised < TOTAL_RAISE_GOAL) revert SaleNotFinalized();

        uint256 ethAmount = deposit.ethAmount;
        uint256 tokenAmount = deposit.tokenAmount;

        // Reset the deposit
        deposit.tokenAmount = 0;
        deposit.ethAmount = 0;

        // Transfer ETH back to the user
        if (deposit.isETH) {
            (bool success, ) = msg.sender.call{value: ethAmount}("");
            if (!success) revert ETHTransferFailed();
        } else {
            if (!IERC20(WETH).transfer(msg.sender, ethAmount)) revert TokenTransferFailed();
        }

        // Burn the user's pNOMA tokens
        PreNomaToken(pNOMA).burn(msg.sender, tokenAmount);

        emit TokensClaimed(msg.sender, tokenAmount, ethAmount);
    }

    function computeLeaf(address account, uint256 amount, uint256 round) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, amount, round));
    }

    function abort() external {
        if (msg.sender != authority && block.timestamp <= deployTime + timeLimit) revert InvalidCaller();
        active = false;
        emit Aborted();
    }

    function _uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    receive() external payable {
        revert("Use depositWithProof() to deposit ETH");
    }
}
