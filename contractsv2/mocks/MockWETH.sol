// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockWETH
/// @notice Mock WETH token for testing on Etherlink
/// @dev Mimics the real WETH token with deposit/withdraw functionality
contract MockWETH is ERC20, Ownable {
    uint8 private constant DECIMALS = 18;
    uint256 private constant INITIAL_SUPPLY = 100_000 * 10 ** DECIMALS; // 100K WETH
    uint256 private constant FAUCET_AMOUNT = 10 * 10 ** DECIMALS; // 10 WETH per faucet

    mapping(address => uint256) public lastFaucetTime;
    uint256 public faucetCooldown = 24 hours;

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);
    event Faucet(address indexed to, uint256 amount);

    constructor() ERC20("Mock Wrapped Ether", "WETH") {
        _transferOwnership(msg.sender);
        _mint(msg.sender, INITIAL_SUPPLY);
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
    /// @param amount Amount to mint to caller (max 10 WETH)
    function faucetWithAmount(uint256 amount) external {
        require(amount <= FAUCET_AMOUNT, "MockWETH: Amount exceeds faucet limit");
        require(
            block.timestamp >= lastFaucetTime[msg.sender] + faucetCooldown,
            "MockWETH: Faucet cooldown active"
        );

        lastFaucetTime[msg.sender] = block.timestamp;
        _mint(msg.sender, amount);
        
        emit Faucet(msg.sender, amount);
    }

    /// @notice Quick faucet with default amount
    function faucet() external {
        require(
            block.timestamp >= lastFaucetTime[msg.sender] + faucetCooldown,
            "MockWETH: Faucet cooldown active"
        );

        lastFaucetTime[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        
        emit Faucet(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Deposit ETH and get WETH (like real WETH)
    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Withdraw WETH and get ETH (like real WETH)
    /// @param amount Amount of WETH to withdraw
    function withdraw(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "MockWETH: Insufficient balance");
        
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
        
        emit Withdrawal(msg.sender, amount);
    }

    /// @notice Fallback to deposit ETH
    receive() external payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Set faucet cooldown period (only owner)
    /// @param newCooldown New cooldown period in seconds
    function setFaucetCooldown(uint256 newCooldown) external onlyOwner {
        faucetCooldown = newCooldown;
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

    /// @notice Emergency function to add ETH to contract for testing
    function addETH() external payable onlyOwner {
        // Just accept ETH to ensure withdraw function works
    }

    /// @notice Emergency function to withdraw ETH (only owner)
    /// @param amount Amount to withdraw
    function withdrawETH(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        payable(msg.sender).transfer(amount);
    }
}