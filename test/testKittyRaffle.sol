// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/strategys/KittyRaffle.sol";
import {OmniYieldPortal} from "../src/OmniYieldPortal.sol";
import {GovernanceV1} from "../src/implementation/GovernanceV1.sol";
import {GovernanceProxy} from "../src/GovernanceProxy.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TreasuryVault} from "../src/TreasuryVault.sol";
import {LPToken} from "../src/LPToken.sol";

// 模拟 AirnodeRrpV0 合约用于测试
contract MockAirnodeRrpV0 {
    mapping(bytes32 => address) public requestCallbacks;
    mapping(bytes32 => bytes) public requestData;

    function makeFullRequest(
        address airnode,
        bytes32 endpointId,
        address sponsor,
        address sponsorWallet,
        address fulfillAddress,
        bytes4 fulfillFunctionId,
        bytes calldata parameters
    ) external returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        requestCallbacks[requestId] = fulfillAddress;
        requestData[requestId] = parameters;
        return requestId;
    }

    function fulfillRequest(bytes32 requestId, bytes memory data) external {
        address callbackAddress = requestCallbacks[requestId];
        (bool success,) =
            callbackAddress.call(abi.encodeWithSelector(KittyRaffle.fulfillRandomness.selector, requestId, data));
        require(success, "Fulfillment failed");
    }
}

