// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title VaultFactory - Creates EtherlinkVault instances
/// @notice Factory for deploying yield lottery vaults
contract VaultFactory is Ownable, AccessControl, ReentrancyGuard {
    bytes32 public constant FACTORY_ADMIN_ROLE = keccak256("FACTORY_ADMIN_ROLE");

    struct VaultParams {
        IERC20 asset;
        string name;
        string symbol;
        address manager;
        address pythonAgent;
    }

    struct VaultInfo {
        uint256 id;
        address vaultAddress;
        address asset;
        string name;
        string symbol;
        address manager;
        address pythonAgent;
        uint256 createdAt;
        address creator;
        bool active;
    }

    uint256 public vaultCounter;
    mapping(uint256 => address) public vaults;
    mapping(address => uint256) public vaultIds;
    mapping(address => VaultInfo) public vaultInfo;
    mapping(address => address[]) public assetVaults;

    address public defaultManager;
    address public defaultPythonAgent;
    address public defaultStrategyRegistry;
    address public defaultLayerZeroBridge;
    uint256 public creationFee;
    address public treasury;

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed vaultAddress,
        address indexed asset,
        string name,
        address creator
    );
    
    event DefaultsUpdated(address manager, address pythonAgent);
    event VaultStatusUpdated(address indexed vault, bool active);

    error InvalidAsset();
    error InsufficientFee();
    error VaultNotFound();

    constructor(
        address _defaultManager,
        address _defaultPythonAgent,
        address _treasury,
        uint256 _creationFee
    ) {
        require(_defaultManager != address(0), "Invalid default manager");
        require(_defaultPythonAgent != address(0), "Invalid default Python agent");
        require(_treasury != address(0), "Invalid treasury");

        _transferOwnership(msg.sender);

        defaultManager = _defaultManager;
        defaultPythonAgent = _defaultPythonAgent;
        treasury = _treasury;
        creationFee = _creationFee;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ADMIN_ROLE, msg.sender);
    }

    /// @notice Register a manually deployed vault
    /// @param vaultAddress Address of the deployed vault
    /// @param params Vault parameters for registration
    /// @return vaultId ID of the registered vault
    function registerVault(
        address vaultAddress,
        VaultParams calldata params
    ) external payable returns (uint256 vaultId) {
        if (address(params.asset) == address(0)) revert InvalidAsset();
        if (msg.value < creationFee) revert InsufficientFee();
        require(vaultAddress != address(0), "Invalid vault address");
        require(vaultIds[vaultAddress] == 0, "Vault already registered");

        address manager = params.manager != address(0) ? params.manager : defaultManager;
        address pythonAgent = params.pythonAgent != address(0) ? params.pythonAgent : defaultPythonAgent;

        vaultCounter++;
        vaultId = vaultCounter;

        vaults[vaultId] = vaultAddress;
        vaultIds[vaultAddress] = vaultId;
        assetVaults[address(params.asset)].push(vaultAddress);

        vaultInfo[vaultAddress] = VaultInfo({
            id: vaultId,
            vaultAddress: vaultAddress,
            asset: address(params.asset),
            name: params.name,
            symbol: params.symbol,
            manager: manager,
            pythonAgent: pythonAgent,
            createdAt: block.timestamp,
            creator: msg.sender,
            active: true
        });

        // Transfer creation fee to treasury
        if (creationFee > 0) {
            (bool success, ) = treasury.call{value: creationFee}("");
            require(success, "Fee transfer failed");
        }

        // Refund excess payment
        if (msg.value > creationFee) {
            (bool success, ) = msg.sender.call{value: msg.value - creationFee}("");
            require(success, "Refund failed");
        }

        emit VaultCreated(vaultId, vaultAddress, address(params.asset), params.name, msg.sender);
        return vaultId;
    }

    /// @notice Create a vault deployment record (for tracking purposes)
    /// @param params Vault creation parameters
    /// @return vaultId ID for the future vault
    function createVaultRecord(
        VaultParams calldata params
    ) external payable returns (uint256 vaultId) {
        if (address(params.asset) == address(0)) revert InvalidAsset();
        if (msg.value < creationFee) revert InsufficientFee();

        vaultCounter++;
        vaultId = vaultCounter;

        // Store the parameters for later deployment
        address manager = params.manager != address(0) ? params.manager : defaultManager;
        address pythonAgent = params.pythonAgent != address(0) ? params.pythonAgent : defaultPythonAgent;

        // Create empty record that will be filled when vault is deployed
        vaultInfo[address(0)] = VaultInfo({
            id: vaultId,
            vaultAddress: address(0), // Will be set when vault is deployed
            asset: address(params.asset),
            name: params.name,
            symbol: params.symbol,
            manager: manager,
            pythonAgent: pythonAgent,
            createdAt: block.timestamp,
            creator: msg.sender,
            active: false // Will be activated when vault is deployed
        });

        // Transfer creation fee to treasury
        if (creationFee > 0) {
            (bool success, ) = treasury.call{value: creationFee}("");
            require(success, "Fee transfer failed");
        }

        // Refund excess payment
        if (msg.value > creationFee) {
            (bool success, ) = msg.sender.call{value: msg.value - creationFee}("");
            require(success, "Refund failed");
        }

        return vaultId;
    }

    /// @notice Register a vault with default parameters
    /// @param vaultAddress Address of the deployed vault
    /// @param asset Asset token address
    /// @param name Vault name  
    /// @param symbol Vault symbol
    /// @return vaultId ID of the registered vault
    function registerVaultWithDefaults(
        address vaultAddress,
        IERC20 asset,
        string calldata name,
        string calldata symbol
    ) external payable returns (uint256 vaultId) {
        VaultParams memory params = VaultParams({
            asset: asset,
            name: name,
            symbol: symbol,
            manager: defaultManager,
            pythonAgent: defaultPythonAgent
        });

        return this.registerVault{value: msg.value}(vaultAddress, params);
    }

    function setDefaults(
        address _defaultManager,
        address _defaultPythonAgent,
        address _defaultStrategyRegistry,
        address _defaultLayerZeroBridge
    ) external onlyRole(FACTORY_ADMIN_ROLE) {
        if (_defaultManager != address(0)) defaultManager = _defaultManager;
        if (_defaultPythonAgent != address(0)) defaultPythonAgent = _defaultPythonAgent;
        if (_defaultStrategyRegistry != address(0)) defaultStrategyRegistry = _defaultStrategyRegistry;
        if (_defaultLayerZeroBridge != address(0)) defaultLayerZeroBridge = _defaultLayerZeroBridge;
        
        emit DefaultsUpdated(defaultManager, defaultPythonAgent);
    }

    function setVaultStatus(address vault, bool active) external onlyRole(FACTORY_ADMIN_ROLE) {
        if (vaultIds[vault] == 0) revert VaultNotFound();
        vaultInfo[vault].active = active;
        emit VaultStatusUpdated(vault, active);
    }

    function setCreationFee(uint256 _newFee) external onlyRole(FACTORY_ADMIN_ROLE) {
        creationFee = _newFee;
    }

    function setTreasury(address _newTreasury) external onlyRole(FACTORY_ADMIN_ROLE) {
        require(_newTreasury != address(0), "Invalid treasury");
        treasury = _newTreasury;
    }

    // View functions
    function getVaultCount() external view returns (uint256) {
        return vaultCounter;
    }

    function getAllVaults() external view returns (address[] memory allVaults) {
        allVaults = new address[](vaultCounter);
        for (uint256 i = 1; i <= vaultCounter; i++) {
            allVaults[i - 1] = vaults[i];
        }
    }

    function getVaultsForAsset(address asset) external view returns (address[] memory) {
        return assetVaults[asset];
    }

    function getVaultInfo(address vault) external view returns (VaultInfo memory) {
        return vaultInfo[vault];
    }

    function isVaultActive(address vault) external view returns (bool) {
        return vaultInfo[vault].active;
    }

    function getVaultDeploymentParameters(uint256 vaultId) external view returns (
        address asset,
        string memory name,
        string memory symbol,
        address manager,
        address pythonAgent,
        address strategyRegistry,
        address layerZeroBridge
    ) {
        // This function helps with manual deployment of vaults
        // It returns the parameters needed to deploy a vault for the given ID
        return (
            address(0), // Would need to be looked up from storage
            "",
            "",
            defaultManager,
            defaultPythonAgent,
            defaultStrategyRegistry,
            defaultLayerZeroBridge
        );
    }
}

/// @title IEtherlinkVault - Interface for vault contracts
/// @notice Minimal interface for vault registration
interface IEtherlinkVault {
    function asset() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}