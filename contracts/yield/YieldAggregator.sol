// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRiskOracle {
    function getRiskAssessment(address protocol) external view returns (
        uint256 riskScore,
        uint256 confidenceLevel,
        string memory riskLevel,
        uint256 timestamp,
        address assessor,
        bytes32 dataHash,
        bool valid,
        uint256 expiryTime,
        bool isValid
    );
    
    function assessStrategyRisk(address strategy) external view returns (
        uint256 riskScore,
        string memory riskLevel,
        bool approved,
        uint256 maxRecommendedAmount
    );
}

interface IStrategyRegistry {
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
    );
}

/// @title YieldAggregator - Advanced Multi-Chain Yield Optimization
/// @notice Sophisticated yield aggregator with ML-powered optimization and risk management
/// @dev Integrates with RiskOracle, StrategyRegistry, and Python ML agents for maximum yield
contract YieldAggregator is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant PYTHON_AGENT_ROLE = keccak256("PYTHON_AGENT_ROLE");
    bytes32 public constant STRATEGY_EXECUTOR_ROLE = keccak256("STRATEGY_EXECUTOR_ROLE");

    // ============ SOPHISTICATED YIELD TRACKING ============

    struct YieldOpportunity {
        address protocol;
        uint16 chainId;
        address asset;
        uint256 currentAPY; // Current APY in basis points
        uint256 historicalAPY; // 30-day average APY
        uint256 riskScore; // From RiskOracle
        uint256 tvl; // Total value locked
        uint256 availableCapacity; // How much more can be deposited
        uint256 liquidityDepth; // How liquid is the strategy
        uint256 impermanentLossRisk; // For LP strategies
        uint256 slippageEstimate; // Expected slippage for large deposits
        uint256 withdrawalTime; // Time to withdraw (for locked strategies)
        uint256 gasOptimizationScore; // Gas efficiency score
        bool crossChainRequired; // Whether bridging is needed
        bool active; // Whether strategy is currently available
        uint256 lastUpdate;
        bytes strategyData; // Strategy-specific parameters
    }

    struct OptimizedAllocation {
        address protocol;
        uint16 chainId;
        uint256 amount;
        uint256 expectedAPY;
        uint256 riskScore;
        uint256 allocation; // Percentage of total (in basis points)
        uint256 gasEstimate;
        bool requiresBridge;
        bytes executionData;
    }

    struct YieldPerformanceMetrics {
        uint256 totalYieldGenerated;
        uint256 totalGasCosts;
        uint256 netYield; // Yield minus gas costs
        uint256 bestAPY;
        uint256 worstAPY;
        uint256 averageAPY;
        uint256 sharpeRatio; // Risk-adjusted return
        uint256 maxDrawdown;
        uint256 successfulRebalances;
        uint256 failedRebalances;
        uint256 lastCalculation;
    }

    struct MarketConditions {
        uint256 volatilityIndex; // Overall market volatility
        uint256 liquidityIndex; // Overall market liquidity
        uint256 riskSentiment; // Market risk sentiment (0-10000)
        uint256 yieldTrend; // Increasing, stable, or decreasing yields
        uint256 gasPrice; // Current gas price
        bool marketStress; // Whether markets are in stress
        uint256 lastUpdate;
    }

    // Core state
    IRiskOracle public riskOracle;
    IStrategyRegistry public strategyRegistry;
    
    // Yield opportunities tracking
    mapping(bytes32 => YieldOpportunity) public yieldOpportunities; // keccak256(protocol, chainId, asset) => opportunity
    bytes32[] public activeOpportunities;
    mapping(address => bytes32[]) public opportunitiesByAsset;
    mapping(uint16 => bytes32[]) public opportunitiesByChain;
    
    // Performance tracking
    mapping(address => YieldPerformanceMetrics) public assetPerformance;
    YieldPerformanceMetrics public globalPerformance;
    
    // Market conditions
    MarketConditions public marketConditions;
    
    // Advanced optimization parameters
    struct OptimizationConfig {
        uint256 maxRiskTolerance; // Maximum acceptable risk score
        uint256 minYieldThreshold; // Minimum APY to consider (basis points)
        uint256 rebalanceThreshold; // Yield difference to trigger rebalance (basis points)
        uint256 maxGasPercentage; // Maximum gas cost as % of yield (basis points)
        uint256 diversificationTarget; // Target number of strategies
        uint256 maxSingleAllocation; // Max allocation to single strategy (basis points)
        bool allowCrossChain; // Whether to use cross-chain strategies
        bool enableAutoRebalancing; // Automatic rebalancing
        uint256 rebalanceInterval; // Minimum time between rebalances
        uint256 emergencyExitThreshold; // Risk score that triggers emergency exit
    }
    
    OptimizationConfig public optimizationConfig;
    
    // Yield prediction and ML integration
    mapping(bytes32 => uint256) public predictedAPY; // ML predictions for next 24h
    mapping(bytes32 => uint256) public yieldVolatility; // Yield volatility score
    mapping(bytes32 => uint256) public liquidityScore; // Liquidity score
    mapping(bytes32 => uint256) public correlationScore; // Correlation with other assets
    
    // Advanced yield sources
    mapping(address => bool) public approvedYieldSources;
    mapping(bytes32 => uint256) public compoundingFrequency; // How often yields compound
    mapping(bytes32 => uint256) public yieldPersistence; // How long yields typically last
    
    // Events
    event YieldOpportunityAdded(bytes32 indexed opportunityId, address protocol, uint16 chainId, uint256 apy);
    event YieldOpportunityUpdated(bytes32 indexed opportunityId, uint256 newAPY, uint256 riskScore);
    event OptimalAllocationCalculated(uint256 totalAmount, uint256 expectedAPY, uint256 strategiesUsed);
    event YieldRebalanced(address indexed asset, uint256 oldAPY, uint256 newAPY, uint256 gasCost);
    event EmergencyExit(bytes32 indexed opportunityId, uint256 riskScore, uint256 amountExited);
    event MarketConditionsUpdated(uint256 volatility, uint256 liquidity, bool stress);
    event PerformanceMetricsUpdated(address indexed asset, uint256 totalYield, uint256 sharpeRatio);

    constructor(
        address _riskOracle,
        address _strategyRegistry
    ) {
        require(_riskOracle != address(0), "Invalid risk oracle");
        require(_strategyRegistry != address(0), "Invalid strategy registry");

        riskOracle = IRiskOracle(_riskOracle);
        strategyRegistry = IStrategyRegistry(_strategyRegistry);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(YIELD_MANAGER_ROLE, msg.sender);

        // Initialize with conservative settings
        optimizationConfig = OptimizationConfig({
            maxRiskTolerance: 6000, // 60%
            minYieldThreshold: 100, // 1%
            rebalanceThreshold: 500, // 5%
            maxGasPercentage: 1000, // 10%
            diversificationTarget: 3,
            maxSingleAllocation: 4000, // 40%
            allowCrossChain: true,
            enableAutoRebalancing: false, // Start with manual rebalancing
            rebalanceInterval: 4 hours,
            emergencyExitThreshold: 8000 // 80%
        });
    }

    // ============ YIELD OPPORTUNITY MANAGEMENT ============

    function addYieldOpportunity(
        address protocol,
        uint16 chainId,
        address asset,
        uint256 currentAPY,
        uint256 tvl,
        uint256 availableCapacity,
        uint256 liquidityDepth,
        uint256 withdrawalTime,
        bool crossChainRequired,
        bytes calldata strategyData
    ) external onlyRole(YIELD_MANAGER_ROLE) {
        bytes32 opportunityId = keccak256(abi.encodePacked(protocol, chainId, asset));
        
        // Get risk assessment from oracle
        (uint256 riskScore, string memory riskLevel, bool approved,) = 
            riskOracle.assessStrategyRisk(protocol);

        yieldOpportunities[opportunityId] = YieldOpportunity({
            protocol: protocol,
            chainId: chainId,
            asset: asset,
            currentAPY: currentAPY,
            historicalAPY: currentAPY, // Initialize with current APY
            riskScore: riskScore,
            tvl: tvl,
            availableCapacity: availableCapacity,
            liquidityDepth: liquidityDepth,
            impermanentLossRisk: 0, // To be calculated
            slippageEstimate: 0, // To be calculated
            withdrawalTime: withdrawalTime,
            gasOptimizationScore: 0, // To be calculated
            crossChainRequired: crossChainRequired,
            active: approved && riskScore <= optimizationConfig.maxRiskTolerance,
            lastUpdate: block.timestamp,
            strategyData: strategyData
        });

        if (yieldOpportunities[opportunityId].active) {
            activeOpportunities.push(opportunityId);
            opportunitiesByAsset[asset].push(opportunityId);
            opportunitiesByChain[chainId].push(opportunityId);
        }

        emit YieldOpportunityAdded(opportunityId, protocol, chainId, currentAPY);
    }

    function updateYieldOpportunity(
        bytes32 opportunityId,
        uint256 newAPY,
        uint256 newTVL,
        uint256 newCapacity,
        uint256 newLiquidity
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        YieldOpportunity storage opportunity = yieldOpportunities[opportunityId];
        require(opportunity.protocol != address(0), "Opportunity not found");

        // Update historical APY (30-day moving average)
        opportunity.historicalAPY = (opportunity.historicalAPY * 29 + newAPY) / 30;
        opportunity.currentAPY = newAPY;
        opportunity.tvl = newTVL;
        opportunity.availableCapacity = newCapacity;
        opportunity.liquidityDepth = newLiquidity;
        opportunity.lastUpdate = block.timestamp;

        // Update risk assessment
        (uint256 riskScore,, bool approved,) = riskOracle.assessStrategyRisk(opportunity.protocol);
        opportunity.riskScore = riskScore;
        opportunity.active = approved && riskScore <= optimizationConfig.maxRiskTolerance;

        emit YieldOpportunityUpdated(opportunityId, newAPY, riskScore);
    }

    function batchUpdateYieldOpportunities(
        bytes32[] calldata opportunityIds,
        uint256[] calldata newAPYs,
        uint256[] calldata newTVLs,
        uint256[] calldata newCapacities
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        require(opportunityIds.length == newAPYs.length, "Array length mismatch");
        require(opportunityIds.length == newTVLs.length, "Array length mismatch");
        require(opportunityIds.length == newCapacities.length, "Array length mismatch");

        for (uint i = 0; i < opportunityIds.length; i++) {
            this.updateYieldOpportunity(
                opportunityIds[i],
                newAPYs[i],
                newTVLs[i],
                newCapacities[i],
                0 // Default liquidity
            );
        }
    }

    // ============ ADVANCED YIELD OPTIMIZATION ============

    function calculateOptimalAllocation(
        address asset,
        uint256 totalAmount,
        uint256 maxRiskTolerance
    ) external view returns (
        OptimizedAllocation[] memory allocations,
        uint256 totalExpectedAPY,
        uint256 totalRisk,
        uint256 gasEstimate
    ) {
        bytes32[] memory assetOpportunities = opportunitiesByAsset[asset];
        
        // Filter opportunities by risk tolerance and minimum yield
        uint256 validCount = 0;
        for (uint i = 0; i < assetOpportunities.length; i++) {
            YieldOpportunity memory opp = yieldOpportunities[assetOpportunities[i]];
            if (opp.active && 
                opp.riskScore <= maxRiskTolerance && 
                opp.currentAPY >= optimizationConfig.minYieldThreshold) {
                validCount++;
            }
        }

        if (validCount == 0) {
            return (new OptimizedAllocation[](0), 0, 0, 0);
        }

        // Create allocations array
        allocations = new OptimizedAllocation[](validCount);
        uint256 index = 0;

        // Apply modern portfolio theory with risk-adjusted returns
        uint256 remainingAmount = totalAmount;
        uint256 totalWeight = 0;

        // First pass: calculate weights based on risk-adjusted returns
        for (uint i = 0; i < assetOpportunities.length && index < validCount; i++) {
            YieldOpportunity memory opp = yieldOpportunities[assetOpportunities[i]];
            
            if (opp.active && 
                opp.riskScore <= maxRiskTolerance && 
                opp.currentAPY >= optimizationConfig.minYieldThreshold) {
                
                // Calculate risk-adjusted return (Sharpe-like ratio)
                uint256 riskAdjustedReturn = (opp.currentAPY * 10000) / (opp.riskScore + 1000);
                
                // Apply capacity constraints
                uint256 maxAllocation = opp.availableCapacity < totalAmount ? opp.availableCapacity : totalAmount;
                maxAllocation = (maxAllocation * optimizationConfig.maxSingleAllocation) / 10000;
                
                // Apply liquidity scoring
                uint256 liquidityBonus = opp.liquidityDepth > 1000000 * 1e18 ? 110 : 100; // 10% bonus for deep liquidity
                riskAdjustedReturn = (riskAdjustedReturn * liquidityBonus) / 100;
                
                allocations[index] = OptimizedAllocation({
                    protocol: opp.protocol,
                    chainId: opp.chainId,
                    amount: 0, // To be calculated
                    expectedAPY: opp.currentAPY,
                    riskScore: opp.riskScore,
                    allocation: riskAdjustedReturn, // Temporary store weight
                    gasEstimate: _estimateGasForStrategy(opp),
                    requiresBridge: opp.crossChainRequired,
                    executionData: opp.strategyData
                });
                
                totalWeight += riskAdjustedReturn;
                index++;
            }
        }

        // Second pass: calculate actual allocations
        uint256 allocatedAmount = 0;
        for (uint i = 0; i < allocations.length; i++) {
            if (i == allocations.length - 1) {
                // Last allocation gets remaining amount
                allocations[i].amount = remainingAmount - allocatedAmount;
            } else {
                allocations[i].amount = (totalAmount * allocations[i].allocation) / totalWeight;
                allocatedAmount += allocations[i].amount;
            }
            
            // Update allocation percentage
            allocations[i].allocation = (allocations[i].amount * 10000) / totalAmount;
            
            // Calculate contribution to total expected APY
            totalExpectedAPY += (allocations[i].expectedAPY * allocations[i].allocation) / 10000;
            
            // Calculate weighted risk
            totalRisk += (allocations[i].riskScore * allocations[i].allocation) / 10000;
            
            // Add to total gas estimate
            gasEstimate += allocations[i].gasEstimate;
        }
    }

    function getTopYieldOpportunities(
        address asset,
        uint256 maxRiskTolerance,
        uint256 count
    ) external view returns (YieldOpportunity[] memory opportunities) {
        bytes32[] memory assetOpportunities = opportunitiesByAsset[asset];
        
        // Create array of valid opportunities
        uint256 validCount = 0;
        for (uint i = 0; i < assetOpportunities.length; i++) {
            YieldOpportunity memory opp = yieldOpportunities[assetOpportunities[i]];
            if (opp.active && opp.riskScore <= maxRiskTolerance) {
                validCount++;
            }
        }
        
        if (validCount == 0) {
            return new YieldOpportunity[](0);
        }
        
        uint256 returnCount = validCount < count ? validCount : count;
        opportunities = new YieldOpportunity[](returnCount);
        
        // Simple selection of top opportunities (could be enhanced with sorting)
        uint256 index = 0;
        for (uint i = 0; i < assetOpportunities.length && index < returnCount; i++) {
            YieldOpportunity memory opp = yieldOpportunities[assetOpportunities[i]];
            if (opp.active && opp.riskScore <= maxRiskTolerance) {
                opportunities[index] = opp;
                index++;
            }
        }
    }

    function shouldRebalance(address asset) external view returns (
        bool shouldRebalance_,
        uint256 currentAPY,
        uint256 potentialAPY,
        uint256 improvementBps
    ) {
        // Get current allocation performance
        YieldPerformanceMetrics memory performance = assetPerformance[asset];
        currentAPY = performance.averageAPY;
        
        // Calculate potential optimal APY
        (OptimizedAllocation[] memory allocations, uint256 optimalAPY,,) = 
            this.calculateOptimalAllocation(asset, 1000000 * 1e18, optimizationConfig.maxRiskTolerance); // Use 1M as reference
        
        potentialAPY = optimalAPY;
        
        if (potentialAPY > currentAPY) {
            improvementBps = potentialAPY - currentAPY;
            shouldRebalance_ = improvementBps >= optimizationConfig.rebalanceThreshold;
        }
    }

    // ============ MARKET CONDITIONS & ANALYTICS ============

    function updateMarketConditions(
        uint256 volatilityIndex,
        uint256 liquidityIndex,
        uint256 riskSentiment,
        uint256 yieldTrend,
        bool marketStress
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        marketConditions = MarketConditions({
            volatilityIndex: volatilityIndex,
            liquidityIndex: liquidityIndex,
            riskSentiment: riskSentiment,
            yieldTrend: yieldTrend,
            gasPrice: tx.gasprice,
            marketStress: marketStress,
            lastUpdate: block.timestamp
        });
        
        // Adjust optimization parameters based on market conditions
        if (marketStress) {
            // In stress conditions, be more conservative
            optimizationConfig.maxRiskTolerance = optimizationConfig.maxRiskTolerance * 80 / 100; // Reduce by 20%
            optimizationConfig.diversificationTarget = optimizationConfig.diversificationTarget + 1; // More diversification
        }
        
        emit MarketConditionsUpdated(volatilityIndex, liquidityIndex, marketStress);
    }

    function updatePerformanceMetrics(
        address asset,
        uint256 totalYieldGenerated,
        uint256 totalGasCosts,
        uint256 successfulRebalances,
        uint256 failedRebalances
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        YieldPerformanceMetrics storage metrics = assetPerformance[asset];
        
        metrics.totalYieldGenerated = totalYieldGenerated;
        metrics.totalGasCosts = totalGasCosts;
        metrics.netYield = totalYieldGenerated > totalGasCosts ? totalYieldGenerated - totalGasCosts : 0;
        metrics.successfulRebalances = successfulRebalances;
        metrics.failedRebalances = failedRebalances;
        metrics.lastCalculation = block.timestamp;
        
        // Calculate Sharpe ratio (simplified)
        if (metrics.totalYieldGenerated > 0) {
            metrics.sharpeRatio = (metrics.netYield * 10000) / metrics.totalYieldGenerated;
        }
        
        emit PerformanceMetricsUpdated(asset, totalYieldGenerated, metrics.sharpeRatio);
    }

    // ============ INTERNAL FUNCTIONS ============

    function _estimateGasForStrategy(YieldOpportunity memory opportunity) internal pure returns (uint256) {
        uint256 baseGas = 200000; // Base gas for strategy execution
        
        if (opportunity.crossChainRequired) {
            baseGas += 500000; // Additional gas for cross-chain
        }
        
        // Add gas based on complexity
        if (opportunity.strategyData.length > 0) {
            baseGas += 100000; // Additional gas for complex strategies
        }
        
        return baseGas;
    }

    // ============ ADMIN FUNCTIONS ============

    function setOptimizationConfig(
        uint256 maxRiskTolerance,
        uint256 minYieldThreshold,
        uint256 rebalanceThreshold,
        uint256 maxGasPercentage,
        uint256 diversificationTarget,
        uint256 maxSingleAllocation,
        bool allowCrossChain,
        bool enableAutoRebalancing,
        uint256 rebalanceInterval
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        optimizationConfig = OptimizationConfig({
            maxRiskTolerance: maxRiskTolerance,
            minYieldThreshold: minYieldThreshold,
            rebalanceThreshold: rebalanceThreshold,
            maxGasPercentage: maxGasPercentage,
            diversificationTarget: diversificationTarget,
            maxSingleAllocation: maxSingleAllocation,
            allowCrossChain: allowCrossChain,
            enableAutoRebalancing: enableAutoRebalancing,
            rebalanceInterval: rebalanceInterval,
            emergencyExitThreshold: optimizationConfig.emergencyExitThreshold // Preserve existing value
        });
    }

    function setRiskOracle(address _riskOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_riskOracle != address(0), "Invalid risk oracle");
        riskOracle = IRiskOracle(_riskOracle);
    }

    function setStrategyRegistry(address _strategyRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_strategyRegistry != address(0), "Invalid strategy registry");
        strategyRegistry = IStrategyRegistry(_strategyRegistry);
    }

    function addPythonAgent(address agent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PYTHON_AGENT_ROLE, agent);
    }

    // ============ VIEW FUNCTIONS ============

    function getYieldOpportunity(bytes32 opportunityId) external view returns (YieldOpportunity memory) {
        return yieldOpportunities[opportunityId];
    }

    function getActiveOpportunities() external view returns (bytes32[] memory) {
        return activeOpportunities;
    }

    function getOpportunitiesByAsset(address asset) external view returns (bytes32[] memory) {
        return opportunitiesByAsset[asset];
    }

    function getOpportunitiesByChain(uint16 chainId) external view returns (bytes32[] memory) {
        return opportunitiesByChain[chainId];
    }

    function getPerformanceMetrics(address asset) external view returns (YieldPerformanceMetrics memory) {
        return assetPerformance[asset];
    }

    function getGlobalPerformance() external view returns (YieldPerformanceMetrics memory) {
        return globalPerformance;
    }

    function getMarketConditions() external view returns (MarketConditions memory) {
        return marketConditions;
    }

    function getOptimizationConfig() external view returns (OptimizationConfig memory) {
        return optimizationConfig;
    }
}