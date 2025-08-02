// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title StrategyRegistry
/// @notice Advanced registry for managing cross-chain DeFi strategies with risk scoring
/// @dev Integrates with Python ML risk assessment for optimal yield strategy selection
contract StrategyRegistry is AccessControl, ReentrancyGuard {
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant RISK_ORACLE_ROLE = keccak256("RISK_ORACLE_ROLE");
    bytes32 public constant PYTHON_AGENT_ROLE = keccak256("PYTHON_AGENT_ROLE");

    struct StrategyInfo {
        address strategyAddress;
        uint16 chainId;
        string name; // "aave", "compound", "increment", etc.
        string protocol; // "lending", "dex", "staking", "lottery"
        uint256 currentAPY; // In basis points
        uint256 riskScore; // 0-10000 (from your Python risk model)
        uint256 tvl; // Total value locked
        uint256 maxCapacity; // Maximum amount this strategy can handle
        uint256 minDeposit; // Minimum deposit amount
        bool active;
        bool crossChainEnabled;
        uint256 lastUpdate;
        bytes strategyData; // Additional strategy-specific data
    }

    struct ChainInfo {
        uint16 chainId;
        string name; // "ethereum", "arbitrum", "polygon", "etherlink"
        address bridgeContract;
        bool active;
        uint256 bridgeFee;
        uint256 averageBlockTime;
    }

    struct RiskAssessment {
        uint256 riskScore;
        uint256 confidenceLevel;
        uint256 lastAssessment;
        string riskLevel; // "LOW", "MEDIUM", "HIGH"
        address assessor; // Python agent address
        bytes assessmentData;
    }

    // Strategy mappings
    mapping(bytes32 => StrategyInfo) public strategies; // keccak256(name + chainId) => strategy
    mapping(string => bytes32[]) public strategiesByName; // "aave" => [ethereum_aave, arbitrum_aave]
    mapping(uint16 => bytes32[]) public strategiesByChain; // chainId => strategy hashes
    mapping(address => bytes32) public strategyByAddress; // strategy address => hash
    
    // Chain management
    mapping(uint16 => ChainInfo) public chains;
    uint16[] public supportedChains;
    
    // Risk assessments
    mapping(bytes32 => RiskAssessment) public riskAssessments;
    mapping(address => bool) public trustedRiskOracles; // Your Python risk model

    // Performance tracking
    mapping(bytes32 => uint256[]) public performanceHistory; // Last 30 days APY
    mapping(bytes32 => uint256) public cumulativeReturns;
    
    // Cross-chain optimization
    mapping(uint16 => uint256) public chainUtilization; // How much capital is on each chain
    uint256 public totalManagedCapital;
    uint256 public targetDiversification = 3000; // 30% max per chain

    event StrategyRegistered(bytes32 indexed strategyHash, string name, uint16 chainId, address strategy);
    event StrategyUpdated(bytes32 indexed strategyHash, uint256 apy, uint256 riskScore);
    event RiskAssessmentUpdated(bytes32 indexed strategyHash, uint256 riskScore, string riskLevel);
    event CrossChainRebalancing(uint16 fromChain, uint16 toChain, uint256 amount);
    event OptimalStrategySelected(bytes32 indexed strategyHash, string reason);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_MANAGER_ROLE, msg.sender);
        _grantRole(RISK_ORACLE_ROLE, msg.sender);
    }

    // ============ STRATEGY REGISTRATION ============

    function registerStrategy(
        string calldata name,
        uint16 chainId,
        address strategyAddress,
        string calldata protocol,
        uint256 initialAPY,
        uint256 maxCapacity,
        uint256 minDeposit,
        bool crossChainEnabled,
        bytes calldata strategyData
    ) external onlyRole(STRATEGY_MANAGER_ROLE) returns (bytes32 strategyHash) {
        strategyHash = keccak256(abi.encodePacked(name, chainId));
        
        require(strategies[strategyHash].strategyAddress == address(0), "Strategy already exists");
        require(chains[chainId].active, "Chain not supported");

        strategies[strategyHash] = StrategyInfo({
            strategyAddress: strategyAddress,
            chainId: chainId,
            name: name,
            protocol: protocol,
            currentAPY: initialAPY,
            riskScore: 5000, // Default medium risk
            tvl: 0,
            maxCapacity: maxCapacity,
            minDeposit: minDeposit,
            active: true,
            crossChainEnabled: crossChainEnabled,
            lastUpdate: block.timestamp,
            strategyData: strategyData
        });

        strategiesByName[name].push(strategyHash);
        strategiesByChain[chainId].push(strategyHash);
        strategyByAddress[strategyAddress] = strategyHash;

        emit StrategyRegistered(strategyHash, name, chainId, strategyAddress);
        return strategyHash;
    }

    function registerChain(
        uint16 chainId,
        string calldata name,
        address bridgeContract,
        uint256 bridgeFee,
        uint256 averageBlockTime
    ) external onlyRole(STRATEGY_MANAGER_ROLE) {
        if (!chains[chainId].active) {
            supportedChains.push(chainId);
        }

        chains[chainId] = ChainInfo({
            chainId: chainId,
            name: name,
            bridgeContract: bridgeContract,
            active: true,
            bridgeFee: bridgeFee,
            averageBlockTime: averageBlockTime
        });
    }

    // ============ PYTHON AGENT INTEGRATION ============

    function updateRiskAssessment(
        bytes32 strategyHash,
        uint256 riskScore,
        uint256 confidenceLevel,
        string calldata riskLevel,
        bytes calldata assessmentData
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        require(strategies[strategyHash].strategyAddress != address(0), "Strategy not found");
        
        strategies[strategyHash].riskScore = riskScore;
        strategies[strategyHash].lastUpdate = block.timestamp;

        riskAssessments[strategyHash] = RiskAssessment({
            riskScore: riskScore,
            confidenceLevel: confidenceLevel,
            lastAssessment: block.timestamp,
            riskLevel: riskLevel,
            assessor: msg.sender,
            assessmentData: assessmentData
        });

        emit RiskAssessmentUpdated(strategyHash, riskScore, riskLevel);
    }

    function updateStrategyPerformance(
        bytes32 strategyHash,
        uint256 newAPY,
        uint256 newTVL
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        require(strategies[strategyHash].strategyAddress != address(0), "Strategy not found");
        
        // Store historical APY (keep last 30 entries)
        if (performanceHistory[strategyHash].length >= 30) {
            // Remove oldest entry
            for (uint i = 0; i < 29; i++) {
                performanceHistory[strategyHash][i] = performanceHistory[strategyHash][i + 1];
            }
            performanceHistory[strategyHash][29] = newAPY;
        } else {
            performanceHistory[strategyHash].push(newAPY);
        }

        strategies[strategyHash].currentAPY = newAPY;
        strategies[strategyHash].tvl = newTVL;
        strategies[strategyHash].lastUpdate = block.timestamp;

        emit StrategyUpdated(strategyHash, newAPY, strategies[strategyHash].riskScore);
    }

    // ============ OPTIMAL STRATEGY SELECTION ============

    function getOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool crossChainAllowed,
        uint16 preferredChain
    ) external view returns (
        bytes32 bestStrategy,
        uint256 expectedReturn,
        uint256 riskScore,
        bool requiresBridge
    ) {
        bytes32[] memory candidates = _getEligibleStrategies(amount, maxRiskTolerance, crossChainAllowed);
        
        if (candidates.length == 0) {
            return (bytes32(0), 0, 0, false);
        }

        uint256 bestRiskAdjustedReturn = 0;
        bestStrategy = bytes32(0);

        for (uint i = 0; i < candidates.length; i++) {
            StrategyInfo memory strategy = strategies[candidates[i]];
            
            // Calculate risk-adjusted return
            uint256 riskAdjustedAPY = strategy.currentAPY * (10000 - strategy.riskScore) / 10000;
            
            // Apply chain preference bonus
            if (strategy.chainId == preferredChain) {
                riskAdjustedAPY = riskAdjustedAPY * 110 / 100; // 10% bonus for same chain
            }

            // Apply diversification bonus if chain is under-utilized
            uint256 chainUtil = chainUtilization[strategy.chainId] * 10000 / totalManagedCapital;
            if (chainUtil < targetDiversification) {
                riskAdjustedAPY = riskAdjustedAPY * 105 / 100; // 5% bonus for diversification
            }

            if (riskAdjustedAPY > bestRiskAdjustedReturn) {
                bestRiskAdjustedReturn = riskAdjustedAPY;
                bestStrategy = candidates[i];
            }
        }

        if (bestStrategy != bytes32(0)) {
            StrategyInfo memory selected = strategies[bestStrategy];
            return (
                bestStrategy,
                bestRiskAdjustedReturn,
                selected.riskScore,
                selected.chainId != preferredChain
            );
        }

        return (bytes32(0), 0, 0, false);
    }

    function getMultiStrategyAllocation(
        uint256 totalAmount,
        uint256 maxRiskTolerance,
        uint256 diversificationTargets
    ) external view returns (
        bytes32[] memory selectedStrategies,
        uint256[] memory allocations,
        uint256 totalExpectedReturn
    ) {
        bytes32[] memory candidates = _getEligibleStrategies(0, maxRiskTolerance, true);
        
        if (candidates.length == 0) {
            return (new bytes32[](0), new uint256[](0), 0);
        }

        // Limit to top strategies for diversification
        uint256 maxStrategies = candidates.length > diversificationTargets ? diversificationTargets : candidates.length;
        selectedStrategies = new bytes32[](maxStrategies);
        allocations = new uint256[](maxStrategies);

        // Sort by risk-adjusted returns
        bytes32[] memory sortedCandidates = _sortStrategiesByRiskAdjustedReturn(candidates);

        uint256 remainingAmount = totalAmount;
        totalExpectedReturn = 0;

        for (uint i = 0; i < maxStrategies && i < sortedCandidates.length; i++) {
            selectedStrategies[i] = sortedCandidates[i];
            
            // Allocate based on capacity and diversification
            StrategyInfo memory strategy = strategies[sortedCandidates[i]];
            uint256 maxAllocation = strategy.maxCapacity > 0 ? strategy.maxCapacity : remainingAmount;
            uint256 diversificationLimit = totalAmount / diversificationTargets;
            
            uint256 allocation = maxAllocation < diversificationLimit ? maxAllocation : diversificationLimit;
            allocation = allocation < remainingAmount ? allocation : remainingAmount;
            
            allocations[i] = allocation;
            remainingAmount -= allocation;
            
            // Calculate expected return
            uint256 riskAdjustedReturn = strategy.currentAPY * (10000 - strategy.riskScore) / 10000;
            totalExpectedReturn += (allocation * riskAdjustedReturn) / totalAmount;

            if (remainingAmount == 0) break;
        }

        return (selectedStrategies, allocations, totalExpectedReturn);
    }

    // ============ CROSS-CHAIN OPTIMIZATION ============

    function getOptimalChainAllocation() external view returns (
        uint16[] memory chains_,
        uint256[] memory targetAllocations,
        uint256[] memory currentAllocations
    ) {
        chains_ = supportedChains;
        targetAllocations = new uint256[](chains_.length);
        currentAllocations = new uint256[](chains_.length);

        for (uint i = 0; i < chains_.length; i++) {
            currentAllocations[i] = chainUtilization[chains_[i]];
            
            // Calculate target allocation based on best opportunities
            uint256 chainScore = _calculateChainScore(chains_[i]);
            targetAllocations[i] = (totalManagedCapital * chainScore) / 10000;
        }
    }

    function shouldRebalanceAcrossChains() external view returns (
        bool needsRebalancing,
        uint16 fromChain,
        uint16 toChain,
        uint256 amount
    ) {
        uint256 maxImbalance = 0;
        
        for (uint i = 0; i < supportedChains.length; i++) {
            for (uint j = i + 1; j < supportedChains.length; j++) {
                uint16 chain1 = supportedChains[i];
                uint16 chain2 = supportedChains[j];
                
                uint256 util1 = chainUtilization[chain1] * 10000 / totalManagedCapital;
                uint256 util2 = chainUtilization[chain2] * 10000 / totalManagedCapital;
                
                uint256 imbalance = util1 > util2 ? util1 - util2 : util2 - util1;
                
                if (imbalance > maxImbalance && imbalance > 1500) { // 15% imbalance threshold
                    maxImbalance = imbalance;
                    fromChain = util1 > util2 ? chain1 : chain2;
                    toChain = util1 > util2 ? chain2 : chain1;
                    amount = (imbalance * totalManagedCapital) / (2 * 10000); // Move half the imbalance
                    needsRebalancing = true;
                }
            }
        }
    }

    // ============ INTERNAL FUNCTIONS ============

    function _getEligibleStrategies(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool crossChainAllowed
    ) internal view returns (bytes32[] memory eligible) {
        uint256 count = 0;
        
        // Count eligible strategies
        for (uint i = 0; i < supportedChains.length; i++) {
            if (!crossChainAllowed && supportedChains[i] != block.chainid) continue;
            
            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                StrategyInfo memory strategy = strategies[chainStrategies[j]];
                if (strategy.active && 
                    strategy.riskScore <= maxRiskTolerance &&
                    (amount == 0 || amount >= strategy.minDeposit) &&
                    (strategy.maxCapacity == 0 || strategy.tvl + amount <= strategy.maxCapacity)) {
                    count++;
                }
            }
        }

        eligible = new bytes32[](count);
        uint256 index = 0;

        // Populate eligible strategies
        for (uint i = 0; i < supportedChains.length; i++) {
            if (!crossChainAllowed && supportedChains[i] != block.chainid) continue;
            
            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                StrategyInfo memory strategy = strategies[chainStrategies[j]];
                if (strategy.active && 
                    strategy.riskScore <= maxRiskTolerance &&
                    (amount == 0 || amount >= strategy.minDeposit) &&
                    (strategy.maxCapacity == 0 || strategy.tvl + amount <= strategy.maxCapacity)) {
                    eligible[index] = chainStrategies[j];
                    index++;
                }
            }
        }
    }

    function _sortStrategiesByRiskAdjustedReturn(bytes32[] memory candidates) 
        internal view returns (bytes32[] memory sorted) {
        sorted = candidates;
        
        // Simple bubble sort for risk-adjusted returns
        for (uint i = 0; i < sorted.length; i++) {
            for (uint j = i + 1; j < sorted.length; j++) {
                StrategyInfo memory strategyI = strategies[sorted[i]];
                StrategyInfo memory strategyJ = strategies[sorted[j]];
                
                uint256 returnI = strategyI.currentAPY * (10000 - strategyI.riskScore) / 10000;
                uint256 returnJ = strategyJ.currentAPY * (10000 - strategyJ.riskScore) / 10000;
                
                if (returnI < returnJ) {
                    bytes32 temp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = temp;
                }
            }
        }
    }

    function _calculateChainScore(uint16 chainId) internal view returns (uint256 score) {
        bytes32[] memory chainStrategies = strategiesByChain[chainId];
        uint256 totalWeight = 0;
        uint256 weightedScore = 0;

        for (uint i = 0; i < chainStrategies.length; i++) {
            StrategyInfo memory strategy = strategies[chainStrategies[i]];
            if (strategy.active) {
                uint256 riskAdjustedReturn = strategy.currentAPY * (10000 - strategy.riskScore) / 10000;
                totalWeight += riskAdjustedReturn;
                weightedScore += riskAdjustedReturn * riskAdjustedReturn;
            }
        }

        return totalWeight > 0 ? weightedScore / totalWeight : 0;
    }

    // ============ VIEW FUNCTIONS FOR PYTHON AGENT ============

    function getStrategyByName(string calldata name, uint16 chainId) external view returns (StrategyInfo memory) {
        bytes32 hash = keccak256(abi.encodePacked(name, chainId));
        return strategies[hash];
    }

    function getAllStrategiesForChain(uint16 chainId) external view returns (StrategyInfo[] memory chainStrategies) {
        bytes32[] memory hashes = strategiesByChain[chainId];
        chainStrategies = new StrategyInfo[](hashes.length);
        
        for (uint i = 0; i < hashes.length; i++) {
            chainStrategies[i] = strategies[hashes[i]];
        }
    }

    function getStrategyPerformanceHistory(bytes32 strategyHash) external view returns (uint256[] memory) {
        return performanceHistory[strategyHash];
    }

    function addPythonAgent(address pythonAgent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PYTHON_AGENT_ROLE, pythonAgent);
        trustedRiskOracles[pythonAgent] = true;
    }
}