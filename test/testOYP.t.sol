// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OmniYieldPortal} from "../src/OmniYieldPortal.sol";
import {GovernanceV1} from "../src/implementation/GovernanceV1.sol";
import {GovernanceProxy} from "../src/GovernanceProxy.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {LPToken} from "../src/LPToken.sol";
import {FlashLoan} from "../src/strategys/FlashLoan.sol";
import {Test, console2} from "forge-std/Test.sol";

contract TestOmniYieldPortal is Test {
    OmniYieldPortal OYP;
    GovernanceV1 Gov;
    TreasuryVault TV;
    GovernanceToken GT;
    LPToken LP;
    FlashLoan FL;
    GovernanceProxy govProxy;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    function setUp() public {
        address impl = address(new GovernanceV1());
        OYP = new OmniYieldPortal(impl);
        GT = GovernanceToken(OYP.getGTAddress());
        TV = TreasuryVault(payable(OYP.getTVAddress()));
        LP = LPToken(OYP.getLPAddress());
        Gov = GovernanceV1(OYP.getGovProxyAddress());
    }

    function testDeposit() public {
        vm.deal(user1, 200 ether);
        vm.startPrank(user1);
        OYP.deposit{value: 200 ether}();

        assertEq(address(TV).balance, 200 ether);
        assertEq(LP.balanceOf(user1), 200 ether);
        assertEq(user1.balance, 0 ether);
        assertEq(OYP.valuePerLP(), 1 wei);
        vm.stopPrank();

        vm.deal(user2, 200 ether);
        vm.startPrank(user2);
        OYP.deposit{value: 200 ether}();

        assertEq(address(TV).balance, 400 ether);
        assertEq(LP.balanceOf(user2), 200 ether);
        assertEq(user2.balance, 0 ether);
        assertEq(OYP.valuePerLP(), 1 wei);
        vm.stopPrank();
    }

    function testClaimGT1() public {
        // Level 1
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        OYP.deposit{value: 10 ether}();

        OYP.claimGovernanceToken();
        assertEq(GT.balanceOf(user1), 1); //user1 LP balance == 10e18, should get 1 GT

        // Level 2
        vm.deal(user1, 110 ether);
        OYP.deposit{value: 110 ether}();

        OYP.claimGovernanceToken();
        assertEq(GT.balanceOf(user1), 11); //user1 LP balance == 120e18, should get 11 GT

        // Level 3
        vm.deal(user1, 1000 ether);
        OYP.deposit{value: 1000 ether}();

        OYP.claimGovernanceToken();
        assertEq(GT.balanceOf(user1), 57); //user1 LP balance == 1120e18, should get 10+45+2=57 GT

        // when withdraw
        // LP balance: 1120e18
        // GT balance: 57
        OYP.withdrawBaseOnLP(100 ether);
        assertEq(GT.balanceOf(user1), 55); //user1 LP balance == 1020e18, should remain 10+45+0=55 GT

        OYP.withdrawBaseOnLP(500 ether);
        assertEq(GT.balanceOf(user1), 31); //user1 LP balance == 520e18, should remain 10+21=31 GT

        OYP.withdrawBaseOnLP(520 ether);
        assertEq(GT.balanceOf(user1), 0); //user1 LP balance == 0, should remain 0 GT
    }

    function testClaimGT2() public {
        vm.deal(user1, 100 ether);
        vm.startPrank(user1);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        vm.stopPrank();
        assertEq(GT.balanceOf(user1), 10);

        vm.deal(user2, 100 ether);
        vm.startPrank(user2);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        vm.stopPrank();
        assertEq(GT.balanceOf(user2), 10);

        vm.deal(user3, 100 ether);
        vm.startPrank(user3);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        vm.stopPrank();
        assertEq(GT.balanceOf(user3), 10);
    }

    function testWithdrawBaseOnETH() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        OYP.deposit{value: 10 ether}();
        OYP.claimGovernanceToken();

        uint256 LPAmount = LP.balanceOf(user1);
        uint256 amount = OYP.convertLPToETH(LPAmount);

        OYP.withdrawBaseOnETH(amount);
        assertEq(GT.balanceOf(user1), 0);
        assertEq(user1.balance, 10 ether);
        vm.stopPrank();
    }

    function testWithdrawBaseOnLP() public {
        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        OYP.deposit{value: 10 ether}();
        OYP.claimGovernanceToken();

        uint256 LPAmount = OYP.convertETHToLP(10 ether);
        OYP.withdrawBaseOnLP(LPAmount);
        assertEq(GT.balanceOf(user1), 0);
        assertEq(user1.balance, 10 ether);
    }

    function testGetRecord() public {
        vm.deal(user1, 35 ether);

        vm.startPrank(user1);
        OYP.deposit{value: 5 ether}();
        OYP.deposit{value: 10 ether}();
        OYP.deposit{value: 20 ether}();

        OYP.withdrawBaseOnETH(5 ether);
        OYP.withdrawBaseOnETH(10 ether);
        OYP.withdrawBaseOnETH(20 ether);

        uint256[] memory depositRecord = OYP.getDepositRecord();
        uint256[] memory withdrawRecord = OYP.getWithdrawRecord();
        uint256[] memory arr1 = new uint256[](3);
        uint256[] memory arr2 = new uint256[](3);
        arr1[0] = 5 ether;
        arr1[1] = 10 ether;
        arr1[2] = 20 ether;
        arr2[0] = 5 ether;
        arr2[1] = 10 ether;
        arr2[2] = 20 ether;

        assertEq(arr1, depositRecord);
        assertEq(arr2, withdrawRecord);
    }

    function testCreateProposal() public {
        // setup
        FL = new FlashLoan(address(TV));
        vm.deal(user1, 100 ether);
        vm.startPrank(user1);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        address strategy1 = address(FL);
        string memory describe = "describe";
        uint256 action1 = 1;

        // create proposal
        (
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
        ) = OYP.getProposalDetail(OYP.createProposal(strategy1, describe, action1));
        vm.stopPrank();

        //check
        assertEq(Gov.proposalId(), 1);
        assertEq(proposer, user1);
        assertEq(strategy, strategy1);
        assertEq(description, describe);
        assertEq(action, "Add");
        assertEq(forVotes, 0);
        assertEq(againstVotes, 0);
        assertEq(startTime, block.timestamp);
        assertEq(endTime, block.timestamp + 3 days);
        assertEq(state, "Active");
        assertEq(executed, false);
    }

    function testVoteSucceed() public {
        // setup 每位用户拥有 10 GT，user1创建了一个提案，时间过去一天
        testCreateProposal();

        vm.deal(user2, 100 ether);
        vm.startPrank(user2);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        vm.stopPrank();

        vm.deal(user3, 100 ether);
        vm.startPrank(user3);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // 用户投票
        vm.prank(user1);
        OYP.voteProposal(1, true);

        vm.prank(user2);
        OYP.voteProposal(1, false);

        vm.prank(user3);
        OYP.voteProposal(1, true);

        //用户在投票期结束时投票
        vm.warp(block.timestamp + 3 days);
        vm.prank(user3);
        OYP.voteProposal(1, false);

        (
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
        ) = OYP.getProposalDetail(1);

        assertEq(forVotes, 20);
        assertEq(againstVotes, 10);
        assertEq(state, "Succeeded");
    }

    function testVoteFail() public {
        // setup 每位用户拥有 10 GT，user1创建了一个提案，时间过去一天
        testCreateProposal();

        vm.deal(user2, 100 ether);
        vm.startPrank(user2);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        vm.stopPrank();

        vm.deal(user3, 100 ether);
        vm.startPrank(user3);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // 用户投票
        vm.prank(user1);
        OYP.voteProposal(1, true);

        vm.prank(user2);
        OYP.voteProposal(1, false);

        vm.prank(user3);
        OYP.voteProposal(1, false);

        //用户在投票期结束时投票
        vm.warp(block.timestamp + 3 days);
        vm.prank(user3);
        OYP.voteProposal(1, false);

        (
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
        ) = OYP.getProposalDetail(1);

        assertEq(forVotes, 10);
        assertEq(againstVotes, 20);
        assertEq(state, "Defeated");
    }

    function testExecuteProposal() public {
        testVoteSucceed();
        vm.deal(address(this), 300 ether);
        OYP.executeProposal(1);
        vm.prank(address(FL));
        (bool profitSuccess,) = address(TV).call(abi.encodeWithSignature("profitIn(uint256)", 300 ether));
        assertEq(TV.totalAssets(), 600 ether);
    }

    function testCheckOwner()public {
        assertEq(address(OYP), Gov.owner());
    }
}
