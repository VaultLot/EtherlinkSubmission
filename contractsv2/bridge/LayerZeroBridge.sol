// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title IBridge
/// @notice Interface for cross-chain bridge functionality
/// @dev Defines the standard methods for bridging assets across chains
interface IBridge {
    // ============ Structs ============
    
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

    // ============ Events ============
    
    event BridgeInitiated(
        bytes32 indexed requestId,
        uint16 indexed dstChainId,
        address indexed token,
        uint256 amount,
        address sender,
        address recipient
    );
    
    event BridgeCompleted(
        bytes32 indexed requestId,
        bool success,
        uint256 amount
    );
    
    event ChainConfigured(
        uint16 indexed chainId,
        address remoteContract,
        bool active
    );
    
    event BridgeFeeUpdated(uint16 indexed chainId, uint256 newFee);

    // ============ Core Bridge Functions ============
    
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

interface IEtherlinkVault {
    function deployToOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool allowCrossChain
    ) external returns (bytes32);
    
    function asset() external view returns (address);
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

/// @title LayerZeroBridge - Enhanced Cross-Chain Bridge
/// @notice Advanced bridge with automatic optimal strategy deployment on destination chains
/// @dev Integrates with StrategyRegistry for maximum yield optimization across chains
contract LayerZeroBridge is IBridge, ILayerZeroReceiver, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Constants & Roles ============
    
