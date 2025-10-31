// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GovernanceToken
 * @dev Governance token with time-weighted voting power mechanism
 * Voting weight increases as tokens are held for longer periods
 */
contract GovernanceToken is ERC20, Ownable {
    // ========== CONSTANTS ==========

    uint256 public constant VESTING_PERIOD = 1 days;

    // ========== STRUCTS ==========

    struct ClaimInfo {
        uint256 timestamp;
        uint256 amount;
    }

    // ========== STATE VARIABLES ==========

    // User voting power tracking
    mapping(address => uint256) public lastProcessedClaimId;
    mapping(address => ClaimInfo[]) public userClaimInfo;
    mapping(address => uint256) public votingWeight;

    // ========== EVENTS ==========

    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    event VotingWeightUpdated(address indexed user, uint256 newWeight);
    event ClaimInfoRecorded(address indexed user, uint256 amount, uint256 timestamp);

    // ========== ERRORS ==========

    error CallerNotAuthorized();
    error InsufficientUserBalance();

    // ========== CONSTRUCTOR ==========

    constructor() ERC20("OmniYield Governance", "OYG") Ownable(msg.sender) {}

    // ========== EXTERNAL FUNCTIONS ==========

    /**
     * @dev Mint new governance tokens and record claim information
     * @param to Recipient address
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _updateVotingWeight(to);
        userClaimInfo[to].push(ClaimInfo({timestamp: block.timestamp, amount: amount}));
        _mint(to, amount);

        emit TokensMinted(to, amount);
        emit ClaimInfoRecorded(to, amount, block.timestamp);
    }

    /**
     * @dev Burn governance tokens and adjust voting weight
     * @param user Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address user, uint256 amount) external onlyOwner {
        _updateVotingWeight(user);

        if (votingWeight[user] <= amount) {
            votingWeight[user] = 0;
        } else {
            votingWeight[user] -= amount;
        }

        _burn(user, amount);
        emit TokensBurned(user, amount);
    }

    /**
     * @dev Get current voting weight for a user
     * @param user Address to query voting weight for
     * @return currentWeight Current voting weight of the user
     */
    function getVotingWeight(address user) external onlyOwner returns (uint256) {
        _updateVotingWeight(user);
        return votingWeight[user];
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @dev Get user's claim information count
     * @param user Address to query
     * @return claimCount Number of claim records
     */
    function getClaimInfoCount(address user) external view returns (uint256) {
        return userClaimInfo[user].length;
    }

    /**
     * @dev Get user's last processed claim ID
     * @param user Address to query
     * @return lastProcessedId Last processed claim ID
     */
    function getLastProcessedClaimId(address user) external view returns (uint256) {
        return lastProcessedClaimId[user];
    }

    /**
     * @dev Get user's current voting weight without updating
     * @param user Address to query
     * @return currentVotingWeight Current voting weight
     */
    function getCurrentVotingWeight(address user) external view returns (uint256) {
        return votingWeight[user];
    }

    // ========== INTERNAL FUNCTIONS ==========

    /**
     * @dev Update voting weight based on vesting period
     * @param user Address to update voting weight for
     */
    function _updateVotingWeight(address user) internal {
        uint256 currentId = lastProcessedClaimId[user];
        uint256 arrayLength = userClaimInfo[user].length;
        uint256 newWeight = votingWeight[user];

        for (uint256 i = currentId; i < arrayLength; i++) {
            ClaimInfo memory info = userClaimInfo[user][i];

            // Check if tokens have been held long enough to count toward voting weight
            if (block.timestamp - info.timestamp < VESTING_PERIOD) {
                break;
            }

            newWeight += info.amount;
            currentId = i + 1;
        }

        if (votingWeight[user] != newWeight) {
            votingWeight[user] = newWeight;
            lastProcessedClaimId[user] = currentId;
            emit VotingWeightUpdated(user, newWeight);
        }
    }
}
