// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title FuzzActors
 * @notice Manages multiple actors for multi-user fuzzing scenarios
 * @dev Actors are assigned roles to simulate realistic protocol usage
 */
abstract contract FuzzActors {
    // Role definitions
    uint8 public constant ROLE_TRADER = 1;
    uint8 public constant ROLE_LENDER = 2;
    uint8 public constant ROLE_STAKER = 3;
    uint8 public constant ROLE_LIQUIDATOR = 4;
    uint8 public constant ROLE_ADMIN = 5;

    // Actor storage
    address[] internal _actors;
    mapping(address => uint8) public actorRole;
    mapping(address => uint256) public actorETHReceived;
    mapping(address => uint256) public actorTokensReceived;
    mapping(address => bool) public actorHasActiveLoan;

    // Actor statistics
    uint256 public totalBorrowOperations;
    uint256 public totalPaybackOperations;
    uint256 public totalStakeOperations;
    uint256 public totalUnstakeOperations;
    uint256 public totalTradeOperations;

    /**
     * @notice Initialize actors with roles
     * @param numActors Number of actors to create
     */
    function _initializeActors(uint256 numActors) internal {
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0x1000 + i));
            _actors.push(actor);

            // Assign roles based on index
            if (i < numActors / 4) {
                actorRole[actor] = ROLE_TRADER;
            } else if (i < numActors / 2) {
                actorRole[actor] = ROLE_LENDER;
            } else if (i < (numActors * 3) / 4) {
                actorRole[actor] = ROLE_STAKER;
            } else if (i < numActors - 1) {
                actorRole[actor] = ROLE_LIQUIDATOR;
            } else {
                actorRole[actor] = ROLE_ADMIN;
            }
        }
    }

    /**
     * @notice Get actor by index (wraps around)
     */
    function getActor(uint8 index) public view returns (address) {
        require(_actors.length > 0, "No actors initialized");
        return _actors[index % _actors.length];
    }

    /**
     * @notice Get all actors with a specific role
     */
    function getActorsByRole(uint8 role) public view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _actors.length; i++) {
            if (actorRole[_actors[i]] == role) count++;
        }

        address[] memory result = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < _actors.length; i++) {
            if (actorRole[_actors[i]] == role) {
                result[idx++] = _actors[i];
            }
        }

        return result;
    }

    /**
     * @notice Get number of actors
     */
    function getActorCount() public view returns (uint256) {
        return _actors.length;
    }

    /**
     * @notice Get actors with active loans
     */
    function getActorsWithLoans() public view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _actors.length; i++) {
            if (actorHasActiveLoan[_actors[i]]) count++;
        }

        address[] memory result = new address[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < _actors.length; i++) {
            if (actorHasActiveLoan[_actors[i]]) {
                result[idx++] = _actors[i];
            }
        }

        return result;
    }

    /**
     * @notice Record that an actor received ETH
     */
    function _recordETHReceived(address actor, uint256 amount) internal {
        actorETHReceived[actor] += amount;
    }

    /**
     * @notice Record that an actor received tokens
     */
    function _recordTokensReceived(address actor, uint256 amount) internal {
        actorTokensReceived[actor] += amount;
    }

    /**
     * @notice Mark actor as having an active loan
     */
    function _setActorLoanStatus(address actor, bool hasLoan) internal {
        actorHasActiveLoan[actor] = hasLoan;
    }

    /**
     * @notice Increment operation counters
     */
    function _recordBorrow() internal {
        totalBorrowOperations++;
    }

    function _recordPayback() internal {
        totalPaybackOperations++;
    }

    function _recordStake() internal {
        totalStakeOperations++;
    }

    function _recordUnstake() internal {
        totalUnstakeOperations++;
    }

    function _recordTrade() internal {
        totalTradeOperations++;
    }
}
