// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title LotteryExtension - Lottery functionality for EtherlinkVaultCore
/// @notice Handles all lottery-related operations as a separate extension
contract LotteryExtension is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant LOTTERY_MANAGER_ROLE = keccak256("LOTTERY_MANAGER_ROLE");

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================

    address public vault;
    IERC20 public asset;
    
    // Lottery state
    uint256 public accumulatedYield;
    uint256 public lotteryInterval = 7 days;
    uint256 public lastLotteryTime;
    address public lastWinner;
    uint256 public lastPayout;
    uint256 public lotteryCount;
    
    // User deposits for lottery
    struct UserDeposit {
        uint256 amount;
        uint256 depositTime;
        uint256 totalRewards;
        bool active;
    }
    
    mapping(address => UserDeposit) public userDeposits;
    address[] public depositors;
    mapping(address => uint256) public depositorIndex;
    uint256 public totalLotteryDeposits;
    
    // Lottery history
    mapping(uint256 => address) public lotteryWinners;
    mapping(uint256 => uint256) public lotteryPayouts;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event LotteryExecuted(uint256 indexed lotteryId, address indexed winner, uint256 payout, uint256 participants);
    event UserDepositUpdated(address indexed user, uint256 amount, bool isDeposit);
    event YieldAccumulated(uint256 amount, uint256 totalAccumulated);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(address _vault, address _asset) {
        require(_vault != address(0), "Invalid vault");
        require(_asset != address(0), "Invalid asset");
        
        vault = _vault;
        asset = IERC20(_asset);
        lastLotteryTime = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(LOTTERY_MANAGER_ROLE, msg.sender);
    }

    // ====================================================================
    // VAULT INTERFACE FUNCTIONS
    // ====================================================================

    function onDeposit(address user, uint256 amount) external onlyRole(VAULT_ROLE) {
        _updateUserDeposit(user, amount, true);
    }

    function onWithdraw(address user, uint256 amount) external onlyRole(VAULT_ROLE) {
        _updateUserDeposit(user, amount, false);
    }

    function onYieldHarvested(uint256 amount) external onlyRole(VAULT_ROLE) {
        accumulatedYield += amount;
        emit YieldAccumulated(amount, accumulatedYield);
        
        // Check if lottery should be triggered
        if (_shouldTriggerLottery()) {
            _executeLottery();
        }
    }

    // ====================================================================
    // LOTTERY LOGIC
    // ====================================================================

    function _updateUserDeposit(address user, uint256 amount, bool isDeposit) internal {
        UserDeposit storage userDeposit = userDeposits[user];
        
        if (isDeposit) {
            if (userDeposit.amount == 0) {
                // New depositor
                depositors.push(user);
                depositorIndex[user] = depositors.length - 1;
                userDeposit.depositTime = block.timestamp;
                userDeposit.active = true;
            }
            userDeposit.amount += amount;
            totalLotteryDeposits += amount;
        } else {
            // Withdrawal
            if (userDeposit.amount >= amount) {
                userDeposit.amount -= amount;
                totalLotteryDeposits -= amount;
                
                if (userDeposit.amount == 0) {
                    // Remove depositor
                    userDeposit.active = false;
                    _removeDepositor(user);
                }
            }
        }
        
        emit UserDepositUpdated(user, amount, isDeposit);
    }

    function _removeDepositor(address user) internal {
        uint256 index = depositorIndex[user];
        uint256 lastIndex = depositors.length - 1;
        
        if (index != lastIndex) {
            address lastDepositor = depositors[lastIndex];
            depositors[index] = lastDepositor;
            depositorIndex[lastDepositor] = index;
        }
        
        depositors.pop();
        delete depositorIndex[user];
    }

    function _shouldTriggerLottery() internal view returns (bool) {
        return block.timestamp >= lastLotteryTime + lotteryInterval &&
               depositors.length > 0 &&
               accumulatedYield > 0;
    }

    function _executeLottery() internal {
        address winner = _selectRandomWinner();
        uint256 payout = accumulatedYield;
        
        // Update user's lifetime rewards
        userDeposits[winner].totalRewards += payout;
        
        // Transfer yield to winner
        asset.safeTransfer(winner, payout);
        
        // Update state
        lastWinner = winner;
        lastPayout = payout;
        lastLotteryTime = block.timestamp;
        lotteryCount++;
        
        // Store lottery history
        lotteryWinners[lotteryCount] = winner;
        lotteryPayouts[lotteryCount] = payout;
        
        // Reset accumulated yield
        accumulatedYield = 0;
        
        emit LotteryExecuted(lotteryCount, winner, payout, depositors.length);
    }

    function _selectRandomWinner() internal view returns (address) {
        // Enhanced randomness using multiple sources
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            blockhash(block.number - 1),
            totalLotteryDeposits,
            lotteryCount
        )));

        uint256 winningNumber = randomSeed % totalLotteryDeposits;
        uint256 currentSum = 0;

        for (uint256 i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            if (userDeposits[depositor].active) {
                currentSum += userDeposits[depositor].amount;
                if (winningNumber < currentSum) {
                    return depositor;
                }
            }
        }

        // Fallback to first depositor
        return depositors[0];
    }

    // ====================================================================
    // MANUAL LOTTERY FUNCTIONS
    // ====================================================================

    function executeLottery() external onlyRole(LOTTERY_MANAGER_ROLE) nonReentrant returns (address winner) {
        require(_shouldTriggerLottery(), "Lottery conditions not met");
        
        winner = _selectRandomWinner();
        uint256 payout = accumulatedYield;
        
        // Update user's lifetime rewards
        userDeposits[winner].totalRewards += payout;
        
        // Transfer yield to winner
        asset.safeTransfer(winner, payout);
        
        // Update state
        lastWinner = winner;
        lastPayout = payout;
        lastLotteryTime = block.timestamp;
        lotteryCount++;
        
        // Store lottery history
        lotteryWinners[lotteryCount] = winner;
        lotteryPayouts[lotteryCount] = payout;
        
        // Reset accumulated yield
        accumulatedYield = 0;
        
        emit LotteryExecuted(lotteryCount, winner, payout, depositors.length);
        return winner;
    }

    function depositYieldForLottery(uint256 amount) external onlyRole(LOTTERY_MANAGER_ROLE) {
        require(amount > 0, "Invalid amount");
        asset.safeTransferFrom(msg.sender, address(this), amount);
        accumulatedYield += amount;
        emit YieldAccumulated(amount, accumulatedYield);
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getLotteryInfo() external view returns (
        uint256 prizePool,
        address winner,
        bool lotteryReady,
        uint256 timeUntilLottery
    ) {
        prizePool = accumulatedYield;
        winner = lastWinner;
        lotteryReady = _shouldTriggerLottery();
        timeUntilLottery = lastLotteryTime + lotteryInterval > block.timestamp 
            ? (lastLotteryTime + lotteryInterval - block.timestamp) 
            : 0;
    }

    function getUserLotteryInfo(address user) external view returns (
        uint256 currentDeposit,
        uint256 winProbability, // in basis points
        uint256 lifetimeRewards,
        bool isActive
    ) {
        UserDeposit memory userDeposit = userDeposits[user];
        
        currentDeposit = userDeposit.amount;
        lifetimeRewards = userDeposit.totalRewards;
        isActive = userDeposit.active;
        
        // Calculate win probability
        if (totalLotteryDeposits > 0 && userDeposit.active) {
            winProbability = (userDeposit.amount * 10000) / totalLotteryDeposits;
        } else {
            winProbability = 0;
        }
    }

    function getDepositors() external view returns (address[] memory) {
        return depositors;
    }

    function getLotteryHistory(uint256 count) external view returns (
        address[] memory winners,
        uint256[] memory payouts,
        uint256[] memory lotteryIds
    ) {
        uint256 startId = lotteryCount > count ? lotteryCount - count + 1 : 1;
        uint256 actualCount = lotteryCount - startId + 1;
        
        winners = new address[](actualCount);
        payouts = new uint256[](actualCount);
        lotteryIds = new uint256[](actualCount);
        
        for (uint256 i = 0; i < actualCount; i++) {
            uint256 id = startId + i;
            winners[i] = lotteryWinners[id];
            payouts[i] = lotteryPayouts[id];
            lotteryIds[i] = id;
        }
    }

    function isLotteryReady() external view returns (bool) {
        return _shouldTriggerLottery();
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setLotteryInterval(uint256 _interval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_interval >= 1 days, "Interval too short");
        lotteryInterval = _interval;
    }

    function setVault(address _newVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newVault != address(0), "Invalid vault");
        
        _revokeRole(VAULT_ROLE, vault);
        vault = _newVault;
        _grantRole(VAULT_ROLE, _newVault);
    }

    function emergencyWithdraw(uint256 amount, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        require(amount <= asset.balanceOf(address(this)), "Insufficient balance");
        
        asset.safeTransfer(to, amount);
    }
}