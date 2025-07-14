// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IMultiTokenVault
/// @notice Interface for a multi-token vault that supports ETH and various ERC20 tokens
/// @dev This interface extends basic vault functionality to support multiple asset types
interface IMultiTokenVault {
    // ============ Structs ============

    /// @notice Information about a supported token
    struct TokenInfo {
        address tokenAddress;
        bytes32 pythPriceId;
        uint8 decimals;
        bool isActive;
        uint256 totalDeposited;
    }

    /// @notice Deposit information for tracking user balances
    struct UserDeposit {
        address token;
        uint256 amount;
        uint256 usdValue;
        uint256 timestamp;
    }

    // ============ Events ============

    event TokenAdded(address indexed token, bytes32 priceId, uint8 decimals);
    event TokenRemoved(address indexed token);
    event TokenDeposited(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 usdValue
    );
    event TokenWithdrawn(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 usdValue
    );
    event ETHDeposited(address indexed user, uint256 amount, uint256 usdValue);
    event ETHWithdrawn(address indexed user, uint256 amount, uint256 usdValue);
    event PriceOracleUpdated(address indexed newOracle);

    // ============ Functions ============

    /// @notice Deposits ETH into the vault
    /// @dev Payable function that accepts ETH deposits
    function depositETH() external payable;

    /// @notice Deposits ERC20 tokens into the vault
    /// @param token The address of the token to deposit
    /// @param amount The amount of tokens to deposit
    function depositToken(address token, uint256 amount) external payable;

    /// @notice Withdraws ETH from the vault
    /// @param amount The amount of ETH to withdraw
    function withdrawETH(uint256 amount) external;

    /// @notice Withdraws ERC20 tokens from the vault
    /// @param token The address of the token to withdraw
    /// @param amount The amount of tokens to withdraw
    function withdrawToken(address token, uint256 amount) external;

    /// @notice Adds a new supported token to the vault
    /// @param token The address of the token to add
    /// @param pythPriceId The Pyth price ID for the token
    /// @param decimals The number of decimals for the token
    function addSupportedToken(
        address token,
        bytes32 pythPriceId,
        uint8 decimals
    ) external;

    /// @notice Removes a token from supported tokens
    /// @param token The address of the token to remove
    function removeSupportedToken(address token) external;

    /// @notice Sets the price oracle address
    /// @param oracle The address of the new price oracle
    function setPriceOracle(address oracle) external;

    /// @notice Gets the total USD value of all assets in the vault
    /// @return totalValue The total USD value
    function getTotalVaultValueUSD() external view returns (uint256 totalValue);

    /// @notice Gets the total USD value of a user's deposits
    /// @param user The address of the user
    /// @return totalValue The total USD value of user's deposits
    function getUserTotalValueUSD(
        address user
    ) external view returns (uint256 totalValue);

    /// @notice Gets user's balance for a specific token
    /// @param user The address of the user
    /// @param token The address of the token
    /// @return balance The user's balance for the token
    function getUserTokenBalance(
        address user,
        address token
    ) external view returns (uint256 balance);

    /// @notice Gets user's ETH balance
    /// @param user The address of the user
    /// @return balance The user's ETH balance
    function getUserETHBalance(
        address user
    ) external view returns (uint256 balance);

    /// @notice Gets information about a supported token
    /// @param token The address of the token
    /// @return info The token information
    function getTokenInfo(
        address token
    ) external view returns (TokenInfo memory info);

    /// @notice Gets all supported tokens
    /// @return tokens Array of supported token addresses
    function getSupportedTokens()
        external
        view
        returns (address[] memory tokens);

    /// @notice Checks if a token is supported
    /// @param token The address of the token to check
    /// @return isSupported Whether the token is supported
    function isTokenSupported(
        address token
    ) external view returns (bool isSupported);
}
