// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IStrategies.sol";

/// @title SimplePancakeSwapStrategy - Simplified PancakeSwap Integration
/// @notice A simplified strategy for PancakeSwap that focuses on basic functionality
/// @dev This version avoids pool existence validation and focuses on core swapping operations
contract SimplePancakeSwapStrategy is IStrategies, AccessControl, ReentrancyGuard {
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
    IERC20 public immutable pairedToken;
    address public vault;
    bool public strategyPaused;
    string public strategyName;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;

    // Simulated liquidity provision
    uint256 public liquidityProvided;
    uint256 public feesAccumulated;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event LiquiditySimulated(uint256 assetAmount, uint256 pairedAmount);

    // ====================================================================
    // CONSTRUCTOR - SIMPLIFIED
    // ====================================================================
    
    constructor(
        address _asset,
        address _pairedToken,
        address _vault
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_pairedToken != address(0), "Invalid paired token");
        require(_vault != address(0), "Invalid vault");

        assetToken = IERC20(_asset);
        pairedToken = IERC20(_pairedToken);
        vault = _vault;
        strategyName = "Simple PancakeSwap Strategy";

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

        // Simulate liquidity provision
        // In production, this would interact with PancakeSwap pools
        liquidityProvided += amount;
        totalDeployed += amount;
        
        // Simulate fee accumulation (0.3% of provided liquidity over time)
        feesAccumulated += (amount * 3) / 1000;
        
        emit Deposit(amount);
        emit StrategyExecuted(amount, data);
        emit LiquiditySimulated(amount, 0);
    }

    function harvest(bytes calldata data) external override nonReentrant whenNotPaused {
        // Simulate yield from fees and rewards
        uint256 simulatedYield = feesAccumulated;
        
        if (simulatedYield > 0) {
            // Reset accumulated fees
            feesAccumulated = 0;
            
            // In testing, we'll just track the yield
            // In production, this would claim fees from PancakeSwap
            totalHarvested += simulatedYield;
            lastHarvestTime = block.timestamp;

            emit Harvest(simulatedYield);
            emit StrategyHarvested(simulatedYield, totalHarvested);
        }
    }

    function emergencyExit(bytes calldata data) external override onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;

        // Transfer all held tokens back to vault
        uint256 assetBalance = assetToken.balanceOf(address(this));
        uint256 pairedBalance = pairedToken.balanceOf(address(this));
        
        if (assetBalance > 0) {
            assetToken.safeTransfer(vault, assetBalance);
        }
        
        if (pairedBalance > 0) {
            pairedToken.safeTransfer(vault, pairedBalance);
        }

        uint256 totalRecovered = assetBalance + pairedBalance;
        emit EmergencyExit(totalRecovered);
        emit EmergencyExitExecuted(totalRecovered);
    }

    function getBalance() external view override returns (uint256) {
        return assetToken.balanceOf(address(this)) + liquidityProvided;
    }

    function underlyingToken() external view override returns (address) {
        return address(assetToken);
    }

    function protocol() external view override returns (address) {
        // Return PancakeSwap router address
        return 0x8a7bBf269B95875FC1829901bb2c815029d8442e;
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
        address paired,
        address protocolAddr,
        uint256 totalDep,
        uint256 totalHarv,
        uint256 liquidity,
        uint256 fees,
        uint256 lastHarvest,
        bool isPaused
    ) {
        return (
            strategyName,
            address(assetToken),
            address(pairedToken),
            0x8a7bBf269B95875FC1829901bb2c815029d8442e, // PancakeSwap router
            totalDeployed,
            totalHarvested,
            liquidityProvided,
            feesAccumulated,
            lastHarvestTime,
            strategyPaused
        );
    }

    function getPendingFees() external view returns (uint256) {
        return feesAccumulated;
    }

    function getLiquidityInfo() external view returns (
        uint256 totalLiquidity,
        uint256 assetBalance,
        uint256 pairedBalance
    ) {
        return (
            liquidityProvided,
            assetToken.balanceOf(address(this)),
            pairedToken.balanceOf(address(this))
        );
    }

    // ====================================================================
    // SIMULATION FUNCTIONS (FOR TESTING)
    // ====================================================================

    function simulateSwap(uint256 amountIn, bool assetToPaired) external onlyRole(HARVESTER_ROLE) {
        // Simulate token swapping for testing
        if (assetToPaired) {
            require(assetToken.balanceOf(address(this)) >= amountIn, "Insufficient asset balance");
            // In production, this would call PancakeSwap router
            emit LiquiditySimulated(amountIn, amountIn * 95 / 100); // Simulate 5% slippage
        } else {
            require(pairedToken.balanceOf(address(this)) >= amountIn, "Insufficient paired token balance");
            emit LiquiditySimulated(amountIn * 95 / 100, amountIn);
        }
    }

    function simulateFeeGeneration(uint256 additionalFees) external onlyRole(HARVESTER_ROLE) {
        // Simulate additional fee generation for testing
        feesAccumulated += additionalFees;
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
        require(token != address(assetToken) && token != address(pairedToken), "Cannot recover main tokens");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // Receive function to accept ETH
    receive() external payable {}

    function withdrawETH(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        payable(msg.sender).transfer(amount);
    }
}