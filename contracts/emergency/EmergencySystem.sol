// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EmergencySystem
/// @notice Emergency controls and circuit breakers for the yield lottery system
/// @dev Provides pause mechanisms and emergency procedures
contract EmergencySystem is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Roles ============
    
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    // ============ Emergency Levels ============
    
    enum EmergencyLevel {
        NONE,       // 0 - Normal operation
        LOW,        // 1 - Minor issue, monitoring increased
        MEDIUM,     // 2 - Partial restrictions
        HIGH,       // 3 - Major restrictions, emergency withdrawals only
        CRITICAL    // 4 - Full lockdown
    }

    // ============ Structs ============
    
    struct EmergencyEvent {
        uint256 id;
        address triggeredBy;
        EmergencyLevel level;
        string reason;
        uint256 timestamp;
        bool resolved;
        uint256 resolvedTimestamp;
        address resolvedBy;
    }

    struct VaultEmergencyState {
        address vault;
        EmergencyLevel currentLevel;
        bool depositsDisabled;
        bool withdrawalsDisabled;
        bool strategiesDisabled;
        bool bridgingDisabled;
        bool lotteryDisabled;
        uint256 lastUpdate;
        uint256 activeIncidents;
    }

    // ============ State Variables ============
    
    mapping(address => VaultEmergencyState) public vaultEmergencyStates;
    mapping(uint256 => EmergencyEvent) public emergencyEvents;
    mapping(address => bool) public authorizedGuardians;
    mapping(address => uint256) public lastGuardianAction;
    
    address[] public monitoredVaults;
    uint256 public eventCounter;
    EmergencyLevel public globalEmergencyLevel = EmergencyLevel.NONE;
    
    // Emergency parameters
    uint256 public emergencyWithdrawalWindow = 24 hours;
    uint256 public guardianCooldown = 1 hours;
    uint256 public maxWithdrawalPerUser = 100000e6; // 100k USDC default

    // ============ Events ============
    
    event EmergencyTriggered(
        uint256 indexed eventId,
        address indexed vault,
        EmergencyLevel level,
        string reason,
        address triggeredBy
    );
    
    event EmergencyResolved(
        uint256 indexed eventId,
        address indexed vault,
        address resolvedBy
    );
    
    event EmergencyWithdrawal(
        address indexed vault,
        address indexed user,
        uint256 amount
    );
    
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event VaultRegistered(address indexed vault);
    event EmergencyParametersUpdated();

    // ============ Errors ============
    
    error EmergencyActive();
    error UnauthorizedGuardian();
    error GuardianCooldownActive();
    error WithdrawalLimitExceeded();
    error VaultNotRegistered();
    error InvalidEmergencyLevel();
    error EventNotFound();
    error EventAlreadyResolved();

    // ============ Constructor ============
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
        _grantRole(GUARDIAN_ROLE, msg.sender);
        
        authorizedGuardians[msg.sender] = true;
    }

    // ============ Emergency Management ============
    
    function registerVault(address vault) external onlyRole(EMERGENCY_ROLE) {
        require(vault != address(0), "Invalid vault address");
        
        if (vaultEmergencyStates[vault].vault == address(0)) {
            monitoredVaults.push(vault);
        }

        vaultEmergencyStates[vault] = VaultEmergencyState({
            vault: vault,
            currentLevel: EmergencyLevel.NONE,
            depositsDisabled: false,
            withdrawalsDisabled: false,
            strategiesDisabled: false,
            bridgingDisabled: false,
            lotteryDisabled: false,
            lastUpdate: block.timestamp,
            activeIncidents: 0
        });

        _grantRole(VAULT_ROLE, vault);
        emit VaultRegistered(vault);
    }

    /// @notice Trigger an emergency for a vault
    /// @param vault Address of the vault
    /// @param level Emergency level to set
    /// @param reason Reason for the emergency
    /// @return eventId Emergency event ID
    function triggerEmergency(
        address vault,
        EmergencyLevel level,
        string memory reason
    ) public returns (uint256 eventId) {
        require(
            hasRole(GUARDIAN_ROLE, msg.sender) || hasRole(EMERGENCY_ROLE, msg.sender),
            "Not authorized"
        );
        require(vaultEmergencyStates[vault].vault != address(0), "Vault not registered");
        require(
            block.timestamp >= lastGuardianAction[msg.sender] + guardianCooldown,
            "Guardian cooldown active"
        );
        require(level != EmergencyLevel.NONE, "Invalid emergency level");

        eventCounter++;
        eventId = eventCounter;

        emergencyEvents[eventId] = EmergencyEvent({
            id: eventId,
            triggeredBy: msg.sender,
            level: level,
            reason: reason,
            timestamp: block.timestamp,
            resolved: false,
            resolvedTimestamp: 0,
            resolvedBy: address(0)
        });

        _setEmergencyLevel(vault, level);
        vaultEmergencyStates[vault].activeIncidents++;
        lastGuardianAction[msg.sender] = block.timestamp;

        emit EmergencyTriggered(eventId, vault, level, reason, msg.sender);
        return eventId;
    }

    function resolveEmergency(
        uint256 eventId,
        address vault
    ) external onlyRole(EMERGENCY_ROLE) {
        if (emergencyEvents[eventId].id == 0) revert EventNotFound();
        if (emergencyEvents[eventId].resolved) revert EventAlreadyResolved();

        emergencyEvents[eventId].resolved = true;
        emergencyEvents[eventId].resolvedTimestamp = block.timestamp;
        emergencyEvents[eventId].resolvedBy = msg.sender;

        VaultEmergencyState storage state = vaultEmergencyStates[vault];
        if (state.activeIncidents > 0) {
            state.activeIncidents--;
        }

        // If no active incidents, return to normal
        if (state.activeIncidents == 0) {
            _setEmergencyLevel(vault, EmergencyLevel.NONE);
        }

        emit EmergencyResolved(eventId, vault, msg.sender);
    }

    function _setEmergencyLevel(address vault, EmergencyLevel level) internal {
        VaultEmergencyState storage state = vaultEmergencyStates[vault];
        state.currentLevel = level;
        state.lastUpdate = block.timestamp;

        // Set restrictions based on emergency level
        if (level == EmergencyLevel.NONE) {
            state.depositsDisabled = false;
            state.withdrawalsDisabled = false;
            state.strategiesDisabled = false;
            state.bridgingDisabled = false;
            state.lotteryDisabled = false;
        } else if (level == EmergencyLevel.LOW) {
            // Monitoring only, no restrictions
        } else if (level == EmergencyLevel.MEDIUM) {
            state.strategiesDisabled = true;
            state.bridgingDisabled = true;
        } else if (level == EmergencyLevel.HIGH) {
            state.depositsDisabled = true;
            state.strategiesDisabled = true;
            state.bridgingDisabled = true;
            state.lotteryDisabled = true;
        } else if (level == EmergencyLevel.CRITICAL) {
            state.depositsDisabled = true;
            state.withdrawalsDisabled = true;
            state.strategiesDisabled = true;
            state.bridgingDisabled = true;
            state.lotteryDisabled = true;
        }

        // Update global emergency level
        _updateGlobalEmergencyLevel();
    }

    function _updateGlobalEmergencyLevel() internal {
        EmergencyLevel maxLevel = EmergencyLevel.NONE;
        
        for (uint256 i = 0; i < monitoredVaults.length; i++) {
            EmergencyLevel vaultLevel = vaultEmergencyStates[monitoredVaults[i]].currentLevel;
            if (vaultLevel > maxLevel) {
                maxLevel = vaultLevel;
            }
        }
        
        globalEmergencyLevel = maxLevel;
    }

    // ============ Emergency Checks ============
    
    function checkEmergencyRestrictions(
        address vault,
        string memory action
    ) external view returns (bool allowed, string memory restrictionReason) {
        VaultEmergencyState memory state = vaultEmergencyStates[vault];
        
        bytes32 actionHash = keccak256(bytes(action));
        
        if (actionHash == keccak256(bytes("deposit"))) {
            if (state.depositsDisabled) {
                return (false, "Deposits disabled due to emergency");
            }
        } else if (actionHash == keccak256(bytes("withdraw"))) {
            if (state.withdrawalsDisabled) {
                return (false, "Withdrawals disabled due to emergency");
            }
        } else if (actionHash == keccak256(bytes("strategy"))) {
            if (state.strategiesDisabled) {
                return (false, "Strategy operations disabled due to emergency");
            }
        } else if (actionHash == keccak256(bytes("bridge"))) {
            if (state.bridgingDisabled) {
                return (false, "Bridging disabled due to emergency");
            }
        } else if (actionHash == keccak256(bytes("lottery"))) {
            if (state.lotteryDisabled) {
                return (false, "Lottery disabled due to emergency");
            }
        }
        
        return (true, "");
    }

    function isEmergencyActive(address vault) external view returns (bool) {
        return vaultEmergencyStates[vault].currentLevel > EmergencyLevel.NONE;
    }

    function getEmergencyLevel(address vault) external view returns (EmergencyLevel) {
        return vaultEmergencyStates[vault].currentLevel;
    }

    // ============ Guardian Management ============
    
    function addGuardian(address guardian) external onlyRole(EMERGENCY_ROLE) {
        require(guardian != address(0), "Invalid guardian");
        authorizedGuardians[guardian] = true;
        _grantRole(GUARDIAN_ROLE, guardian);
        emit GuardianAdded(guardian);
    }

    function removeGuardian(address guardian) external onlyRole(EMERGENCY_ROLE) {
        authorizedGuardians[guardian] = false;
        _revokeRole(GUARDIAN_ROLE, guardian);
        emit GuardianRemoved(guardian);
    }

    function isGuardian(address account) external view returns (bool) {
        return authorizedGuardians[account];
    }

    // ============ Emergency Procedures ============
    
    function emergencyPauseVault(address vault) external onlyRole(GUARDIAN_ROLE) {
        string memory reason = "Emergency pause triggered by guardian";
        triggerEmergency(vault, EmergencyLevel.HIGH, reason);
    }

    function emergencyShutdown(address vault) external onlyRole(EMERGENCY_ROLE) {
        string memory reason = "Emergency shutdown";
        triggerEmergency(vault, EmergencyLevel.CRITICAL, reason);
    }

    function batchEmergencyShutdown(address[] calldata vaults) external onlyRole(EMERGENCY_ROLE) {
        for (uint256 i = 0; i < vaults.length; i++) {
            string memory reason = "Batch emergency shutdown";
            triggerEmergency(vaults[i], EmergencyLevel.CRITICAL, reason);
        }
    }

    /// @notice Activate emergency mode system-wide
    /// @param reason Reason for activating emergency mode
    function activateEmergencyMode(string memory reason) external onlyRole(EMERGENCY_ROLE) {
        // Set all monitored vaults to CRITICAL
        for (uint256 i = 0; i < monitoredVaults.length; i++) {
            address vault = monitoredVaults[i];
            if (vaultEmergencyStates[vault].currentLevel < EmergencyLevel.CRITICAL) {
                triggerEmergency(vault, EmergencyLevel.CRITICAL, reason);
            }
        }
    }

    /// @notice Deactivate emergency mode system-wide  
    function deactivateEmergencyMode() external onlyRole(EMERGENCY_ROLE) {
        // Resolve all active emergencies
        for (uint256 i = 1; i <= eventCounter; i++) {
            if (!emergencyEvents[i].resolved) {
                emergencyEvents[i].resolved = true;
                emergencyEvents[i].resolvedTimestamp = block.timestamp;
                emergencyEvents[i].resolvedBy = msg.sender;
            }
        }
        
        // Reset all vault states
        for (uint256 i = 0; i < monitoredVaults.length; i++) {
            address vault = monitoredVaults[i];
            vaultEmergencyStates[vault].activeIncidents = 0;
            _setEmergencyLevel(vault, EmergencyLevel.NONE);
        }
    }

    // ============ Configuration ============
    
    function setEmergencyParameters(
        uint256 _emergencyWithdrawalWindow,
        uint256 _guardianCooldown,
        uint256 _maxWithdrawalPerUser
    ) external onlyRole(EMERGENCY_ROLE) {
        emergencyWithdrawalWindow = _emergencyWithdrawalWindow;
        guardianCooldown = _guardianCooldown;
        maxWithdrawalPerUser = _maxWithdrawalPerUser;
        
        emit EmergencyParametersUpdated();
    }

    // ============ View Functions ============
    
    function getVaultEmergencyState(address vault) external view returns (VaultEmergencyState memory) {
        return vaultEmergencyStates[vault];
    }

    function getEmergencyEvent(uint256 eventId) external view returns (EmergencyEvent memory) {
        return emergencyEvents[eventId];
    }

    function getActiveEmergencies() external view returns (uint256[] memory activeEvents) {
        uint256 count = 0;
        
        // Count active events
        for (uint256 i = 1; i <= eventCounter; i++) {
            if (!emergencyEvents[i].resolved) {
                count++;
            }
        }
        
        activeEvents = new uint256[](count);
        uint256 index = 0;
        
        // Populate active events
        for (uint256 i = 1; i <= eventCounter; i++) {
            if (!emergencyEvents[i].resolved && index < count) {
                activeEvents[index] = i;
                index++;
            }
        }
    }

    function getMonitoredVaults() external view returns (address[] memory) {
        return monitoredVaults;
    }

    function getEmergencyStats() external view returns (
        uint256 totalEvents,
        uint256 activeEvents,
        uint256 monitoredVaultCount,
        EmergencyLevel currentGlobalLevel
    ) {
        uint256 active = 0;
        for (uint256 i = 1; i <= eventCounter; i++) {
            if (!emergencyEvents[i].resolved) {
                active++;
            }
        }
        
        return (eventCounter, active, monitoredVaults.length, globalEmergencyLevel);
    }

    // ============ Helper Functions ============
    
    function emergencyLevelToString(EmergencyLevel level) public pure returns (string memory) {
        if (level == EmergencyLevel.NONE) return "NONE";
        if (level == EmergencyLevel.LOW) return "LOW";
        if (level == EmergencyLevel.MEDIUM) return "MEDIUM";
        if (level == EmergencyLevel.HIGH) return "HIGH";
        if (level == EmergencyLevel.CRITICAL) return "CRITICAL";
        return "UNKNOWN";
    }

    function stringToEmergencyLevel(string memory levelStr) public pure returns (EmergencyLevel) {
        bytes32 levelHash = keccak256(bytes(levelStr));
        
        if (levelHash == keccak256(bytes("NONE"))) return EmergencyLevel.NONE;
        if (levelHash == keccak256(bytes("LOW"))) return EmergencyLevel.LOW;
        if (levelHash == keccak256(bytes("MEDIUM"))) return EmergencyLevel.MEDIUM;
        if (levelHash == keccak256(bytes("HIGH"))) return EmergencyLevel.HIGH;
        if (levelHash == keccak256(bytes("CRITICAL"))) return EmergencyLevel.CRITICAL;
        
        revert InvalidEmergencyLevel();
    }
}