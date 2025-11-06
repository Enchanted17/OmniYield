// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAirnodeRrpV0 {
    function makeFullRequest(
        address airnode,
        bytes32 endpointId,
        address sponsor,
        address sponsorWallet,
        address fulfillAddress,
        bytes4 fulfillFunctionId,
        bytes calldata parameters
    ) external returns (bytes32 requestId);
}

contract KittyRaffle is ERC721, Ownable {
    // API3 QRNG 配置
    IAirnodeRrpV0 public immutable airnodeRrp;
    
    // Sepolia 测试网地址
    address public AIRNODE_RRP;
    address public QRNG_AIRNODE;
    bytes32 public constant ENDPOINT_ID_UINT256 = 0xfb6d017bb87991b7495f563db3c8cf59ff87b09781947bb1e417006ad7e55d57;
    
    address public treasuryVault;
    bool public setTv = false;

    // 抽奖配置
    uint256 public constant TICKET_PRICE = 0.001 ether;
    uint256 public constant PLATFORM_FEE_PERCENT = 5;
    uint256 public constant MIN_PLAYERS = 2;
    uint256 public constant ROUND_DURATION = 10 minutes;
    
    // 小猫NFT稀有度配置
    struct CatRarity {
        string name;
        uint256 probability;
        string metadataURI;
    }
    
    CatRarity[] public catRarities;
    uint256 public nextTokenId = 1;
    
    
    // 玩家数据结构
    struct Player {
        address addr;
        uint256 index;
    }
    
    // 当前轮次状态
    struct Round {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPrize;
        uint256 playerCount;
        bool isActive;
        bool prizeDistributed;
        bytes32 pendingRequestId;
        mapping(uint256 => Player) players;
        mapping(address => uint256) playerIndices;
    }
    
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(address => bool)) public roundParticipants;
    mapping(uint256 => address) public roundWinners;
    mapping(uint256 => uint256) public winnerCatRarity;
    mapping(uint256 => string) public tokenIdToMetadata;
    
    uint256 public currentRoundId = 1;
    
    // 事件
    event RoundStarted(uint256 roundId, uint256 startTime, uint256 endTime);
    event TicketPurchased(uint256 roundId, address player, uint256 ticketCount);
    event WinnerSelected(uint256 roundId, address winner, uint256 prize, uint256 catRarity);
    event RoundRefunded(uint256 roundId, uint256 totalRefund);
    event RandomnessRequested(uint256 roundId, bytes32 requestId);
    event CatNFTMinted(address to, uint256 tokenId, uint256 rarity);
    event SetTreasuryVault(address TreasuryVault, uint256 time);
    
    // 错误
    error OnlyAirnodeRrp();
    error InvalidRound();
    error RoundEnded();
    error RoundNotEnded();
    error RoundAlreadyFinished();
    error InsufficientPlayers();
    error AlreadyParticipated();
    error OnlyEOAAllowed();
    error InvalidRarityConfig();

    modifier onlyAfterSetup() {
        require(setTv == true, "Treasury vault not set");
        _;
    }
    
    constructor(address Airnode, address qing_airnode) ERC721("LuckyCatNFT", "LCAT") Ownable(msg.sender) {
        AIRNODE_RRP = Airnode;
        QRNG_AIRNODE = qing_airnode;
        airnodeRrp = IAirnodeRrpV0(AIRNODE_RRP);
    }

    function setTreasuryVault(address _tv) onlyOwner external {
        require(setTv == false, "Already set");
        treasuryVault = _tv;
        setTv = true;
        emit SetTreasuryVault(_tv, block.timestamp);
        _initializeCatRarities();
        _startNewRound();
    }
    
    function _initializeCatRarities() internal {
        // 普通 - 60%
        catRarities.push(CatRarity({
            name: "Common Cat",
            probability: 6000,
            metadataURI: "ipfs://QmCommonCatURI"
        }));
        
        // 稀有 - 25%
        catRarities.push(CatRarity({
            name: "Rare Cat", 
            probability: 2500,
            metadataURI: "ipfs://QmRareCatURI"
        }));
        
        // 史诗 - 10%
        catRarities.push(CatRarity({
            name: "Epic Cat",
            probability: 1000,
            metadataURI: "ipfs://QmEpicCatURI"
        }));
        
        // 传说 - 5%
        catRarities.push(CatRarity({
            name: "Legendary Cat",
            probability: 500,
            metadataURI: "ipfs://QmLegendaryCatURI"
        }));
        
        // 验证概率总和
        uint256 totalProb;
        for (uint i = 0; i < catRarities.length; i++) {
            totalProb += catRarities[i].probability;
        }
        if (totalProb != 10000) {
            revert InvalidRarityConfig();
        }
    }
    
    function _startNewRound() internal {
        Round storage newRound = rounds[currentRoundId];
        newRound.roundId = currentRoundId;
        newRound.startTime = block.timestamp;
        newRound.endTime = block.timestamp + ROUND_DURATION;
        newRound.isActive = true;
        newRound.playerCount = 0;
        newRound.totalPrize = 0;
        
        emit RoundStarted(currentRoundId, newRound.startTime, newRound.endTime);
    }
    
    function participate() external payable onlyAfterSetup {
        // 防止合约参与
        // if (msg.sender != tx.origin) {
        //     revert OnlyEOAAllowed();
        // }
        
        Round storage currentRound = rounds[currentRoundId];
        
        if (!currentRound.isActive) {
            revert InvalidRound();
        }
        
        if (block.timestamp >= currentRound.endTime) {
            revert RoundEnded();
        }
        
        if (roundParticipants[currentRoundId][msg.sender]) {
            revert AlreadyParticipated();
        }
        
        if (msg.value != TICKET_PRICE) {
            revert("Invalid ticket price");
        }
        
        // 记录参与者
        roundParticipants[currentRoundId][msg.sender] = true;
        
        uint256 playerIndex = currentRound.playerCount;
        currentRound.players[playerIndex] = Player(msg.sender, playerIndex);
        currentRound.playerIndices[msg.sender] = playerIndex;
        currentRound.playerCount++;
        currentRound.totalPrize += msg.value;
        
        emit TicketPurchased(currentRoundId, msg.sender, 1);
    }
    
    function drawWinner() external onlyAfterSetup {
        Round storage currentRound = rounds[currentRoundId];
        
        if (!currentRound.isActive) {
            revert InvalidRound();
        }
        
        if (block.timestamp < currentRound.endTime) {
            revert RoundNotEnded();
        }
        
        if (currentRound.prizeDistributed) {
            revert RoundAlreadyFinished();
        }
        
        if (currentRound.playerCount < MIN_PLAYERS) {
            _refundRound(currentRoundId);
            return;
        }
        
        bytes32 requestId = airnodeRrp.makeFullRequest(
            QRNG_AIRNODE,
            ENDPOINT_ID_UINT256,
            address(this),
            address(this),
            address(this),
            this.fulfillRandomness.selector,
            ""
        );
        
        currentRound.pendingRequestId = requestId;
        emit RandomnessRequested(currentRoundId, requestId);
    }
    
    function fulfillRandomness(bytes32 requestId, bytes calldata data) external onlyAfterSetup {
        if (msg.sender != AIRNODE_RRP) {
            revert OnlyAirnodeRrp();
        }
        
        uint256 targetRoundId;
        bool found;
        
        for (uint256 i = 1; i <= currentRoundId; i++) {
            if (rounds[i].pendingRequestId == requestId && rounds[i].isActive) {
                targetRoundId = i;
                found = true;
                break;
            }
        }
        
        if (!found) {
            revert InvalidRound();
        }
        
        Round storage targetRound = rounds[targetRoundId];
        uint256 randomness = abi.decode(data, (uint256));
        uint256 winnerIndex = randomness % targetRound.playerCount;
        address winner = targetRound.players[winnerIndex].addr;
        uint256 catRarityIndex = _selectCatRarity(randomness >> 128);
        
        _distributePrize(targetRoundId, winner, catRarityIndex);
        currentRoundId++;
        _startNewRound();
    }
    
    function _selectCatRarity(uint256 randomness) internal view returns (uint256) {
        uint256 rand = randomness % 10000;
        uint256 cumulativeProb;
        
        for (uint256 i = 0; i < catRarities.length; i++) {
            cumulativeProb += catRarities[i].probability;
            if (rand < cumulativeProb) {
                return i;
            }
        }
        return 0;
    }
    
    function _distributePrize(uint256 roundId, address winner, uint256 catRarityIndex) internal {
        Round storage round = rounds[roundId];
        
        uint256 platformFee = (round.totalPrize * PLATFORM_FEE_PERCENT) / 100;
        uint256 winnerPrize = round.totalPrize - platformFee;
        
        (bool success1, ) = treasuryVault.call{value: platformFee}(abi.encodeWithSignature("profitIn(uint256)",platformFee));
        (bool success2, ) = winner.call{value: winnerPrize}("");
        require(success1 && success2, "Transfer failed");
        
        _mintCatNFT(winner, catRarityIndex);
        
        roundWinners[roundId] = winner;
        winnerCatRarity[roundId] = catRarityIndex;
        round.prizeDistributed = true;
        round.isActive = false;
        
        emit WinnerSelected(roundId, winner, winnerPrize, catRarityIndex);
    }
    
    function _mintCatNFT(address to, uint256 rarityIndex) internal {
        uint256 tokenId = nextTokenId;
        tokenIdToMetadata[tokenId] = catRarities[rarityIndex].metadataURI;
        _mint(to, tokenId);
        nextTokenId++;
        emit CatNFTMinted(to, tokenId, rarityIndex);
    }
    
    function _refundRound(uint256 roundId) internal {
        Round storage round = rounds[roundId];
        emit RoundRefunded(roundId, round.totalPrize);
        round.totalPrize = 0;
        round.isActive = false;
        round.prizeDistributed = true;
        currentRoundId++;
        _startNewRound();
    }
    
    function tokenURI(uint256 tokenId) public view override onlyAfterSetup returns (string memory) {
        _requireOwned(tokenId);
        return tokenIdToMetadata[tokenId];
    }
    
    // 视图函数
    function getRoundInfo(uint256 roundId) public view onlyAfterSetup returns (
        uint256 roundId_,
        uint256 startTime,
        uint256 endTime,
        uint256 totalPrize,
        uint256 playerCount,
        bool isActive,
        bool prizeDistributed,
        bytes32 pendingRequestId
    ) {
        Round storage round = rounds[roundId];
        return (
            round.roundId,
            round.startTime,
            round.endTime,
            round.totalPrize,
            round.playerCount,
            round.isActive,
            round.prizeDistributed,
            round.pendingRequestId
        );
    }
    
    function getCurrentRoundInfo() public view onlyAfterSetup returns (
        uint256 roundId,
        uint256 startTime,
        uint256 endTime,
        uint256 totalPrize,
        uint256 playerCount,
        bool isActive,
        bool prizeDistributed
    ) {
        Round storage round = rounds[currentRoundId];
        return (
            round.roundId,
            round.startTime,
            round.endTime,
            round.totalPrize,
            round.playerCount,
            round.isActive,
            round.prizeDistributed
        );
    }
    
    function getCatRarityCount() public view onlyAfterSetup returns (uint256) {
        return catRarities.length;
    }
    
    function hasParticipated(uint256 roundId, address player) public view onlyAfterSetup returns (bool) {
        return roundParticipants[roundId][player];
    }
    
    function getPlayerByIndex(uint256 roundId, uint256 index) public view onlyAfterSetup returns (address) {
        require(index < rounds[roundId].playerCount, "Invalid index");
        return rounds[roundId].players[index].addr;
    }
    
    // 管理员函数
    function manualDrawWinner(uint256 roundId) external onlyAfterSetup onlyOwner {
        Round storage round = rounds[roundId];
        require(round.isActive && !round.prizeDistributed, "Round not active or already finished");
        require(block.timestamp >= round.endTime, "Round not ended");
        _refundRound(roundId);
    }
    
    function emergencyStop(uint256 roundId) external onlyAfterSetup onlyOwner {
        Round storage round = rounds[roundId];
        round.isActive = false;
    }
    
    receive() external payable {}
}