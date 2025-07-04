// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockVault {
    address[] public strategies;
    mapping(address => bool) public isStrategy;
    
    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }
    
    function depositToStrategy(address strategy, uint256 amount, bytes calldata data) external {
        // Mock implementation
    }
}

contract MockDeBridge {
    mapping(address => mapping(address => uint256)) public conversionRates;
    
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        bytes extraData;
    }
    
    function setConversionRate(address tokenIn, address tokenOut, uint256 rate) external {
        conversionRates[tokenIn][tokenOut] = rate;
    }
    
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256) {
        uint256 rate = conversionRates[tokenIn][tokenOut];
        if (rate == 0) return amountIn; // 1:1 if no rate set
        return (amountIn * rate) / 1e18;
    }
    
    function swap(SwapParams calldata params) external returns (uint256) {
        uint256 rate = conversionRates[params.tokenIn][params.tokenOut];
        if (rate == 0) return params.amountIn; // 1:1 if no rate set
        return (params.amountIn * rate) / 1e18;
    }
    
    function send(
        address _tokenAddress,
        uint256 _amount,
        uint256 _chainIdTo,
        bytes memory _receiver,
        uint256 _permit,
        bool _useAssetFee,
        uint32 _referralCode,
        bytes calldata _autoParams
    ) external payable {
        // Mock implementation - just emit event or store data
    }
}

contract MockRoyaltyVault is ERC20 {
    mapping(address => mapping(address => uint256)) public claimableAmounts;
    
    constructor() ERC20("Mock Royalty Vault", "MRV") {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function setClaimableAmount(address token, address claimer, uint256 amount) external {
        claimableAmounts[token][claimer] = amount;
    }
    
    function claimRevenueOnBehalfByTokenBatch(
        address claimer,
        address[] calldata tokens
    ) external returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = claimableAmounts[tokens[i]][claimer];
            // Transfer tokens to claimer (mock)
        }
        return amounts;
    }
}
