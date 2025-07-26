// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title RiskOracle - Advanced ML-Powered Risk Assessment
/// @notice Oracle that interfaces with Python ML models for real-time risk scoring
/// @dev Designed to integrate seamlessly with your Python risk assessment API
contract RiskOracle is AccessControl, ReentrancyGuard {
    bytes32 public constant RISK_ASSESSOR_ROLE = keccak256("RISK_ASSESSOR_ROLE");
    bytes32 public constant PYTHON_AGENT_ROLE = keccak256("PYTHON_AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    struct RiskAssessment {
        uint256 riskScore; // 0-10000 (0 = no risk, 10000 = maximum risk)
        uint256 confidenceLevel; // 0-10000 (confidence in the assessment)
        string riskLevel; // "LOW", "MEDIUM", "HIGH", "CRITICAL"
        uint256 timestamp;
        address assessor; // Python agent that provided the assessment
        bytes32 dataHash; // Hash of assessment data for verification
        bool valid;
        uint256 expiryTime;
    }

    struct ProtocolMetrics {
        uint256 tvl;
        uint256 utilizationRate;
        uint256 dailyVolume;
        uint256 liquidityDepth;
        uint256 volatilityScore;
        uint256 lastUpdate;
        bool anomalyDetected;
    }

    struct RiskFactors {
        uint256 smartContractRisk; // Audit scores, bug bounties, etc.
        uint256 liquidityRisk; // Liquidity depth and concentration
        uint256 marketRisk; // Price volatility and correlation
        uint256 operationalRisk; // Team, governance, regulatory
        uint256 technicalRisk; // Infrastructure, oracle, bridge risks
        uint256 composabilityRisk; // Interconnected protocol risks
        uint256 lastCalculation;
    }

    // Core risk data
    mapping(address => RiskAssessment) public currentRiskAssessments;
    mapping(address => RiskFactors) public protocolRiskFactors;
    mapping(address => ProtocolMetrics) public protocolMetrics;
    
    // Historical risk tracking
    mapping(address => uint256[]) public riskHistory; // Last 30 days
    mapping(address => mapping(uint256 => uint256)) public dailyRiskScores; // day => risk score
    
    // ML model integration
    mapping(address => bool) public trustedPythonAgents;
    mapping(bytes32 => bool) public processedAssessments; // Prevent replay attacks
    uint256 public assessmentValidityPeriod = 4 hours; // How long assessments remain valid
    
    // Emergency risk monitoring
    mapping(address => bool) public emergencyProtocols; // Protocols under emergency monitoring
    mapping(address => uint256) public emergencyThresholds; // Custom emergency thresholds per protocol
    uint256 public globalEmergencyThreshold = 8000; // 80% risk score triggers emergency
    
    // Aggregated risk metrics
    struct SystemRisk {
        uint256 averageRisk;
        uint256 maxRisk;
        uint256 riskTrend; // Increasing, stable, or decreasing
        uint256 protocolsAtRisk;
        uint256 totalValueAtRisk;
        uint256 lastUpdate;
    }
    
    SystemRisk public systemRisk;
    
    // Risk prediction and trends
    mapping(address => uint256) public predictedRisk24h; // ML prediction for next 24h
    mapping(address => uint256) public riskTrend; // 0=decreasing, 1=stable, 2=increasing
    
    // Events
    event RiskAssessmentUpdated(
        address indexed protocol,
        uint256 riskScore,
        string riskLevel,
        address indexed assessor,
        uint256 timestamp
    );
    
    event EmergencyRiskAlert(
        address indexed protocol,
        uint256 riskScore,
        string reason,
        uint256 timestamp
    );
    
    event AnomalyDetected(
        address indexed protocol,
        string anomalyType,
        uint256 severity,
        bytes32 dataHash
    );
    
    event SystemRiskUpdate(
        uint256 averageRisk,
        uint256 maxRisk,
        uint256 protocolsAtRisk,
        uint256 totalValueAtRisk
    );

    event PythonAgentUpdated(address indexed agent, bool trusted);
    event RiskModelVersionUpdated(string newVersion, bytes32 modelHash);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RISK_ASSESSOR_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }

    // ============ PYTHON AGENT INTEGRATION ============

    function updateRiskAssessment(
        address protocol,
        uint256 riskScore,
        uint256 confidenceLevel,
        string calldata riskLevel,
        bytes32 dataHash,
        bytes calldata mlModelData
    ) external onlyRole(PYTHON_AGENT_ROLE) nonReentrant {
        require(protocol != address(0), "Invalid protocol");
        require(riskScore <= 10000, "Invalid risk score");
        require(confidenceLevel <= 10000, "Invalid confidence");
        require(!processedAssessments[dataHash], "Assessment already processed");
        
        // Verify this is a trusted Python agent
        require(trustedPythonAgents[msg.sender], "Untrusted agent");
        
        // Store the assessment
        currentRiskAssessments[protocol] = RiskAssessment({
            riskScore: riskScore,
            confidenceLevel: confidenceLevel,
            riskLevel: riskLevel,
            timestamp: block.timestamp,
            assessor: msg.sender,
            dataHash: dataHash,
            valid: true,
            expiryTime: block.timestamp + assessmentValidityPeriod
        });
        
        // Mark as processed to prevent replay
        processedAssessments[dataHash] = true;
        
        // Update historical data
        _updateRiskHistory(protocol, riskScore);
        
        // Check for emergency conditions
        _checkEmergencyConditions(protocol, riskScore, riskLevel);
        
        // Update system-wide risk metrics
        _updateSystemRisk();
        
        emit RiskAssessmentUpdated(protocol, riskScore, riskLevel, msg.sender, block.timestamp);
    }

    function batchUpdateRiskAssessments(
        address[] calldata protocols,
        uint256[] calldata riskScores,
        uint256[] calldata confidenceLevels,
        string[] calldata riskLevels,
        bytes32[] calldata dataHashes
    ) external onlyRole(PYTHON_AGENT_ROLE) nonReentrant {
        require(protocols.length == riskScores.length, "Array length mismatch");
        require(protocols.length == confidenceLevels.length, "Array length mismatch");
        require(protocols.length == riskLevels.length, "Array length mismatch");
        require(protocols.length == dataHashes.length, "Array length mismatch");
        
        for (uint i = 0; i < protocols.length; i++) {
            if (protocols[i] != address(0) && 
                riskScores[i] <= 10000 && 
                confidenceLevels[i] <= 10000 &&
                !processedAssessments[dataHashes[i]]) {
                
                this.updateRiskAssessment(
                    protocols[i],
                    riskScores[i],
                    confidenceLevels[i],
                    riskLevels[i],
                    dataHashes[i],
                    ""
                );
            }
        }
    }

    function updateProtocolMetrics(
        address protocol,
        uint256 tvl,
        uint256 utilizationRate,
        uint256 dailyVolume,
        uint256 liquidityDepth,
        uint256 volatilityScore,
        bool anomalyDetected
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        protocolMetrics[protocol] = ProtocolMetrics({
            tvl: tvl,
            utilizationRate: utilizationRate,
            dailyVolume: dailyVolume,
            liquidityDepth: liquidityDepth,
            volatilityScore: volatilityScore,
            lastUpdate: block.timestamp,
            anomalyDetected: anomalyDetected
        });
        
        if (anomalyDetected) {
            emit AnomalyDetected(
                protocol,
                "METRICS_ANOMALY",
                volatilityScore,
                keccak256(abi.encodePacked(tvl, utilizationRate, dailyVolume))
            );
        }
    }

    function updateRiskFactors(
        address protocol,
        uint256 smartContractRisk,
        uint256 liquidityRisk,
        uint256 marketRisk,
        uint256 operationalRisk,
        uint256 technicalRisk,
        uint256 composabilityRisk
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        protocolRiskFactors[protocol] = RiskFactors({
            smartContractRisk: smartContractRisk,
            liquidityRisk: liquidityRisk,
            marketRisk: marketRisk,
            operationalRisk: operationalRisk,
            technicalRisk: technicalRisk,
            composabilityRisk: composabilityRisk,
            lastCalculation: block.timestamp
        });
    }

    function updateRiskPredictions(
        address protocol,
        uint256 predicted24hRisk,
        uint256 trend
    ) external onlyRole(PYTHON_AGENT_ROLE) {
        require(trend <= 2, "Invalid trend value");
        predictedRisk24h[protocol] = predicted24hRisk;
        riskTrend[protocol] = trend;
    }

    // ============ RISK ASSESSMENT FUNCTIONS ============

    function getRiskAssessment(address protocol) external view returns (RiskAssessment memory assessment, bool isValid) {
        assessment = currentRiskAssessments[protocol];
        isValid = assessment.valid && block.timestamp <= assessment.expiryTime;
        
        if (!isValid) {
            // Return a conservative default assessment
            assessment = RiskAssessment({
                riskScore: 5000, // 50% default risk
                confidenceLevel: 0,
                riskLevel: "UNKNOWN",
                timestamp: 0,
                assessor: address(0),
                dataHash: bytes32(0),
                valid: false,
                expiryTime: 0
            });
        }
    }

    function getDetailedRiskAnalysis(address protocol) external view returns (
        RiskAssessment memory currentRisk,
        RiskFactors memory factors,
        ProtocolMetrics memory metrics,
        uint256 prediction24h,
        uint256 trend,
        bool isEmergency
    ) {
        (currentRisk,) = this.getRiskAssessment(protocol);
        factors = protocolRiskFactors[protocol];
        metrics = protocolMetrics[protocol];
        prediction24h = predictedRisk24h[protocol];
        trend = riskTrend[protocol];
        isEmergency = emergencyProtocols[protocol] || currentRisk.riskScore > globalEmergencyThreshold;
    }

    function assessStrategyRisk(address strategy) external view returns (
        uint256 riskScore,
        string memory riskLevel,
        bool approved,
        uint256 maxRecommendedAmount
    ) {
        (RiskAssessment memory assessment, bool valid) = this.getRiskAssessment(strategy);
        
        if (!valid) {
            return (5000, "UNKNOWN", false, 0);
        }
        
        riskScore = assessment.riskScore;
        riskLevel = assessment.riskLevel;
        approved = riskScore < globalEmergencyThreshold;
        
        // Calculate max recommended amount based on risk and protocol metrics
        ProtocolMetrics memory metrics = protocolMetrics[strategy];
        
        if (approved && metrics.tvl > 0) {
            // Conservative allocation: lower risk = higher allocation
            uint256 riskAdjustedCapacity = (metrics.tvl * (10000 - riskScore)) / 10000;
            maxRecommendedAmount = riskAdjustedCapacity / 10; // Max 10% of risk-adjusted capacity
        } else {
            maxRecommendedAmount = 0;
        }
    }

    function performEmergencyRiskScan() external view returns (
        bool systemAtRisk,
        address[] memory highRiskProtocols,
        uint256[] memory riskScores,
        uint256 totalValueAtRisk
    ) {
        // Scan all assessed protocols for emergency conditions
        uint256 emergencyCount = 0;
        
        // Count emergency protocols (simplified approach)
        // In practice, you'd iterate through all known protocols
        address[] memory allProtocols = new address[](0); // Would be populated from a registry
        
        for (uint i = 0; i < allProtocols.length; i++) {
            (RiskAssessment memory assessment,) = this.getRiskAssessment(allProtocols[i]);
            if (assessment.riskScore > globalEmergencyThreshold) {
                emergencyCount++;
                totalValueAtRisk += protocolMetrics[allProtocols[i]].tvl;
            }
        }
        
        systemAtRisk = emergencyCount > 0 || systemRisk.averageRisk > 6000;
        
        // Populate arrays with emergency protocols
        highRiskProtocols = new address[](emergencyCount);
        riskScores = new uint256[](emergencyCount);
        
        uint256 index = 0;
        for (uint i = 0; i < allProtocols.length && index < emergencyCount; i++) {
            (RiskAssessment memory assessment,) = this.getRiskAssessment(allProtocols[i]);
            if (assessment.riskScore > globalEmergencyThreshold) {
                highRiskProtocols[index] = allProtocols[i];
                riskScores[index] = assessment.riskScore;
                index++;
            }
        }
    }

    // ============ INTERNAL FUNCTIONS ============

    function _updateRiskHistory(address protocol, uint256 riskScore) internal {
        uint256[] storage history = riskHistory[protocol];
        
        // Keep last 30 entries
        if (history.length >= 30) {
            for (uint i = 0; i < 29; i++) {
                history[i] = history[i + 1];
            }
            history[29] = riskScore;
        } else {
            history.push(riskScore);
        }
        
        // Store daily risk score
        uint256 today = block.timestamp / 1 days;
        dailyRiskScores[protocol][today] = riskScore;
    }

    function _checkEmergencyConditions(address protocol, uint256 riskScore, string memory riskLevel) internal {
        uint256 threshold = emergencyThresholds[protocol] > 0 ? emergencyThresholds[protocol] : globalEmergencyThreshold;
        
        if (riskScore > threshold) {
            emergencyProtocols[protocol] = true;
            emit EmergencyRiskAlert(protocol, riskScore, riskLevel, block.timestamp);
        } else if (emergencyProtocols[protocol] && riskScore < threshold - 500) { // Hysteresis
            emergencyProtocols[protocol] = false;
        }
    }

    function _updateSystemRisk() internal {
        // Simplified system risk calculation
        // In practice, this would aggregate across all known protocols
        systemRisk.lastUpdate = block.timestamp;
        emit SystemRiskUpdate(
            systemRisk.averageRisk,
            systemRisk.maxRisk,
            systemRisk.protocolsAtRisk,
            systemRisk.totalValueAtRisk
        );
    }

    // ============ ADMIN FUNCTIONS ============

    function addPythonAgent(address agent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(agent != address(0), "Invalid agent");
        trustedPythonAgents[agent] = true;
        _grantRole(PYTHON_AGENT_ROLE, agent);
        emit PythonAgentUpdated(agent, true);
    }

    function removePythonAgent(address agent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedPythonAgents[agent] = false;
        _revokeRole(PYTHON_AGENT_ROLE, agent);
        emit PythonAgentUpdated(agent, false);
    }

    function setGlobalEmergencyThreshold(uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(threshold <= 10000, "Invalid threshold");
        globalEmergencyThreshold = threshold;
    }

    function setProtocolEmergencyThreshold(address protocol, uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(threshold <= 10000, "Invalid threshold");
        emergencyThresholds[protocol] = threshold;
    }

    function setAssessmentValidityPeriod(uint256 period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(period >= 1 hours && period <= 24 hours, "Invalid period");
        assessmentValidityPeriod = period;
    }

    function clearEmergencyStatus(address protocol) external onlyRole(EMERGENCY_ROLE) {
        emergencyProtocols[protocol] = false;
    }

    // ============ VIEW FUNCTIONS ============

    function getRiskHistory(address protocol) external view returns (uint256[] memory) {
        return riskHistory[protocol];
    }

    function getDailyRiskScore(address protocol, uint256 day) external view returns (uint256) {
        return dailyRiskScores[protocol][day];
    }

    function isEmergencyProtocol(address protocol) external view returns (bool) {
        return emergencyProtocols[protocol];
    }

    function getSystemRisk() external view returns (SystemRisk memory) {
        return systemRisk;
    }

    function getTrustedAgents() external view returns (address[] memory) {
        // In practice, you'd maintain an array of trusted agents
        return new address[](0);
    }

    function getProtocolMetrics(address protocol) external view returns (ProtocolMetrics memory) {
        return protocolMetrics[protocol];
    }

    function getRiskFactors(address protocol) external view returns (RiskFactors memory) {
        return protocolRiskFactors[protocol];
    }
}