    bytes32 public constant BRIDGE_ADMIN_ROLE = keccak256("BRIDGE_ADMIN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant STRATEGY_DEPLOYER_ROLE = keccak256("STRATEGY_DEPLOYER_ROLE");

    // Enhanced Chain IDs for better cross-chain support
    uint16 public constant ETHEREUM_CHAIN_ID = 101;
    uint16 public constant ARBITRUM_CHAIN_ID = 110;
    uint16 public constant POLYGON_CHAIN_ID = 109;
    uint16 public constant OPTIMISM_CHAIN_ID = 111;
    uint16 public constant ETHERLINK_CHAIN_ID = 30302;

    // ============ Enhanced State Variables ============
    
    ILayerZeroEndpoint public immutable layerZeroEndpoint;
    address public vault;
    IStrategyRegistry public strategyRegistry;
    
    mapping(bytes32 => BridgeRequest) public bridgeRequests;
    mapping(uint16 => ChainConfig) public chainConfigs;
    mapping(address => bool) public supportedTokens;
    mapping(uint16 => bytes) public trustedRemotes;
    
    // Auto-deployment settings
    struct AutoDeployConfig {
        bool enabled;
        uint256 minAmount;
        uint256 maxRiskTolerance;
        uint256 defaultRiskTolerance;
        bool allowCrossChainRebalancing;
    }
    
    AutoDeployConfig public autoDeployConfig;
    
    // Strategy deployment tracking
    mapping(bytes32 => uint256) public deployedAmounts; // requestId => amount deployed
    mapping(uint16 => uint256) public chainDeployments; // chainId => total deployed
    
    uint256 public bridgeNonce;
    bool public paused;
    
    // Enhanced events
    event AutoStrategyDeployment(bytes32 indexed requestId, uint16 chainId, address strategy, uint256 amount);
    event OptimalStrategySelected(bytes32 indexed requestId, bytes32 strategyHash, uint256 expectedAPY);
    event CrossChainRebalancing(uint16 fromChain, uint16 toChain, uint256 amount, bytes32 requestId);
    event TrustedRemoteSet(uint16 chainId, bytes remoteAddress);
    event SupportedTokenUpdated(address token, bool supported);

    // ============ Errors ============
    
    error BridgePaused();
    error ChainNotSupported();
    error TokenNotSupported();
    error InsufficientAmount();
    error ExcessiveAmount();
    error InsufficientFee();
    error InvalidRecipient();
    error RequestNotFound();
    error RequestAlreadyCompleted();
    error UnauthorizedCaller();
    error OnlyLayerZero();
    error UntrustedSource();

    // ============ Modifiers ============
    
    modifier whenNotPaused() {
        if (paused) revert BridgePaused();
        _;
    }
    
    modifier onlyVault() {
        if (!hasRole(VAULT_ROLE, msg.sender)) revert UnauthorizedCaller();
        _;
    }

    // ============ Constructor ============
    
    constructor(
        address _layerZeroEndpoint,
        address _vault,
        address _strategyRegistry,
        address _admin
    ) {
        require(_layerZeroEndpoint != address(0), "Invalid LayerZero endpoint");
        require(_vault != address(0), "Invalid vault");
        require(_admin != address(0), "Invalid admin");

        layerZeroEndpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
        vault = _vault;
        strategyRegistry = IStrategyRegistry(_strategyRegistry);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(BRIDGE_ADMIN_ROLE, _admin);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(STRATEGY_DEPLOYER_ROLE, _admin);

        // Initialize auto-deployment configuration
        autoDeployConfig = AutoDeployConfig({
            enabled: true,
            minAmount: 100 * 10**6, // 100 USDC minimum
            maxRiskTolerance: 6000, // 60% max risk
            defaultRiskTolerance: 5000, // 50% default risk
            allowCrossChainRebalancing: true
        });

        // Initialize chain configurations with enhanced settings
        _initializeEnhancedChainConfigs();
    }

    function _initializeEnhancedChainConfigs() internal {
        // Ethereum - Premier DeFi ecosystem
        chainConfigs[ETHEREUM_CHAIN_ID] = ChainConfig({
            chainId: ETHEREUM_CHAIN_ID,
            remoteContract: address(0),
            active: false,
            minAmount: 1000 * 10**6, // 1000 USDC (higher minimum for Ethereum)
            maxAmount: 10000000 * 10**6, // 10M USDC
            fee: 0.02 ether // Higher fee for Ethereum
        });

        // Arbitrum - L2 with lower fees
        chainConfigs[ARBITRUM_CHAIN_ID] = ChainConfig({
            chainId: ARBITRUM_CHAIN_ID,
            remoteContract: address(0),
            active: false,
            minAmount: 100 * 10**6, // 100 USDC
            maxAmount: 5000000 * 10**6, // 5M USDC
            fee: 0.005 ether
        });

        // Polygon - Fast and cheap
        chainConfigs[POLYGON_CHAIN_ID] = ChainConfig({
            chainId: POLYGON_CHAIN_ID,
            remoteContract: address(0),
            active: false,
            minAmount: 50 * 10**6, // 50 USDC
            maxAmount: 2000000 * 10**6, // 2M USDC
            fee: 0.001 ether
        });
    }

    // ============ ENHANCED BRIDGE FUNCTIONS ============
    
    function bridgeToOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bytes calldata data
    ) external payable onlyRole(VAULT_ROLE) whenNotPaused nonReentrant returns (bytes32 requestId) {
        require(amount >= autoDeployConfig.minAmount, "Amount below minimum");
        require(maxRiskTolerance <= 10000, "Invalid risk tolerance");

        // Get optimal strategy across all chains
        (bytes32 bestStrategy, uint256 expectedReturn, uint256 riskScore, bool requiresBridge) = 
            strategyRegistry.getOptimalStrategy(amount, maxRiskTolerance, true, ETHERLINK_CHAIN_ID);

        if (bestStrategy == bytes32(0)) {
            revert("No suitable strategy found");
        }

        if (riskScore > maxRiskTolerance) {
            revert("Risk tolerance exceeded");
        }

        // Generate unique request ID
        requestId = keccak256(abi.encodePacked(
            block.timestamp,
            bridgeNonce++,
            msg.sender,
            amount,
            bestStrategy
        ));

        // If strategy requires bridging, execute cross-chain deployment
        if (requiresBridge) {
            return _executeCrossChainDeployment(requestId, amount, bestStrategy, expectedReturn, riskScore, data);
        } else {
            // Deploy locally on Etherlink
            return _executeLocalDeployment(requestId, amount, bestStrategy, expectedReturn, data);
        }
    }

