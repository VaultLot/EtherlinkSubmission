// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IStrategies.sol";

/// @title BaseStrategy
/// @notice Base implementation for all yield strategies in the Etherlink ecosystem
/// @dev Provides common functionality and security features for strategy contracts
abstract contract BaseStrategy is IStrategies, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================
    
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    IERC20 public immutable assetToken;
    address public immutable protocolAddress;
    address public vault;
    bool public strategyPaused;
    string public strategyName;
    
    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;
    
    // Risk and performance tracking
    uint256 public maxSlippage = 300; // 3% default
    uint256 public maxSingleDeployment = 1000000 * 10**6; // 1M USDC default
    uint256 public minHarvestAmount = 1 * 10**6; // 1 USDC minimum

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event StrategyPaused();
    event StrategyUnpaused();
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event MaxDeploymentUpdated(uint256 oldMax, uint256 newMax);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        address _asset,
        address _protocolAddress,
        address _vault,
        string memory _name
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_protocolAddress != address(0), "Invalid protocol");
        require(_vault != address(0), "Invalid vault");

        assetToken = IERC20(_asset);
        protocolAddress = _protocolAddress;
        vault = _vault;
        strategyName = _name;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_ROLE, _vault);
        _grantRole(HARVESTER_ROLE, msg.sender);
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused, "Strategy is paused");
        _;
    }

    modifier onlyHarvester() {
        require(hasRole(HARVESTER_ROLE, msg.sender), "Not authorized harvester");
        _;
    }

    // ====================================================================
    // STRATEGY INTERFACE IMPLEMENTATION
    // ====================================================================
    
    function execute(uint256 amount, bytes calldata data) external virtual override onlyVault nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= maxSingleDeployment, "Amount exceeds max deployment");
        
        // Transfer tokens from vault
        assetToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Execute strategy-specific logic
        _executeStrategy(amount, data);
        
        totalDeployed += amount;
        emit StrategyExecuted(amount, data);
    }

    function harvest(bytes calldata data) external virtual override onlyHarvester nonReentrant whenNotPaused {
        uint256 balanceBefore = assetToken.balanceOf(address(this));
        
        // Execute strategy-specific harvest logic
        _harvestRewards(data);
        
        uint256 harvested = assetToken.balanceOf(address(this)) - balanceBefore;
        
        if (harvested >= minHarvestAmount) {
            // Transfer harvested amount to vault
            _transferToVault(harvested);
            
            totalHarvested += harvested;
            lastHarvestTime = block.timestamp;
            harvestCount++;
            
            emit StrategyHarvested(harvested, totalHarvested);
        }
    }

    function emergencyExit(bytes calldata data) external virtual override onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;
        
        // Execute strategy-specific emergency exit
        uint256 recovered = _emergencyWithdraw(data);
        
        // Transfer all remaining tokens to vault
        uint256 remainingBalance = assetToken.balanceOf(address(this));
        if (remainingBalance > 0) {
            _transferToVault(remainingBalance);
            recovered += remainingBalance;
        }
        
        emit EmergencyExitExecuted(recovered);
    }

    function getBalance() external view virtual override returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function underlyingToken() external view virtual override returns (address) {
        return address(assetToken);
    }

    function protocol() external view virtual override returns (address) {
        return protocolAddress;
    }

    function paused() external view virtual override returns (bool) {
        return strategyPaused;
    }

    // ====================================================================
    // INTERNAL FUNCTIONS (To be implemented by derived strategies)
    // ====================================================================
    
    /// @notice Execute strategy-specific deployment logic
    /// @param amount Amount to deploy
    /// @param data Strategy-specific data
    function _executeStrategy(uint256 amount, bytes calldata data) internal virtual;

    /// @notice Execute strategy-specific harvest logic
    /// @param data Strategy-specific data
    function _harvestRewards(bytes calldata data) internal virtual;

    /// @notice Execute strategy-specific emergency withdrawal
    /// @param data Strategy-specific data
    /// @return recovered Amount recovered from the strategy
    function _emergencyWithdraw(bytes calldata data) internal virtual returns (uint256 recovered);

    // ====================================================================
    // INTERNAL HELPER FUNCTIONS
    // ====================================================================
    
    function _transferToVault(uint256 amount) internal {
        if (amount > 0) {
            assetToken.safeTransfer(vault, amount);
        }
    }

    function _getAssetBalance() internal view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = true;
        emit StrategyPaused();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = false;
        emit StrategyUnpaused();
    }

    function setMaxSlippage(uint256 newSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSlippage <= 1000, "Slippage too high"); // Max 10%
        uint256 oldSlippage = maxSlippage;
        maxSlippage = newSlippage;
        emit SlippageUpdated(oldSlippage, newSlippage);
    }

    function setMaxSingleDeployment(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldMax = maxSingleDeployment;
        maxSingleDeployment = newMax;
        emit MaxDeploymentUpdated(oldMax, newMax);
    }

    function setMinHarvestAmount(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minHarvestAmount = newMin;
    }

    function grantHarvesterRole(address harvester) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(HARVESTER_ROLE, harvester);
    }

    function revokeHarvesterRole(address harvester) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(HARVESTER_ROLE, harvester);
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    
    function getStrategyInfo() external view returns (
        string memory name,
        address asset,
        address protocolAddr,
        uint256 totalDep,
        uint256 totalHarv,
        uint256 lastHarvest,
        bool isPaused
    ) {
        return (
            strategyName,
            address(assetToken),
            protocolAddress,
            totalDeployed,
            totalHarvested,
            lastHarvestTime,
            strategyPaused
        );
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 harvestsCount,
        uint256 avgHarvestAmount,
        uint256 lastHarvestTimestamp
    ) {
        uint256 avgHarvest = harvestCount > 0 ? totalHarvested / harvestCount : 0;
        
        return (
            totalDeployed,
            totalHarvested,
            harvestCount,
            avgHarvest,
            lastHarvestTime
        );
    }
}