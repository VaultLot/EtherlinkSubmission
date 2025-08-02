// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title RealProtocolStrategyRegistry
/// @notice Enhanced registry for managing real DeFi protocol strategies with risk scoring
/// @dev Integrates with Python ML risk assessment and real protocol data
contract RealProtocolStrategyRegistry is AccessControl, ReentrancyGuard {
    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant RISK_ORACLE_ROLE = keccak256("RISK_ORACLE_ROLE");
    bytes32 public constant PYTHON_AGENT_ROLE = keccak256("PYTHON_AGENT_ROLE");

    struct StrategyInfo {
        address strategyAddress;
        uint16 chainId;
        string name; // "superlend_usdc", "pancake_usdc_eth", etc.
        string protocol; // "superlend", "pancakeswap", "compound", etc.
        address protocolContract; // Main protocol contract address
        uint256 currentAPY; // In basis points
        uint256 riskScore; // 0-10000 (from your Python risk model)
        uint256 tvl; // Total value locked in USD (6 decimals)
        uint256 maxCapacity; // Maximum amount this strategy can handle
        uint256 minDeposit; // Minimum deposit amount
        bool active;
        bool crossChainEnabled;
        uint256 lastUpdate;
        bytes strategyData; // Additional strategy-specific data
        // Real protocol specific fields
        uint256 protocolTVL; // Protocol's total TVL
        uint256 liquidityRating; // Liquidity depth rating (0-10000)
        uint256 auditScore; // Security audit score (0-10000)
        address[] underlyingTokens; // Tokens involved in the strategy
    }

    struct ChainInfo {
        uint16 chainId;
        string name; // "ethereum", "arbitrum", "polygon", "etherlink"
        address bridgeContract;
        bool active;
        uint256 bridgeFee;
        uint256 averageBlockTime;
        uint256 gasPrice; // Current gas price in wei
        uint256 protocolCount; // Number of protocols on this chain
    }

    struct RealTimeMetrics {
        uint256 timestamp;
        uint256 apy; // Current APY from real data
        uint256 volume24h; // 24h volume in USD
        uint256 tvlChange24h; // TVL change in last 24h (basis points)
        uint256 volatility; // Price volatility score
        uint256 liquidityDepth; // Available liquidity
        bool anomalyDetected; // ML-detected anomaly
        bytes32 dataSource; // Source of the data (e.g., "defillama", "coingecko")
    }

    struct ProtocolIntegration {
        string protocolName;
        address mainContract;
        string contractType; // "lending", "dex", "farming", "staking"
        address[] supportedTokens;
        uint256[] poolIds; // For protocols with multiple pools
        bool verified; // Whether integration is verified
        uint256 integrationDate;
        string apiEndpoint; // For fetching real-time data
    }

    // Core mappings
    mapping(bytes32 => StrategyInfo) public strategies; // keccak256(name + chainId) => strategy
    mapping(string => bytes32[]) public strategiesByName;
    mapping(uint16 => bytes32[]) public strategiesByChain;
    mapping(address => bytes32) public strategyByAddress;
    mapping(string => ProtocolIntegration) public protocolIntegrations;

    // Real-time data
    mapping(bytes32 => RealTimeMetrics) public realTimeMetrics;
    mapping(bytes32 => uint256[]) public apyHistory; // Last 30 days
    mapping(bytes32 => uint256) public lastDataUpdate;

    // Chain management
    mapping(uint16 => ChainInfo) public chains;
    uint16[] public supportedChains;

    // Risk and performance tracking
    mapping(bytes32 => uint256) public performanceScore; // 0-10000
    mapping(bytes32 => uint256) public cumulativeReturns;
    mapping(bytes32 => uint256) public maxDrawdown;
    mapping(bytes32 => uint256) public sharpeRatio;

    // Protocol-specific configurations
    uint16 public constant ETHERLINK_CHAIN_ID = 30302; // Changed from uint256 to uint16
    uint256 public dataFreshnessThreshold = 1 hours; // Max age for real-time data
    uint256 public minTVLForListing = 100000 * 10**6; // $100K minimum TVL
    uint256 public maxRiskScore = 7000; // 70% max risk for auto-approval

    // Real protocol addresses
    struct KnownProtocols {
        address superlendPool;
        address pancakeFactory;
        address pancakeRouter;
        address aaveOracle;
        address aclManager;
    }

    KnownProtocols public knownProtocols;

    event StrategyRegistered(bytes32 indexed strategyHash, string name, uint16 chainId, address strategy);
    event RealTimeDataUpdated(bytes32 indexed strategyHash, uint256 apy, uint256 tvl, uint256 timestamp);
    event ProtocolIntegrationAdded(string indexed protocolName, address mainContract, string contractType);
    event AnomalyDetected(bytes32 indexed strategyHash, string anomalyType, uint256 severity);
    event StrategyRiskUpdated(bytes32 indexed strategyHash, uint256 oldRisk, uint256 newRisk);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_MANAGER_ROLE, msg.sender);
        _grantRole(RISK_ORACLE_ROLE, msg.sender);

        // Initialize known protocol addresses
        knownProtocols = KnownProtocols({
            superlendPool: 0x5e580E0FF1981E7c916D6D9a036A8596E35fCE31,
            pancakeFactory: 0xfaAdaeBdcc60A2FeC900285516F4882930Db8Ee8,
            pancakeRouter: 0x8a7bBf269B95875FC1829901bb2c815029d8442e,
            aaveOracle: 0xE06cda30A2d4714fECE928b36497b8462A21d79a,
            aclManager: 0x3941BfFABA0db23934e67FD257cC6F724F0DDd23
        });

        // Initialize Etherlink chain
        _initializeEtherlinkChain();

        // Add known protocol integrations
        _initializeProtocolIntegrations();
    }

    function _initializeEtherlinkChain() internal {
        chains[ETHERLINK_CHAIN_ID] = ChainInfo({
            chainId: ETHERLINK_CHAIN_ID,
            name: "etherlink",
            bridgeContract: address(0), // To be set when bridge is deployed
            active: true,
            bridgeFee: 0,
            averageBlockTime: 15, // seconds
            gasPrice: 1 gwei,
            protocolCount: 0
        });
        supportedChains.push(ETHERLINK_CHAIN_ID);
    }

    function _initializeProtocolIntegrations() internal {
        // Superlend integration
        address[] memory superlendTokens = new address[](4);
        superlendTokens[0] = 0x744D7931B12E890b7b32A076a918B112B950B67d; // USDC aToken
        superlendTokens[1] = 0xc7DE9218466862ce30CC415eD6d5Af61Eb7FFD57; // XTZ aToken
        superlendTokens[2] = 0x71B27362B3be20Bbb91247d8CfCaB4dADfD0244A; // WBTC aToken
        superlendTokens[3] = 0xe0339800272c442dc031fF80Cd85ac4c17AB383e; // USDT aToken

        uint256[] memory emptyPools = new uint256[](0);

        protocolIntegrations["superlend"] = ProtocolIntegration({
            protocolName: "superlend",
            mainContract: knownProtocols.superlendPool,
            contractType: "lending",
            supportedTokens: superlendTokens,
            poolIds: emptyPools,
            verified: true,
            integrationDate: block.timestamp,
            apiEndpoint: "superlend_api" // To be used by Python agent
        });

        // PancakeSwap integration
        address[] memory pancakeTokens = new address[](2);
        pancakeTokens[0] = 0x79b1a1445e53fe7bC9063c0d54A531D1d2f814D7; // Position Manager
        pancakeTokens[1] = 0x8a7bBf269B95875FC1829901bb2c815029d8442e; // Smart Router

        protocolIntegrations["pancakeswap"] = ProtocolIntegration({
            protocolName: "pancakeswap",
            mainContract: knownProtocols.pancakeFactory,
            contractType: "dex",
            supportedTokens: pancakeTokens,
            poolIds: emptyPools,
            verified: true,
            integrationDate: block.timestamp,
            apiEndpoint: "pancakeswap_api"
        });
    }

    // ============ REAL PROTOCOL STRATEGY REGISTRATION ============

    function registerRealStrategy(
        string calldata name,
        uint16 chainId,
        address strategyAddress,
        string calldata protocol,
        address protocolContract,
        uint256 initialAPY,
        uint256 maxCapacity,
        uint256 minDeposit,
        address[] calldata underlyingTokens,
        bytes calldata strategyData
    ) external onlyRole(STRATEGY_MANAGER_ROLE) returns (bytes32 strategyHash) {
        strategyHash = keccak256(abi.encodePacked(name, chainId));

        require(strategies[strategyHash].strategyAddress == address(0), "Strategy already exists");
        require(chains[chainId].active, "Chain not supported");
        require(protocolIntegrations[protocol].verified, "Protocol not verified");

        strategies[strategyHash] = StrategyInfo({
            strategyAddress: strategyAddress,
            chainId: chainId,
            name: name,
            protocol: protocol,
            protocolContract: protocolContract,
            currentAPY: initialAPY,
            riskScore: 5000, // Default medium risk
            tvl: 0,
            maxCapacity: maxCapacity,
            minDeposit: minDeposit,
            active: true,
            crossChainEnabled: false, // Default to same-chain
            lastUpdate: block.timestamp,
            strategyData: strategyData,
            protocolTVL: 0, // To be updated by Python agent
            liquidityRating: 5000, // Default medium liquidity
            auditScore: 7000, // Default good audit score
            underlyingTokens: underlyingTokens
        });

        strategiesByName[name].push(strategyHash);
        strategiesByChain[chainId].push(strategyHash);
        strategyByAddress[strategyAddress] = strategyHash;

        emit StrategyRegistered(strategyHash, name, chainId, strategyAddress);
        return strategyHash;
    }

    // ============ REAL-TIME DATA UPDATES ============

    function updateRealTimeMetrics(
        bytes32 strategyHash,
        uint256 currentAPY,
        uint256 volume24h,
        uint256 tvlChange24h,
        uint256 volatility,
        uint256 liquidityDepth,
        bool anomalyDetected,
        bytes32 dataSource
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        require(strategies[strategyHash].strategyAddress != address(0), "Strategy not found");

        realTimeMetrics[strategyHash] = RealTimeMetrics({
            timestamp: block.timestamp,
            apy: currentAPY,
            volume24h: volume24h,
            tvlChange24h: tvlChange24h,
            volatility: volatility,
            liquidityDepth: liquidityDepth,
            anomalyDetected: anomalyDetected,
            dataSource: dataSource
        });

        // Update strategy APY
        strategies[strategyHash].currentAPY = currentAPY;
        strategies[strategyHash].lastUpdate = block.timestamp;

        // Store APY history (keep last 30 entries)
        uint256[] storage history = apyHistory[strategyHash];
        if (history.length >= 30) {
            for (uint i = 0; i < 29; i++) {
                history[i] = history[i + 1];
            }
            history[29] = currentAPY;
        } else {
            history.push(currentAPY);
        }

        lastDataUpdate[strategyHash] = block.timestamp;

        if (anomalyDetected) {
            emit AnomalyDetected(strategyHash, "METRICS_ANOMALY", volatility);
        }

        emit RealTimeDataUpdated(strategyHash, currentAPY, volume24h, block.timestamp);
    }

    function batchUpdateMetrics(
        bytes32[] calldata strategyHashes,
        uint256[] calldata apys,
        uint256[] calldata volumes,
        uint256[] calldata tvlChanges
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        require(strategyHashes.length == apys.length, "Array length mismatch");

        for (uint i = 0; i < strategyHashes.length; i++) {
            this.updateRealTimeMetrics(
                strategyHashes[i],
                apys[i],
                volumes[i],
                tvlChanges[i],
                0, // Default volatility
                0, // Default liquidity depth
                false, // No anomaly by default
                "batch_update"
            );
        }
    }

    // ============ ENHANCED STRATEGY SELECTION ============

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

        uint256 bestScore = 0;
        bestStrategy = bytes32(0);

        for (uint i = 0; i < candidates.length; i++) {
            bytes32 candidateHash = candidates[i];
            StrategyInfo memory strategy = strategies[candidateHash];
            RealTimeMetrics memory metrics = realTimeMetrics[candidateHash];

            // Skip if data is stale
            if (block.timestamp - metrics.timestamp > dataFreshnessThreshold) {
                continue;
            }

            // Calculate composite score based on multiple factors
            uint256 apyScore = strategy.currentAPY; // Higher APY = better
            uint256 riskAdjustment = (10000 - strategy.riskScore) / 10; // Lower risk = better
            uint256 liquidityBonus = strategy.liquidityRating / 100; // Higher liquidity = better
            uint256 auditBonus = strategy.auditScore / 100; // Better audit = better

            // Chain preference bonus
            uint256 chainBonus = strategy.chainId == preferredChain ? 500 : 0;

            // Real-time metrics bonus
            uint256 volumeBonus = metrics.volume24h > 1000000 * 10**6 ? 200 : 0; // $1M+ volume
            uint256 volatilityPenalty = metrics.volatility > 2000 ? 500 : 0; // High volatility penalty

            uint256 totalScore = apyScore + riskAdjustment + liquidityBonus + auditBonus + chainBonus + volumeBonus - volatilityPenalty;

            if (totalScore > bestScore) {
                bestScore = totalScore;
                bestStrategy = candidateHash;
            }
        }

        if (bestStrategy != bytes32(0)) {
            StrategyInfo memory selected = strategies[bestStrategy];
            return (
                bestStrategy,
                selected.currentAPY,
                selected.riskScore,
                selected.chainId != preferredChain
            );
        }

        return (bytes32(0), 0, 0, false);
    }

    function getTopStrategiesByProtocol(
        string calldata protocolName,
        uint256 maxRiskTolerance,
        uint256 count
    ) external view returns (
        bytes32[] memory topStrategies,
        uint256[] memory apys,
        uint256[] memory riskScores,
        uint256[] memory tvls
    ) {
        // Get all strategies for this protocol
        bytes32[] memory allStrategies = _getStrategiesByProtocol(protocolName);

        // Filter by risk tolerance and get top performers
        uint256 validCount = 0;
        for (uint i = 0; i < allStrategies.length; i++) {
            StrategyInfo memory strategy = strategies[allStrategies[i]];
            if (strategy.active && strategy.riskScore <= maxRiskTolerance) {
                validCount++;
            }
        }

        uint256 returnCount = validCount < count ? validCount : count;
        topStrategies = new bytes32[](returnCount);
        apys = new uint256[](returnCount);
        riskScores = new uint256[](returnCount);
        tvls = new uint256[](returnCount);

        uint256 index = 0;
        for (uint i = 0; i < allStrategies.length && index < returnCount; i++) {
            StrategyInfo memory strategy = strategies[allStrategies[i]];
            if (strategy.active && strategy.riskScore <= maxRiskTolerance) {
                topStrategies[index] = allStrategies[i];
                apys[index] = strategy.currentAPY;
                riskScores[index] = strategy.riskScore;
                tvls[index] = strategy.tvl;
                index++;
            }
        }
    }

    // ============ PROTOCOL-SPECIFIC ANALYTICS ============

    function getProtocolAnalytics(string calldata protocolName) external view returns (
        uint256 totalTVL,
        uint256 averageAPY,
        uint256 strategyCount,
        uint256 averageRisk,
        bool hasAnomalies,
        uint256 liquidityRating
    ) {
        bytes32[] memory protocolStrategies = _getStrategiesByProtocol(protocolName);

        if (protocolStrategies.length == 0) {
            return (0, 0, 0, 0, false, 0);
        }

        uint256 totalAPY = 0;
        uint256 totalRisk = 0;
        uint256 totalLiquidity = 0;

        for (uint i = 0; i < protocolStrategies.length; i++) {
            StrategyInfo memory strategy = strategies[protocolStrategies[i]];
            RealTimeMetrics memory metrics = realTimeMetrics[protocolStrategies[i]];

            if (strategy.active) {
                totalTVL += strategy.tvl;
                totalAPY += strategy.currentAPY;
                totalRisk += strategy.riskScore;
                totalLiquidity += strategy.liquidityRating;

                if (metrics.anomalyDetected) {
                    hasAnomalies = true;
                }
            }
        }

        strategyCount = protocolStrategies.length;
        averageAPY = strategyCount > 0 ? totalAPY / strategyCount : 0;
        averageRisk = strategyCount > 0 ? totalRisk / strategyCount : 0;
        liquidityRating = strategyCount > 0 ? totalLiquidity / strategyCount : 0;
    }

    function getChainAnalytics(uint16 chainId) external view returns (
        uint256 totalStrategies,
        uint256 activeStrategies,
        uint256 totalTVL,
        uint256 averageAPY,
        uint256 averageRisk
    ) {
        bytes32[] memory chainStrategies = strategiesByChain[chainId];

        uint256 activeCount = 0;
        uint256 totalAPY = 0;
        uint256 totalRisk = 0;

        for (uint i = 0; i < chainStrategies.length; i++) {
            StrategyInfo memory strategy = strategies[chainStrategies[i]];

            if (strategy.active) {
                activeCount++;
                totalTVL += strategy.tvl;
                totalAPY += strategy.currentAPY;
                totalRisk += strategy.riskScore;
            }
        }

        totalStrategies = chainStrategies.length;
        activeStrategies = activeCount;
        averageAPY = activeCount > 0 ? totalAPY / activeCount : 0;
        averageRisk = activeCount > 0 ? totalRisk / activeCount : 0;
    }

    // ============ INTERNAL HELPER FUNCTIONS ============

    function _getEligibleStrategies(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool crossChainAllowed
    ) internal view returns (bytes32[] memory eligible) {
        uint256 count = 0;

        // Count eligible strategies
        for (uint i = 0; i < supportedChains.length; i++) {
            if (!crossChainAllowed && supportedChains[i] != ETHERLINK_CHAIN_ID) continue;

            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                StrategyInfo memory strategy = strategies[chainStrategies[j]];
                RealTimeMetrics memory metrics = realTimeMetrics[chainStrategies[j]];

                bool isDataFresh = block.timestamp - metrics.timestamp <= dataFreshnessThreshold;

                if (strategy.active && 
                    strategy.riskScore <= maxRiskTolerance &&
                    (amount == 0 || amount >= strategy.minDeposit) &&
                    (strategy.maxCapacity == 0 || strategy.tvl + amount <= strategy.maxCapacity) &&
                    isDataFresh &&
                    !metrics.anomalyDetected) {
                    count++;
                }
            }
        }

        eligible = new bytes32[](count);
        uint256 index = 0;

        // Populate eligible strategies
        for (uint i = 0; i < supportedChains.length; i++) {
            if (!crossChainAllowed && supportedChains[i] != ETHERLINK_CHAIN_ID) continue;

            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                StrategyInfo memory strategy = strategies[chainStrategies[j]];
                RealTimeMetrics memory metrics = realTimeMetrics[chainStrategies[j]];

                bool isDataFresh = block.timestamp - metrics.timestamp <= dataFreshnessThreshold;

                if (strategy.active && 
                    strategy.riskScore <= maxRiskTolerance &&
                    (amount == 0 || amount >= strategy.minDeposit) &&
                    (strategy.maxCapacity == 0 || strategy.tvl + amount <= strategy.maxCapacity) &&
                    isDataFresh &&
                    !metrics.anomalyDetected) {
                    eligible[index] = chainStrategies[j];
                    index++;
                }
            }
        }
    }

    function _getStrategiesByProtocol(string calldata protocolName) internal view returns (bytes32[] memory) {
        uint256 count = 0;

        // Count strategies for this protocol
        for (uint i = 0; i < supportedChains.length; i++) {
            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                if (keccak256(bytes(strategies[chainStrategies[j]].protocol)) == keccak256(bytes(protocolName))) {
                    count++;
                }
            }
        }

        bytes32[] memory result = new bytes32[](count);
        uint256 index = 0;

        // Populate result
        for (uint i = 0; i < supportedChains.length; i++) {
            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                if (keccak256(bytes(strategies[chainStrategies[j]].protocol)) == keccak256(bytes(protocolName))) {
                    result[index] = chainStrategies[j];
                    index++;
                }
            }
        }

        return result;
    }

    // ============ VIEW FUNCTIONS FOR PYTHON AGENT ============

    function getStrategyByName(string calldata name, uint16 chainId) external view returns (
        address strategyAddress,
        uint16 chainId_,
        string memory name_,
        string memory protocol,
        uint256 currentAPY,
        uint256 riskScore,
        uint256 tvl,
        uint256 maxCapacity,
        uint256 minDeposit,
        bool active,
        bool crossChainEnabled,
        uint256 lastUpdate,
        bytes memory strategyData
    ) {
        bytes32 hash = keccak256(abi.encodePacked(name, chainId));
        StrategyInfo memory strategy = strategies[hash];
        
        return (
            strategy.strategyAddress,
            strategy.chainId,
            strategy.name,
            strategy.protocol,
            strategy.currentAPY,
            strategy.riskScore,
            strategy.tvl,
            strategy.maxCapacity,
            strategy.minDeposit,
            strategy.active,
            strategy.crossChainEnabled,
            strategy.lastUpdate,
            strategy.strategyData
        );
    }

    function getStrategyRealTimeMetrics(bytes32 strategyHash) external view returns (RealTimeMetrics memory) {
        return realTimeMetrics[strategyHash];
    }

    function getStrategyAPYHistory(bytes32 strategyHash) external view returns (uint256[] memory) {
        return apyHistory[strategyHash];
    }

    function getAllActiveStrategies() external view returns (bytes32[] memory activeStrategies) {
        uint256 count = 0;

        // Count active strategies
        for (uint i = 0; i < supportedChains.length; i++) {
            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                if (strategies[chainStrategies[j]].active) {
                    count++;
                }
            }
        }

        activeStrategies = new bytes32[](count);
        uint256 index = 0;

        // Populate active strategies
        for (uint i = 0; i < supportedChains.length; i++) {
            bytes32[] memory chainStrategies = strategiesByChain[supportedChains[i]];
            for (uint j = 0; j < chainStrategies.length; j++) {
                if (strategies[chainStrategies[j]].active) {
                    activeStrategies[index] = chainStrategies[j];
                    index++;
                }
            }
        }
    }

    function isDataFresh(bytes32 strategyHash) external view returns (bool) {
        return block.timestamp - lastDataUpdate[strategyHash] <= dataFreshnessThreshold;
    }

    // ============ ADMIN FUNCTIONS ============

    function addPythonAgent(address pythonAgent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PYTHON_AGENT_ROLE, pythonAgent);
    }

    function updateProtocolContract(string calldata protocolName, address newContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolIntegrations[protocolName].mainContract = newContract;
    }

    function setDataFreshnessThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dataFreshnessThreshold = newThreshold;
    }

    function emergencyPauseStrategy(bytes32 strategyHash) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategies[strategyHash].active = false;
    }

    function emergencyPauseProtocol(string calldata protocolName) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32[] memory protocolStrategies = _getStrategiesByProtocol(protocolName);
        for (uint i = 0; i < protocolStrategies.length; i++) {
            strategies[protocolStrategies[i]].active = false;
        }
    }
}