    function _executeCrossChainDeployment(
        bytes32 requestId,
        uint256 amount,
        bytes32 strategyHash,
        uint256 expectedReturn,
        uint256 riskScore,
        bytes calldata data
    ) internal returns (bytes32) {
        // Determine destination chain (simplified - would get from strategy registry)
        uint16 dstChainId = ETHEREUM_CHAIN_ID; // Default to Ethereum for maximum yield
        
        ChainConfig memory config = chainConfigs[dstChainId];
        require(config.active, "Chain not supported");
        require(msg.value >= config.fee, "Insufficient bridge fee");

        address assetToken = IEtherlinkVault(vault).asset();
        
        // Store bridge request with strategy information
        bridgeRequests[requestId] = BridgeRequest({
            id: requestId,
            srcChainId: ETHERLINK_CHAIN_ID,
            dstChainId: dstChainId,
            token: assetToken,
            amount: amount,
            sender: msg.sender,
            recipient: vault, // Funds go back to vault for strategy deployment
            data: abi.encode(strategyHash, expectedReturn, riskScore, data),
            timestamp: block.timestamp,
            completed: false
        });

        // Transfer tokens from vault
        IERC20(assetToken).safeTransferFrom(vault, address(this), amount);

        // Prepare enhanced payload for destination
        bytes memory payload = abi.encode(
            requestId,
            assetToken,
            amount,
            strategyHash,
            expectedReturn,
            riskScore,
            autoDeployConfig.defaultRiskTolerance,
            data
        );

        // Execute LayerZero bridge
        layerZeroEndpoint.send{value: msg.value}(
            dstChainId,
            trustedRemotes[dstChainId],
            payload,
            payable(msg.sender),
            address(0),
            bytes("")
        );

        chainDeployments[dstChainId] += amount;
        
        emit BridgeInitiated(requestId, dstChainId, assetToken, amount, msg.sender, vault);
        emit OptimalStrategySelected(requestId, strategyHash, expectedReturn);
        
        return requestId;
    }

    function _executeLocalDeployment(
        bytes32 requestId,
        uint256 amount,
        bytes32 strategyHash,
        uint256 expectedReturn,
        bytes calldata data
    ) internal returns (bytes32) {
        // Deploy to local strategy on Etherlink
        try IEtherlinkVault(vault).deployToOptimalStrategy(amount, autoDeployConfig.maxRiskTolerance, false) returns (bytes32 allocationId) {
            deployedAmounts[requestId] = amount;
            
            emit AutoStrategyDeployment(requestId, ETHERLINK_CHAIN_ID, address(0), amount);
            emit OptimalStrategySelected(requestId, strategyHash, expectedReturn);
            
            return requestId;
        } catch {
            revert("Local deployment failed");
        }
    }

    // ============ Core Bridge Functions ============
    
