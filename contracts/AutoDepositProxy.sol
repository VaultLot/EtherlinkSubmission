// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Vault} from "./Vault.sol";

/// @title AutoDepositProxy
/// @notice A proxy contract that automatically deposits received USDC into a vault
/// @dev This allows funds to be sent directly to this contract, which auto-deposits to the vault.
contract AutoDepositProxy {
    using SafeERC20 for IERC20;

    /// @notice The target vault for deposits
    Vault public immutable vault;

    /// @notice The USDC token
    IERC20 public immutable usdc;

    /// @notice Address that should receive the vault shares
    address public immutable beneficiary;

    event AutoDeposit(address indexed beneficiary, uint256 usdcAmount, uint256 sharesReceived);

    constructor(address _vault, address _usdc, address _beneficiary) {
        vault = Vault(_vault);
        usdc = IERC20(_usdc);
        beneficiary = _beneficiary;

        // Pre-approve vault to save gas on deposits.
        // Changed from safeApprove to approve for OpenZeppelin v5 compatibility.
        usdc.approve(_vault, type(uint256).max);
    }

    /// @notice Automatically deposit any USDC balance to the vault.
    /// @dev Can be called by anyone; sends vault shares to the beneficiary.
    function autoDeposit() public {
        uint256 balance = usdc.balanceOf(address(this));
        if (balance > 0) {
            // The vault's deposit function will pull the funds from this proxy contract.
            // The approval for this is given in the constructor.
            uint256 shares = vault.deposit(balance, beneficiary);
            emit AutoDeposit(beneficiary, balance, shares);
        }
    }

    /// @notice Fallback function that triggers auto-deposit when this contract is called.
    /// @dev This allows the contract to automatically deposit when USDC arrives from a bridge.
    fallback() external {
        autoDeposit();
    }

    receive() external payable {
        // This contract is not meant to hold ETH.
    }
}
