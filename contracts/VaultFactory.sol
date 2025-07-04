// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Vault.sol";

/// @title VaultFactory Contract for Flow
/// @notice Factory contract for creating and managing Vault instances on Flow.
/// @dev Implements access control for vault creation and management.
contract VaultFactory is Ownable {
    uint256 public vaultCounter;
    mapping(uint256 => address) public vaults;

    address public defaultManager;
    address public defaultAgent;
    uint256 public creationFee;
    address public treasury;

    struct VaultParams {
        IERC20 asset;
        string name;
        string symbol;
        address manager;
        address agent;
    }

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed vaultAddress,
        address indexed asset,
        address creator
    );

    error InvalidAsset();
    error InsufficientFee();

    constructor(
        address _defaultManager,
        address _defaultAgent,
        address _treasury,
        uint256 _creationFee
    ) Ownable(msg.sender) {
        defaultManager = _defaultManager;
        defaultAgent = _defaultAgent;
        treasury = _treasury;
        creationFee = _creationFee;
    }

    function createVault(
        VaultParams calldata params
    ) external payable returns (address vaultAddress, uint256 vaultId) {
        if (address(params.asset) == address(0)) revert InvalidAsset();
        if (msg.value < creationFee) revert InsufficientFee();

        address manager = params.manager != address(0) ? params.manager : defaultManager;
        address agent = params.agent != address(0) ? params.agent : defaultAgent;

        vaultCounter++;
        vaultId = vaultCounter;

        // Note: The deBridgeGate parameter has been removed for Flow-specific deployment.
        Vault vault = new Vault(
            params.asset,
            params.name,
            params.symbol,
            manager,
            agent
        );

        vaultAddress = address(vault);
        vaults[vaultId] = vaultAddress;

        if (creationFee > 0) {
            (bool success, ) = treasury.call{value: creationFee}("");
            require(success, "Fee transfer failed");
        }

        emit VaultCreated(vaultId, vaultAddress, address(params.asset), msg.sender);
        return (vaultAddress, vaultId);
    }

    function getVaultCount() external view returns (uint256) {
        return vaultCounter;
    }

    // --- Admin Functions ---
    function setTreasury(address _newTreasury) external onlyOwner {
        treasury = _newTreasury;
    }

    function setCreationFee(uint256 _newFee) external onlyOwner {
        creationFee = _newFee;
    }
}