    function bridgeToken(
        uint16 dstChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external payable override onlyVault whenNotPaused nonReentrant returns (bytes32 requestId) {
        ChainConfig memory config = chainConfigs[dstChainId];
        
        if (!config.active) revert ChainNotSupported();
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (amount < config.minAmount) revert InsufficientAmount();
        if (amount > config.maxAmount) revert ExcessiveAmount();
        if (recipient == address(0)) revert InvalidRecipient();
        if (msg.value < config.fee) revert InsufficientFee();

        // Generate unique request ID
        requestId = keccak256(abi.encodePacked(
            block.timestamp,
            bridgeNonce++,
            msg.sender,
            dstChainId,
            token,
            amount
        ));

        // Store bridge request
        bridgeRequests[requestId] = BridgeRequest({
            id: requestId,
            srcChainId: ETHERLINK_CHAIN_ID,
            dstChainId: dstChainId,
            token: token,
            amount: amount,
            sender: msg.sender,
            recipient: recipient,
            data: data,
            timestamp: block.timestamp,
            completed: false
        });

        // Transfer tokens from vault
        IERC20(token).safeTransferFrom(vault, address(this), amount);

        // Prepare LayerZero payload
        bytes memory payload = abi.encode(requestId, token, amount, recipient, data);

        // Send LayerZero message
        layerZeroEndpoint.send{value: msg.value}(
            dstChainId,
            trustedRemotes[dstChainId],
            payload,
            payable(msg.sender),
            address(0),
            bytes("")
        );

        emit BridgeInitiated(requestId, dstChainId, token, amount, msg.sender, recipient);
        return requestId;
    }

    function completeBridge(
        bytes32 requestId,
        uint16 srcChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external override onlyRole(BRIDGE_ADMIN_ROLE) {
        // This function would be called by the bridge admin after verifying
        // the cross-chain transaction on the destination chain
        BridgeRequest storage request = bridgeRequests[requestId];
        
        if (request.id == bytes32(0)) revert RequestNotFound();
        if (request.completed) revert RequestAlreadyCompleted();

        request.completed = true;
        emit BridgeCompleted(requestId, true, amount);
    }

    // ============ LayerZero Receiver ============
    
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external override {
        if (msg.sender != address(layerZeroEndpoint)) revert OnlyLayerZero();
        
        // Convert bytes to bytes32 for comparison
        bytes32 srcAddressHash = keccak256(_srcAddress);
        bytes32 trustedRemoteHash = keccak256(trustedRemotes[_srcChainId]);
        
        if (srcAddressHash != trustedRemoteHash) revert UntrustedSource();

        // Decode payload
        (bytes32 requestId, address token, uint256 amount, address recipient, bytes memory data) = 
            abi.decode(_payload, (bytes32, address, uint256, address, bytes));

        // Handle incoming bridge transaction
        _handleIncomingBridge(requestId, _srcChainId, token, amount, recipient, data);
    }

    function _handleIncomingBridge(
        bytes32 requestId,
        uint16 srcChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes memory data
    ) internal {
        // Create bridge request record
        bridgeRequests[requestId] = BridgeRequest({
            id: requestId,
            srcChainId: srcChainId,
            dstChainId: ETHERLINK_CHAIN_ID,
            token: token,
            amount: amount,
            sender: address(0), // Unknown sender from other chain
            recipient: recipient,
            data: data,
            timestamp: block.timestamp,
            completed: true
        });

        // If this is for the vault, deposit the funds
        if (recipient == vault || recipient == address(this)) {
            // Transfer tokens to vault for yield farming
            IERC20(token).safeTransfer(vault, amount);
        } else {
            // Transfer to specified recipient
            IERC20(token).safeTransfer(recipient, amount);
        }

        emit BridgeCompleted(requestId, true, amount);
    }

    // ============ Configuration Functions ============
    
    function configureChain(
        uint16 chainId,
        address remoteContract,
        bool active,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 fee
    ) external override onlyRole(BRIDGE_ADMIN_ROLE) {
        chainConfigs[chainId] = ChainConfig({
            chainId: chainId,
            remoteContract: remoteContract,
            active: active,
            minAmount: minAmount,
            maxAmount: maxAmount,
            fee: fee
        });

        emit ChainConfigured(chainId, remoteContract, active);
    }

    function configureSupportedToken(address token, bool active) external override onlyRole(BRIDGE_ADMIN_ROLE) {
        supportedTokens[token] = active;
        emit SupportedTokenUpdated(token, active);
    }

    function setTrustedRemote(uint16 _chainId, bytes calldata _remoteAddress) external onlyRole(BRIDGE_ADMIN_ROLE) {
        trustedRemotes[_chainId] = _remoteAddress;
        emit TrustedRemoteSet(_chainId, _remoteAddress);
    }

    // ============ View Functions ============
    
    function getBridgeFee(uint16 dstChainId, uint256 amount) external view override returns (uint256 fee) {
        ChainConfig memory config = chainConfigs[dstChainId];
        if (!config.active) return 0;
        
        // Base fee + potential amount-based fee
        return config.fee;
    }

    function isChainSupported(uint16 chainId) external view override returns (bool supported) {
        return chainConfigs[chainId].active;
    }

    function isTokenSupported(address token) external view override returns (bool supported) {
        return supportedTokens[token];
    }

    function getBridgeRequest(bytes32 requestId) external view override returns (BridgeRequest memory request) {
        return bridgeRequests[requestId];
    }

    function getChainConfig(uint16 chainId) external view override returns (ChainConfig memory config) {
        return chainConfigs[chainId];
    }

    function estimateLayerZeroFee(
        uint16 dstChainId,
        bytes calldata payload
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        return layerZeroEndpoint.estimateFees(
            dstChainId,
            address(this),
            payload,
            false,
            bytes("")
        );
    }

    // ============ Admin Functions ============
    
    function setPaused(bool _paused) external override onlyRole(BRIDGE_ADMIN_ROLE) {
        paused = _paused;
    }

    function setVault(address _newVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newVault != address(0), "Invalid vault");
        
        if (vault != address(0)) {
            _revokeRole(VAULT_ROLE, vault);
        }
        
        vault = _newVault;
        _grantRole(VAULT_ROLE, _newVault);
    }

    function emergencyWithdraw(
        address token,
        uint256 amount,
        address to
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }

    function withdrawNative(uint256 amount, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    // ============ Utility Functions ============
    
    function getBridgeHistory(uint256 limit) external view returns (BridgeRequest[] memory requests) {
        uint256 totalRequests = bridgeNonce;
        uint256 returnCount = limit > totalRequests ? totalRequests : limit;
        
        requests = new BridgeRequest[](returnCount);
        
        // This is simplified - in production you'd want better indexing
        // For now, just return empty array as implementation would be complex
        return requests;
    }

    function getActiveBridges() external view returns (uint256 count) {
        // Return count of active bridge requests
        // Implementation would require additional tracking
        return 0;
    }

    // Receive function to accept ETH for bridge fees
    receive() external payable {}
}