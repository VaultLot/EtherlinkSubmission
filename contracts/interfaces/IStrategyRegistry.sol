// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStrategyRegistry {
    function getOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bool crossChainAllowed,
        uint16 preferredChain
    ) external view returns (
        bytes32 bestStrategy,
        uint256 expectedReturn,
        uint256 riskScore,
        bool requiresBridge
    );

    function getMultiStrategyAllocation(
        uint256 totalAmount,
        uint256 maxRiskTolerance,
        uint256 diversificationTargets
    ) external view returns (
        bytes32[] memory selectedStrategies,
        uint256[] memory allocations,
        uint256 totalExpectedReturn
    );

    function getStrategyByName(string calldata name, uint16 chainId) external view returns (
        address strategyAddress,
        uint16 chainId_,
        string memory name_,
        string memory protocol,
        uint256 currentAPY,
        uint256 riskScore,
        uint256 tvl,
        uint256 maxCapacity,
        uint256 minDeposit,
        bool active,
        bool crossChainEnabled,
        uint256 lastUpdate,
        bytes memory strategyData
    );

    function addPythonAgent(address agent) external;
}