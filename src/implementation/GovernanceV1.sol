// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts//proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
/**
 * @title Governance
 * @dev Handles proposal creation, voting, and execution for protocol governance
 * Manages strategy whitelisting and community decision making
 */

contract GovernanceV1 is UUPSUpgradeable, Initializable {
    // ========== STATE VARIABLES ==========
    address public owner;
    uint256 public proposalId;
    uint256 public constant VOTING_CYCLE = 3 days;

    // Strategy management
    address[] public strategies;

    // Proposal state tracking
    enum ProposalState {
        Active,
        Defeated,
        Succeeded,
        Executed
    }
    enum Action {
        Add,
        Delete,
        Upgrade,
        Other
    }

    struct Proposal {
        address proposer;
        address strategy;
        string description;
        Action action;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        ProposalState state;
        bool executed;
    }

    mapping(address => bool) public isStrategy;
    mapping(uint256 => Proposal) public idToProposal;
    mapping(address => mapping(uint256 => bool)) public hasUserVoted;

    // ========== EVENTS ==========

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address strategy,
        Action action,
        string description,
        uint256 startTime,
        uint256 endTime
    );

    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        bool support,
        uint256 weight,
        uint256 totalForVotes,
        uint256 totalAgainstVotes
    );

    event ProposalStateUpdated(uint256 indexed proposalId, ProposalState oldState, ProposalState newState);
    event ProposalExecuted(uint256 indexed proposalId, address strategy, Action action, bool success);
    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);

    // ========== ERRORS ==========

    error VotingPeriodEnded();
    error InvalidProposalId();
    error AlreadyVoted();
    error ProposalNotExecutable();
    error StrategyAlreadyExists();
    error StrategyDoesNotExist();
    error ProposalDefeated();
    error ProposalActive();

    modifier onlyOwner() {
        require(msg.sender == owner, "onlyOnwer");
        _;
    }

    function initialize() public initializer {
        owner = msg.sender;
    }

    // ========== EXTERNAL FUNCTIONS ==========

    /**
     * @dev Create a new governance proposal
     * @param proposer Address of the proposal creator
     * @param strategy Strategy address affected by the proposal
     * @param description Description of the proposal
     * @param actionType Type of action (1: Add, 2: Delete, other: Other)
     * @param startTime Starting timestamp of the proposal
     * @return createdProposalId ID of the created proposal
     */
    function createProposal(
        address proposer,
        address strategy,
        string memory description,
        uint256 actionType,
        uint256 startTime
    ) external onlyOwner returns (uint256) {
        proposalId++;

        Action action = _parseActionType(actionType);

        idToProposal[proposalId] = Proposal({
            proposer: proposer,
            strategy: strategy,
            description: description,
            action: action,
            forVotes: 0,
            againstVotes: 0,
            startTime: startTime,
            endTime: startTime + VOTING_CYCLE,
            state: ProposalState.Active,
            executed: false
        });

        emit ProposalCreated(proposalId, proposer, strategy, action, description, startTime, startTime + VOTING_CYCLE);

        return proposalId;
    }

    /**
     * @dev Cast a vote on an active proposal
     * @param voter Address of the voter
     * @param id Proposal ID to vote on
     * @param weight Voting weight of the voter
     * @param support Whether to support the proposal (true) or oppose (false)
     * @return success Boolean indicating if vote was successfully cast
     */
    function vote(address voter, uint256 id, uint256 weight, bool support) external onlyOwner returns (bool) {
        if (id > proposalId || id == 0) {
            revert InvalidProposalId();
        }

        Proposal storage proposal = idToProposal[id];

        // Check if voting period is still active
        if (block.timestamp >= proposal.endTime) {
            _updateProposalState(id);
            return false;
        }

        if (hasUserVoted[voter][id]) {
            return false;
        }

        // Record vote
        hasUserVoted[voter][id] = true;

        if (support) {
            proposal.forVotes += weight;
        } else {
            proposal.againstVotes += weight;
        }

        emit VoteCast(voter, id, support, weight, proposal.forVotes, proposal.againstVotes);

        return true;
    }

    /**
     * @dev Execute a succeeded proposal
     * @param id Proposal ID to execute
     */
    function executeProposal(uint256 id) external onlyOwner {
        Proposal storage proposal = idToProposal[id];

        if (proposal.state == ProposalState.Defeated) {
            revert ProposalDefeated();
        }
        if (proposal.state == ProposalState.Active) {
            revert ProposalActive();
        }
        if (proposal.executed) {
            revert ProposalNotExecutable();
        }

        ProposalState oldState = proposal.state;
        proposal.state = ProposalState.Executed;
        proposal.executed = true;

        bool success = false;

        // Execute proposal action
        if (proposal.action == Action.Add) {
            _addStrategy(proposal.strategy);
            success = true;
        } else if (proposal.action == Action.Delete) {
            _removeStrategy(proposal.strategy);
            success = true;
        } else if (proposal.action == Action.Upgrade) {
            _upgradeGovernance(proposal.strategy);
            success = true;
        }

        emit ProposalStateUpdated(id, oldState, proposal.state);
        emit ProposalExecuted(id, proposal.strategy, proposal.action, success);
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @dev Get detailed proposal information
     * @param id Proposal ID to query
     */
    function getProposalDetail(uint256 id)
        external
        view
        onlyOwner
        returns (
            address proposer,
            address strategy,
            string memory description,
            string memory action,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 startTime,
            uint256 endTime,
            string memory state,
            bool executed
        )
    {
        Proposal storage proposal = idToProposal[id];

        return (
            proposal.proposer,
            proposal.strategy,
            proposal.description,
            _actionToString(proposal.action),
            proposal.forVotes,
            proposal.againstVotes,
            proposal.startTime,
            proposal.endTime,
            _stateToString(proposal.state),
            proposal.executed
        );
    }

    /**
     * @dev Check if address is an approved strategy
     * @param addr Address to check
     * @return isApprovedStrategy Boolean indicating if address is approved strategy
     */
    function checkIsStrategy(address addr) external view returns (bool) {
        return isStrategy[addr];
    }

    /**
     * @dev Get total number of strategies
     * @return strategyCount Number of approved strategies
     */
    function getStrategyCount() external view returns (uint256) {
        return strategies.length;
    }

    /**
     * @dev Get all approved strategies
     * @return approvedStrategies Array of strategy addresses
     */
    function getAllStrategies() external view returns (address[] memory) {
        return strategies;
    }

    /**
     * @dev Check if user has voted on a specific proposal
     * @param voter Voter address
     * @param id Proposal ID
     * @return hasVoted Boolean indicating if user has voted
     */
    function hasVoted(address voter, uint256 id) external view returns (bool) {
        return hasUserVoted[voter][id];
    }

    function _authorizeUpgrade(address _newImplementation) internal override {}

    // ========== INTERNAL FUNCTIONS ==========

    /**
     * @dev Add a strategy to the approved list
     * @param newStrategy Address of the strategy to add
     */
    function _addStrategy(address newStrategy) internal {
        if (isStrategy[newStrategy]) {
            revert StrategyAlreadyExists();
        }

        isStrategy[newStrategy] = true;
        strategies.push(newStrategy);

        emit StrategyAdded(newStrategy);
    }

    /**
     * @dev Remove a strategy from the approved list
     * @param strategy Address of the strategy to remove
     */
    function _removeStrategy(address strategy) internal {
        if (!isStrategy[strategy]) {
            revert StrategyDoesNotExist();
        }

        isStrategy[strategy] = false;

        // Remove from strategies array
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == strategy) {
                // Swap with last element and pop
                strategies[i] = strategies[strategies.length - 1];
                strategies.pop();
                break;
            }
        }

        emit StrategyRemoved(strategy);
    }

    function _upgradeGovernance(address newImplementation) internal {
        upgradeToAndCall(newImplementation, abi.encodeWithSignature("initialize(address)", owner));
    }

    /**
     * @dev Update proposal state based on current conditions
     * @param id Proposal ID to update
     */
    function _updateProposalState(uint256 id) internal {
        Proposal storage proposal = idToProposal[id];

        if (proposal.state == ProposalState.Active && block.timestamp >= proposal.endTime) {
            ProposalState oldState = proposal.state;
            ProposalState newState =
                proposal.forVotes > proposal.againstVotes ? ProposalState.Succeeded : ProposalState.Defeated;

            proposal.state = newState;

            emit ProposalStateUpdated(id, oldState, newState);
        }
    }

    /**
     * @dev Parse action type from uint to enum
     * @param actionType Numeric action type
     * @return action Corresponding Action enum value
     */
    function _parseActionType(uint256 actionType) internal pure returns (Action) {
        if (actionType == 1) return Action.Add;
        if (actionType == 2) return Action.Delete;
        if (actionType == 3) return Action.Upgrade;
        return Action.Other;
    }

    /**
     * @dev Convert Action enum to string
     * @param action Action enum value
     * @return actionString String representation of the action
     */
    function _actionToString(Action action) internal pure returns (string memory) {
        if (action == Action.Add) return "Add";
        if (action == Action.Delete) return "Delete";
        if (action == Action.Upgrade) return "Upgrade";
        if (action == Action.Other) return "Other";
        return "Unknown";
    }

    /**
     * @dev Convert ProposalState enum to string
     * @param state ProposalState enum value
     * @return stateString String representation of the state
     */
    function _stateToString(ProposalState state) internal pure returns (string memory) {
        if (state == ProposalState.Active) return "Active";
        if (state == ProposalState.Defeated) return "Defeated";
        if (state == ProposalState.Succeeded) return "Succeeded";
        if (state == ProposalState.Executed) return "Executed";
        return "Unknown";
    }
}
