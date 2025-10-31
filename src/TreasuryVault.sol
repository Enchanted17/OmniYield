// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TreasuryVault
 * @dev Secure vault contract for managing user funds and strategy interactions
 * Handles deposit/withdrawal tracking and strategy fund allocation
 */
interface IGov {
    function checkIsStrategy(address) external view returns (bool);
}

interface IOYP {
    function getGovAddress() external view returns (address);
}

contract TreasuryVault is Ownable {
    // ========== STATE VARIABLES ==========

    uint256 public totalAssets;
    mapping(address => uint256[]) public userDepositRecord;
    mapping(address => uint256[]) public userWithdrawRecord;

    // ========== EVENTS ==========

    event DepositReceived(address indexed user, uint256 amount);
    event WithdrawalProcessed(address indexed user, uint256 amount);
    event FundsTransferredToStrategy(address indexed strategy, address to, uint256 amount);
    event ProfitRecorded(address indexed strategy, uint256 amount);

    // ========== CONSTRUCTOR ==========

    constructor() Ownable(msg.sender) {}

    // ========== EXTERNAL FUNCTIONS ==========

    /**
     * @dev Process user deposit and record transaction
     * @param user Address of the depositing user
     * @param amount Amount of ETH being deposited
     */
    function deposit(address user, uint256 amount) external payable onlyOwner {
        require(msg.value == amount, "Sent value does not match specified amount");

        userDepositRecord[user].push(amount);
        totalAssets += amount;

        emit DepositReceived(user, amount);
    }

    /**
     * @dev Process user withdrawal and update records
     * @param user Address of the withdrawing user
     * @param amount Amount of ETH to withdraw
     */
    function withdraw(address user, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient contract balance");

        userWithdrawRecord[user].push(amount);
        totalAssets -= amount;
        payable(user).transfer(amount);

        emit WithdrawalProcessed(user, amount);
    }

    /**
     * @dev Transfer funds to approved strategy contracts
     * @param to Recipient address (typically a strategy contract)
     * @param amount Amount of ETH to transfer
     */
    function callTransfer(address to, uint256 amount) external {
        require(address(this).balance >= amount, "Insufficient contract balance");

        address gov = IOYP(owner()).getGovAddress();
        bool isApprovedStrategy = IGov(gov).checkIsStrategy(msg.sender);

        require(isApprovedStrategy, "Caller is not an approved strategy");

        payable(to).transfer(amount);

        emit FundsTransferredToStrategy(msg.sender, to, amount);
    }

    /**
     * @dev Record profit from strategy operations
     * @param amount Profit amount to be recorded
     */
    function profitIn(uint256 amount) external {
        address gov = IOYP(owner()).getGovAddress();
        bool isApprovedStrategy = IGov(gov).checkIsStrategy(msg.sender);

        require(isApprovedStrategy, "Caller is not an approved strategy");

        totalAssets += amount;

        emit ProfitRecorded(msg.sender, amount);
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @dev Get user's deposit history
     * @param user Address to query deposit records for
     * @return Array of deposit amounts
     */
    function getUserDepositRecord(address user) external view onlyOwner returns (uint256[] memory) {
        return userDepositRecord[user];
    }

    /**
     * @dev Get user's withdrawal history
     * @param user Address to query withdrawal records for
     * @return Array of withdrawal amounts
     */
    function getUserWithdrawRecord(address user) external view onlyOwner returns (uint256[] memory) {
        return userWithdrawRecord[user];
    }

    /**
     * @dev Get current contract ETH balance
     * @return Current balance in wei
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ========== FALLBACK FUNCTION ==========

    /**
     * @dev Receive ETH transfers
     */
    receive() external payable {
        // Accept ETH transfers without additional logic
    }
}
