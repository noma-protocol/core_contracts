// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./interfaces/IModelHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

contract Migration is Ownable {

    IModelHelper public modelHelper;
    ERC20 public nomaToken;
    uint256 public initialIMV;
    address public vault;

    mapping(address => uint256) public initialBalances;
    mapping(address => uint256) public withdrawnAmounts; 
    address private firstHolder; // Track the first holder

    error OnlyNomaFactory();
    error NoWithdrawableAmount();
    
    constructor(
        address _modelHelper,
        address _nomaToken,
        address _vault,
        uint256 _initialIMV,
        address[] memory holders,
        uint256[] memory balances
    ) Ownable(msg.sender) {
        require(holders.length > 0, "Holders array cannot be empty");

        modelHelper = IModelHelper(_modelHelper);
        nomaToken = ERC20(_nomaToken);
        initialIMV = _initialIMV;
        vault = _vault;

        // Track the first holder
        firstHolder = holders[0];

        // Set initial balances
        for (uint256 i = 0; i < holders.length; i++) {
            initialBalances[holders[i]] = balances[i];
        }
    }

    function withdraw() external {
        uint256 withdrawableAmount;

        if (msg.sender == firstHolder) {
            withdrawableAmount = initialBalances[msg.sender] - withdrawnAmounts[msg.sender];
        } else {
            uint256 currentIMV = getIMV();
            require(currentIMV > initialIMV, "IMV has not increased");

            // Calculate the maximum withdrawable percentage based on IMV increase
            uint256 maxWithdrawPercentage = ((currentIMV - initialIMV) * 100) / initialIMV;

            if (maxWithdrawPercentage <= 0) {
                revert NoWithdrawableAmount();
            }

            if (maxWithdrawPercentage > 100) {
                maxWithdrawPercentage = 100; // Cap at 100%
            }

            // Calculate the total withdrawable amount for the caller
            uint256 totalWithdrawable = (initialBalances[msg.sender] * maxWithdrawPercentage) / 100;

            // Subtract the already withdrawn amount to get the remaining withdrawable balance
            withdrawableAmount = totalWithdrawable - withdrawnAmounts[msg.sender];

            if (withdrawableAmount <= 0) {
                revert NoWithdrawableAmount();
            }
        }

        // Update withdrawn amounts and transfer tokens
        withdrawnAmounts[msg.sender] += withdrawableAmount;
        nomaToken.transfer(msg.sender, withdrawableAmount);
    }

    function getIMV() public view returns (uint256) {
        return modelHelper.getIntrinsicMinimumValue(vault);
    }

    function setBalances(
        address[] memory holders,
        uint256[] memory balances
    ) external onlyOwner {
        for (uint256 i = 0; i < holders.length; i++) {
            initialBalances[holders[i]] = balances[i];
        }
    }

}
