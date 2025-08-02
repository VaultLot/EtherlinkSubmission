// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockUSDT
/// @notice Mock USDT token for testing on Etherlink
/// @dev Mimics the real USDT token with 6 decimals
contract MockUSDT is ERC20, Ownable {
    uint8 private constant DECIMALS = 6;
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** DECIMALS; // 1B USDT
    uint256 private constant FAUCET_AMOUNT = 10_000 * 10 ** DECIMALS; // 10K USDT per faucet

    mapping(address => uint256) public lastFaucetTime;
    uint256 public faucetCooldown = 24 hours;

    event Faucet(address indexed to, uint256 amount);
    event FaucetCooldownUpdated(uint256 newCooldown);

    constructor() ERC20("Mock Tether USD", "USDT") {
        _transferOwnership(msg.sender);
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /// @notice Mint new tokens (only owner)
    /// @param to Address to mint to
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn tokens from caller
    /// @param amount Amount to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Faucet function for testing with custom amount
    /// @param amount Amount to mint to caller (max 10,000 USDT)
    function faucetWithAmount(uint256 amount) external {
        require(amount <= FAUCET_AMOUNT, "MockUSDT: Amount exceeds faucet limit");
        require(
            block.timestamp >= lastFaucetTime[msg.sender] + faucetCooldown,
            "MockUSDT: Faucet cooldown active"
        );

        lastFaucetTime[msg.sender] = block.timestamp;
        _mint(msg.sender, amount);
        
        emit Faucet(msg.sender, amount);
    }

    /// @notice Quick faucet with default amount
    function faucet() external {
        require(
            block.timestamp >= lastFaucetTime[msg.sender] + faucetCooldown,
            "MockUSDT: Faucet cooldown active"
        );

        lastFaucetTime[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        
        emit Faucet(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Set faucet cooldown period (only owner)
    /// @param newCooldown New cooldown period in seconds
    function setFaucetCooldown(uint256 newCooldown) external onlyOwner {
        faucetCooldown = newCooldown;
        emit FaucetCooldownUpdated(newCooldown);
    }

    /// @notice Check how much time left for faucet cooldown
    /// @param user Address to check
    /// @return timeLeft Time left in seconds (0 if can use faucet)
    function getFaucetTimeLeft(address user) external view returns (uint256 timeLeft) {
        uint256 nextFaucetTime = lastFaucetTime[user] + faucetCooldown;
        if (block.timestamp >= nextFaucetTime) {
            return 0;
        }
        return nextFaucetTime - block.timestamp;
    }

    /// @notice Check if user can use faucet
    /// @param user Address to check
    /// @return ready Whether user can use faucet
    function canUseFaucet(address user) external view returns (bool ready) {
        return block.timestamp >= lastFaucetTime[user] + faucetCooldown;
    }

    /// @notice Emergency mint for testing scenarios (only owner)
    /// @param amount Amount to mint to owner
    function emergencyMint(uint256 amount) external onlyOwner {
        _mint(msg.sender, amount);
    }
}