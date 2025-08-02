// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IStrategies.sol";

// Real Superlend/Aave Protocol Interfaces
interface IPoolAddressesProvider {
    function getPool() external view returns (address);
    function getPriceOracle() external view returns (address);
    function getACLManager() external view returns (address);
}

interface IPool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    );

    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface IAaveOracle {
    function getAssetPrice(address asset) external view returns (uint256);
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);
}

interface IAToken is IERC20 {
    function scaledBalanceOf(address user) external view returns (uint256);
    function getScaledUserBalanceAndSupply(address user) external view returns (uint256, uint256);
    function scaledTotalSupply() external view returns (uint256);
}

/// @title SuperlendStrategy - Real Aave/Superlend Integration
/// @notice Strategy that deposits assets into Superlend (Aave fork) for yield generation
/// @dev Integrates with real Superlend protocol deployed on Etherlink
contract SuperlendStrategy is IStrategies, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================

    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Real Superlend contract addresses on Etherlink
    IPoolAddressesProvider public constant POOL_ADDRESSES_PROVIDER = 
        IPoolAddressesProvider(0x5e580E0FF1981E7c916D6D9a036A8596E35fCE31);
    
    address public constant AAVE_ORACLE = 0xE06cda30A2d4714fECE928b36497b8462A21d79a;
    address public constant ACL_MANAGER = 0x3941BfFABA0db23934e67FD257cC6F724F0DDd23;

    // Known aToken addresses from deployment
    mapping(address => address) public aTokenAddresses;

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================

    IERC20 public immutable assetToken;
    IAToken public immutable aToken;
    IPool public immutable pool;
    IAaveOracle public immutable priceOracle;
    
    address public vault;
    bool public strategyPaused;
    string public strategyName;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;

    // Risk and performance tracking
    uint256 public maxSlippage = 300; // 3% default
    uint256 public maxSingleDeployment = 1000000 * 10**6; // 1M USDC default
    uint256 public minHarvestAmount = 1 * 10**6; // 1 USDC minimum

    // Real protocol data
    uint256 public lastRecordedLiquidityIndex;
    uint256 public lastSupplyRate;

    // ====================================================================
    // EVENTS
    // ====================================================================

    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event StrategyPaused();
    event StrategyUnpaused();
    event ATokenUpdated(address indexed asset, address indexed aToken);
    event SupplyRateUpdated(uint256 newRate);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_vault != address(0), "Invalid vault");

        assetToken = IERC20(_asset);
        vault = _vault;
        strategyName = _name;

        // Get pool from addresses provider
        pool = IPool(POOL_ADDRESSES_PROVIDER.getPool());
        priceOracle = IAaveOracle(POOL_ADDRESSES_PROVIDER.getPriceOracle());

        // Initialize known aToken mappings
        _initializeATokenMappings();

        // Get aToken for this asset
        address aTokenAddr = _getATokenAddress(_asset);
        require(aTokenAddr != address(0), "aToken not found");
        aToken = IAToken(aTokenAddr);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STRATEGY_ROLE, _vault);
        _grantRole(HARVESTER_ROLE, msg.sender);
    }

    function _initializeATokenMappings() internal {
        // USDC
        aTokenAddresses[0x0F8f22977d57e0b7b04999419865dCd0277b8C41] = 0x744D7931B12E890b7b32A076a918B112B950B67d;
        // XTZ
        aTokenAddresses[0xc4ad0AB9eB49654738C76967E78152ADAbE99Db4] = 0xc7DE9218466862ce30CC415eD6d5Af61Eb7FFD57;
        // WBTC
        aTokenAddresses[0xF1611a297B1D9120fd4383856B4524Ad54BC7086] = 0x71B27362B3be20Bbb91247d8CfCaB4dADfD0244A;
        // USDT
        aTokenAddresses[0x576039C3D55527CF86FFBcA84771AcDed99310f7] = 0xe0339800272c442dc031fF80Cd85ac4c17AB383e;
    }

    function _getATokenAddress(address asset) internal view returns (address) {
        // First check our mapping
        if (aTokenAddresses[asset] != address(0)) {
            return aTokenAddresses[asset];
        }

        // If not in mapping, get from pool
        try pool.getReserveData(asset) returns (
            uint256,
            uint128,
            uint128,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16,
            address aTokenAddress,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            return aTokenAddress;
        } catch {
            return address(0);
        }
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

        // Approve pool
        assetToken.approve(address(pool), amount);

        // Supply to Superlend
        pool.supply(address(assetToken), amount, address(this), 0);

        totalDeployed += amount;

        // Update liquidity index for tracking
        _updateLiquidityIndex();

        emit StrategyExecuted(amount, data);
    }

    function harvest(bytes calldata data) external override onlyHarvester nonReentrant whenNotPaused {
        uint256 assetBalanceBefore = assetToken.balanceOf(address(this));
        
        // Get current aToken balance
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        
        if (aTokenBalance == 0) {
            return; // Nothing to harvest
        }

        // Calculate yield (interest earned)
        uint256 currentTotalBalance = _getTotalBalance();
        uint256 yield = currentTotalBalance > totalDeployed ? currentTotalBalance - totalDeployed : 0;

        if (yield >= minHarvestAmount) {
            // Withdraw only the yield
            pool.withdraw(address(assetToken), yield, address(this));
            
            uint256 actualHarvested = assetToken.balanceOf(address(this)) - assetBalanceBefore;
            
            if (actualHarvested > 0) {
                // Transfer harvested amount to vault
                assetToken.safeTransfer(vault, actualHarvested);
                
                totalHarvested += actualHarvested;
                lastHarvestTime = block.timestamp;
                harvestCount++;
                
                emit StrategyHarvested(actualHarvested, totalHarvested);
            }
        }

        // Update metrics
        _updateLiquidityIndex();
    }

    function emergencyExit(bytes calldata data) external override onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;

        uint256 aTokenBalance = aToken.balanceOf(address(this));
        uint256 recovered = 0;

        if (aTokenBalance > 0) {
            try pool.withdraw(address(assetToken), type(uint256).max, address(this)) returns (uint256 withdrawnAmount) {
                recovered = withdrawnAmount;
            } catch {
                // Try to withdraw exact balance
                try pool.withdraw(address(assetToken), aTokenBalance, address(this)) returns (uint256 withdrawnAmount) {
                    recovered = withdrawnAmount;
                } catch {
                    // Emergency exit failed
                }
            }
        }

        // Transfer any remaining tokens to vault
        uint256 remainingBalance = assetToken.balanceOf(address(this));
        if (remainingBalance > 0) {
            assetToken.safeTransfer(vault, remainingBalance);
            recovered = remainingBalance;
        }

        emit EmergencyExitExecuted(recovered);
    }

    function getBalance() external view override returns (uint256) {
        return _getTotalBalance();
    }

    function underlyingToken() external view override returns (address) {
        return address(assetToken);
    }

    function protocol() external view override returns (address) {
        return address(pool);
    }

    function paused() external view override returns (bool) {
        return strategyPaused;
    }

    function setPaused(bool pauseState) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (pauseState) {
            strategyPaused = true;
            emit StrategyPaused();
        } else {
            strategyPaused = false;
            emit StrategyUnpaused();
        }
    }

    // ====================================================================
    // SUPERLEND-SPECIFIC FUNCTIONS
    // ====================================================================

    function _getTotalBalance() internal view returns (uint256) {
        // Get the actual balance including interest
        return aToken.balanceOf(address(this));
    }

    function _updateLiquidityIndex() internal {
        try pool.getReserveData(address(assetToken)) returns (
            uint256,
            uint128 liquidityIndex,
            uint128 currentLiquidityRate,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16,
            address,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            lastRecordedLiquidityIndex = uint256(liquidityIndex);
            lastSupplyRate = uint256(currentLiquidityRate);
            emit SupplyRateUpdated(lastSupplyRate);
        } catch {
            // Silently fail
        }
    }

    function getCurrentSupplyRate() external view returns (uint256) {
        try pool.getReserveData(address(assetToken)) returns (
            uint256,
            uint128,
            uint128 currentLiquidityRate,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16,
            address,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            return uint256(currentLiquidityRate);
        } catch {
            return lastSupplyRate;
        }
    }

    function getSupplyAPY() external view returns (uint256) {
        uint256 supplyRate = this.getCurrentSupplyRate();
        // Convert from ray (1e27) to basis points (1e4)
        // APY calculation: (1 + rate/SECONDS_PER_YEAR)^SECONDS_PER_YEAR - 1
        // Simplified to just rate for basic implementation
        return supplyRate / 1e23; // Convert from ray to basis points
    }

    function getHealthFactor() external view returns (uint256) {
        try pool.getUserAccountData(address(this)) returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256 healthFactor
        ) {
            return healthFactor;
        } catch {
            return type(uint256).max; // No debt, infinite health factor
        }
    }

    function getAssetPrice() external view returns (uint256) {
        try priceOracle.getAssetPrice(address(assetToken)) returns (uint256 price) {
            return price;
        } catch {
            return 0;
        }
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setMaxSlippage(uint256 newSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSlippage <= 1000, "Slippage too high"); // Max 10%
        maxSlippage = newSlippage;
    }

    function setMaxSingleDeployment(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxSingleDeployment = newMax;
    }

    function setMinHarvestAmount(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minHarvestAmount = newMin;
    }

    function updateATokenMapping(address asset, address aTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aTokenAddresses[asset] = aTokenAddress;
        emit ATokenUpdated(asset, aTokenAddress);
    }

    function grantHarvesterRole(address harvester) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(HARVESTER_ROLE, harvester);
    }

    function revokeHarvesterRole(address harvester) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(HARVESTER_ROLE, harvester);
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

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
            address(pool),
            totalDeployed,
            totalHarvested,
            lastHarvestTime,
            strategyPaused
        );
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 harvestsCount,
        uint256 avgHarvestAmount,
        uint256 lastHarvestTimestamp,
        uint256 currentAPY
    ) {
        uint256 avgHarvest = harvestCount > 0 ? totalHarvested / harvestCount : 0;
        uint256 apy = this.getSupplyAPY();

        return (
            totalDeployed,
            totalHarvested,
            harvestCount,
            avgHarvest,
            lastHarvestTime,
            apy
        );
    }

    function getDetailedPosition() external view returns (
        uint256 aTokenBalance,
        uint256 supplyRate,
        uint256 assetPrice,
        uint256 positionValue,
        uint256 liquidityIndex
    ) {
        aTokenBalance = aToken.balanceOf(address(this));
        supplyRate = this.getCurrentSupplyRate();
        assetPrice = this.getAssetPrice();
        positionValue = aTokenBalance * assetPrice / 1e8; // Assuming 8 decimals for price
        liquidityIndex = lastRecordedLiquidityIndex;
    }

    function getReserveData() external view returns (
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowRate,
        uint40 lastUpdateTimestamp,
        address aTokenAddress
    ) {
        try pool.getReserveData(address(assetToken)) returns (
            uint256,
            uint128 _liquidityIndex,
            uint128 _currentLiquidityRate,
            uint128,
            uint128 _variableBorrowRate,
            uint128,
            uint40 _lastUpdateTimestamp,
            uint16,
            address _aTokenAddress,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            return (
                _liquidityIndex,
                _currentLiquidityRate,
                _variableBorrowRate,
                _lastUpdateTimestamp,
                _aTokenAddress
            );
        } catch {
            return (0, 0, 0, 0, address(0));
        }
    }
}