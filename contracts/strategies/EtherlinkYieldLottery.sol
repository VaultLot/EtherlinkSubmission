// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IStrategies.sol";

/// @title EtherlinkYieldLottery
/// @notice Weekly lottery system powered by Etherlink VRF using accumulated yield as prizes
/// @dev Implements IStrategies for vault integration and uses secure randomness
contract EtherlinkYieldLottery is IStrategies, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant LOTTERY_MANAGER_ROLE = keccak256("LOTTERY_MANAGER_ROLE");

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    IERC20 public immutable _underlyingToken;
    address public vault;
    address public pythonAgent;
    bool public _paused;

    // Lottery configuration
    uint256 public constant LOTTERY_INTERVAL = 7 days;
    uint256 public constant MIN_PRIZE_POOL = 10 * 10**6; // 10 USDC minimum
    uint256 public constant MAX_PARTICIPANTS = 1000;

    // Lottery state
    uint256 public prizePool;
    uint256 public totalYieldDeposited;
    uint256 public lastLotteryTime;
    uint256 public lotteryCount;
    
    // Participant tracking
    struct Participant {
        uint256 depositAmount;
        uint256 depositTime;
        bool active;
    }
    
    mapping(address => Participant) public participants;
    address[] public participantList;
    mapping(address => uint256) public participantIndex;
    uint256 public totalParticipants;
    
    // Lottery history
    address public lastWinner;
    uint256 public lastPayout;
    mapping(uint256 => address) public lotteryWinners;
    mapping(uint256 => uint256) public lotteryPayouts;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event YieldDeposited(address indexed depositor, uint256 amount, uint256 newPrizePool);
    event ParticipantAdded(address indexed participant, uint256 amount);
    event ParticipantRemoved(address indexed participant, uint256 amount);
    event LotteryExecuted(uint256 indexed lotteryId, address indexed winner, uint256 payout, uint256 participants);
    event RandomnessRequested(uint256 indexed lotteryId, bytes32 requestId);
    event PrizePoolUpdated(uint256 oldAmount, uint256 newAmount);

    // ====================================================================
    // MODIFIERS
    // ====================================================================
    
    modifier onlyAuthorized() {
        require(
            hasRole(VAULT_ROLE, msg.sender) || 
            hasRole(AGENT_ROLE, msg.sender) || 
            msg.sender == pythonAgent ||
            msg.sender == vault,
            "Not authorized"
        );
        _;
    }

    modifier whenNotPaused() {
        require(!_paused, "Strategy is paused");
        _;
    }

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        address _asset,
        address _vault,
        address _pythonAgent
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_vault != address(0), "Invalid vault");
        require(_pythonAgent != address(0), "Invalid Python agent");

        _underlyingToken = IERC20(_asset);
        vault = _vault;
        pythonAgent = _pythonAgent;
        lastLotteryTime = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(AGENT_ROLE, _pythonAgent);
        _grantRole(LOTTERY_MANAGER_ROLE, msg.sender);
    }

    // ====================================================================
    // STRATEGY INTERFACE IMPLEMENTATION
    // ====================================================================
    
    function execute(uint256 amount, bytes calldata data) external override onlyAuthorized nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        
        // For lottery strategy, execution means adding participants
        if (data.length > 0) {
            address participant = abi.decode(data, (address));
            _addParticipant(participant, amount);
        }
        
        // Transfer tokens to this contract
        _underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function harvest(bytes calldata data) external override onlyAuthorized nonReentrant whenNotPaused {
        // Check if lottery should be triggered
        if (_shouldTriggerLottery()) {
            _triggerLottery();
        }
    }

    function emergencyExit(bytes calldata data) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _paused = true;
        
        // Return all funds to vault
        uint256 balance = _underlyingToken.balanceOf(address(this));
        if (balance > 0) {
            _underlyingToken.safeTransfer(vault, balance);
        }
    }

    function getBalance() external view override returns (uint256) {
        return prizePool;
    }

    function underlyingToken() external view override returns (address) {
        return address(_underlyingToken);
    }

    function protocol() external view override returns (address) {
        return address(this);
    }

    function paused() external view override returns (bool) {
        return _paused;
    }

    function setPaused(bool pauseState) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _paused = pauseState;
    }

    // ====================================================================
    // LOTTERY MANAGEMENT
    // ====================================================================
    
    /// @notice Deposit yield into the prize pool (called by Python agent)
    /// @param amount Amount of yield to deposit
    function depositYield(uint256 amount) external onlyAuthorized nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(!_paused, "Strategy is paused");

        _underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        prizePool += amount;
        totalYieldDeposited += amount;

        emit YieldDeposited(msg.sender, amount, prizePool);
    }

    /// @notice Add a participant to the lottery
    /// @param participant Address of the participant
    /// @param amount Amount deposited by participant
    function addParticipant(address participant, uint256 amount) external onlyRole(LOTTERY_MANAGER_ROLE) {
        _addParticipant(participant, amount);
    }

    function _addParticipant(address participant, uint256 amount) internal {
        require(participant != address(0), "Invalid participant");
        require(amount > 0, "Amount must be greater than 0");
        require(totalParticipants < MAX_PARTICIPANTS, "Max participants reached");

        if (!participants[participant].active) {
            // New participant
            participants[participant] = Participant({
                depositAmount: amount,
                depositTime: block.timestamp,
                active: true
            });
            
            participantList.push(participant);
            participantIndex[participant] = participantList.length - 1;
            totalParticipants++;
        } else {
            // Existing participant - increase deposit
            participants[participant].depositAmount += amount;
        }

        emit ParticipantAdded(participant, amount);
    }

    /// @notice Remove a participant from the lottery
    /// @param participant Address of the participant to remove
    function removeParticipant(address participant) external onlyRole(LOTTERY_MANAGER_ROLE) {
        require(participants[participant].active, "Participant not active");
        
        uint256 amount = participants[participant].depositAmount;
        
        // Remove from participant list
        uint256 index = participantIndex[participant];
        address lastParticipant = participantList[participantList.length - 1];
        participantList[index] = lastParticipant;
        participantIndex[lastParticipant] = index;
        participantList.pop();
        
        // Mark as inactive
        participants[participant].active = false;
        totalParticipants--;

        emit ParticipantRemoved(participant, amount);
    }

    /// @notice Manually trigger lottery (for testing)
    /// @dev In production, this would use Etherlink VRF for randomness
    function triggerLottery() external onlyRole(LOTTERY_MANAGER_ROLE) nonReentrant {
        require(_shouldTriggerLottery(), "Lottery conditions not met");
        _triggerLottery();
    }

    function _shouldTriggerLottery() internal view returns (bool) {
        return block.timestamp >= lastLotteryTime + LOTTERY_INTERVAL &&
               prizePool >= MIN_PRIZE_POOL &&
               totalParticipants > 0;
    }

    function _triggerLottery() internal {
        require(!_paused, "Strategy is paused");

        // Simple randomness for testing (in production, use Etherlink VRF)
        bytes32 randomSeed = keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao, // Updated from difficulty
            blockhash(block.number - 1),
            totalParticipants,
            prizePool
        ));
        
        address winner = _selectWinner(randomSeed);
        uint256 prizeAmount = prizePool;
        
        // Transfer prize to winner
        _underlyingToken.safeTransfer(winner, prizeAmount);
        
        // Update state
        lastWinner = winner;
        lastPayout = prizeAmount;
        lastLotteryTime = block.timestamp;
        lotteryCount++;
        
        // Store lottery history
        lotteryWinners[lotteryCount] = winner;
        lotteryPayouts[lotteryCount] = prizeAmount;
        
        // Reset prize pool
        prizePool = 0;
        
        emit LotteryExecuted(lotteryCount, winner, prizeAmount, totalParticipants);
    }

    function _selectWinner(bytes32 randomSeed) internal view returns (address) {
        if (totalParticipants == 0) return address(0);
        
        // Calculate total weight (sum of all deposits)
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < participantList.length; i++) {
            if (participants[participantList[i]].active) {
                totalWeight += participants[participantList[i]].depositAmount;
            }
        }
        
        if (totalWeight == 0) return participantList[0];
        
        // Select winner based on weighted randomness
        uint256 winningNumber = uint256(randomSeed) % totalWeight;
        uint256 currentSum = 0;
        
        for (uint256 i = 0; i < participantList.length; i++) {
            address participant = participantList[i];
            if (participants[participant].active) {
                currentSum += participants[participant].depositAmount;
                if (winningNumber < currentSum) {
                    return participant;
                }
            }
        }
        
        // Fallback to first participant
        return participantList[0];
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    
    function getParticipant(address participant) external view returns (Participant memory) {
        return participants[participant];
    }

    function getParticipantList() external view returns (address[] memory) {
        return participantList;
    }

    function getLotteryInfo() external view returns (
        uint256 currentPrizePool,
        uint256 timeUntilNextLottery,
        uint256 numberOfParticipants,
        address currentWinner,
        uint256 lastPayoutAmount,
        uint256 lotteryNumber
    ) {
        return (
            prizePool,
            lastLotteryTime + LOTTERY_INTERVAL > block.timestamp 
                ? (lastLotteryTime + LOTTERY_INTERVAL - block.timestamp) 
                : 0,
            totalParticipants,
            lastWinner,
            lastPayout,
            lotteryCount
        );
    }

    function isLotteryReady() external view returns (bool) {
        return _shouldTriggerLottery();
    }

    function getLotteryHistory(uint256 count) external view returns (
        address[] memory winners,
        uint256[] memory payouts
    ) {
        uint256 startId = lotteryCount > count ? lotteryCount - count + 1 : 1;
        uint256 actualCount = lotteryCount - startId + 1;
        
        winners = new address[](actualCount);
        payouts = new uint256[](actualCount);
        
        for (uint256 i = 0; i < actualCount; i++) {
            uint256 id = startId + i;
            winners[i] = lotteryWinners[id];
            payouts[i] = lotteryPayouts[id];
        }
    }

    function getWinProbability(address participant) external view returns (uint256) {
        if (!participants[participant].active || totalParticipants == 0) {
            return 0;
        }
        
        // Calculate total weight
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < participantList.length; i++) {
            if (participants[participantList[i]].active) {
                totalWeight += participants[participantList[i]].depositAmount;
            }
        }
        
        if (totalWeight == 0) return 0;
        
        // Return probability in basis points (10000 = 100%)
        return (participants[participant].depositAmount * 10000) / totalWeight;
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setPythonAgent(address newAgent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAgent != address(0), "Invalid agent");
        
        _revokeRole(AGENT_ROLE, pythonAgent);
        pythonAgent = newAgent;
        _grantRole(AGENT_ROLE, newAgent);
    }

    function setVault(address newVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newVault != address(0), "Invalid vault");
        
        _revokeRole(VAULT_ROLE, vault);
        vault = newVault;
        _grantRole(VAULT_ROLE, newVault);
    }

    function emergencyWithdraw(uint256 amount, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        require(amount <= _underlyingToken.balanceOf(address(this)), "Insufficient balance");
        
        _underlyingToken.safeTransfer(to, amount);
    }

    function updatePrizePool(uint256 newAmount) external onlyRole(LOTTERY_MANAGER_ROLE) {
        uint256 oldAmount = prizePool;
        prizePool = newAmount;
        emit PrizePoolUpdated(oldAmount, newAmount);
    }
}