contract KittyRaffleTest is Test {
    KittyRaffle public kittyRaffle;
    MockAirnodeRrpV0 public mockAirnode;
    OmniYieldPortal OYP;
    GovernanceV1 Gov;
    TreasuryVault TV;
    GovernanceToken GT;
    LPToken LP;
    GovernanceProxy govProxy;

    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);

    uint256 constant TICKET_PRICE = 0.001 ether;
    uint256 constant PLATFORM_FEE_PERCENT = 5;

    function setUp() public {
        // 部署模拟合约
        mockAirnode = new MockAirnodeRrpV0();

        address impl = address(new GovernanceV1());
        OYP = new OmniYieldPortal(impl);
        GT = GovernanceToken(OYP.getGTAddress());
        TV = TreasuryVault(payable(OYP.getTVAddress()));
        LP = LPToken(OYP.getLPAddress());
        Gov = GovernanceV1(OYP.getGovProxyAddress());

        // 部署 KittyRaffle 合约，传入模拟地址
        vm.startPrank(owner);
        kittyRaffle = new KittyRaffle(
            address(mockAirnode), // 使用模拟 AirnodeRrp
            address(0x123) // 模拟 QRNG Airnode 地址
        );

        //投票通过策略
        vm.deal(user1, 100 ether);
        vm.startPrank(user1);
        OYP.deposit{value: 100 ether}();
        OYP.claimGovernanceToken();
        address strategy1 = address(kittyRaffle);
        string memory describe = "describe";
        uint256 action1 = 1;

        OYP.createProposal(strategy1, describe, action1);

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
        //执行
        OYP.executeProposal(1);

        // 设置 treasury vault 来激活合约
        vm.prank(owner);
        kittyRaffle.setTreasuryVault(address(TV));
        vm.stopPrank();

        vm.deal(owner, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    function testInitialState() public {
        // 测试初始状态
        assertEq(kittyRaffle.owner(), owner);
        assertEq(kittyRaffle.treasuryVault(), address(TV));
        assertTrue(kittyRaffle.setTv());
        assertEq(kittyRaffle.currentRoundId(), 1);

        // 检查第一轮是否已启动
        (
            uint256 roundId,
            uint256 startTime,
            uint256 endTime,
            uint256 totalPrize,
            uint256 playerCount,
            bool isActive,
            bool prizeDistributed
        ) = kittyRaffle.getCurrentRoundInfo();

        assertEq(roundId, 1);
        assertTrue(isActive);
        assertFalse(prizeDistributed);
        assertEq(totalPrize, 0);
        assertEq(playerCount, 0);
        assertTrue(endTime > startTime);
    }

    function testParticipate() public {
        vm.startPrank(user1);

        // 参与抽奖
        kittyRaffle.participate{value: TICKET_PRICE}();

        // 验证参与状态
        assertTrue(kittyRaffle.hasParticipated(1, user1));
        assertEq(kittyRaffle.getPlayerByIndex(1, 0), user1);

        (,,, uint256 totalPrize, uint256 playerCount,,) = kittyRaffle.getCurrentRoundInfo();
        assertEq(totalPrize, TICKET_PRICE);
        assertEq(playerCount, 1);

        vm.stopPrank();
    }

    function testParticipate_RevertWhen_AlreadyParticipated() public {
        vm.startPrank(user1);
        kittyRaffle.participate{value: TICKET_PRICE}();

        vm.expectRevert(KittyRaffle.AlreadyParticipated.selector);
        kittyRaffle.participate{value: TICKET_PRICE}();

        vm.stopPrank();
    }

    function testParticipate_RevertWhen_WrongAmount() public {
        vm.startPrank(user1);

        vm.expectRevert("Invalid ticket price");
        kittyRaffle.participate{value: 0.0005 ether}();

        vm.expectRevert("Invalid ticket price");
        kittyRaffle.participate{value: 0.002 ether}();

        vm.stopPrank();
    }

    function testMultipleParticipants() public {
        // 多个玩家参与
        vm.startPrank(user1);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        vm.startPrank(user2);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        vm.startPrank(user3);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        (,,, uint256 totalPrize, uint256 playerCount,,) = kittyRaffle.getCurrentRoundInfo();
        assertEq(totalPrize, TICKET_PRICE * 3);
        assertEq(playerCount, 3);

        // 验证所有玩家都被记录
        assertTrue(kittyRaffle.hasParticipated(1, user1));
        assertTrue(kittyRaffle.hasParticipated(1, user2));
        assertTrue(kittyRaffle.hasParticipated(1, user3));

        assertEq(kittyRaffle.getPlayerByIndex(1, 0), user1);
        assertEq(kittyRaffle.getPlayerByIndex(1, 1), user2);
        assertEq(kittyRaffle.getPlayerByIndex(1, 2), user3);
    }

    function testDrawWinner_WithEnoughPlayers() public {
        // 设置三个玩家
        vm.startPrank(user1);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        vm.startPrank(user2);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        vm.startPrank(user3);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        uint256 initialTreasuryBalance = address(TV).balance;

        // 推进时间到轮次结束
        vm.warp(block.timestamp + 11 minutes);

        // 开奖
        vm.prank(user1);
        kittyRaffle.drawWinner();

        // 模拟随机数回调
        (,,,,,,, bytes32 pendingRequestId) = kittyRaffle.getRoundInfo(1);
        uint256 randomness = 12345; // 测试用随机数
        bytes memory data = abi.encode(randomness);
        mockAirnode.fulfillRequest(pendingRequestId, data);

        // 验证新轮次开始
        assertEq(kittyRaffle.currentRoundId(), 2);

        (,,,,, bool isActive,) = kittyRaffle.getCurrentRoundInfo();
        assertTrue(isActive);
    }

    function testDrawWinner_RevertWhen_NotEnoughPlayers() public {
        // 只有一个玩家参与
        vm.prank(user1);
        kittyRaffle.participate{value: TICKET_PRICE}();

        // 推进时间到轮次结束
        vm.warp(block.timestamp + 11 minutes);

        // 开奖 - 应该退款
        vm.prank(user1);
        kittyRaffle.drawWinner();

        // 验证新轮次开始
        assertEq(kittyRaffle.currentRoundId(), 2);

        (,,, uint256 totalPrize, uint256 playerCount, bool isActive,) = kittyRaffle.getCurrentRoundInfo();
        assertEq(totalPrize, 0);
        assertEq(playerCount, 0);
        assertTrue(isActive);
    }

    function testDrawWinner_RevertWhen_RoundNotEnded() public {
        vm.startPrank(user1);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        vm.startPrank(user2);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        // 尝试在轮次结束前开奖
        vm.expectRevert(KittyRaffle.RoundNotEnded.selector);
        kittyRaffle.drawWinner();
    }

    function testEmergencyStop() public {
        vm.startPrank(user1);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        // 所有者紧急停止
        vm.prank(owner);
        kittyRaffle.emergencyStop(1);

        (,,,,, bool isActive,,) = kittyRaffle.getRoundInfo(1);
        assertFalse(isActive);

        // 非所有者不能紧急停止
        vm.prank(user1);
        vm.expectRevert();
        kittyRaffle.emergencyStop(1);
    }

    function testManualDrawWinner() public {
        vm.startPrank(user1);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        // 推进时间到轮次结束
        vm.warp(block.timestamp + 11 minutes);

        // 所有者手动开奖（退款）
        vm.prank(owner);
        kittyRaffle.manualDrawWinner(1);

        // 验证新轮次开始
        assertEq(kittyRaffle.currentRoundId(), 2);
    }

    function testCatRarities() public {
        // 测试小猫稀有度配置
        uint256 rarityCount = kittyRaffle.getCatRarityCount();
        assertEq(rarityCount, 4);

        // 可以添加更多测试来验证稀有度概率等
    }

    function testSetTreasuryVault_RevertWhen_AlreadySet() public {
        vm.startPrank(owner);

        vm.expectRevert("Already set");
        kittyRaffle.setTreasuryVault(address(0x123));

        vm.stopPrank();
    }

    function testSetTreasuryVault_RevertWhen_NotOwner() public {
        vm.prank(user1);

        vm.expectRevert();
        kittyRaffle.setTreasuryVault(address(0x123));
    }

    function testFunctions_RevertWhen_TreasuryNotSet() public {
        // 部署新合约但不设置 treasury vault
        // 部署模拟合约
        mockAirnode = new MockAirnodeRrpV0();
        TV = new TreasuryVault();

        // 部署 KittyRaffle 合约，传入模拟地址
        vm.startPrank(owner);
        KittyRaffle newRaffle = new KittyRaffle(
            address(mockAirnode), // 使用模拟 AirnodeRrp
            address(0x123) // 模拟 QRNG Airnode 地址
        );

        vm.startPrank(user1);

        vm.expectRevert("Treasury vault not set");
        newRaffle.participate{value: TICKET_PRICE}();

        vm.expectRevert("Treasury vault not set");
        newRaffle.drawWinner();

        vm.stopPrank();
    }

    function testTokenURI() public {
        // 测试 NFT 元数据
        vm.startPrank(user1);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        vm.startPrank(user2);
        kittyRaffle.participate{value: TICKET_PRICE}();
        vm.stopPrank();

        // 完成一轮抽奖来铸造 NFT
        vm.warp(block.timestamp + 11 minutes);
        vm.prank(user1);
        kittyRaffle.drawWinner();

        // 模拟随机数回调
        (,,,,,,, bytes32 pendingRequestId) = kittyRaffle.getRoundInfo(1);
        uint256 randomness = 12345; // 测试用随机数
        bytes memory data = abi.encode(randomness);
        mockAirnode.fulfillRequest(pendingRequestId, data);

        // 验证 NFT 被铸造
        address winner = kittyRaffle.roundWinners(1);
        assertTrue(winner != address(0));

        uint256 rarity = kittyRaffle.winnerCatRarity(1);
        assertTrue(rarity < 4); // 应该在 0-3 范围内

        // 验证 tokenURI
        string memory uri = kittyRaffle.tokenURI(1);
        assertTrue(bytes(uri).length > 0);
    }

    function testReceiveEther() public {
        // 测试合约能否接收 ETH
        uint256 initialBalance = address(kittyRaffle).balance;

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool success,) = address(kittyRaffle).call{value: 0.1 ether}("");

        assertTrue(success);
        assertEq(address(kittyRaffle).balance, initialBalance + 0.1 ether);
    }
}
