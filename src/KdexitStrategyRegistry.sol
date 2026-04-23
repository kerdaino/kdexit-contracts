// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IKdexitStrategyRegistry} from "./interfaces/IKdexitStrategyRegistry.sol";
import {KdexitRoles} from "./access/KdexitRoles.sol";
import {KdexitTypes} from "./libraries/KdexitTypes.sol";

/// @title KdexitStrategyRegistry
/// @notice Minimal Phase 4 scaffold for strategy registration and metadata management.
contract KdexitStrategyRegistry is IKdexitStrategyRegistry, AccessControl {
    error AdminAddressZero();

    mapping(bytes32 strategyId => KdexitTypes.StrategyConfig config) private _strategies;

    constructor(address defaultAdmin) {
        if (defaultAdmin == address(0)) revert AdminAddressZero();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(KdexitRoles.ADMIN_ROLE, defaultAdmin);
    }

    function setStrategy(bytes32 strategyId, KdexitTypes.StrategyConfig calldata config)
        external
        onlyRole(KdexitRoles.ADMIN_ROLE)
    {
        _strategies[strategyId] = config;
        emit StrategyAuthorizationRegistered(
            strategyId,
            config.target,
            msg.sender,
            config.enabled,
            keccak256(config.metadata),
            uint64(block.timestamp)
        );
    }

    function getStrategy(bytes32 strategyId)
        external
        view
        returns (KdexitTypes.StrategyConfig memory)
    {
        return _strategies[strategyId];
    }

    function isStrategyEnabled(bytes32 strategyId) external view returns (bool) {
        return _strategies[strategyId].enabled;
    }
}
