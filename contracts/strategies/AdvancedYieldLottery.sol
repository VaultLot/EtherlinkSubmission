// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title IStrategies
/// @notice Interface that strategy contracts must implement for the yield lottery system
interface IStrategies {
    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event Harvest(uint256 earned);
    event EmergencyExit(uint256 amount);

    function execute(uint256 amount, bytes calldata data) external;
    function harvest(bytes calldata data) external;
    function emergencyExit(bytes calldata data) external;
    function getBalance() external view returns (uint256 balance);
    function underlyingToken() external view returns (address token);
    function protocol() external view returns (address protocol);
    function paused() external view returns (bool paused);
    function setPaused(bool _paused) external;
}

/// @title IYieldAggregator
/// @notice Interface for yield aggregation and optimization
interface IYieldAggregator {
    struct OptimizedAllocation {
        address protocol;
        uint16 chainId;
        uint256 amount;
        uint256 expectedAPY;
        uint256 riskScore;
        uint256 allocation;
        uint256 gasEstimate;
        bool requiresBridge;
        bytes executionData;
    }

    function calculateOptimalAllocation(
        address asset,
        uint256 totalAmount,
        uint256 maxRiskTolerance
    ) external view returns (
        OptimizedAllocation[] memory allocations,
        uint256 totalExpectedAPY,
        uint256 totalRisk,
        uint256 gasEstimate
    );
    
    function getTopYieldOpportunities(
        address asset,
        uint256 maxRiskTolerance,
        uint256 count
    ) external view returns (
        address[] memory protocols,
        uint256[] memory apys,
        uint256[] memory riskScores
    );
}

/// @title IEtherlinkRandomness
/// @notice Interface for Etherlink VRF randomness
interface IEtherlinkRandomness {
    function requestRandomness(uint256 callbackGasLimit) external returns (bytes32 requestId);
}

