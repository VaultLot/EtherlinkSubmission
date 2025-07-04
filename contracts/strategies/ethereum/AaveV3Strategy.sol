// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../../interfaces/Strategies.sol";

/// @title IAavePool
/// @notice Interface for Aave V3 Pool
interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

/// @title IAToken
/// @notice Interface for Aave aTokens
interface IAToken {
    function balanceOf(address user) external view returns (uint256);
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

/// @title AaveV3Strategy
/// @notice Strategy for depositing USDC into Aave V3 to earn yield
contract AaveV3Strategy is IStrategies, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    
    /// @notice Aave V3 Pool address on Ethereum
    address public constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    
    /// @notice USDC token address on Ethereum
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    /// @notice aUSDC token address on Ethereum (Aave V3 USDC)
    address public constant AUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    
    /// @notice Role for vault that can execute strategy
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    // ============ State Variables ============
    
    /// @notice The vault address that owns this strategy
    address public vault;
    
    /// @notice Whether the strategy is paused
    bool public paused;
    
    /// @notice Total amount deposited in Aave
    uint256 public totalDeposited;
    
    /// @notice Last harvest timestamp
    uint256 public lastHarvest;
    
    /// @notice Strategy deployment timestamp
    uint256 public immutable deploymentTime;

    // ============ Errors ============
    
    error OnlyVault();

    // ============ Modifiers ============
    
    modifier onlyVault() {
        if (msg.sender != vault && !hasRole(VAULT_ROLE, msg.sender)) {
            revert OnlyVault();
        }
        _;
    }
    
    modifier whenNotPaused() {
        if (paused) revert IStrategies.StrategyPaused();
        _;
    }

    // ============ Constructor ============
    
    constructor(address _vault) {
        vault = _vault;
        deploymentTime = block.timestamp;
        lastHarvest = block.timestamp;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        
        // Approve Aave pool to spend USDC
        IERC20(USDC).approve(AAVE_POOL, type(uint256).max);
        
        emit IStrategies.VaultSet(_vault);
    }

    // ============ External Functions ============
    
    /// @inheritdoc IStrategies
    function execute(uint256 amount, bytes calldata data) external onlyVault whenNotPaused nonReentrant {
        if (amount == 0) revert IStrategies.InvalidAmount();
        
        // Transfer USDC from vault
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        
        // Supply to Aave V3
        try IAavePool(AAVE_POOL).supply(USDC, amount, address(this), 0) {
            totalDeposited += amount;
            emit IStrategies.Deposit(amount);
            emit IStrategies.Executed(amount, data);
        } catch (bytes memory reason) {
            // Return funds to vault on failure
            IERC20(USDC).safeTransfer(msg.sender, amount);
            revert IStrategies.DepositFailed(reason);
        }
    }
    
    /// @inheritdoc IStrategies
    function harvest(bytes calldata data) external onlyVault nonReentrant {
        uint256 currentBalance = getBalance();
        uint256 earned = currentBalance > totalDeposited ? currentBalance - totalDeposited : 0;
        
        if (earned > 0) {
            // Withdraw earned interest
            try IAavePool(AAVE_POOL).withdraw(USDC, earned, vault) returns (uint256 withdrawn) {
                lastHarvest = block.timestamp;
                emit IStrategies.Claim(withdrawn);
                emit IStrategies.Harvested(data);
            } catch (bytes memory reason) {
                revert IStrategies.ClaimFailed(reason);
            }
        }
    }
    
    /// @inheritdoc IStrategies
    function emergencyExit(bytes calldata data) external onlyVault nonReentrant {
        uint256 balance = getBalance();
        if (balance == 0) revert IStrategies.NoUnderlyingBalance();
        
        try IAavePool(AAVE_POOL).withdraw(USDC, type(uint256).max, vault) returns (uint256 withdrawn) {
            totalDeposited = 0;
            emit IStrategies.EmergencyExited(withdrawn, data);
        } catch (bytes memory reason) {
            revert IStrategies.WithdrawFailed(reason);
        }
    }
    
    /// @inheritdoc IStrategies
    function claimRewards(bytes calldata data) external onlyVault {
        // Aave V3 doesn't have additional reward tokens for USDC
        // Interest is automatically accrued in aToken balance
        emit IStrategies.Harvested(data);
    }
    
    /// @inheritdoc IStrategies
    function setVault(address _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_vault == address(0)) revert IStrategies.InvalidTokenAddress();
        
