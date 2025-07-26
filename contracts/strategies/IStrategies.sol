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