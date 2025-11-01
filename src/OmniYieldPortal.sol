// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernanceV1} from "./implementation/GovernanceV1.sol";
import {GovernanceProxy} from "./GovernanceProxy.sol";
import {GovernanceToken} from "./GovernanceToken.sol";
import {TreasuryVault} from "./TreasuryVault.sol";
import {LPToken} from "./LPToken.sol";

/**
 * @title OmniYieldPortal
 * @dev Main entry point for users to interact with the OmniYield protocol
 * Handles deposits, withdrawals, governance participation, and LP token management
 */
contract OmniYieldPortal {
    // ========== STATE VARIABLES ==========

    GovernanceToken public gt;
    TreasuryVault public tv;
    LPToken public lp;
    GovernanceV1 public gov;
    GovernanceProxy public govProxy;

    // LP pricing and system parameters
    uint256 public valuePerLP = 1; // Initial LP value (1 wei per LP)
    uint256 public minAmountToDeposit = 1 ether;
    uint256 public minValueToWithdraw = 1 ether;

    // Governance token distribution tiers
    uint256 public constant GT_TOKEN_TIER_1 = 10 ether;
    uint256 public constant GT_TOKEN_TIER_2 = 100 ether;
    uint256 public constant GT_TOKEN_TIER_3 = 1000 ether;
    uint256 public constant TIER_1_LP_PER_GT = 10 ether;
    uint256 public constant TIER_2_LP_PER_GT = 20 ether;
    uint256 public constant TIER_3_LP_PER_GT = 50 ether;
    uint256 public constant MIN_PROPOSAL_AMOUNT = 10;

    // User governance token tracking
    mapping(address => uint256) public userGTTheoreticalAmount;

    // ========== EVENTS ==========

    event Deposit(address indexed user, uint256 amount, uint256 lpAmount);
    event Withdraw(address indexed user, uint256 amount, uint256 lpAmount, bool basedOnETH);
    event GovernanceTokenClaimed(address indexed user, uint256 amount);
    event ValuePerLPUpdated(uint256 newValuePerLP, uint256 totalAssets, uint256 totalSupply);
    event ProposalCreated(address indexed user, uint256 proposalId, address strategy);
    event VoteCast(address indexed user, uint256 proposalId, bool support, uint256 weight);
    event ProposalExecuted(uint256 proposalId);

    // ========== ERRORS ==========

    error InsufficientGTBalance();
    error MinimumThresholdNotReached();
    error NotQualifiedForProposal();
    error InsufficientLPBalance();

    // ========== MODIFIERS ==========

    /**
     * @dev Updates valuePerLP before deposit/withdraw operations
     * Calculates current LP price based on total assets and LP supply
     */
    modifier updateValuePerLPStart() {
        uint256 lpTotalSupply = lp.totalSupply();
        uint256 totalAssets = tv.totalAssets();

        if (lpTotalSupply == 0 || totalAssets == 0) {
            valuePerLP = 1;
        } else {
            valuePerLP = totalAssets / lpTotalSupply;
        }
        _;
    }

    // ========== CONSTRUCTOR ==========

    constructor(address impl) {
        bytes memory data = abi.encodeWithSignature("initialize()");
        gt = new GovernanceToken();
        tv = new TreasuryVault();
        lp = new LPToken();
        govProxy = new GovernanceProxy(impl, data);
        gov = GovernanceV1(address(govProxy));
    }

    // ========== EXTERNAL FUNCTIONS ==========

    /**
     * @dev Deposit ETH into the protocol and receive LP tokens
     * @return success Boolean indicating if deposit was successful
     */
    function deposit() external payable updateValuePerLPStart returns (bool) {
        // Checks
        require(msg.value >= minAmountToDeposit, "Deposit amount below minimum");

        // Effects
        address user = msg.sender;
        uint256 amount = msg.value;
        uint256 lpAmount = amount / valuePerLP;

        _updateValuePerLPEnd(amount, lpAmount, true);
        uint256 userLPAfterDeposit = lpAmount + lp.balanceOf(user);
        _updateUserGTTheoreticalAmount(user, userLPAfterDeposit);

        lp.mint(user, lpAmount);

        // Interactions
        tv.deposit{value: amount}(user, amount);

        emit Deposit(user, amount, lpAmount);
        return true;
    }

    /**
     * @dev Withdraw funds based on ETH amount
     * @param amount Amount of ETH to withdraw
     * @return success Boolean indicating if withdrawal was successful
     */
    function withdrawBaseOnETH(uint256 amount) external updateValuePerLPStart returns (bool) {
        // Checks
        address user = msg.sender;
        uint256 lpAmount = amount / valuePerLP;
        require(amount >= minValueToWithdraw, "Withdrawal amount below minimum");
        require(lp.balanceOf(user) >= lpAmount, "Insufficient LP balance");

        // Effects
        _updateValuePerLPEnd(amount, lpAmount, false);
        uint256 userLPAfterBurn = lp.balanceOf(user) - lpAmount;
        _updateUserGTTheoreticalAmount(user, userLPAfterBurn);

        // Burn excess governance tokens if user has more than theoretical amount
        if (gt.balanceOf(user) > userGTTheoreticalAmount[user]) {
            uint256 gtAmountToBurn = gt.balanceOf(user) - userGTTheoreticalAmount[user];
            gt.burn(user, gtAmountToBurn);
        }

        lp.burn(user, lpAmount);

        // Interactions
        tv.withdraw(user, amount);

        emit Withdraw(user, amount, lpAmount, true);
        return true;
    }

    /**
     * @dev Withdraw funds based on LP token amount
     * @param lpAmount Amount of LP tokens to burn for withdrawal
     * @return success Boolean indicating if withdrawal was successful
     */
    function withdrawBaseOnLP(uint256 lpAmount) external updateValuePerLPStart returns (bool) {
        // Checks
        address user = msg.sender;
        uint256 amount = lpAmount * valuePerLP;
        require(amount >= minValueToWithdraw, "Withdrawal value below minimum");
        require(lp.balanceOf(user) >= lpAmount, "Insufficient LP balance");

        // Effects
        _updateValuePerLPEnd(amount, lpAmount, false);
        uint256 userLPAfterBurn = lp.balanceOf(user) - lpAmount;
        _updateUserGTTheoreticalAmount(user, userLPAfterBurn);

        // Burn excess governance tokens if user has more than theoretical amount
        if (gt.balanceOf(user) > userGTTheoreticalAmount[user]) {
            uint256 gtAmountToBurn = gt.balanceOf(user) - userGTTheoreticalAmount[user];
            gt.burn(user, gtAmountToBurn);
        }

        lp.burn(user, lpAmount);

        // Interactions
        tv.withdraw(user, amount);

        emit Withdraw(user, amount, lpAmount, false);
        return true;
    }

    /**
     * @dev Claim governance tokens based on user's LP holdings
     */
    function claimGovernanceToken() external {
        address user = msg.sender;
        uint256 maxAmount = userGTTheoreticalAmount[user];

        require(maxAmount != 0, "No governance tokens available to claim");

        uint256 amountToClaim = maxAmount - gt.balanceOf(user);
        if (amountToClaim == 0) {
            revert InsufficientGTBalance();
        }

        gt.mint(user, amountToClaim);

        emit GovernanceTokenClaimed(user, amountToClaim);
    }

    // ========== GOVERNANCE FUNCTIONS ==========

    /**
     * @dev Create a new governance proposal
     * @param strategy Strategy address for the proposal
     * @param description Description of the proposal
     * @param action Action type for the proposal
     * @return proposalId ID of the created proposal
     */
    function createProposal(address strategy, string memory description, uint256 action)
        external
        returns (uint256 proposalId)
    {
        address user = msg.sender;
        require(gt.balanceOf(user) >= MIN_PROPOSAL_AMOUNT, "Insufficient governance tokens for proposal");

        proposalId = gov.createProposal(user, strategy, description, action, block.timestamp);

        emit ProposalCreated(user, proposalId, strategy);
    }

    /**
     * @dev Vote on a governance proposal
     * @param id Proposal ID
     * @param approve Whether to support the proposal
     * @return success Boolean indicating if vote was cast successfully
     */
    function voteProposal(uint256 id, bool approve) external returns (bool) {
        address user = msg.sender;
        uint256 weight = gt.getVotingWeight(user);
        bool success = gov.vote(user, id, weight, approve);

        if (success) {
            emit VoteCast(user, id, approve, weight);
        }

        return success;
    }

    /**
     * @dev Execute a passed governance proposal
     * @param id Proposal ID to execute
     */
    function executeProposal(uint256 id) external {
        gov.executeProposal(id);
        emit ProposalExecuted(id);
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @dev Get user's deposit history
     * @return depositHistory Array of deposit amounts
     */
    function getDepositRecord() external view returns (uint256[] memory) {
        return tv.getUserDepositRecord(msg.sender);
    }

    /**
     * @dev Get user's withdrawal history
     * @return withdrawHistory Array of withdrawal amounts
     */
    function getWithdrawRecord() external view returns (uint256[] memory) {
        return tv.getUserWithdrawRecord(msg.sender);
    }

    /**
     * @dev Convert ETH amount to LP tokens
     * @param amount ETH amount to convert
     * @return lpAmount Equivalent LP token amount
     */
    function convertETHToLP(uint256 amount) external view returns (uint256) {
        return amount / valuePerLP;
    }

    /**
     * @dev Convert LP tokens to ETH amount
     * @param lpAmount LP token amount to convert
     * @return ethAmount Equivalent ETH amount
     */
    function convertLPToETH(uint256 lpAmount) external view returns (uint256) {
        return lpAmount * valuePerLP;
    }

    /**
     * @dev Get detailed proposal information
     */
    function getProposalDetail(uint256 id)
        external
        view
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
        return gov.getProposalDetail(id);
    }

    /**
     * @dev Get TreasuryVault contract address
     */
    function getTVAddress() external view returns (address) {
        return address(tv);
    }

    /**
     * @dev Get GovernanceToken contract address
     */
    function getGTAddress() external view returns (address) {
        return address(gt);
    }

    /**
     * @dev Get LPToken contract address
     */
    function getLPAddress() external view returns (address) {
        return address(lp);
    }

    /**
     * @dev Get Governance contract address
     */
    function getGovProxyAddress() external view returns (address) {
        return address(gov);
    }

    // ========== INTERNAL FUNCTIONS ==========

    /**
     * @dev Update user's theoretical governance token amount based on LP holdings
     * @param user User address
     * @param userLPAmount User's current LP token balance
     */
    function _updateUserGTTheoreticalAmount(address user, uint256 userLPAmount) internal {
        if (userLPAmount < GT_TOKEN_TIER_1) {
            userGTTheoreticalAmount[user] = 0;
        } else if (userLPAmount <= GT_TOKEN_TIER_2) {
            userGTTheoreticalAmount[user] = userLPAmount / TIER_1_LP_PER_GT;
        } else if (userLPAmount <= GT_TOKEN_TIER_3) {
            uint256 tier1Amount = GT_TOKEN_TIER_2 / TIER_1_LP_PER_GT;
            uint256 tier2Amount = (userLPAmount - GT_TOKEN_TIER_2) / TIER_2_LP_PER_GT;
            userGTTheoreticalAmount[user] = tier1Amount + tier2Amount;
        } else {
            uint256 tier1Amount = GT_TOKEN_TIER_2 / TIER_1_LP_PER_GT;
            uint256 tier2Amount = (GT_TOKEN_TIER_3 - GT_TOKEN_TIER_2) / TIER_2_LP_PER_GT;
            uint256 tier3Amount = (userLPAmount - GT_TOKEN_TIER_3) / TIER_3_LP_PER_GT;
            userGTTheoreticalAmount[user] = tier1Amount + tier2Amount + tier3Amount;
        }
    }

    /**
     * @dev Update LP value after deposit/withdrawal operations
     * @param amount ETH amount involved in the operation
     * @param lpAmount LP amount involved in the operation
     * @param isDeposit Whether this is a deposit (true) or withdrawal (false)
     */
    function _updateValuePerLPEnd(uint256 amount, uint256 lpAmount, bool isDeposit) internal {
        uint256 newValuePerLP;

        if (isDeposit) {
            newValuePerLP = (amount + tv.totalAssets()) / (lpAmount + lp.totalSupply());
        } else {
            if (lpAmount == lp.totalSupply()) {
                newValuePerLP = 1;
            } else {
                newValuePerLP = (tv.totalAssets() - amount) / (lp.totalSupply() - lpAmount);
            }
        }

        valuePerLP = newValuePerLP;

        emit ValuePerLPUpdated(newValuePerLP, tv.totalAssets(), lp.totalSupply());
    }
}