        vault = _vault;
        _grantRole(VAULT_ROLE, _vault);
        
        emit IStrategies.VaultSet(_vault);
    }
    
    /// @inheritdoc IStrategies
    function setPaused(bool _paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = _paused;
        emit IStrategies.PausedState(_paused);
    }
    
    /// @inheritdoc IStrategies
    function addRewardToken(address tokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Aave V3 USDC doesn't have additional reward tokens
        // This function exists for interface compliance
        if (tokenAddress == address(0)) revert IStrategies.InvalidTokenAddress();
        // No-op for this strategy
    }

    // ============ View Functions ============
    
    /// @inheritdoc IStrategies
    function underlyingToken() external pure returns (address) {
        return USDC;
    }
    
    /// @inheritdoc IStrategies
    function protocol() external pure returns (address) {
        return AAVE_POOL;
    }
    
    /// @inheritdoc IStrategies
    function depositSelector() external pure returns (bytes4) {
        return IAavePool.supply.selector;
    }
    
    /// @inheritdoc IStrategies
    function withdrawSelector() external pure returns (bytes4) {
        return IAavePool.withdraw.selector;
    }
    
    /// @inheritdoc IStrategies
    function claimSelector() external pure returns (bytes4) {
        return this.harvest.selector;
    }
    
    /// @inheritdoc IStrategies
    function getBalanceSelector() external pure returns (bytes4) {
        return this.getBalance.selector;
    }
    
    /// @inheritdoc IStrategies
    function getBalance() public view returns (uint256) {
        try IAToken(AUSDC).balanceOf(address(this)) returns (uint256 balance) {
            return balance;
        } catch {
            revert IStrategies.GetBalanceFailed("");
        }
    }
    
    /// @inheritdoc IStrategies
    function knownRewardTokens(address token) external pure returns (bool) {
        // Aave V3 USDC doesn't have additional reward tokens
        return token == USDC || token == AUSDC;
    }
    
    /// @inheritdoc IStrategies
    function rewardTokensList() external pure returns (address[] memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC; // Interest earned in USDC
        return tokens;
    }
    
    /// @inheritdoc IStrategies
    function queryProtocol(
        bytes4 selector,
        bytes calldata params
    ) external view returns (bytes memory) {
        if (selector == IAavePool.getUserAccountData.selector) {
            (address user) = abi.decode(params, (address));
            try IAavePool(AAVE_POOL).getUserAccountData(user) returns (
                uint256 totalCollateralBase,
                uint256 totalDebtBase,
                uint256 availableBorrowsBase,
                uint256 currentLiquidationThreshold,
                uint256 ltv,
                uint256 healthFactor
            ) {
                return abi.encode(
                    totalCollateralBase,
                    totalDebtBase,
                    availableBorrowsBase,
                    currentLiquidationThreshold,
                    ltv,
                    healthFactor
                );
            } catch {
                return "";
            }
        }
        
        return "";
    }
    
    /// @notice Get current APY from Aave (approximate)
    /// @return apy Current APY in basis points (e.g., 500 = 5%)
    function getCurrentAPY() external view returns (uint256 apy) {
        if (totalDeposited == 0 || deploymentTime == block.timestamp) {
            return 0;
        }
        
        uint256 currentBalance = getBalance();
        if (currentBalance <= totalDeposited) {
            return 0;
        }
        
        uint256 earned = currentBalance - totalDeposited;
        uint256 timeElapsed = block.timestamp - deploymentTime;
        
        // Calculate annualized return
        // APY = (earned / principal) * (365 days / time elapsed) * 10000 (for basis points)
        apy = (earned * 365 days * 10000) / (totalDeposited * timeElapsed);
    }
    
    /// @notice Get strategy health metrics
    /// @return healthy Whether strategy is performing well
    /// @return metrics Array of health metrics [APY, utilization, time since last harvest]
    function getHealthMetrics() external view returns (bool healthy, uint256[] memory metrics) {
        metrics = new uint256[](3);
        metrics[0] = this.getCurrentAPY();
        metrics[1] = totalDeposited > 0 ? (getBalance() * 10000) / totalDeposited : 0; // Utilization ratio
        metrics[2] = block.timestamp - lastHarvest; // Time since last harvest
        
        // Strategy is healthy if:
        // 1. APY > 1% (100 basis points)
        // 2. No major losses (utilization > 95%)
        // 3. Harvested within last 7 days
        healthy = metrics[0] > 100 && metrics[1] > 9500 && metrics[2] < 7 days;
    }
}
