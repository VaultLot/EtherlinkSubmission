// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    
    /// @notice Initiate a cross-chain bridge transaction
    /// @param dstChainId Destination chain ID
    /// @param token Token address to bridge
    /// @param amount Amount to bridge
    /// @param recipient Recipient address on destination chain
    /// @param data Additional data for the bridge transaction
    /// @return requestId Unique identifier for this bridge request
    function bridgeToken(
        uint16 dstChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external payable returns (bytes32 requestId);

    /// @notice Handle incoming bridge transaction from another chain
    /// @param requestId Bridge request identifier
    /// @param srcChainId Source chain ID
    /// @param token Token address
    /// @param amount Amount bridged
    /// @param recipient Recipient address
    /// @param data Additional data
    function completeBridge(
        bytes32 requestId,
        uint16 srcChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external;

    // ============ Configuration Functions ============
    
    /// @notice Configure a destination chain
    /// @param chainId Chain ID to configure
    /// @param remoteContract Address of the bridge contract on the remote chain
    /// @param active Whether the chain is active for bridging
    /// @param minAmount Minimum bridge amount
    /// @param maxAmount Maximum bridge amount
    /// @param fee Bridge fee for this chain
    function configureChain(
        uint16 chainId,
        address remoteContract,
        bool active,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 fee
    ) external;

    /// @notice Add a supported token for bridging
    /// @param token Token address to support
    /// @param active Whether the token is active for bridging
    function configureSupportedToken(address token, bool active) external;

    // ============ View Functions ============
    
    /// @notice Get bridge fee for a specific chain and amount
    /// @param dstChainId Destination chain ID
    /// @param amount Amount to bridge
    /// @return fee Bridge fee in native token
    function getBridgeFee(uint16 dstChainId, uint256 amount) external view returns (uint256 fee);

    /// @notice Check if a chain is supported for bridging
    /// @param chainId Chain ID to check
    /// @return supported Whether the chain is supported
    function isChainSupported(uint16 chainId) external view returns (bool supported);

    /// @notice Check if a token is supported for bridging
    /// @param token Token address to check
    /// @return supported Whether the token is supported
    function isTokenSupported(address token) external view returns (bool supported);

    /// @notice Get bridge request details
    /// @param requestId Bridge request ID
    /// @return request Bridge request details
    function getBridgeRequest(bytes32 requestId) external view returns (BridgeRequest memory request);

    /// @notice Get chain configuration
    /// @param chainId Chain ID
    /// @return config Chain configuration
    function getChainConfig(uint16 chainId) external view returns (ChainConfig memory config);

    // ============ Admin Functions ============
    
    /// @notice Pause/unpause bridging operations
    /// @param paused Whether to pause bridging
    function setPaused(bool paused) external;

    /// @notice Emergency withdraw tokens
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    /// @param to Recipient address
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

/// @title Bridge Errors
/// @notice Common errors for bridge implementations
interface IBridgeErrors {
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
}