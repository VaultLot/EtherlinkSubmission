// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ====================================================================
// MOCK LENDING PROTOCOL (like Aave/Compound)
// ====================================================================

/// @title MockLendingProtocol
/// @notice Mock lending protocol for testing yield strategies
contract MockLendingProtocol is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Market {
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 supplyRate; // APY in basis points (500 = 5%)
        uint256 borrowRate;
        uint256 utilizationRate;
        bool active;
    }

    mapping(address => Market) public markets;
    mapping(address => mapping(address => uint256)) public userSupplies;
    mapping(address => mapping(address => uint256)) public lastUpdateTime;

    event Supply(address indexed user, address indexed asset, uint256 amount);
    event Withdraw(address indexed user, address indexed asset, uint256 amount);
    event MarketAdded(address indexed asset, uint256 supplyRate);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function addMarket(
        address asset,
        uint256 supplyRate,
        uint256 borrowRate
    ) external onlyRole(ADMIN_ROLE) {
        markets[asset] = Market({
            totalSupply: 0,
            totalBorrow: 0,
            supplyRate: supplyRate,
            borrowRate: borrowRate,
            utilizationRate: 0,
            active: true
        });
        
        emit MarketAdded(asset, supplyRate);
    }

    function supply(address asset, uint256 amount, address onBehalfOf) external {
        require(markets[asset].active, "Market not active");
        require(amount > 0, "Amount must be positive");
        
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate accrued interest before updating
        _accrueInterest(asset, onBehalfOf);
        
        userSupplies[asset][onBehalfOf] += amount;
        markets[asset].totalSupply += amount;
        lastUpdateTime[asset][onBehalfOf] = block.timestamp;

        emit Supply(onBehalfOf, asset, amount);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(markets[asset].active, "Market not active");
        
        // Calculate accrued interest
        _accrueInterest(asset, msg.sender);
        
        uint256 userBalance = userSupplies[asset][msg.sender];
        
        if (amount == type(uint256).max) {
            amount = userBalance;
        }
        
        require(userBalance >= amount, "Insufficient balance");
        
        userSupplies[asset][msg.sender] -= amount;
        markets[asset].totalSupply -= amount;
        
        IERC20(asset).safeTransfer(to, amount);
        
        emit Withdraw(msg.sender, asset, amount);
        return amount;
    }

    function _accrueInterest(address asset, address user) internal {
        uint256 timeDelta = block.timestamp - lastUpdateTime[asset][user];
        if (timeDelta == 0 || userSupplies[asset][user] == 0) return;
        
        Market storage market = markets[asset];
        uint256 interest = (userSupplies[asset][user] * market.supplyRate * timeDelta) / (365 days * 10000);
        
        if (interest > 0) {
            userSupplies[asset][user] += interest;
            market.totalSupply += interest;
        }
        
        lastUpdateTime[asset][user] = block.timestamp;
    }

    function getSupplyBalance(address asset, address user) external view returns (uint256) {
        uint256 balance = userSupplies[asset][user];
        if (balance == 0) return 0;
        
        // Calculate accrued interest
        uint256 timeDelta = block.timestamp - lastUpdateTime[asset][user];
        Market memory market = markets[asset];
        uint256 interest = (balance * market.supplyRate * timeDelta) / (365 days * 10000);
        
        return balance + interest;
    }

    function getSupplyRate(address asset) external view returns (uint256) {
        return markets[asset].supplyRate;
    }

    function claimRewards(address user) external returns (uint256) {
        // Mock reward claiming - return small amount for testing
        return 0;
    }

    function setSupplyRate(address asset, uint256 newRate) external onlyRole(ADMIN_ROLE) {
        markets[asset].supplyRate = newRate;
    }
}

// ====================================================================
// MOCK DEX PROTOCOL (like Uniswap/QuipuSwap)
// ====================================================================

