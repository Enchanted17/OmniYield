// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITV {
    function callTransfer(address to, uint256 amount) external;
    function receiveProfit() external payable;
}

contract FlashLoan {
    address public immutable treasury;
    address public owner;
    bool public active = true;

    uint256 public totalProfit;
    uint256 public totalLoans;
    uint256 public constant FEE_RATE = 5; // 0.05%

    event FlashLoanExecuted(uint256 amount, uint256 profit, uint256 repayment);
    event ProfitReported(uint256 profit);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyActive() {
        require(active, "Strategy inactive");
        _;
    }

    constructor(address _treasury) {
        owner = msg.sender;
        treasury = _treasury;
    }

    /**
     * @dev 执行闪电贷 - 正确区分本金还款和利润报告
     */
    function executeFlashLoan(uint256 amount) external onlyActive returns (uint256) {
        require(amount > 0, "Amount must be positive");

        totalLoans++;

        // 1. 从TV借款
        ITV(treasury).callTransfer(address(this), amount);

        // 2. 执行套利
        uint256 profit = _executeArbitrage(amount);

        // 3. 计算手续费和净利润
        uint256 fee = (amount * FEE_RATE) / 10000;
        uint256 netProfit = profit > fee ? profit - fee : 0;

        // 4. 先偿还本金（普通转账，不增加totalAssert）
        (bool repaySuccess,) = treasury.call{value: amount}("");
        require(repaySuccess, "Principal repayment failed");

        // 5. 如果有净利润，通过profitIn函数报告利润
        if (netProfit > 0) {
            // 调用TV的profitIn函数来记录利润
            (bool profitSuccess,) =
                treasury.call{value: netProfit}(abi.encodeWithSignature("profitIn(uint256)", netProfit));
            require(profitSuccess, "Profit reporting failed");
            totalProfit += netProfit;

            emit ProfitReported(netProfit);
        }

        // 6. 清理：确保Strategy不持有资金
        _cleanupRemainingBalance();

        emit FlashLoanExecuted(amount, profit, amount + fee);
        return profit;
    }

    /**
     * @dev 简化的套利逻辑
     */
    function _executeArbitrage(uint256 amount) internal view returns (uint256) {
        // 模拟套利逻辑
        uint256 simulatedProfit = amount * 10 / 10000; // 0.1% 利润

        // 模拟计算消耗gas
        uint256 gasStart = gasleft();
        while (gasStart - gasleft() < 50000) {
            // 消耗gas
        }

        return simulatedProfit;
    }

    /**
     * @dev 清理剩余资金（确保Strategy不持有资金）
     */
    function _cleanupRemainingBalance() internal {
        uint256 remainingBalance = address(this).balance;
        if (remainingBalance > 0) {
            // 如果有剩余资金，都当作利润报告给TV
            (bool success,) =
                treasury.call{value: remainingBalance}(abi.encodeWithSignature("profitIn(uint256)", remainingBalance));
            if (success) {
                totalProfit += remainingBalance;
            }
        }
    }

    /**
     * @dev 获取合约余额（应该始终接近0）
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev 紧急停止并清理所有资金
     */
    function emergencyStop() external onlyOwner {
        active = false;
        _cleanupRemainingBalance();
    }

    // 接收ETH（从TV借款）
    receive() external payable {}
}
