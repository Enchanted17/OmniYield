// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OmniYieldPortal} from "../src/OmniYieldPortal.sol";
import {GovernanceV1} from "../src/implementation/GovernanceV1.sol";
import {GovernanceProxy} from "../src/GovernanceProxy.sol";
import {GovernanceV2} from "../src/implementation/GovernanceV2.sol";
import {Test, console2} from "forge-std/Test.sol";

contract TestOmniYieldPortal is Test {
    OmniYieldPortal OYP;
    GovernanceV1 Gov;
    GovernanceProxy govProxy;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    function setUp() public {
        address impl = address(new GovernanceV1());
        OYP = new OmniYieldPortal(impl);
        Gov = GovernanceV1(OYP.getGovProxyAddress());
    }

    function testUpgrade() public {
        // setup
        address newImpl = address(new GovernanceV2());
        vm.deal(user1, 100 ether);
        vm.startPrank(user1);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        string memory describe = "describe";
        uint256 action1 = 3;

        OYP.createProposal(newImpl, describe, action1);

        vm.warp(block.timestamp + 1 days);
        OYP.voteProposal(1, true);

        vm.warp(block.timestamp + 3 days);
        OYP.voteProposal(1, true);

        OYP.executeProposal(1);
        uint256 num = GovernanceV2(payable(OYP.getGovProxyAddress())).myNumber();
        assertEq(num, 1);
    }
}
