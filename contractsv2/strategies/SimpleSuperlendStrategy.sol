// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IStrategies.sol";

/// @title SimpleSuperlendStrategy - Simplified Superlend Integration
/// @notice A simplified strategy for Superlend protocol that focuses on basic functionality
/// @dev This version has minimal constructor requirements and focuses on core lending operations
contract SimpleSuperlendStrategy is IStrategies, AccessControl, ReentrancyGuard {
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
    IERC20 public immutable aToken; // Superlend aToken
    address public immutable poolAddress;
    address public vault;
    bool public strategyPaused;
    string public strategyName;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);

    // ====================================================================
    // CONSTRUCTOR - SIMPLIFIED
    // ====================================================================
    
    constructor(
        address _asset,
        address _pool,
        address _vault
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_pool != address(0), "Invalid pool");
        require(_vault != address(0), "Invalid vault");

        assetToken = IERC20(_asset);
        aToken = IERC20(_asset); // Using same token for testing
        poolAddress = _pool;
        vault = _vault;
        strategyName = "Simple Superlend Strategy";

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

    // ====================================================================
    // STRATEGY INTERFACE IMPLEMENTATION
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) external override onlyVault nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        // Transfer tokens from vault
        assetToken.safeTransferFrom(msg.sender, address(this), amount);

        // For testing, we'll just hold the tokens (simulating lending)
        // In production, this would interact with Superlend pool
        totalDeployed += amount;
        
        emit Deposit(amount);
        emit StrategyExecuted(amount, data);
    }

    function harvest(bytes calldata data) external override nonReentrant whenNotPaused {
        // Simulate yield generation (1% of deployed amount)
        uint256 simulatedYield = totalDeployed / 100;
        
        if (simulatedYield > 0) {
            // In testing, we'll mint some yield to simulate earnings
            // In production, this would claim rewards from Superlend
            totalHarvested += simulatedYield;
            lastHarvestTime = block.timestamp;

            emit Harvest(simulatedYield);
            emit StrategyHarvested(simulatedYield, totalHarvested);
        }
    }

    function emergencyExit(bytes calldata data) external override onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;

        // Transfer all held tokens back to vault
        uint256 balance = assetToken.balanceOf(address(this));
        if (balance > 0) {
            assetToken.safeTransfer(vault, balance);
        }

        emit EmergencyExit(balance);
        emit EmergencyExitExecuted(balance);
    }

    function getBalance() external view override returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function underlyingToken() external view override returns (address) {
        return address(assetToken);
    }

    function protocol() external view override returns (address) {
        return poolAddress;
    }

    function paused() external view override returns (bool) {
        return strategyPaused;
    }

    function setPaused(bool pauseState) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = pauseState;
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
            poolAddress,
            totalDeployed,
            totalHarvested,
            lastHarvestTime,
            strategyPaused
        );
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function updateVault(address _newVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newVault != address(0), "Invalid vault");
        vault = _newVault;
    }

    function updateStrategyName(string calldata _newName) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyName = _newName;
    }

    // Emergency function to recover any stuck tokens
    function recoverToken(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(assetToken), "Cannot recover main asset");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // Receive function to accept ETH
    receive() external payable {}

    function withdrawETH(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        payable(msg.sender).transfer(amount);
    }
}