/// @title AdvancedYieldLottery - Sophisticated Multi-Source Yield Lottery
/// @notice Advanced lottery system with ML-optimized yield generation and fair distribution
/// @dev Integrates multiple yield sources, sophisticated randomness, and dynamic prize pools
contract AdvancedYieldLottery is IStrategies, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant LOTTERY_MANAGER_ROLE = keccak256("LOTTERY_MANAGER_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant PYTHON_AGENT_ROLE = keccak256("PYTHON_AGENT_ROLE");

    // ============ ADVANCED LOTTERY MECHANICS ============

    struct LotteryConfig {
        uint256 drawInterval; // Time between draws
        uint256 minPrizePool; // Minimum prize pool to trigger draw
        uint256 maxParticipants; // Maximum participants per draw
        uint256 entryFee; // Fee per lottery entry (in basis points of deposit)
        uint256 devFee; // Developer fee (in basis points)
        uint256 nextPrizeFee; // Fee that goes to next lottery (in basis points)
        uint256 burnFee; // Fee that gets burned (in basis points)
        bool emergencyMode; // Emergency mode disables new entries
        bool dynamicPrizes; // Whether prize amounts are dynamic
        uint256 volatilityMultiplier; // Multiplier based on yield volatility
    }

    struct Participant {
        address user;
        uint256 depositAmount;
        uint256 entryCount; // Number of lottery entries
        uint256 depositTime;
        uint256 lastRewardTime;
        uint256 totalRewardsWon;
        uint256 participationStreak; // Consecutive lotteries participated
        bool active;
        uint256 riskTolerance; // User's risk tolerance for yield strategies
        bool autoCompound; // Whether to auto-compound rewards
    }

    struct LotteryDraw {
        uint256 drawId;
        uint256 timestamp;
        address winner;
        uint256 prizeAmount;
        uint256 totalParticipants;
        uint256 totalPrizePool;
        uint256 yieldGenerated; // Yield that contributed to this draw
        bytes32 randomnessRequestId;
        bytes32 randomSeed;
        bool completed;
        uint256 gasUsed;
        string yieldSources; // Which yield sources contributed
    }

    struct YieldSource {
        address protocol;
        uint16 chainId;
        uint256 allocation; // Amount allocated to this source
        uint256 currentAPY;
        uint256 yieldGenerated;
        uint256 lastHarvest;
        bool active;
        string name; // "aave", "compound", "increment", etc.
    }

    struct AdvancedMetrics {
        uint256 totalYieldGenerated;
        uint256 totalPrizesDistributed;
        uint256 averagePrizeAmount;
        uint256 participationRate;
        uint256 yieldEfficiency; // Yield generated per gas spent
        uint256 randomnessQuality; // Quality score of randomness
        uint256 fairnessScore; // Statistical fairness measure
        uint256 lastAnalysis;
    }

    // ============ STATE VARIABLES ============

    IERC20 public immutable asset;
    IYieldAggregator public yieldAggregator;
    IEtherlinkRandomness public randomnessOracle;
    
    LotteryConfig public lotteryConfig;
    AdvancedMetrics public metrics;
    
    // Participant management
    mapping(address => Participant) public participants;
    address[] public participantList;
    mapping(address => uint256) public participantIndex;
    uint256 public totalDeposits;
    uint256 public totalEntries;
    
    // Lottery draws
    mapping(uint256 => LotteryDraw) public lotteryDraws;
    uint256 public currentDrawId;
    uint256 public lastDrawTime;
    
    // Yield sources
    mapping(bytes32 => YieldSource) public yieldSources; // keccak256(protocol, chainId) => source
    bytes32[] public activeYieldSources;
    uint256 public totalYieldAllocated;
    uint256 public totalYieldGenerated;
    uint256 public currentPrizePool;
    
    // Advanced randomness
    mapping(bytes32 => uint256) public randomnessRequests; // requestId => drawId
    mapping(uint256 => bytes32) public pendingRandomness; // drawId => requestId
    
    // Yield optimization
    uint256 public maxRiskTolerance = 6000; // 60%
    uint256 public rebalanceThreshold = 500; // 5% APY difference triggers rebalance
    uint256 public lastRebalance;
    uint256 public gasReserve = 0.1 ether; // Reserve for optimization transactions
    
    // Dynamic pricing and game theory
    mapping(address => uint256) public userRiskPreference;
    mapping(address => uint256) public loyaltyBonus; // Bonus based on participation history
    uint256 public competitivePressure; // Increases with more participants
    
    // Multi-chain yield coordination
    mapping(uint16 => uint256) public chainAllocations; // How much yield deployed per chain
    mapping(uint16 => bool) public supportedChains;
    
    // Pause state
    bool private _paused;
    
    // Events
    event LotteryDrawCompleted(
        uint256 indexed drawId,
        address indexed winner,
        uint256 prizeAmount,
        uint256 participants,
        bytes32 randomSeed
    );
    
    event ParticipantAdded(address indexed user, uint256 amount, uint256 entries);
    event ParticipantRemoved(address indexed user, uint256 amount);
    event YieldHarvested(bytes32 indexed sourceId, uint256 amount, uint256 newAPY);
    event YieldRebalanced(uint256 oldAllocation, uint256 newAllocation, uint256 expectedImprovement);
    event RandomnessRequested(uint256 indexed drawId, bytes32 requestId);
    event EmergencyModeToggled(bool enabled, string reason);
    event YieldSourceAdded(bytes32 indexed sourceId, address protocol, string name, uint256 allocation);
    event AdvancedMetricsUpdated(uint256 totalYield, uint256 efficiency, uint256 fairnessScore);

    constructor(
        address _asset,
        address _yieldAggregator,
        address _randomnessOracle
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_yieldAggregator != address(0), "Invalid yield aggregator");
        require(_randomnessOracle != address(0), "Invalid randomness oracle");

        asset = IERC20(_asset);
        yieldAggregator = IYieldAggregator(_yieldAggregator);
        randomnessOracle = IEtherlinkRandomness(_randomnessOracle);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LOTTERY_MANAGER_ROLE, msg.sender);
        _grantRole(YIELD_MANAGER_ROLE, msg.sender);

        // Initialize with sophisticated defaults
        lotteryConfig = LotteryConfig({
            drawInterval: 7 days,
            minPrizePool: 100 * 10**6, // 100 USDC
            maxParticipants: 10000,
            entryFee: 0, // No entry fee initially
            devFee: 500, // 5%
            nextPrizeFee: 1000, // 10% goes to next lottery
            burnFee: 0, // No burn initially
            emergencyMode: false,
            dynamicPrizes: true,
            volatilityMultiplier: 10000 // 100% (no multiplier initially)
        });

        lastDrawTime = block.timestamp;
        
        // Initialize supported chains
        supportedChains[101] = true; // Ethereum
        supportedChains[110] = true; // Arbitrum
        supportedChains[109] = true; // Polygon
        supportedChains[30302] = true; // Etherlink
    }

    // ============ STRATEGY INTERFACE IMPLEMENTATION ============

    function execute(uint256 amount, bytes calldata data) external override onlyRole(YIELD_MANAGER_ROLE) {
        require(amount > 0, "Invalid amount");
        require(!lotteryConfig.emergencyMode, "Emergency mode active");
        
        // Decode execution data if provided
        (uint256 riskTolerance, bool rebalanceYield) = data.length > 0 
            ? abi.decode(data, (uint256, bool))
            : (maxRiskTolerance, true);

        // Transfer assets from caller
        asset.safeTransferFrom(msg.sender, address(this), amount);
        
        if (rebalanceYield) {
            // Optimize yield allocation using ML-powered aggregator
            _optimizeYieldAllocation(amount, riskTolerance);
        } else {
            // Simple addition to prize pool
            currentPrizePool += amount;
        }
        
        // Update metrics
        totalYieldAllocated += amount;
    }

    function harvest(bytes calldata data) external override onlyRole(YIELD_MANAGER_ROLE) {
        // Harvest from all active yield sources
        uint256 totalHarvested = 0;
        for (uint i = 0; i < activeYieldSources.length; i++) {
            YieldSource storage source = yieldSources[activeYieldSources[i]];
            if (source.active) {
                uint256 harvested = _harvestFromSource(activeYieldSources[i]);
                totalHarvested += harvested;
            }
        }
        
        // Add harvested yield to prize pool
        currentPrizePool += totalHarvested;
        totalYieldGenerated += totalHarvested;
        
        // Update metrics
        _updateAdvancedMetrics();
        
        // Check if lottery draw should be triggered
        if (_shouldTriggerDraw()) {
            _initiateLotteryDraw();
        }
    }

    function emergencyExit(bytes calldata data) external override onlyRole(LOTTERY_MANAGER_ROLE) {
        lotteryConfig.emergencyMode = true;
        _paused = true;
        
        // Emergency harvest from all sources
        for (uint i = 0; i < activeYieldSources.length; i++) {
            try this._emergencyHarvestFromSource(activeYieldSources[i]) {
                // Continue with next source if one fails
            } catch {
                // Log error but continue
            }
        }
        
        emit EmergencyModeToggled(true, "Emergency exit triggered");
    }

    function getBalance() external view override returns (uint256) {
        return currentPrizePool;
    }

    function underlyingToken() external view override returns (address) {
        return address(asset);
    }

    function protocol() external view override returns (address) {
        return address(this);
    }

    function paused() external view override returns (bool) {
        return _paused || lotteryConfig.emergencyMode;
    }

    function setPaused(bool pauseState) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _paused = pauseState;
    }

    // ============ PARTICIPANT MANAGEMENT ============

    function addParticipant(address user, uint256 amount, uint256 userRiskTolerance) external onlyRole(LOTTERY_MANAGER_ROLE) {
        require(!lotteryConfig.emergencyMode, "Emergency mode active");
        require(participantList.length < lotteryConfig.maxParticipants, "Max participants reached");
        require(amount > 0, "Invalid amount");

        if (!participants[user].active) {
            // New participant
            participants[user] = Participant({
                user: user,
                depositAmount: amount,
                entryCount: _calculateEntries(amount),
                depositTime: block.timestamp,
                lastRewardTime: 0,
                totalRewardsWon: 0,
                participationStreak: 0,
                active: true,
                riskTolerance: userRiskTolerance,
                autoCompound: false
            });
            
            participantList.push(user);
            participantIndex[user] = participantList.length - 1;
        } else {
            // Existing participant - increase deposit
            participants[user].depositAmount += amount;
            participants[user].entryCount += _calculateEntries(amount);
        }
        
        totalDeposits += amount;
        totalEntries += _calculateEntries(amount);
        
        // Update user risk preference and loyalty
        userRiskPreference[user] = userRiskTolerance;
        loyaltyBonus[user] = _calculateLoyaltyBonus(user);
        
        emit ParticipantAdded(user, amount, participants[user].entryCount);
    }

    function removeParticipant(address user) external onlyRole(LOTTERY_MANAGER_ROLE) {
        require(participants[user].active, "User not active");
        
        Participant storage participant = participants[user];
        uint256 amount = participant.depositAmount;
        
        // Remove from participant list
        uint256 index = participantIndex[user];
        address lastParticipant = participantList[participantList.length - 1];
        participantList[index] = lastParticipant;
        participantIndex[lastParticipant] = index;
        participantList.pop();
        
        totalDeposits -= amount;
        totalEntries -= participant.entryCount;
        
        // Mark as inactive
        participant.active = false;
        
        emit ParticipantRemoved(user, amount);
    }

    // ============ ADVANCED LOTTERY DRAW SYSTEM ============

    function _initiateLotteryDraw() internal {
        require(currentPrizePool >= lotteryConfig.minPrizePool, "Insufficient prize pool");
        require(participantList.length > 0, "No participants");
        require(block.timestamp >= lastDrawTime + lotteryConfig.drawInterval, "Draw interval not met");

        currentDrawId++;
        
        // Request randomness from Etherlink
        bytes32 requestId = randomnessOracle.requestRandomness(300000); // 300k gas limit
        
        randomnessRequests[requestId] = currentDrawId;
        pendingRandomness[currentDrawId] = requestId;
        
        // Initialize draw structure
        lotteryDraws[currentDrawId] = LotteryDraw({
            drawId: currentDrawId,
            timestamp: block.timestamp,
            winner: address(0),
            prizeAmount: _calculateDynamicPrize(),
            totalParticipants: participantList.length,
            totalPrizePool: currentPrizePool,
            yieldGenerated: totalYieldGenerated,
            randomnessRequestId: requestId,
            randomSeed: bytes32(0),
            completed: false,
            gasUsed: 0,
            yieldSources: _getActiveYieldSourceNames()
        });
        
        emit RandomnessRequested(currentDrawId, requestId);
    }

    function completeLotteryDraw(bytes32 requestId, uint256 randomness) external {
        require(randomnessRequests[requestId] != 0, "Invalid request");
        
        uint256 drawId = randomnessRequests[requestId];
        LotteryDraw storage draw = lotteryDraws[drawId];
        
        require(!draw.completed, "Draw already completed");
        require(draw.randomnessRequestId == requestId, "Request mismatch");
        
        // Generate enhanced randomness
        bytes32 enhancedSeed = keccak256(abi.encodePacked(
            randomness,
            block.timestamp,
            block.prevrandao, // Updated from difficulty
            blockhash(block.number - 1),
            totalEntries,
            drawId
        ));
        
        // Select winner using fair algorithm
        address winner = _selectAdvancedWinner(enhancedSeed);
        
        // Calculate final prize with dynamic adjustments
        uint256 finalPrize = _calculateFinalPrize(draw.prizeAmount);
        
        // Distribute prizes and fees
        _distributePrizes(winner, finalPrize, drawId);
        
        // Update draw
        draw.winner = winner;
        draw.prizeAmount = finalPrize;
        draw.randomSeed = enhancedSeed;
        draw.completed = true;
        draw.gasUsed = gasleft();
        
        // Update participant stats
        participants[winner].totalRewardsWon += finalPrize;
        participants[winner].lastRewardTime = block.timestamp;
        participants[winner].participationStreak++;
        
        // Update global stats
        lastDrawTime = block.timestamp;
        
        // Update metrics
        metrics.totalPrizesDistributed += finalPrize;
        metrics.averagePrizeAmount = metrics.totalPrizesDistributed / currentDrawId;
        
        emit LotteryDrawCompleted(drawId, winner, finalPrize, draw.totalParticipants, enhancedSeed);
    }

    function _selectAdvancedWinner(bytes32 seed) internal view returns (address) {
        uint256 totalWeightedEntries = 0;
        
        // Calculate total weighted entries (considering loyalty bonuses)
        for (uint i = 0; i < participantList.length; i++) {
            address participant = participantList[i];
            if (participants[participant].active) {
                uint256 baseEntries = participants[participant].entryCount;
                uint256 loyaltyMultiplier = loyaltyBonus[participant];
                totalWeightedEntries += (baseEntries * loyaltyMultiplier) / 10000;
            }
        }
        
        uint256 winningNumber = uint256(seed) % totalWeightedEntries;
        uint256 currentSum = 0;
        
        // Find winner using weighted selection
        for (uint i = 0; i < participantList.length; i++) {
            address participant = participantList[i];
            if (participants[participant].active) {
                uint256 baseEntries = participants[participant].entryCount;
                uint256 loyaltyMultiplier = loyaltyBonus[participant];
                uint256 weightedEntries = (baseEntries * loyaltyMultiplier) / 10000;
                
                currentSum += weightedEntries;
                if (winningNumber < currentSum) {
                    return participant;
                }
            }
        }
        
        // Fallback to first participant
        return participantList[0];
    }

    // ============ YIELD OPTIMIZATION ============

    function _optimizeYieldAllocation(uint256 newAmount, uint256 riskTolerance) internal {
        uint256 totalAmount = currentPrizePool + newAmount;
        
        try yieldAggregator.calculateOptimalAllocation(
            address(asset),
            totalAmount,
            riskTolerance
        ) returns (
            IYieldAggregator.OptimizedAllocation[] memory allocations,
            uint256 totalExpectedAPY,
            uint256 totalRisk,
            uint256 gasEstimate
        ) {
            // Extract protocols and amounts from allocations
            address[] memory protocols = new address[](allocations.length);
            uint256[] memory amounts = new uint256[](allocations.length);
            
            for (uint256 i = 0; i < allocations.length; i++) {
                protocols[i] = allocations[i].protocol;
                amounts[i] = allocations[i].amount;
            }
            
            // Rebalance based on optimal allocation
            _rebalanceYieldSources(protocols, amounts, totalExpectedAPY);
        } catch {
            // Fallback: just add to prize pool
            currentPrizePool += newAmount;
        }
    }

    function _rebalanceYieldSources(
        address[] memory protocols,
        uint256[] memory amounts,
        uint256 expectedAPY
    ) internal {
        // Simplified rebalancing - in production this would be more sophisticated
        for (uint i = 0; i < protocols.length && i < 5; i++) {
            if (amounts[i] > 0) {
                bytes32 sourceId = keccak256(abi.encodePacked(protocols[i], uint16(101))); // Default to Ethereum
                
                // Update or create yield source
                if (yieldSources[sourceId].protocol == address(0)) {
                    yieldSources[sourceId] = YieldSource({
                        protocol: protocols[i],
                        chainId: 101, // Default chain
                        allocation: amounts[i],
                        currentAPY: expectedAPY,
                        yieldGenerated: 0,
                        lastHarvest: block.timestamp,
                        active: true,
                        name: "optimal_strategy"
                    });
                    activeYieldSources.push(sourceId);
                } else {
                    yieldSources[sourceId].allocation = amounts[i];
                    yieldSources[sourceId].currentAPY = expectedAPY;
                }
            }
        }
        
        lastRebalance = block.timestamp;
        emit YieldRebalanced(totalYieldAllocated, totalYieldAllocated + amounts[0], expectedAPY);
    }

    function _harvestFromSource(bytes32 sourceId) internal returns (uint256 harvested) {
        YieldSource storage source = yieldSources[sourceId];
        
        // Simulate harvest - in production this would interact with actual protocols
        uint256 timeSinceLastHarvest = block.timestamp - source.lastHarvest;
        uint256 annualizedReturn = (source.allocation * source.currentAPY) / 10000;
        harvested = (annualizedReturn * timeSinceLastHarvest) / 365 days;
        
        if (harvested > 0) {
            source.yieldGenerated += harvested;
            source.lastHarvest = block.timestamp;
            
            emit YieldHarvested(sourceId, harvested, source.currentAPY);
        }
    }

    function _emergencyHarvestFromSource(bytes32 sourceId) external {
        require(msg.sender == address(this), "Internal only");
        YieldSource storage source = yieldSources[sourceId];
        source.active = false;
        // Emergency harvest logic would go here
    }

    // ============ HELPER FUNCTIONS ============

    function _calculateEntries(uint256 amount) internal pure returns (uint256) {
        // Each 1 USDC = 1 entry, with bonuses for larger deposits
        uint256 baseEntries = amount / 1e6; // Assuming 6 decimals for USDC
        
        // Bonus entries for larger deposits (quadratic scaling)
        if (amount >= 1000 * 1e6) { // 1000+ USDC
            return baseEntries + (baseEntries / 10); // 10% bonus
        } else if (amount >= 100 * 1e6) { // 100+ USDC
            return baseEntries + (baseEntries / 20); // 5% bonus
        }
        
        return baseEntries;
    }

    function _calculateLoyaltyBonus(address user) internal view returns (uint256) {
        Participant memory participant = participants[user];
        
        // Base multiplier is 10000 (100%)
        uint256 multiplier = 10000;
        
        // Bonus for participation streak
        if (participant.participationStreak >= 10) {
            multiplier += 1000; // 10% bonus for 10+ weeks
        } else if (participant.participationStreak >= 5) {
            multiplier += 500; // 5% bonus for 5+ weeks
        }
        
        // Bonus for large deposits
        if (participant.depositAmount >= 10000 * 1e6) { // 10K+ USDC
            multiplier += 500; // 5% bonus
        }
        
        return multiplier;
    }

    function _calculateDynamicPrize() internal view returns (uint256) {
        if (!lotteryConfig.dynamicPrizes) {
            return currentPrizePool;
        }
        
        // Adjust prize based on participation and market conditions
        uint256 basePrize = currentPrizePool;
        uint256 participationBonus = (participantList.length * 100) / lotteryConfig.maxParticipants; // 0-100%
        uint256 volatilityAdjustment = (lotteryConfig.volatilityMultiplier * basePrize) / 10000;
        
        return basePrize + (basePrize * participationBonus / 10000) + volatilityAdjustment;
    }

    function _calculateFinalPrize(uint256 basePrize) internal view returns (uint256) {
        // Apply fees
        uint256 totalFees = lotteryConfig.devFee + lotteryConfig.nextPrizeFee + lotteryConfig.burnFee;
        return (basePrize * (10000 - totalFees)) / 10000;
    }

    function _distributePrizes(address winner, uint256 prizeAmount, uint256 drawId) internal {
        // Transfer prize to winner
        asset.safeTransfer(winner, prizeAmount);
        
        // Handle fees
        uint256 devFeeAmount = (currentPrizePool * lotteryConfig.devFee) / 10000;
        uint256 nextPrizeFeeAmount = (currentPrizePool * lotteryConfig.nextPrizeFee) / 10000;
        
        // Update prize pool
        currentPrizePool = currentPrizePool - prizeAmount - devFeeAmount;
        currentPrizePool += nextPrizeFeeAmount; // Add to next lottery
    }

    function _shouldTriggerDraw() internal view returns (bool) {
        return currentPrizePool >= lotteryConfig.minPrizePool &&
               participantList.length > 0 &&
               block.timestamp >= lastDrawTime + lotteryConfig.drawInterval &&
               !lotteryConfig.emergencyMode;
    }

    function _updateAdvancedMetrics() internal {
        metrics.totalYieldGenerated = totalYieldGenerated;
        metrics.participationRate = (participantList.length * 10000) / lotteryConfig.maxParticipants;
        
        // Calculate yield efficiency (yield per gas)
        if (metrics.totalYieldGenerated > 0) {
            metrics.yieldEfficiency = metrics.totalYieldGenerated / (gasleft() + 1);
        }
        
        metrics.lastAnalysis = block.timestamp;
        
        emit AdvancedMetricsUpdated(metrics.totalYieldGenerated, metrics.yieldEfficiency, metrics.fairnessScore);
    }

    function _getActiveYieldSourceNames() internal view returns (string memory) {
        // Simplified - in production would concatenate actual source names
        return "multi_source_yield";
    }

    // ============ VIEW FUNCTIONS ============

    function getParticipant(address user) external view returns (Participant memory) {
        return participants[user];
    }

    function getLotteryDraw(uint256 drawId) external view returns (LotteryDraw memory) {
        return lotteryDraws[drawId];
    }

    function getYieldSource(bytes32 sourceId) external view returns (YieldSource memory) {
        return yieldSources[sourceId];
    }

    function getActiveYieldSources() external view returns (bytes32[] memory) {
        return activeYieldSources;
    }

    function getAdvancedMetrics() external view returns (AdvancedMetrics memory) {
        return metrics;
    }

    function getLotteryConfig() external view returns (LotteryConfig memory) {
        return lotteryConfig;
    }

    function getTotalStats() external view returns (
        uint256 totalDeposits_,
        uint256 totalEntries_,
        uint256 currentPrizePool_,
        uint256 totalYieldGenerated_,
        uint256 totalParticipants,
        uint256 currentDrawId_
    ) {
        return (
            totalDeposits,
            totalEntries,
            currentPrizePool,
            totalYieldGenerated,
            participantList.length,
            currentDrawId
        );
    }

    // ============ ADMIN FUNCTIONS ============

    function setLotteryConfig(
        uint256 drawInterval,
        uint256 minPrizePool,
        uint256 maxParticipants,
        uint256 entryFee,
        uint256 devFee,
        uint256 nextPrizeFee,
        bool dynamicPrizes
    ) external onlyRole(LOTTERY_MANAGER_ROLE) {
        lotteryConfig.drawInterval = drawInterval;
        lotteryConfig.minPrizePool = minPrizePool;
        lotteryConfig.maxParticipants = maxParticipants;
        lotteryConfig.entryFee = entryFee;
        lotteryConfig.devFee = devFee;
        lotteryConfig.nextPrizeFee = nextPrizeFee;
        lotteryConfig.dynamicPrizes = dynamicPrizes;
    }

    function setYieldAggregator(address _yieldAggregator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_yieldAggregator != address(0), "Invalid aggregator");
        yieldAggregator = IYieldAggregator(_yieldAggregator);
    }

    function addPythonAgent(address agent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PYTHON_AGENT_ROLE, agent);
    }

    function withdrawGasReserve(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(this).balance >= amount, "Insufficient balance");
        payable(msg.sender).transfer(amount);
    }

    // Receive function for gas reserves
    receive() external payable {
        // Accept ETH for gas reserves
    }
}