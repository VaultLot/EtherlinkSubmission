// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IStrategies
/// @notice Interface that strategy contracts must implement for the yield lottery system
/// @dev Your Python agent will interact with strategies through this interface
interface IStrategies {
    // ============ Events ============
    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event Harvest(uint256 earned);
    event EmergencyExit(uint256 amount);

    // ============ Core Strategy Functions ============
    
    /// @notice Execute the strategy by depositing tokens
    /// @param amount Amount of tokens to deposit into the strategy
    /// @param data Additional data needed for the strategy execution
    function execute(uint256 amount, bytes calldata data) external;

    /// @notice Harvest rewards/yield from the strategy
    /// @param data Additional data needed for harvesting
    function harvest(bytes calldata data) external;

    /// @notice Emergency exit - withdraw all funds from the strategy
    /// @param data Additional data needed for emergency exit
    function emergencyExit(bytes calldata data) external;

    /// @notice Get the current balance of the strategy
    /// @return balance Current balance of the strategy in underlying tokens
    function getBalance() external view returns (uint256 balance);

    // ============ View Functions ============
    
    /// @notice Get the underlying token address
    /// @return token Address of the underlying token
    function underlyingToken() external view returns (address token);

    /// @notice Get the protocol address this strategy interacts with
    /// @return protocol Address of the DeFi protocol
    function protocol() external view returns (address protocol);

    /// @notice Check if the strategy is currently paused
    /// @return paused True if strategy is paused
    function paused() external view returns (bool paused);

    // ============ Admin Functions ============
    
    /// @notice Set the pause state of the strategy
    /// @param _paused New pause state
    function setPaused(bool _paused) external;
}

/// @title IStrategyManager
/// @notice Interface for your Python agent to implement strategy management
/// @dev This interface defines how your Python agent should interact with the vault
interface IStrategyManager {
    /// @notice Assess the risk of a strategy allocation
    /// @param strategy Address of the strategy
    /// @param amount Amount to allocate
    /// @param data Additional strategy data
    /// @return riskScore Risk score (0-10000, where 10000 is highest risk)
    /// @return approved Whether the allocation is approved
    function assessRisk(
        address strategy,
        uint256 amount,
        bytes calldata data
    ) external view returns (uint256 riskScore, bool approved);

    /// @notice Get optimal allocation across multiple strategies
    /// @param strategies Array of strategy addresses
    /// @param totalAmount Total amount to allocate
    /// @return allocations Array of amounts to allocate to each strategy
    function getOptimalAllocation(
        address[] calldata strategies,
        uint256 totalAmount
    ) external view returns (uint256[] memory allocations);

    /// @notice Update strategy performance metrics
    /// @param strategy Address of the strategy
    /// @param performance Performance metric
    /// @param riskMetrics Additional risk metrics
    function updateStrategyMetrics(
        address strategy,
        uint256 performance,
        bytes calldata riskMetrics
    ) external;
}

/// @title Strategy Errors
/// @notice Common errors that strategies may throw
interface IStrategyErrors {
    error StrategyPaused();
    error InsufficientBalance();
    error InvalidAmount();
    error DepositFailed();
    error WithdrawFailed();
    error HarvestFailed();
    error UnauthorizedCaller();
    error InvalidStrategy();
}

/// @title IStrategyRegistry
/// @notice Interface for strategy registry contract
interface IStrategyRegistry {
    struct StrategyInfo {
        address strategyAddress;
        uint16 chainId;
        string name;
        string protocol;
        uint256 currentAPY;
        uint256 riskScore;
        uint256 tvl;
        uint256 maxCapacity;
        uint256 minDeposit;
        bool active;
        bool crossChainEnabled;
        uint256 lastUpdate;
        bytes strategyData;
    }

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

    function getMultiStrategyAllocation(
        uint256 totalAmount,
        uint256 maxRiskTolerance,
        uint256 diversificationTargets
    ) external view returns (
        bytes32[] memory selectedStrategies,
        uint256[] memory allocations,
        uint256 totalExpectedReturn
    );

    function getStrategyByName(string calldata name, uint16 chainId) external view returns (StrategyInfo memory);
    
    function addPythonAgent(address agent) external;
}

/// @title IRiskOracle
/// @notice Interface for risk assessment oracle
interface IRiskOracle {
    struct RiskAssessment {
        uint256 riskScore;
        uint256 confidenceLevel;
        string riskLevel;
        uint256 timestamp;
        address assessor;
        bytes32 dataHash;
        bool valid;
        uint256 expiryTime;
    }

    function getRiskAssessment(address protocol) external view returns (
        RiskAssessment memory assessment,
        bool isValid
    );
    
    function assessStrategyRisk(address strategy) external view returns (
        uint256 riskScore,
        string memory riskLevel,
        bool approved,
        uint256 maxRecommendedAmount
    );
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

/// @title IEtherlinkVault
/// @notice Interface for the main vault contract
interface IEtherlinkVault {
    function deployToOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool allowCrossChain
    ) external returns (bytes32);
    
    function asset() external view returns (address);
    
    function addNamedStrategy(address strategy, string calldata name) external;
    
    function removeNamedStrategy(address strategy) external;
    
    function executeLottery() external returns (address winner);
    
    function getProtocolStatus() external view returns (
        uint256 liquidUSDC,
        uint256 prizePool,
        address lastWinner,
        uint256 totalDeployed,
        uint256 numberOfStrategies,
        uint256 avgAPY,
        bool lotteryReady,
        uint256 timeUntilLottery
    );
}

/// @title IBridge
/// @notice Interface for cross-chain bridge functionality
interface IBridge {
    struct BridgeRequest {
        bytes32 id;
        uint16 srcChainId;
        uint16 dstChainId;
        address token;
        uint256 amount;
        address sender;
        address recipient;
        bytes data;
        uint256 timestamp;
        bool completed;
    }

    struct ChainConfig {
        uint16 chainId;
        address remoteContract;
        bool active;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 fee;
    }

    function bridgeToken(
        uint16 dstChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external payable returns (bytes32 requestId);

    function completeBridge(
        bytes32 requestId,
        uint16 srcChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external;

    function configureChain(
        uint16 chainId,
        address remoteContract,
        bool active,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 fee
    ) external;

    function configureSupportedToken(address token, bool active) external;

    function getBridgeFee(uint16 dstChainId, uint256 amount) external view returns (uint256 fee);
    
    function isChainSupported(uint16 chainId) external view returns (bool supported);
    
    function isTokenSupported(address token) external view returns (bool supported);
    
    function getBridgeRequest(bytes32 requestId) external view returns (BridgeRequest memory request);
    
    function getChainConfig(uint16 chainId) external view returns (ChainConfig memory config);
    
    function setPaused(bool paused) external;
    
    function emergencyWithdraw(address token, uint256 amount, address to) external;
}

/// @title ILayerZeroReceiver
/// @notice Interface for receiving LayerZero messages
interface ILayerZeroReceiver {
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external;
}

/// @title ILayerZeroEndpoint
/// @notice Interface for LayerZero endpoint
interface ILayerZeroEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external view returns (uint256 nativeFee, uint256 zroFee);

    function getInboundNonce(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (uint64);
    
    function getOutboundNonce(uint16 _dstChainId, address _srcAddress) external view returns (uint64);
}

/// @title IEtherlinkRandomness
/// @notice Interface for Etherlink VRF randomness
interface IEtherlinkRandomness {
    function requestRandomness(uint256 callbackGasLimit) external returns (bytes32 requestId);
}