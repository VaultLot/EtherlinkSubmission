// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AutoDepositProxy
/// @notice Automatically deposits received tokens into a vault for yield lottery
/// @dev Allows funds to be sent directly to this contract, which auto-deposits to the vault
contract AutoDepositProxy {
    using SafeERC20 for IERC20;

    /// @notice The target vault for deposits
    address public immutable vault;

    /// @notice The token to auto-deposit
    IERC20 public immutable token;

    /// @notice Address that should receive the vault shares
    address public immutable beneficiary;

    event AutoDeposit(address indexed beneficiary, uint256 tokenAmount, uint256 sharesReceived);

    constructor(address _vault, address _token, address _beneficiary) {
        require(_vault != address(0), "Invalid vault");
        require(_token != address(0), "Invalid token");
        require(_beneficiary != address(0), "Invalid beneficiary");
        
        vault = _vault;
        token = IERC20(_token);
        beneficiary = _beneficiary;

        // Pre-approve vault to save gas on deposits
        token.approve(_vault, type(uint256).max);
    }

    /// @notice Automatically deposit any token balance to the vault
    /// @dev Can be called by anyone; sends vault shares to the beneficiary
    function autoDeposit() public {
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            uint256 shares = EtherlinkVault(vault).deposit(balance, beneficiary);
            emit AutoDeposit(beneficiary, balance, shares);
        }
    }

    /// @notice Fallback function that triggers auto-deposit when this contract is called
    /// @dev This allows the contract to automatically deposit when tokens arrive from a bridge
    fallback() external {
        autoDeposit();
    }

    receive() external payable {
        // This contract is not meant to hold ETH for this use case
        revert("ETH not accepted");
    }

    /// @notice Check if there are tokens ready to be deposited
    function pendingDeposit() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice Emergency function to recover tokens (only beneficiary can call)
    function emergencyWithdraw() external {
        require(msg.sender == beneficiary, "Only beneficiary");
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.safeTransfer(beneficiary, balance);
        }
    }
}

// Import for interface
interface EtherlinkVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}