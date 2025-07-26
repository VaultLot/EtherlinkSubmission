// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title EtherlinkVaultCore - Core ERC4626 Vault Implementation
/// @notice Simplified core vault for yield lottery system
/// @dev Core functionality only - extensions handled by separate contracts
contract EtherlinkVaultCore is Ownable, ERC20, AccessControl, ReentrancyGuard, IERC4626 {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================
    
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    IERC20 private immutable _asset;
    address public pythonAgent;
    
    // Core strategy management
    address[] public strategies;
    mapping(address => bool) public isStrategy;
    mapping(address => uint256) public strategyAllocations;
    mapping(string => address) public namedStrategies;
    mapping(address => string) public strategyNames;
    
    // Basic yield tracking
    uint256 public totalYieldGenerated;
    uint256 public lastHarvestTime;
    
    // Extension contracts
    address public lotteryExtension;
    address public optimizationExtension;
    address public bridgeExtension;
    
    // Emergency controls
    bool public emergencyMode;
    bool public depositsEnabled = true;
    bool public withdrawalsEnabled = true;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyAdded(address indexed strategy, string name);
    event StrategyRemoved(address indexed strategy, string name);
    event StrategyExecuted(address indexed strategy, uint256 amount, string name);
    event YieldHarvested(uint256 totalYield);
    event ExtensionUpdated(address indexed extension, string extensionType);
    event EmergencyModeToggled(bool enabled);

    // ====================================================================
    // ERRORS
    // ====================================================================
    
    error InvalidStrategy();
    error StrategyAlreadyExists();
    error StrategyDoesNotExist();
    error EmergencyModeActive();
    error DepositsDisabled();
    error WithdrawalsDisabled();
    error InsufficientBalance();

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyAgent() {
        require(
            hasRole(AGENT_ROLE, msg.sender) || 
            msg.sender == pythonAgent, 
            "Not authorized agent"
        );
        _;
    }
    
    modifier whenNotEmergency() {
        if (emergencyMode) revert EmergencyModeActive();
        _;
    }
    
    modifier whenDepositsEnabled() {
        if (!depositsEnabled) revert DepositsDisabled();
        _;
    }
    
    modifier whenWithdrawalsEnabled() {
        if (!withdrawalsEnabled) revert WithdrawalsDisabled();
        _;
    }

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        IERC20 assetToken,
        string memory name,
        string memory symbol,
        address _manager,
        address _pythonAgent
    ) ERC20(name, symbol) {
        require(address(assetToken) != address(0), "Invalid asset");
        require(_manager != address(0), "Invalid manager");
        require(_pythonAgent != address(0), "Invalid Python agent");

        _transferOwnership(msg.sender);

        _asset = assetToken;
        pythonAgent = _pythonAgent;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, _manager);
        _grantRole(AGENT_ROLE, _pythonAgent);
    }

    // ====================================================================
    // ERC4626 IMPLEMENTATION
    // ====================================================================

    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 assetsInStrategies = 0;
        for (uint i = 0; i < strategies.length; i++) {
            try IStrategy(strategies[i]).getBalance() returns (uint256 balance) {
                assetsInStrategies += balance;
            } catch {
                // Strategy might be temporarily unavailable
            }
        }
        return _asset.balanceOf(address(this)) + assetsInStrategies;
    }

    function convertToShares(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding.Down);
    }

    function convertToAssets(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding.Down);
    }

    function maxDeposit(address) public view virtual override returns (uint256) {
        return depositsEnabled && !emergencyMode ? type(uint256).max : 0;
    }

    function previewDeposit(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding.Down);
    }

    function deposit(uint256 assetsValue, address receiver) 
        public 
        virtual 
        override 
        nonReentrant 
        whenNotEmergency 
        whenDepositsEnabled 
        returns (uint256 shares) 
    {
        shares = previewDeposit(assetsValue);
        _deposit(assetsValue, shares, receiver);
        
        // Notify lottery extension if available
        if (lotteryExtension != address(0)) {
            try ILotteryExtension(lotteryExtension).onDeposit(receiver, assetsValue) {
                // Success
            } catch {
                // Continue if extension fails
            }
        }
        
        return shares;
    }

    function maxMint(address) public view virtual override returns (uint256) {
        return depositsEnabled && !emergencyMode ? type(uint256).max : 0;
    }

    function previewMint(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding.Up);
    }

    function mint(uint256 sharesValue, address receiver) 
        public 
        virtual 
        override 
        nonReentrant 
        whenNotEmergency 
        whenDepositsEnabled 
        returns (uint256 assets) 
    {
        assets = previewMint(sharesValue);
        _deposit(assets, sharesValue, receiver);
        return assets;
    }

    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        if (!withdrawalsEnabled || emergencyMode) return 0;
        return _convertToAssets(balanceOf(owner), Math.Rounding.Down);
    }

    function previewWithdraw(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding.Up);
    }

    function withdraw(uint256 assetsValue, address receiver, address owner) 
        public 
        virtual 
        override 
        nonReentrant 
        whenWithdrawalsEnabled 
        returns (uint256 shares) 
    {
        shares = previewWithdraw(assetsValue);
        _withdraw(assetsValue, shares, receiver, owner);
        return shares;
    }

    function maxRedeem(address owner) public view virtual override returns (uint256) {
        if (!withdrawalsEnabled || emergencyMode) return 0;
        return balanceOf(owner);
    }

    function previewRedeem(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding.Down);
    }

    function redeem(uint256 sharesValue, address receiver, address owner) 
        public 
        virtual 
        override 
        nonReentrant 
        whenWithdrawalsEnabled 
        returns (uint256 assets) 
    {
        assets = previewRedeem(sharesValue);
        _withdraw(assets, sharesValue, receiver, owner);
        return assets;
    }

    // ====================================================================
    // INTERNAL ERC4626 LOGIC
    // ====================================================================

    function _deposit(uint256 assetsValue, uint256 sharesValue, address receiver) internal {
        require(receiver != address(0), "Deposit to zero address");
        require(assetsValue > 0, "Zero assets");

        _asset.safeTransferFrom(msg.sender, address(this), assetsValue);
        _mint(receiver, sharesValue);
        
        emit Deposit(msg.sender, receiver, assetsValue, sharesValue);
    }

    function _withdraw(uint256 assetsValue, uint256 sharesValue, address receiver, address owner) internal {
        require(receiver != address(0), "Withdraw to zero address");
        require(assetsValue > 0, "Zero assets");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, sharesValue);
        }

        uint256 availableBalance = _asset.balanceOf(address(this));
        if (availableBalance < assetsValue) {
            revert InsufficientBalance();
        }

        _burn(owner, sharesValue);
        _asset.safeTransfer(receiver, assetsValue);
        
        emit Withdraw(msg.sender, receiver, owner, assetsValue, sharesValue);
    }

    function _convertToShares(uint256 assetsValue, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? assetsValue
            : Math.mulDiv(assetsValue, supply, totalAssets(), rounding);
    }

    function _convertToAssets(uint256 sharesValue, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? sharesValue
            : Math.mulDiv(sharesValue, totalAssets(), supply, rounding);
    }

    // ====================================================================
    // STRATEGY MANAGEMENT
    // ====================================================================

    function addNamedStrategy(
        address _strategy, 
        string calldata strategyName
    ) external onlyRole(MANAGER_ROLE) {
        if (_strategy == address(0)) revert InvalidStrategy();
        if (isStrategy[_strategy]) revert StrategyAlreadyExists();

        isStrategy[_strategy] = true;
        strategies.push(_strategy);
        namedStrategies[strategyName] = _strategy;
        strategyNames[_strategy] = strategyName;
        
        emit StrategyAdded(_strategy, strategyName);
    }

    function removeNamedStrategy(
        address _strategy
    ) external onlyRole(MANAGER_ROLE) {
        if (!isStrategy[_strategy]) revert StrategyDoesNotExist();
        
        isStrategy[_strategy] = false;
        string memory name = strategyNames[_strategy];
        delete namedStrategies[name];
        delete strategyNames[_strategy];

        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _strategy) {
                strategies[i] = strategies[strategies.length - 1];
                strategies.pop();
                break;
            }
        }
        emit StrategyRemoved(_strategy, name);
    }

    function deployToNamedStrategy(
        string calldata strategyName,
        uint256 _amount,
        bytes calldata _data
    ) external onlyAgent nonReentrant whenNotEmergency {
        address strategy = namedStrategies[strategyName];
        if (strategy == address(0)) revert StrategyDoesNotExist();
        if (_asset.balanceOf(address(this)) < _amount) revert InsufficientBalance();

        _asset.approve(strategy, _amount);
        IStrategy(strategy).execute(_amount, _data);
        
        strategyAllocations[strategy] += _amount;
        emit StrategyExecuted(strategy, _amount, strategyName);
    }

    function harvestAllStrategies() external onlyAgent nonReentrant returns (uint256 totalHarvested) {
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            string memory name = strategyNames[strategy];
            
            uint256 balanceBefore = _asset.balanceOf(address(this));
            
            try IStrategy(strategy).harvest("") {
                uint256 harvested = _asset.balanceOf(address(this)) - balanceBefore;
                if (harvested > 0) {
                    totalYieldGenerated += harvested;
                    totalHarvested += harvested;
                    
                    // Notify lottery extension
                    if (lotteryExtension != address(0)) {
                        try ILotteryExtension(lotteryExtension).onYieldHarvested(harvested) {
                            // Success
                        } catch {
                            // Continue if extension fails
                        }
                    }
                }
            } catch {
                // Continue with other strategies if one fails
            }
        }

        if (totalHarvested > 0) {
            lastHarvestTime = block.timestamp;
            emit YieldHarvested(totalHarvested);
        }
    }

    // ====================================================================
    // EXTENSION MANAGEMENT
    // ====================================================================

    function setLotteryExtension(address _extension) external onlyRole(MANAGER_ROLE) {
        lotteryExtension = _extension;
        emit ExtensionUpdated(_extension, "lottery");
    }

    function setOptimizationExtension(address _extension) external onlyRole(MANAGER_ROLE) {
        optimizationExtension = _extension;
        emit ExtensionUpdated(_extension, "optimization");
    }

    function setBridgeExtension(address _extension) external onlyRole(MANAGER_ROLE) {
        bridgeExtension = _extension;
        emit ExtensionUpdated(_extension, "bridge");
    }

    // ====================================================================
    // SIMPLE PYTHON AGENT FUNCTIONS
    // ====================================================================

    function getProtocolStatus() external view returns (
        uint256 liquidUSDC,
        uint256 prizePool,
        address lastWinner,
        uint256 totalDeployed,
        uint256 numberOfStrategies,
        uint256 avgAPY,
        bool lotteryReady,
        uint256 timeUntilLottery
    ) {
        liquidUSDC = _asset.balanceOf(address(this)) / 1e6;
        
        // Get lottery info from extension
        if (lotteryExtension != address(0)) {
            try ILotteryExtension(lotteryExtension).getLotteryInfo() returns (
                uint256 pool, address winner, bool ready, uint256 timeLeft
            ) {
                prizePool = pool / 1e6;
                lastWinner = winner;
                lotteryReady = ready;
                timeUntilLottery = timeLeft;
            } catch {
                // Default values if extension fails
            }
        }
        
        totalDeployed = 0;
        for (uint i = 0; i < strategies.length; i++) {
            totalDeployed += strategyAllocations[strategies[i]];
        }
        totalDeployed = totalDeployed / 1e6;
        
        numberOfStrategies = strategies.length;
        avgAPY = 500; // Default 5% APY
    }

    function simulateYieldHarvestAndDeposit(
        uint256 yieldAmount
    ) external onlyAgent nonReentrant returns (bool success, string memory result) {
        if (yieldAmount == 0) {
            return (false, "Zero yield amount");
        }

        totalYieldGenerated += yieldAmount;
        
        // Notify lottery extension
        if (lotteryExtension != address(0)) {
            try ILotteryExtension(lotteryExtension).onYieldHarvested(yieldAmount) {
                // Success
            } catch {
                // Continue if extension fails
            }
        }

        return (true, "Simulated yield harvest successful");
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setPythonAgent(address _newAgent) external onlyRole(MANAGER_ROLE) {
        require(_newAgent != address(0), "Invalid agent");
        
        if (pythonAgent != address(0)) {
            _revokeRole(AGENT_ROLE, pythonAgent);
        }
        
        pythonAgent = _newAgent;
        _grantRole(AGENT_ROLE, _newAgent);
    }

    function setEmergencyMode(bool _enabled) external onlyRole(MANAGER_ROLE) {
        emergencyMode = _enabled;
        emit EmergencyModeToggled(_enabled);
    }

    function setDepositsEnabled(bool _enabled) external onlyRole(MANAGER_ROLE) {
        depositsEnabled = _enabled;
    }

    function setWithdrawalsEnabled(bool _enabled) external onlyRole(MANAGER_ROLE) {
        withdrawalsEnabled = _enabled;
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }

    function getNamedStrategies() external view returns (string[] memory names, address[] memory addresses) {
        names = new string[](strategies.length);
        addresses = new address[](strategies.length);
        
        for (uint i = 0; i < strategies.length; i++) {
            addresses[i] = strategies[i];
            names[i] = strategyNames[strategies[i]];
        }
    }

    // Receive function to accept ETH for gas reserves
    receive() external payable {}

    function withdrawETH(uint256 amount) external onlyRole(MANAGER_ROLE) {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        payable(msg.sender).transfer(amount);
    }
}

// ====================================================================
// INTERFACES
// ====================================================================

interface IStrategy {
    function execute(uint256 amount, bytes calldata data) external;
    function harvest(bytes calldata data) external;
    function getBalance() external view returns (uint256);
}

interface ILotteryExtension {
    function onDeposit(address user, uint256 amount) external;
    function onYieldHarvested(uint256 amount) external;
    function getLotteryInfo() external view returns (
        uint256 prizePool,
        address lastWinner,
        bool lotteryReady,
        uint256 timeUntilLottery
    );
}