/// @title MockDEXProtocol
/// @notice Mock DEX for testing LP and swap strategies
contract MockDEXProtocol is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Pool {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalLiquidity;
        uint256 feeRate; // In basis points
        bool active;
    }

    mapping(bytes32 => Pool) public pools;
    mapping(bytes32 => mapping(address => uint256)) public userLiquidity;
    mapping(address => uint256) public exchangeRates; // Mock exchange rates (token -> rate in 1e18)

    event PoolCreated(bytes32 indexed poolId, address tokenA, address tokenB);
    event LiquidityAdded(bytes32 indexed poolId, address user, uint256 liquidity);
    event LiquidityRemoved(bytes32 indexed poolId, address user, uint256 liquidity);
    event Swap(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function createPool(
        address tokenA,
        address tokenB,
        uint256 feeRate
    ) external onlyRole(ADMIN_ROLE) returns (bytes32 poolId) {
        require(tokenA != tokenB, "Identical tokens");
        
        // Sort tokens to ensure consistent pool ID
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        
        poolId = keccak256(abi.encodePacked(tokenA, tokenB));
        
        pools[poolId] = Pool({
            tokenA: tokenA,
            tokenB: tokenB,
            reserveA: 0,
            reserveB: 0,
            totalLiquidity: 0,
            feeRate: feeRate,
            active: true
        });
        
        emit PoolCreated(poolId, tokenA, tokenB);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(block.timestamp <= deadline, "Expired");
        
        bytes32 poolId = _getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        require(pool.active, "Pool not active");
        
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountBDesired);
        
        // For simplicity, use desired amounts
        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = amountA + amountB; // Simplified liquidity calculation
        
        require(amountA >= amountAMin && amountB >= amountBMin, "Insufficient amounts");
        
        pool.reserveA += amountA;
        pool.reserveB += amountB;
        pool.totalLiquidity += liquidity;
        userLiquidity[poolId][to] += liquidity;
        
        emit LiquidityAdded(poolId, to, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(block.timestamp <= deadline, "Expired");
        
        bytes32 poolId = _getPoolId(tokenA, tokenB);
        Pool storage pool = pools[poolId];
        
        require(userLiquidity[poolId][msg.sender] >= liquidity, "Insufficient liquidity");
        
        // Calculate proportional amounts
        amountA = (pool.reserveA * liquidity) / pool.totalLiquidity;
        amountB = (pool.reserveB * liquidity) / pool.totalLiquidity;
        
        require(amountA >= amountAMin && amountB >= amountBMin, "Insufficient amounts");
        
        userLiquidity[poolId][msg.sender] -= liquidity;
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        pool.totalLiquidity -= liquidity;
        
        IERC20(tokenA).safeTransfer(to, amountA);
        IERC20(tokenB).safeTransfer(to, amountB);
        
        emit LiquidityRemoved(poolId, msg.sender, liquidity);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        require(block.timestamp <= deadline, "Expired");

        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 amountOut = getAmountOut(amountIn, tokenIn, tokenOut);
        require(amountOut >= amountOutMin, "Insufficient output amount");

        IERC20(tokenOut).safeTransfer(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) public view returns (uint256) {
        uint256 rateIn = exchangeRates[tokenIn] > 0 ? exchangeRates[tokenIn] : 1e18;
        uint256 rateOut = exchangeRates[tokenOut] > 0 ? exchangeRates[tokenOut] : 1e18;
        
        // Simple rate conversion with 0.3% fee
        return (amountIn * rateIn * 997) / (rateOut * 1000);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        for (uint256 i = 1; i < path.length; i++) {
            amounts[i] = getAmountOut(amounts[i-1], path[i-1], path[i]);
        }
    }

    function _getPoolId(address tokenA, address tokenB) internal pure returns (bytes32) {
        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }

    function setExchangeRate(address token, uint256 rate) external onlyRole(ADMIN_ROLE) {
        exchangeRates[token] = rate;
    }

    function getUserLiquidity(address tokenA, address tokenB, address user) external view returns (uint256) {
        bytes32 poolId = _getPoolId(tokenA, tokenB);
        return userLiquidity[poolId][user];
    }

    function getPoolInfo(address tokenA, address tokenB) external view returns (Pool memory) {
        bytes32 poolId = _getPoolId(tokenA, tokenB);
        return pools[poolId];
    }
}

// ====================================================================
// MOCK STAKING PROTOCOL
// ====================================================================

/// @title MockStakingProtocol
/// @notice Mock staking protocol for testing staking strategies
contract MockStakingProtocol is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct StakingPool {
        IERC20 stakingToken;
        uint256 rewardRate; // Rewards per second per token
        uint256 totalStaked;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        bool active;
    }

    struct UserInfo {
        uint256 stakedAmount;
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
        uint256 lastStakeTime;
    }

    mapping(address => StakingPool) public stakingPools;
    mapping(address => mapping(address => UserInfo)) public userInfo;

    event Staked(address indexed user, address indexed token, uint256 amount);
    event Unstaked(address indexed user, address indexed token, uint256 amount);
    event RewardsClaimed(address indexed user, address indexed token, uint256 reward);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function createStakingPool(
        address token,
        uint256 rewardRate
    ) external onlyRole(ADMIN_ROLE) {
        stakingPools[token] = StakingPool({
            stakingToken: IERC20(token),
            rewardRate: rewardRate,
            totalStaked: 0,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            active: true
        });
    }

    function stake(uint256 amount) external {
        address token = msg.sender; // Simplified: use sender as token for testing
        StakingPool storage pool = stakingPools[token];
        require(pool.active, "Pool not active");

        _updateReward(token, msg.sender);

        pool.stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        
        userInfo[token][msg.sender].stakedAmount += amount;
        pool.totalStaked += amount;
        userInfo[token][msg.sender].lastStakeTime = block.timestamp;

        emit Staked(msg.sender, token, amount);
    }

    function unstake(uint256 amount) external {
        address token = msg.sender; // Simplified
        _updateReward(token, msg.sender);

        UserInfo storage user = userInfo[token][msg.sender];
        require(user.stakedAmount >= amount, "Insufficient staked amount");

        user.stakedAmount -= amount;
        stakingPools[token].totalStaked -= amount;

        stakingPools[token].stakingToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, token, amount);
    }

    function claimRewards() external returns (uint256) {
        address token = msg.sender; // Simplified
        _updateReward(token, msg.sender);

        uint256 reward = userInfo[token][msg.sender].rewards;
        if (reward > 0) {
            userInfo[token][msg.sender].rewards = 0;
            // In a real protocol, you'd transfer reward tokens
            // For testing, we'll just return the reward amount
        }

        emit RewardsClaimed(msg.sender, token, reward);
        return reward;
    }

    function _updateReward(address token, address user) internal {
        StakingPool storage pool = stakingPools[token];
        
        pool.rewardPerTokenStored = rewardPerToken(token);
        pool.lastUpdateTime = block.timestamp;

        if (user != address(0)) {
            userInfo[token][user].rewards = earned(token, user);
            userInfo[token][user].userRewardPerTokenPaid = pool.rewardPerTokenStored;
        }
    }

    function rewardPerToken(address token) public view returns (uint256) {
        StakingPool memory pool = stakingPools[token];
        
        if (pool.totalStaked == 0) {
            return pool.rewardPerTokenStored;
        }
        
        return pool.rewardPerTokenStored + 
            (((block.timestamp - pool.lastUpdateTime) * pool.rewardRate * 1e18) / pool.totalStaked);
    }

    function earned(address token, address user) public view returns (uint256) {
        UserInfo memory userStake = userInfo[token][user];
        
        return (userStake.stakedAmount * 
            (rewardPerToken(token) - userStake.userRewardPerTokenPaid)) / 1e18 + 
            userStake.rewards;
    }

    function getStakedBalance(address user) external view returns (uint256) {
        return userInfo[msg.sender][user].stakedAmount; // Simplified
    }

    function getAPR() external view returns (uint256) {
        return 5000; // 50% APR for testing
    }
}