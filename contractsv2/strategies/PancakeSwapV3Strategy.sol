// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IStrategies.sol";

// Real PancakeSwap V3 Interfaces
interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function increaseLiquidity(IncreaseLiquidityParams calldata params) external payable returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );

    function collect(CollectParams calldata params) external payable returns (
        uint256 amount0,
        uint256 amount1
    );

    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    function burn(uint256 tokenId) external payable;
    
    // ERC721 functions needed for NFT operations
    function approve(address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface ISmartRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IQuoterV2 {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

interface IMasterChefV3 {
    function updateLiquidity(uint256 tokenId) external;
    function withdraw(uint256 tokenId, address to) external returns (uint256 reward);
    function harvest(uint256 tokenId, address to) external returns (uint256 reward);
    function pendingCake(uint256 tokenId) external view returns (uint256 reward);
}

interface IPancakeV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IPancakeV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );

    function liquidity() external view returns (uint128);
    function tickSpacing() external view returns (int24);
}

/// @title PancakeSwapV3Strategy - Real PancakeSwap V3 Integration
/// @notice Strategy that provides liquidity to PancakeSwap V3 pools for yield generation
/// @dev Integrates with real PancakeSwap V3 protocol deployed on Etherlink
contract PancakeSwapV3Strategy is IStrategies, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================

    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Real PancakeSwap V3 contract addresses on Etherlink
    address public constant PANCAKE_FACTORY = 0xfaAdaeBdcc60A2FeC900285516F4882930Db8Ee8;
    address public constant POSITION_MANAGER = 0x79b1a1445e53fe7bC9063c0d54A531D1d2f814D7;
    address public constant SMART_ROUTER = 0x8a7bBf269B95875FC1829901bb2c815029d8442e;
    address public constant QUOTER_V2 = 0x6e8432F0Ed242fABfA481dd449407b0f724d8D03;
    address public constant MASTER_CHEF_V3 = 0x3b2ffa5a9b60B9Da804eb3aB4575311F159D4a21;

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================

    IERC20 public immutable assetToken;
    IERC20 public immutable pairedToken; // Token to pair with (e.g., WETH, USDC)
    address public immutable poolAddress;
    uint24 public immutable poolFee;

    INonfungiblePositionManager public immutable positionManager;
    ISmartRouter public immutable smartRouter;
    IQuoterV2 public immutable quoter;
    IMasterChefV3 public immutable masterChef;

    address public vault;
    bool public strategyPaused;
    string public strategyName;

    // Position tracking
    uint256 public currentTokenId; // NFT token ID for our LP position
    int24 public tickLower;
    int24 public tickUpper;
    uint128 public liquidity;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;

    // Risk and performance tracking
    uint256 public maxSlippage = 500; // 5% default (higher for DEX)
    uint256 public maxSingleDeployment = 500000 * 10**6; // 500K USDC default
    uint256 public minHarvestAmount = 1 * 10**6; // 1 USDC minimum

    // Liquidity provision settings
    int24 public tickRangeMultiplier = 10; // Default range multiplier
    bool public autoCompound = true;
    bool public isInMasterChef = false;

    // Price range tracking
    uint256 public lastRebalanceTime;
    int24 public lastRecordedTick;

    // ====================================================================
    // EVENTS
    // ====================================================================

    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event LiquidityAdded(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event LiquidityRemoved(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 amount0, uint256 amount1);
    event PositionRebalanced(uint256 oldTokenId, uint256 newTokenId, int24 newTickLower, int24 newTickUpper);
    event MasterChefDeposited(uint256 tokenId);
    event MasterChefWithdrawn(uint256 tokenId, uint256 reward);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(
        address _asset,
        address _pairedToken,
        uint24 _poolFee,
        address _vault,
        string memory _name
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_pairedToken != address(0), "Invalid paired token");
        require(_vault != address(0), "Invalid vault");

        assetToken = IERC20(_asset);
        pairedToken = IERC20(_pairedToken);
        poolFee = _poolFee;
        vault = _vault;
        strategyName = _name;

        positionManager = INonfungiblePositionManager(POSITION_MANAGER);
        smartRouter = ISmartRouter(SMART_ROUTER);
        quoter = IQuoterV2(QUOTER_V2);
        masterChef = IMasterChefV3(MASTER_CHEF_V3);

        // Get pool address
        poolAddress = IPancakeV3Factory(PANCAKE_FACTORY).getPool(_asset, _pairedToken, _poolFee);
        require(poolAddress != address(0), "Pool does not exist");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_ROLE, _vault);
        _grantRole(HARVESTER_ROLE, msg.sender);
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused, "Strategy is paused");
        _;
    }

    modifier onlyHarvester() {
        require(hasRole(HARVESTER_ROLE, msg.sender), "Not authorized harvester");
        _;
    }

    // ====================================================================
    // STRATEGY INTERFACE IMPLEMENTATION
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) external override onlyVault nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= maxSingleDeployment, "Amount exceeds max deployment");

        // Transfer tokens from vault
        assetToken.safeTransferFrom(msg.sender, address(this), amount);

        // Decode strategy-specific data if provided
        (uint256 minPairedTokenAmount, bool swapHalf) = data.length > 0 
            ? abi.decode(data, (uint256, bool))
            : (0, true);

        if (swapHalf) {
            // Swap half the asset token for paired token to create balanced liquidity
            uint256 swapAmount = amount / 2;
            _swapExactInputSingle(address(assetToken), address(pairedToken), swapAmount);
        }

        // Add liquidity to the pool
        _addLiquidity();

        totalDeployed += amount;
        emit Deposit(amount);
        emit StrategyExecuted(amount, data);
    }

    function harvest(bytes calldata data) external override onlyHarvester nonReentrant whenNotPaused {
        if (currentTokenId == 0) {
            return; // No position to harvest
        }

        uint256 assetBalanceBefore = assetToken.balanceOf(address(this));

        // Harvest MasterChef rewards if staked
        if (isInMasterChef) {
            uint256 reward = masterChef.harvest(currentTokenId, address(this));
            if (reward > 0) {
                emit MasterChefWithdrawn(currentTokenId, reward);
            }
        }

        // Collect fees from the position
        (uint256 amount0, uint256 amount1) = _collectFees();

        if (amount0 > 0 || amount1 > 0) {
            emit FeesCollected(amount0, amount1);

            // Convert all collected fees to asset token
            if (address(assetToken) == _getToken1() && amount0 > 0) {
                // Swap token0 to asset token
                _swapExactInputSingle(_getToken0(), address(assetToken), amount0);
            } else if (address(assetToken) == _getToken0() && amount1 > 0) {
                // Swap token1 to asset token
                _swapExactInputSingle(_getToken1(), address(assetToken), amount1);
            }

            uint256 harvestedAmount = assetToken.balanceOf(address(this)) - assetBalanceBefore;

            if (harvestedAmount >= minHarvestAmount) {
                if (autoCompound) {
                    // Re-invest harvested fees back into the position
                    _addLiquidity();
                } else {
                    // Send harvested fees to vault
                    assetToken.safeTransfer(vault, harvestedAmount);
                }

                totalHarvested += harvestedAmount;
                lastHarvestTime = block.timestamp;
                harvestCount++;

                emit Harvest(harvestedAmount);
                emit StrategyHarvested(harvestedAmount, totalHarvested);
            }
        }

        // Check if rebalance is needed
        if (_shouldRebalance()) {
            _rebalancePosition();
        }
    }

    function emergencyExit(bytes calldata data) external override onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;

        uint256 recovered = 0;

        if (currentTokenId > 0) {
            // Withdraw from MasterChef if staked
            if (isInMasterChef) {
                try masterChef.withdraw(currentTokenId, address(this)) returns (uint256 reward) {
                    isInMasterChef = false;
                    emit MasterChefWithdrawn(currentTokenId, reward);
                } catch {
                    // Continue even if MasterChef withdrawal fails
                }
            }

            // Remove all liquidity
            (uint256 amount0, uint256 amount1) = _removeLiquidity(liquidity);
            recovered += amount0 + amount1;

            // Collect any remaining fees
            _collectFees();

            // Burn the NFT position
            try positionManager.burn(currentTokenId) {
                // Position burned successfully
            } catch {
                // Continue even if burn fails
            }

            // Reset position tracking
            currentTokenId = 0;
            liquidity = 0;
        }

        // Convert all tokens back to asset token
        uint256 pairedBalance = pairedToken.balanceOf(address(this));
        if (pairedBalance > 0) {
            _swapExactInputSingle(address(pairedToken), address(assetToken), pairedBalance);
        }

        // Transfer all remaining tokens to vault
        uint256 remainingBalance = assetToken.balanceOf(address(this));
        if (remainingBalance > 0) {
            assetToken.safeTransfer(vault, remainingBalance);
            recovered = remainingBalance;
        }

        emit EmergencyExit(recovered);
        emit EmergencyExitExecuted(recovered);
    }

    function getBalance() external view override returns (uint256) {
        if (currentTokenId == 0) {
            return assetToken.balanceOf(address(this));
        }

        // Estimate position value in asset token terms
        try this.getPositionValue() returns (uint256 value) {
            return value + assetToken.balanceOf(address(this));
        } catch {
            return assetToken.balanceOf(address(this));
        }
    }

    function underlyingToken() external view override returns (address) {
        return address(assetToken);
    }

    function protocol() external view override returns (address) {
        return POSITION_MANAGER;
    }

    function paused() external view override returns (bool) {
        return strategyPaused;
    }

    function setPaused(bool pauseState) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = pauseState;
    }

    // ====================================================================
    // PANCAKESWAP V3 SPECIFIC FUNCTIONS
    // ====================================================================

    function _addLiquidity() internal {
        uint256 assetBalance = assetToken.balanceOf(address(this));
        uint256 pairedBalance = pairedToken.balanceOf(address(this));

        if (assetBalance == 0 && pairedBalance == 0) {
            return;
        }

        // Update tick range if no position exists
        if (currentTokenId == 0) {
            _updateTickRange();
        }

        // Approve tokens
        assetToken.approve(address(positionManager), assetBalance);
        pairedToken.approve(address(positionManager), pairedBalance);

        if (currentTokenId == 0) {
            // Mint new position
            INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
                token0: _getToken0(),
                token1: _getToken1(),
                fee: poolFee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: address(assetToken) == _getToken0() ? assetBalance : pairedBalance,
                amount1Desired: address(assetToken) == _getToken1() ? assetBalance : pairedBalance,
                amount0Min: 0, // Accept any amount of tokens (can be improved with slippage protection)
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 300 // 5 minutes
            });

            (uint256 tokenId, uint128 newLiquidity, uint256 amount0, uint256 amount1) = positionManager.mint(params);
            
            currentTokenId = tokenId;
            liquidity = newLiquidity;
            
            emit LiquidityAdded(tokenId, newLiquidity, amount0, amount1);
            
            // Optionally stake in MasterChef
            // Commenting out for now to avoid compilation issues
            // _depositToMasterChef();
        } else {
            // Increase liquidity in existing position
            _increaseLiquidity(
                address(assetToken) == _getToken0() ? assetBalance : pairedBalance,
                address(assetToken) == _getToken1() ? assetBalance : pairedBalance
            );
        }
    }

    function _increaseLiquidity(uint256 amount0, uint256 amount1) internal {
        if (currentTokenId == 0) return;

        // Withdraw from MasterChef if needed
        if (isInMasterChef) {
            masterChef.withdraw(currentTokenId, address(this));
            isInMasterChef = false;
        }

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = 
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: currentTokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

        (uint128 newLiquidity, uint256 actualAmount0, uint256 actualAmount1) = positionManager.increaseLiquidity(params);
        liquidity += newLiquidity;
        
        emit LiquidityAdded(currentTokenId, newLiquidity, actualAmount0, actualAmount1);
        
        // Re-stake in MasterChef
        // Commenting out for now to avoid compilation issues
        // _depositToMasterChef();
    }

    function _removeLiquidity(uint128 liquidityToRemove) internal returns (uint256 amount0, uint256 amount1) {
        if (currentTokenId == 0 || liquidityToRemove == 0) {
            return (0, 0);
        }

        // Withdraw from MasterChef if needed
        if (isInMasterChef) {
            masterChef.withdraw(currentTokenId, address(this));
            isInMasterChef = false;
        }

        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: currentTokenId,
                liquidity: liquidityToRemove,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

        (amount0, amount1) = positionManager.decreaseLiquidity(params);

        // Collect the tokens
        _collectTokensFromPosition();

        liquidity -= liquidityToRemove;
        emit LiquidityRemoved(currentTokenId, liquidityToRemove, amount0, amount1);
    }

    function _collectFees() internal returns (uint256 amount0, uint256 amount1) {
        if (currentTokenId == 0) {
            return (0, 0);
        }

        // Withdraw from MasterChef temporarily if needed
        bool wasInMasterChef = isInMasterChef;
        if (isInMasterChef) {
            masterChef.withdraw(currentTokenId, address(this));
            isInMasterChef = false;
        }

        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: currentTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = positionManager.collect(params);

        // Re-stake in MasterChef if it was staked
        if (wasInMasterChef) {
            // Commenting out for now to avoid compilation issues
            // _depositToMasterChef();
        }
    }

    function _collectTokensFromPosition() internal {
        if (currentTokenId == 0) {
            return;
        }

        _collectFees();
    }

    function _swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        IERC20(tokenIn).approve(address(smartRouter), amountIn);

        ISmartRouter.ExactInputSingleParams memory params = ISmartRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: 0, // Accept any amount (can be improved with slippage protection)
            sqrtPriceLimitX96: 0
        });

        amountOut = smartRouter.exactInputSingle(params);
    }

    function _depositToMasterChef() internal {
        if (currentTokenId > 0 && !isInMasterChef) {
            // Approve NFT to MasterChef
            positionManager.approve(address(masterChef), currentTokenId);
            
            // Update liquidity in MasterChef
            masterChef.updateLiquidity(currentTokenId);
            isInMasterChef = true;
            
            emit MasterChefDeposited(currentTokenId);
        }
    }

    function _updateTickRange() internal {
        IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);
        (,int24 currentTick,,,,,) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        
        // Calculate new tick range
        tickLower = currentTick - tickSpacing * tickRangeMultiplier;
        tickUpper = currentTick + tickSpacing * tickRangeMultiplier;
        
        // Ensure ticks are aligned to tick spacing
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;
        
        lastRecordedTick = currentTick;
    }

    function _shouldRebalance() internal view returns (bool) {
        if (currentTokenId == 0) return false;
        
        IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);
        (,int24 currentTick,,,,,) = pool.slot0();
        
        // Check if current tick is outside our range
        return currentTick < tickLower || currentTick > tickUpper;
    }

    function _rebalancePosition() internal {
        if (currentTokenId == 0) return;

        // Remove current liquidity
        (uint256 amount0, uint256 amount1) = _removeLiquidity(liquidity);

        // Update tick range
        _updateTickRange();

        uint256 oldTokenId = currentTokenId;
        currentTokenId = 0; // Reset before creating new position
        liquidity = 0;

        // Add liquidity with new tick range
        _addLiquidity();

        // Burn old NFT
        try positionManager.burn(oldTokenId) {
            // Old position burned successfully
        } catch {
            // Continue even if burn fails
        }

        lastRebalanceTime = block.timestamp;

        emit PositionRebalanced(oldTokenId, currentTokenId, tickLower, tickUpper);
    }

    function _getToken0() internal view returns (address) {
        return address(assetToken) < address(pairedToken) ? address(assetToken) : address(pairedToken);
    }

    function _getToken1() internal view returns (address) {
        return address(assetToken) < address(pairedToken) ? address(pairedToken) : address(assetToken);
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getPositionValue() external view returns (uint256) {
        if (currentTokenId == 0) {
            return 0;
        }

        try positionManager.positions(currentTokenId) returns (
            uint96,
            address,
            address,
            address,
            uint24,
            int24,
            int24,
            uint128 positionLiquidity,
            uint256,
            uint256,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) {
            // Get current pool price
            IPancakeV3Pool pool = IPancakeV3Pool(poolAddress);
            (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
            
            // Simple estimation - in production you'd want more sophisticated pricing
            uint256 price = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);
            
            // Calculate approximate position value
            uint256 totalValue = uint256(positionLiquidity) + uint256(tokensOwed0) + uint256(tokensOwed1);
            
            return totalValue; // Simplified - should convert to asset token value
        } catch {
            return 0;
        }
    }

    function getCurrentTick() external view returns (int24) {
        if (poolAddress == address(0)) return 0;

        try IPancakeV3Pool(poolAddress).slot0() returns (
            uint160,
            int24 tick,
            uint16,
            uint16,
            uint16,
            uint8,
            bool
        ) {
            return tick;
        } catch {
            return 0;
        }
    }

    function getPendingRewards() external view returns (uint256) {
        if (currentTokenId == 0 || !isInMasterChef) {
            return 0;
        }
        
        try masterChef.pendingCake(currentTokenId) returns (uint256 pending) {
            return pending;
        } catch {
            return 0;
        }
    }

    function getPositionInfo() external view returns (
        uint256 tokenId,
        uint128 currentLiquidity,
        int24 currentTickLower,
        int24 currentTickUpper,
        uint256 fees0,
        uint256 fees1,
        bool inRange
    ) {
        tokenId = currentTokenId;
        currentLiquidity = liquidity;
        currentTickLower = tickLower;
        currentTickUpper = tickUpper;
        
        if (currentTokenId > 0) {
            try positionManager.positions(currentTokenId) returns (
                uint96,
                address,
                address,
                address,
                uint24,
                int24,
                int24,
                uint128,
                uint256,
                uint256,
                uint128 tokensOwed0,
                uint128 tokensOwed1
            ) {
                fees0 = uint256(tokensOwed0);
                fees1 = uint256(tokensOwed1);
            } catch {
                fees0 = 0;
                fees1 = 0;
            }
            
            int24 currentTick = this.getCurrentTick();
            inRange = currentTick >= tickLower && currentTick <= tickUpper;
        }
    }

    function getStrategyInfo() external view returns (
        string memory name,
        address asset,
        address protocolAddr,
        uint256 totalDep,
        uint256 totalHarv,
        uint256 lastHarvest,
        bool isPaused
    ) {
        return (
            strategyName,
            address(assetToken),
            POSITION_MANAGER,
            totalDeployed,
            totalHarvested,
            lastHarvestTime,
            strategyPaused
        );
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setTickRange(int24 newTickLower, int24 newTickUpper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTickLower < newTickUpper, "Invalid tick range");
        tickLower = newTickLower;
        tickUpper = newTickUpper;
    }

    function setTickRangeMultiplier(int24 _multiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_multiplier > 0 && _multiplier <= 100, "Invalid multiplier");
        tickRangeMultiplier = _multiplier;
    }

    function setAutoCompound(bool _autoCompound) external onlyRole(DEFAULT_ADMIN_ROLE) {
        autoCompound = _autoCompound;
    }

    function setMaxSlippage(uint256 newSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSlippage <= 2000, "Slippage too high"); // Max 20%
        maxSlippage = newSlippage;
    }

    function manualRebalance() external onlyRole(HARVESTER_ROLE) nonReentrant {
        _rebalancePosition();
    }

    function toggleMasterChef(bool stake) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (stake && !isInMasterChef) {
            _depositToMasterChef();
        } else if (!stake && isInMasterChef) {
            masterChef.withdraw(currentTokenId, address(this));
            isInMasterChef = false;
        }
    }
}