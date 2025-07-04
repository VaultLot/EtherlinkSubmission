// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./interfaces/Strategies.sol";

/// @title Vault Contract for Flow (OpenZeppelin v5 Compatible)
/// @notice An ERC4626-compliant vault that manages deposits and allocates them to yield strategies.
/// @dev Implements the IERC4626 interface from scratch.
contract Vault is Ownable, ERC20, AccessControl, ReentrancyGuard, IERC4626 {
    using SafeERC20 for IERC20;

    // --- Roles ---
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    // --- State Variables ---
    IERC20 private immutable _asset;
    address[] public strategies;
    mapping(address => bool) public isStrategy;

    // --- Events ---
    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event StrategyExecuted(address indexed strategy, uint256 amount, bytes data);
    event StrategyHarvested(address indexed strategy, bytes data);

    // --- Errors ---
    error InvalidStrategy();
    error StrategyAlreadyExists();
    error StrategyDoesNotExist();
    error ExecutionFailed();
    error InvalidAddress();
    error InsufficientBalance();

    // --- Modifiers ---
    modifier onlyManager() {
        require(hasRole(MANAGER_ROLE, msg.sender), "Vault: caller is not a manager");
        _;
    }

    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "Vault: caller is not an agent");
        _;
    }

    constructor(
        IERC20 assetToken,
        string memory name,
        string memory symbol,
        address _manager,
        address _agent
    ) ERC20(name, symbol) Ownable(msg.sender) {
        require(address(assetToken) != address(0), "Vault: asset is zero address");
        require(_manager != address(0), "Vault: manager is zero address");
        require(_agent != address(0), "Vault: agent is zero address");

        _asset = assetToken;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(AGENT_ROLE, DEFAULT_ADMIN_ROLE);

        _grantRole(MANAGER_ROLE, _manager);
        _grantRole(AGENT_ROLE, _agent);
    }

    // ========================================================
    // ERC4626 IMPLEMENTATION
    // ========================================================

    /** @dev See {IERC4626-asset}. */
    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 assetsInStrategies = 0;
        for (uint i = 0; i < strategies.length; i++) {
            assetsInStrategies += IStrategies(strategies[i]).getBalance();
        }
        return _asset.balanceOf(address(this)) + assetsInStrategies;
    }

    /** @dev See {IERC4626-convertToShares}. */
    function convertToShares(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding(0)); // Down
    }

    /** @dev See {IERC4626-convertToAssets}. */
    function convertToAssets(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding(0)); // Down
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4626-previewDeposit}. */
    function previewDeposit(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding(0)); // Down
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(uint256 assetsValue, address receiver) public virtual override nonReentrant returns (uint256 shares) {
        shares = previewDeposit(assetsValue);
        _deposit(assetsValue, shares, receiver);
        return shares;
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4626-previewMint}. */
    function previewMint(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding(1)); // Up
    }

    /** @dev See {IERC4626-mint}. */
    function mint(uint256 sharesValue, address receiver) public virtual override nonReentrant returns (uint256 assets) {
        assets = previewMint(sharesValue);
        _deposit(assets, sharesValue, receiver);
        return assets;
    }

    /** @dev See {IERC4626-maxWithdraw}. */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding(0)); // Down
    }

    /** @dev See {IERC4626-previewWithdraw}. */
    function previewWithdraw(uint256 assetsValue) public view virtual override returns (uint256) {
        return _convertToShares(assetsValue, Math.Rounding(1)); // Up
    }

    /** @dev See {IERC4626-withdraw}. */
    function withdraw(uint256 assetsValue, address receiver, address owner) public virtual override nonReentrant returns (uint256 shares) {
        shares = previewWithdraw(assetsValue);
        _withdraw(assetsValue, shares, receiver, owner);
        return shares;
    }

    /** @dev See {IERC4626-maxRedeem}. */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    /** @dev See {IERC4626-previewRedeem}. */
    function previewRedeem(uint256 sharesValue) public view virtual override returns (uint256) {
        return _convertToAssets(sharesValue, Math.Rounding(0)); // Down
    }

    /** @dev See {IERC4626-redeem}. */
    function redeem(uint256 sharesValue, address receiver, address owner) public virtual override nonReentrant returns (uint256 assets) {
        assets = previewRedeem(sharesValue);
        _withdraw(assets, sharesValue, receiver, owner);
        return assets;
    }

    // ========================================================
    // INTERNAL LOGIC
    // ========================================================

    function _deposit(uint256 assetsValue, uint256 sharesValue, address receiver) internal {
        require(receiver != address(0), "Vault: deposit to the zero address");
        require(assetsValue > 0, "Vault: deposit of zero assets");

        _asset.safeTransferFrom(msg.sender, address(this), assetsValue);
        _mint(receiver, sharesValue);
        emit Deposit(msg.sender, receiver, assetsValue, sharesValue);
    }

    function _withdraw(uint256 assetsValue, uint256 sharesValue, address receiver, address owner) internal {
        require(receiver != address(0), "Vault: withdraw to the zero address");
        require(assetsValue > 0, "Vault: withdraw of zero assets");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, sharesValue);
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


    // ========================================================
    // STRATEGY MANAGEMENT
    // ========================================================

    function addStrategy(address _strategy) external onlyManager {
        if (_strategy == address(0)) revert InvalidAddress();
        if (isStrategy[_strategy]) revert StrategyAlreadyExists();

        isStrategy[_strategy] = true;
        strategies.push(_strategy);
        emit StrategyAdded(_strategy);
    }

    function removeStrategy(address _strategy) external onlyManager {
        if (!isStrategy[_strategy]) revert StrategyDoesNotExist();
        isStrategy[_strategy] = false;

        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _strategy) {
                strategies[i] = strategies[strategies.length - 1];
                strategies.pop();
                break;
            }
        }
        emit StrategyRemoved(_strategy);
    }

    function depositToStrategy(
        address _strategy,
        uint256 _amount,
        bytes calldata _data
    ) external onlyAgent nonReentrant {
        if (!isStrategy[_strategy]) revert StrategyDoesNotExist();
        if (_asset.balanceOf(address(this)) < _amount) revert InsufficientBalance();

        // Changed from safeApprove to the standard approve for OZ v5 compatibility
        _asset.approve(_strategy, _amount);
        IStrategies(_strategy).execute(_amount, _data);
        emit StrategyExecuted(_strategy, _amount, _data);
    }
    
    function harvestStrategy(
        address _strategy,
        bytes calldata _data
    ) external onlyAgent nonReentrant {
        if (!isStrategy[_strategy]) revert StrategyDoesNotExist();

        IStrategies(_strategy).harvest(_data);
        emit StrategyHarvested(_strategy, _data);
    }

    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }
}
