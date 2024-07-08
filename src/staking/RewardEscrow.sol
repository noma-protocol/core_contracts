// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/SafeMath.sol";

contract RewardEscrow  {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public rewardToken;

    struct Escrow {
        uint256 amount;
        uint256 releaseTime;
        bool withdrawn;
    }

    mapping(address => Escrow[]) public escrows;
    mapping(address => uint256) public totalEscrowPositionsByUser;

    event EscrowCreated(address indexed user, uint256 amount, uint256 releaseTime);
    event EscrowWithdrawn(address indexed user, uint256 amount);


    constructor(IERC20 _rewardToken) /*Ownable(msg.sender)*/ {
        rewardToken = _rewardToken;
    }

    function createEscrowEntries(
        address user, 
        uint256[] calldata amounts, 
        uint256[] calldata releaseTimes
    ) public  {
        require(amounts.length == releaseTimes.length, "Mismatched input lengths");

        uint256 totalEscrowed = 0;
        uint256 totalEscrowPositions = totalEscrowPositionsByUser[user];
        
        if (totalEscrowPositions > 0) {
            totalEscrowPositions = totalEscrowPositions + amounts.length;
        } else {
            totalEscrowPositions = amounts.length;
        }

        require(totalEscrowPositions > 0, "error creating entries");

        totalEscrowPositionsByUser[user] = totalEscrowPositions;

        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "can't create entry");

            escrows[user].push(Escrow({
                amount: amounts[i],
                releaseTime: releaseTimes[i],
                withdrawn: false
            }));
            
            totalEscrowed = totalEscrowed + amounts[i];
        }   

        emit EscrowCreated(user, totalEscrowed, releaseTimes[0]);
    }

    function vestEscrowEntry(uint256 escrowIndex) public {
        Escrow storage escrow = escrows[msg.sender][escrowIndex];
        require(block.timestamp >= escrow.releaseTime, "Escrow not yet released");
        require(!escrow.withdrawn, "Escrow already withdrawn");

        escrow.withdrawn = true;
        rewardToken.safeTransfer(msg.sender, escrow.amount);

        emit EscrowWithdrawn(msg.sender, escrow.amount);
    }

    function getEscrowDetails(address user, uint256 index) public view 
    returns (uint256 amount, uint256 releaseTime, bool withdrawn) {
        require(totalEscrowPositionsByUser[user] > 0, "no positions to fetch");

        Escrow storage escrow = escrows[user][index];
        return (escrow.amount, escrow.releaseTime, escrow.withdrawn);
    }

    function totalEscrowed(address user) external view returns (uint256 total) {
        Escrow[] storage userEscrows = escrows[user];
        for (uint256 i = 0; i < userEscrows.length; i++) {
            if (!userEscrows[i].withdrawn) {
                total = total.add(userEscrows[i].amount);
            }
        }
    }

    function getTotalEscrowPositionsByUser(address user) external view returns (uint256) {
        return totalEscrowPositionsByUser[user];
    }
 
    function getEscrowPositions(address user) external view returns (Escrow[] memory) {
        return escrows[user];
    }
 }
