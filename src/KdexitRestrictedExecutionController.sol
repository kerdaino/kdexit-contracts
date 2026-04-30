// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IKdexitStrategyRegistry} from "./interfaces/IKdexitStrategyRegistry.sol";
import {KdexitRoles} from "./access/KdexitRoles.sol";
import {KdexitTypes} from "./libraries/KdexitTypes.sol";

/// @title KdexitRestrictedExecutionController
/// @notice Internal-beta preparation gate for future restricted sell execution.
/// @dev This contract does not move tokens, custody funds, approve spenders,
/// perform swaps, or call adapters. It only validates a strict sell preparation
/// request against admin-managed allowlists and emits an indexable event.
contract KdexitRestrictedExecutionController is AccessControl, Pausable {
    error AdminAddressZero();
    error StrategyRegistryAddressZero();
    error UserAddressZero();
    error TokenInAddressZero();
    error TokenOutAddressZero();
    error AdapterAddressZero();
    error AdapterIdZero();
    error AmountInZero();
    error RestrictedExecutionExpired(uint64 deadline, uint256 currentTime);
    error StrategyNotEnabled(bytes32 strategyId);
    error AdapterNotAllowed(address adapter);
    error TokenNotAllowed(address token);

    struct AdapterConfig {
        bool allowed;
        bytes32 adapterId;
    }

    IKdexitStrategyRegistry public immutable STRATEGY_REGISTRY;

    mapping(address adapter => AdapterConfig config) private _adapters;
    mapping(address token => bool allowed) private _allowedTokens;

    event RestrictedSellAdapterAllowed(
        address indexed adapter, bytes32 indexed adapterId, address indexed actor
    );

    event RestrictedSellAdapterRemoved(
        address indexed adapter, bytes32 indexed adapterId, address indexed actor
    );

    event RestrictedSellTokenAllowed(address indexed token, address indexed actor);

    event RestrictedSellTokenRemoved(address indexed token, address indexed actor);

    event RestrictedSellExecutionPrepared(
        bytes32 indexed preparationId,
        address indexed user,
        bytes32 indexed strategyId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address adapter,
        bytes32 adapterId,
        uint64 deadline,
        address submitter,
        uint64 preparedAt
    );

    event RestrictedExecutionPauseStateChanged(
        bool indexed isPaused, address indexed actor, uint64 changedAt
    );

    constructor(address defaultAdmin, address emergencyPauser, address strategyRegistry_) {
        if (defaultAdmin == address(0)) revert AdminAddressZero();
        if (strategyRegistry_ == address(0)) revert StrategyRegistryAddressZero();

        STRATEGY_REGISTRY = IKdexitStrategyRegistry(strategyRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(KdexitRoles.ADMIN_ROLE, defaultAdmin);

        if (emergencyPauser != address(0)) {
            _grantRole(KdexitRoles.EMERGENCY_PAUSER_ROLE, emergencyPauser);
        }
    }

    /// @notice Allows or removes one reviewed sell adapter address.
    /// @dev Allowlisting an adapter does not call it and does not grant custody.
    /// It only makes the address eligible for future restricted sell preparation.
    function setAdapterAllowed(address adapter, bytes32 adapterId, bool allowed)
        external
        onlyRole(KdexitRoles.ADMIN_ROLE)
    {
        if (adapter == address(0)) revert AdapterAddressZero();

        if (allowed) {
            if (adapterId == bytes32(0)) revert AdapterIdZero();
            _adapters[adapter] = AdapterConfig({allowed: true, adapterId: adapterId});
            emit RestrictedSellAdapterAllowed(adapter, adapterId, msg.sender);
        } else {
            bytes32 previousAdapterId = _adapters[adapter].adapterId;
            delete _adapters[adapter];
            emit RestrictedSellAdapterRemoved(adapter, previousAdapterId, msg.sender);
        }
    }

    /// @notice Allows or removes one ERC-20 token address for internal-beta preparation.
    /// @dev Both tokenIn and tokenOut must be allowlisted. This prevents a future
    /// execution path from treating user-provided token addresses as open-ended.
    function setTokenAllowed(address token, bool allowed)
        external
        onlyRole(KdexitRoles.ADMIN_ROLE)
    {
        if (token == address(0)) revert TokenInAddressZero();

        _allowedTokens[token] = allowed;
        if (allowed) {
            emit RestrictedSellTokenAllowed(token, msg.sender);
        } else {
            emit RestrictedSellTokenRemoved(token, msg.sender);
        }
    }

    /// @notice Validates and records a future restricted sell preparation request.
    /// @dev This is intentionally event-only. A later asset-moving function must
    /// separately verify EIP-712 authorization, consume nonce, enforce pause, and
    /// perform settlement checks before any token movement.
    function prepareRestrictedSellExecution(KdexitTypes.RestrictedSellParams calldata params)
        external
        onlyRole(KdexitRoles.EXECUTION_RELAYER_ROLE)
        whenNotPaused
        returns (bytes32 preparationId)
    {
        _validateRestrictedSellParams(params);

        AdapterConfig memory adapterConfig = _adapters[params.adapter];
        uint64 preparedAt = uint64(block.timestamp);
        preparationId = keccak256(
            abi.encode(
                params.user,
                params.strategyId,
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                params.minAmountOut,
                params.adapter,
                adapterConfig.adapterId,
                params.deadline,
                msg.sender,
                preparedAt,
                block.chainid
            )
        );

        emit RestrictedSellExecutionPrepared(
            preparationId,
            params.user,
            params.strategyId,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            params.minAmountOut,
            params.adapter,
            adapterConfig.adapterId,
            params.deadline,
            msg.sender,
            preparedAt
        );
    }

    function pause() external onlyRole(KdexitRoles.EMERGENCY_PAUSER_ROLE) {
        _pause();
        emit RestrictedExecutionPauseStateChanged(true, msg.sender, uint64(block.timestamp));
    }

    function unpause() external onlyRole(KdexitRoles.ADMIN_ROLE) {
        _unpause();
        emit RestrictedExecutionPauseStateChanged(false, msg.sender, uint64(block.timestamp));
    }

    function getAdapterConfig(address adapter) external view returns (AdapterConfig memory) {
        return _adapters[adapter];
    }

    function isAdapterAllowed(address adapter) external view returns (bool) {
        return _adapters[adapter].allowed;
    }

    function isTokenAllowed(address token) external view returns (bool) {
        return _allowedTokens[token];
    }

    function isEmergencyPaused() external view returns (bool) {
        return paused();
    }

    function _validateRestrictedSellParams(KdexitTypes.RestrictedSellParams calldata params)
        internal
        view
    {
        if (params.user == address(0)) revert UserAddressZero();
        if (params.tokenIn == address(0)) revert TokenInAddressZero();
        if (params.tokenOut == address(0)) revert TokenOutAddressZero();
        if (params.adapter == address(0)) revert AdapterAddressZero();
        if (params.amountIn == 0) revert AmountInZero();
        if (params.deadline < block.timestamp) {
            revert RestrictedExecutionExpired(params.deadline, block.timestamp);
        }
        if (!STRATEGY_REGISTRY.isStrategyEnabled(params.strategyId)) {
            revert StrategyNotEnabled(params.strategyId);
        }
        if (!_adapters[params.adapter].allowed) revert AdapterNotAllowed(params.adapter);
        if (!_allowedTokens[params.tokenIn]) revert TokenNotAllowed(params.tokenIn);
        if (!_allowedTokens[params.tokenOut]) revert TokenNotAllowed(params.tokenOut);
    }
}
