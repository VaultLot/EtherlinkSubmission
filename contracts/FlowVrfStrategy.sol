// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// This import path has been updated for OpenZeppelin v5
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/Strategies.sol";

/// @title FlowVrfYieldStrategy
/// @notice A strategy that collects deposits and uses yield from another source (e.g., Aave) to fund a no-loss lottery. The winner is chosen using Flow's native VRF.
/// @dev This contract showcases integration with Flow's native randomness feature.
contract FlowVrfYieldStrategy is IStrategies, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Address of the Flow's Cadence Arch contract for VRF
    address constant public CADENCE_ARCH = 0x0000000000000000000000010000000000000001;

    address public immutable vault;
    // Changed from public to internal to resolve function signature conflict
    IERC20 internal immutable _underlyingToken;
    address public immutable yieldSource; // e.g., an Aave or Compound strategy contract

    address[] public depositors;
    mapping(address => uint256) public depositAmounts;
    uint256 public totalDeposited;
    address public lastWinner;
    bool public paused;

    event YieldDeposited(uint256 amount);
    event WinnerAwarded(address indexed winner, uint256 amount);

    constructor(address _vault, address _underlying, address _yieldSource) {
        vault = _vault;
        _underlyingToken = IERC20(_underlying);
        yieldSource = _yieldSource;
    }

    function execute(uint256 amount, bytes calldata data) external override nonReentrant {
        require(msg.sender == vault, "Only vault can execute");
        require(!paused, "Strategy is paused");
        require(amount > 0, "Amount must be positive");

        if (depositAmounts[tx.origin] == 0) {
            depositors.push(tx.origin);
        }
        depositAmounts[tx.origin] += amount;
        totalDeposited += amount;
        
        emit Deposit(amount);
    }

    function depositYield(uint256 yieldAmount) external nonReentrant {
        require(yieldAmount > 0, "Yield must be positive");
        _underlyingToken.safeTransferFrom(msg.sender, address(this), yieldAmount);
        emit YieldDeposited(yieldAmount);
    }
    
    function harvest(bytes calldata data) external override nonReentrant {
        require(msg.sender == vault, "Only vault can call harvest");
        uint256 yieldBalance = _underlyingToken.balanceOf(address(this)) - totalDeposited;

        if (yieldBalance > 0 && depositors.length > 0) {
            address winner = _pickWinner();
            lastWinner = winner;
            
            _underlyingToken.safeTransfer(winner, yieldBalance);
            emit WinnerAwarded(winner, yieldBalance);
        }
        emit Harvested(data);
    }

    function _pickWinner() internal view returns (address) {
        (bool ok, bytes memory data) = CADENCE_ARCH.staticcall(
            abi.encodeWithSignature("revertibleRandom()")
        );
        require(ok, "Failed to fetch random number from Flow VRF");
        
        uint64 randomNumber = abi.decode(data, (uint64));
        
        uint256 winnerIndex = randomNumber % depositors.length;
        return depositors[winnerIndex];
    }
    
    function emergencyExit(bytes calldata data) external override {
        require(msg.sender == vault, "Only vault can exit");
        uint256 balance = _underlyingToken.balanceOf(address(this));
        if (balance > 0) {
            _underlyingToken.safeTransfer(vault, balance);
        }
        emit EmergencyExited(balance, data);
    }

    function getBalance() public view override returns (uint256) {
        return _underlyingToken.balanceOf(address(this));
    }

    // --- Interface Compliance ---
    
    function underlyingToken() external view override returns (address) { 
        return address(_underlyingToken); 
    }

    // NOTE: The explicit `paused()` function was removed.
    // The `bool public paused;` state variable automatically creates a public getter.

    function knownRewardTokens(address token) external view override returns (bool) {
        return token == address(_underlyingToken);
    }

    function rewardTokensList() external view override returns (address[] memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = address(_underlyingToken);
        return tokens;
    }

    function setPaused(bool _paused) external override {
        // In a real implementation, this should be restricted (e.g., onlyAgent)
        require(msg.sender == vault, "Only vault can set pause");
        paused = _paused;
    }

    // --- Unused Functions for this Strategy ---
    function protocol() external pure override returns (address) { return address(0); }
    function depositSelector() external pure override returns (bytes4) { return bytes4(0); }
    function withdrawSelector() external pure override returns (bytes4) { return bytes4(0); }
    function claimSelector() external pure override returns (bytes4) { return bytes4(0); }
    function getBalanceSelector() external pure override returns (bytes4) { return bytes4(0); }
    function setVault(address _vault) external override {}
    function addRewardToken(address tokenAddress) external override {}
    function claimRewards(bytes calldata data) external override {}
    function queryProtocol(bytes4 selector, bytes calldata params) external view override returns (bytes memory) { return ""; }
}
