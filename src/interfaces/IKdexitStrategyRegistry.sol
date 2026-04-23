// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {KdexitTypes} from "../libraries/KdexitTypes.sol";

interface IKdexitStrategyRegistry {
    event StrategyAuthorizationRegistered(
        bytes32 indexed strategyId,
        address indexed target,
        address indexed actor,
        bool enabled,
        bytes32 metadataHash,
        uint64 configuredAt
    );

    function setStrategy(bytes32 strategyId, KdexitTypes.StrategyConfig calldata config) external;

    function getStrategy(bytes32 strategyId)
        external
        view
        returns (KdexitTypes.StrategyConfig memory);

    function isStrategyEnabled(bytes32 strategyId) external view returns (bool);
}
