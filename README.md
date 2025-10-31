- [中文](#Chinese)
- [English](#English)

<a id="Chinese"></a>
# OmniYield Protocol

**OmniYield** 是一个去中心化的收益聚合与治理协议，允许用户存入 ETH 获取流动性凭证（LP Token），并通过持有 LP 获得治理代币（GT），参与协议策略的投票决策。资金由 `TreasuryVault` 管理，仅向治理通过的策略合约分配，实现安全、透明、社区驱动的资金运作。

---

## 核心特性

| 特性 | 说明 |
|------|------|
| **自动复利收益** | 用户存入 ETH → 铸造 LP → 资金进入金库 → 策略产生收益 → 自动提升 LP 价值 |
| **时间加权治理** | 持有 GT 越久，投票权重越高（每日线性解锁） |
| **分层治理代币奖励** | LP 持有量越高，获得的 GT 越多（三档递增） |
| **策略白名单治理** | 社区提案 + 投票决定哪些策略可调用金库资金 |
| **安全金库设计** | 仅治理批准的策略可提取资金，防止恶意合约 |

---

## 合约架构

```text
OmniYieldPortal.sol       ← 用户入口（存款、取款、治理）
├── GovernanceToken.sol   ← GT 代币（时间加权投票）
├── LPToken.sol           ← LP 代币（流动性份额）
├── TreasuryVault.sol     ← 资金金库（存取款 + 策略调用）
└── Governance.sol        ← 治理模块（提案、投票、执行）
└── strategys
        └── FlashLoan.sol ← 策略样例
```

## 合约详解
1. `OmniYieldPortal.sol` – **主入口**
    - 用户通过 `deposit()` 存入 ETH，获得 LP。
    - 支持按 ETH 或 LP 数量取款。
    - 根据 LP 持有量自动计算可领取的 治理代币（GT）。
    - 提供提案创建、投票、执行接口。

2. `GovernanceToken.sol` – **GT 代币**
    - 继承 OpenZeppelin ERC20 + Ownable。
    - 实现 时间加权投票权：`votingWeight = Σ(已持有 ≥ 1天的 mint 数量)`
    - 每次 `mint` / `burn` / 查询投票权时自动更新权重。

3. `LPToken.sol` – **流动性凭证**
    - 标准 ERC20，铸造/销毁仅限 `OmniYieldPortal` 调用。
    - 代表用户在金库中的份额。
    - 价值随金库总资产增长（`valuePerLP` 动态更新）。

4. `TreasuryVault.sol` – **资金金库**
    - 接收用户存款，记录存取历史。
    - 仅允许 治理批准的策略 调用：
        - `callTransfer(to, amount)`：转账给策略
        - `profitIn(amount)`：策略报告收益

    - 提供 `totalAssets` 供 LP 定价。

5. `Governance.sol` – **治理中心**
    - 提案生命周期：Active → Succeeded/Defeated → Executed
    - 支持 添加 / 删除策略
    - 投票周期：3 天（自定义）
    - 投票权重来自 `GovernanceToken.getVotingWeight()`

## 治理代币（GT）分配规则
| LP 持有量      | 每单位 LP 获得的 GT    |
|----------------|-----------------------|
| < 10 ETH       | 0                     |
| 10 ~ 100 ETH   | 1 GT = 10 ETH LP      |
| 100 ~ 1000 ETH | 1 GT = 20 ETH LP      |
| ≥ 1000 ETH     |1 GT = 50 ETH LP       |

用户可随时调用 `claimGovernanceToken()` 领取未领 GT
取款时若 GT 余额 > 理论值，多余部分自动销毁

## 投票权机制（时间加权）
```solidity
if (block.timestamp - mintTime >= 1 day) {
    votingWeight += amount;
}
```
- 每天线性解锁投票权
- 防止短期投机操纵
- n鼓励长期持有

## 安全机制
|风险             | 防护措施                                  |
|恶意策略提取资金 | 仅 `Governance` 批准的策略可调用 `callTransfer`|
|---             |---                                        |
|提案 spam       | 需持有 ≥ 10 GT 才能创建提案                 |
|投票权刷量       | 投票权需持有 ≥ 1 天才能生效                |
|资金错配         | 所有存取款路径更新 `valuePerLP`，防止价格偏差 |
|合约所有权集中   | 部署后 `owner` 可移交至多签或 DAO            |

## 部署流程
```bash
# 1. 编译
forge build

# 2. 部署主合约（自动部署所有子合约）
forge create OmniYieldPortal --rpc-url $RPC --private-key $KEY

# 3. 转移 Ownership（可选）
cast send <Portal> "transferOwnership(address)" $MULTISIG
```
- 部署后地址：
    - OmniYieldPortal: 主入口
    - GovernanceToken: GT
    - LPToken: LP
    - TreasuryVault: 金库
    - Governance: 治理

## 用户操作指南
**存款**
```js
await portal.deposit({ value: ethers.parseEther("5") });
```
**取款**
```js
await portal.withdrawBaseOnETH(ethers.parseEther("2")); //ETH 数额
await portal.withdrawBaseOnLP(ethers.parseEther("2"));  //LP 数额
```
**领取治理代币**
```js
await portal.claimGovernanceToken();
```
**创建提案**
```js
await portal.createProposal(
  strategyAddress,
  "Add new Aave V3 strategy",
  1 // 1=Add, 2=Delete
);
```
**投票**
```js
await portal.voteProposal(proposalId, true); // 支持
await portal.voteProposal(proposalId, false); // 反对
```

## 审计要点
- valuePerLP 更新逻辑防整数截断
- 策略调用权限严格校验
- 投票权重防重入
- totalAssets 与实际余额一致性
- 提案执行幂等性

## 未来计划
- 支持多资产存款（USDC, DAI等）
- 策略收益自动分配
- 治理参数可升级（投票周期、阈值）
- 集成 Chainlink VRF 随机策略轮换
- 提高提案自由度

---


---
<a id="English"></a>
# OmniYield Protocol()

**OmniYield** is a decentralized yield aggregation and governance protocol that allows users to deposit ETH to receive liquidity certificates (LP Tokens). By holding LPs, users earn governance tokens (GT) that enable them to participate in strategic decision-making through on-chain voting. Funds are managed by the `TreasuryVault`, which allocates assets only to governance-approved strategy contracts — ensuring **security**, **transparency**, and **community-driven** fund operations.

---

## Core Features

| Feature | Description |
|----------|-------------|
| **Auto-Compounding Yield** | Users deposit ETH → Mint LP → Funds enter the vault → Strategy generates yield → LP value automatically increases |
| **Time-Weighted Governance** | The longer GTs are held, the higher the voting weight (linear daily unlock) |
| **Tiered GT Rewards** | The more LPs held, the more GTs earned (three-tier reward system) |
| **Whitelisted Strategy Governance** | Community proposals and votes determine which strategies can access the vault |
| **Secure Vault Design** | Only governance-approved strategies can withdraw funds, preventing malicious behavior |

---

## Contract Architecture

```txt
OmniYieldPortal.sol       ← User entry point (deposit, withdraw, governance)
├── GovernanceToken.sol   ← GT token (time-weighted voting)
├── LPToken.sol           ← LP token (liquidity share)
├── TreasuryVault.sol     ← Vault (storage + strategy management)
└── Governance.sol        ← Governance module (proposal, voting, execution)
└── strategys
        └── FlashLoan.sol ← Example strategy
```

---

## Contract Details

1. **`OmniYieldPortal.sol` – Main Entry**
   - Users call `deposit()` to deposit ETH and receive LPs.
   - Supports withdrawal by ETH or LP amount.
   - Automatically calculates claimable governance tokens (GT) based on LP holdings.
   - Provides interfaces for proposal creation, voting, and execution.

2. **`GovernanceToken.sol` – GT Token**
   - Inherits from OpenZeppelin’s ERC20 + Ownable.
   - Implements time-weighted voting:  
     `votingWeight = Σ(minted amount held ≥ 1 day)`
   - Automatically updates voting weight on `mint`, `burn`, and voting queries.

3. **`LPToken.sol` – Liquidity Certificate**
   - Standard ERC20, minting and burning restricted to `OmniYieldPortal`.
   - Represents user share in the vault.
   - Value grows dynamically with the vault’s total assets (`valuePerLP`).

4. **`TreasuryVault.sol` – Fund Vault**
   - Receives user deposits and tracks all transactions.
   - Only governance-approved strategies may call:  
     - `callTransfer(to, amount)` – Transfer funds to strategy  
     - `profitIn(amount)` – Report profits to vault  
   - Provides `totalAssets` for LP valuation.

5. **`Governance.sol` – Governance Center**
   - Proposal lifecycle: Active → Succeeded/Defeated → Executed  
   - Supports adding/removing strategies.  
   - Default voting period: 3 days (customizable).  
   - Voting weights sourced from `GovernanceToken.getVotingWeight()`.

---

## Governance Token (GT) Distribution Rules

| LP Holdings | GT per LP Unit |
|--------------|----------------|
| < 10 ETH     | 0              |
| 10 ~ 100 ETH | 1 GT per 10 ETH LP |
| 100 ~ 1000 ETH | 1 GT per 20 ETH LP |
| ≥ 1000 ETH   | 1 GT per 50 ETH LP |

Users can call `claimGovernanceToken()` anytime to claim pending GTs.  
If GT balance exceeds the theoretical maximum upon withdrawal, the surplus is automatically burned.

---

## Voting Power Mechanism (Time-Weighted)

```solidity
if (block.timestamp - mintTime >= 1 day) {
    votingWeight += amount;
}
```

- Voting power unlocks linearly per day.  
- Prevents short-term manipulation.  
- Encourages long-term holding.

---

## Security Mechanisms

| Risk | Mitigation |
|------|-------------|
| Malicious strategy fund drain | Only `Governance`-approved strategies can call `callTransfer` |
| Proposal spam | Requires ≥10 GT to create a proposal |
| Vote farming | Voting rights activate only after 1 day of holding |
| Fund mismatch | All deposits/withdrawals update `valuePerLP` to prevent mispricing |
| Centralized ownership | Ownership can be transferred to a multisig or DAO post-deployment |

---

## Deployment Process

```bash
# 1. Build
forge build

# 2. Deploy main contract (auto-deploys all subcontracts)
forge create OmniYieldPortal --rpc-url $RPC --private-key $KEY

# 3. Transfer Ownership (optional)
cast send <Portal> "transferOwnership(address)" $MULTISIG
```

Deployed contracts:
- OmniYieldPortal: Main entry
- GovernanceToken: GT
- LPToken: LP
- TreasuryVault: Vault
- Governance: Governance module

---

## User Guide

**Deposit**
```js
await portal.deposit({ value: ethers.parseEther("5") });
```

**Withdraw**
```js
await portal.withdrawBaseOnETH(ethers.parseEther("2")); // By ETH amount  
await portal.withdrawBaseOnLP(ethers.parseEther("2"));  // By LP amount
```

**Claim Governance Tokens**
```js
await portal.claimGovernanceToken();
```

**Create Proposal**
```js
await portal.createProposal(
  strategyAddress,
  "Add new Aave V3 strategy",
  1 // 1 = Add, 2 = Delete
);
```

**Vote**
```js
await portal.voteProposal(proposalId, true);  // Support  
await portal.voteProposal(proposalId, false); // Oppose
```

---

## Audit Focus

- Ensure `valuePerLP` updates avoid integer truncation.  
- Strict access control on strategy calls.  
- Prevent reentrancy in voting weight calculations.  
- Maintain consistency between `totalAssets` and actual vault balance.  
- Guarantee idempotency in proposal execution.

---

## Future Plans

- Support for multiple asset deposits (USDC, DAI, etc.).  
- Automatic yield distribution among LP holders.  
- Upgradable governance parameters (voting period, thresholds).  
- Integration with Chainlink VRF for randomized strategy rotation.  
- Expanded proposal creation flexibility.

