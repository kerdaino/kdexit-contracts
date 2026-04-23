// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IKdexitExecutionController} from "./interfaces/IKdexitExecutionController.sol";
import {IKdexitStrategyRegistry} from "./interfaces/IKdexitStrategyRegistry.sol";
import {KdexitRoles} from "./access/KdexitRoles.sol";
import {KdexitTypes} from "./libraries/KdexitTypes.sol";

/// @title KdexitExecutionController
/// @notice Minimal Phase 4 scaffold for execution request intake and future orchestration.
/// @dev This contract records role-restricted execution requests only. It does not move assets.
/// During emergency pause, all execution-moving entrypoints must remain unavailable while
/// read-only reconciliation and indexing helpers continue to work.
contract KdexitExecutionController is IKdexitExecutionController, AccessControl, Pausable {
    error AdminAddressZero();
    error StrategyRegistryAddressZero();
    error ExecutionIdZero();
    error AccountAddressZero();
    error ExecutionAlreadySubmitted(bytes32 executionId);
    error ExecutionNotSubmitted(bytes32 executionId);
    error ExecutionNotPending(bytes32 executionId);
    error StrategyNotEnabled(bytes32 strategyId);

    IKdexitStrategyRegistry public immutable STRATEGY_REGISTRY;

    mapping(bytes32 executionId => KdexitTypes.ExecutionReceipt receipt) private _executionReceipts;

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

    /// @notice Scaffold-only request intake for future relayer-driven execution flows.
    /// @dev This records a validated request for future reconciliation and indexing only.
    function submitExecutionRequest(KdexitTypes.ExecutionRequest calldata request)
        external
        onlyRole(KdexitRoles.EXECUTION_RELAYER_ROLE)
        whenNotPaused
    {
        if (request.executionId == bytes32(0)) revert ExecutionIdZero();
        if (request.account == address(0)) revert AccountAddressZero();
        if (_executionReceipts[request.executionId].status != KdexitTypes.ExecutionRequestStatus.None) {
            revert ExecutionAlreadySubmitted(request.executionId);
        }
        if (!STRATEGY_REGISTRY.isStrategyEnabled(request.strategyId)) {
            revert StrategyNotEnabled(request.strategyId);
        }

        uint64 submittedAt = uint64(block.timestamp);
        _executionReceipts[request.executionId] = KdexitTypes.ExecutionReceipt({
            executionId: request.executionId,
            account: request.account,
            strategyId: request.strategyId,
            amountIn: request.amountIn,
            payloadHash: request.payloadHash,
            requestedAt: request.requestedAt,
            submittedBy: msg.sender,
            submittedAt: submittedAt,
            finalizedBy: address(0),
            finalizedAt: 0,
            resultHash: bytes32(0),
            failureCode: bytes32(0),
            failureContextHash: bytes32(0),
            status: KdexitTypes.ExecutionRequestStatus.Submitted
        });

        emit ExecutionRequestSubmitted(
            request.executionId,
            request.strategyId,
            request.account,
            msg.sender,
            request.amountIn,
            request.payloadHash,
            request.requestedAt,
            submittedAt
        );
    }

    /// @notice Scaffold-only completion recorder for future relayer-driven reconciliation.
    /// @dev This does not perform execution or settlement. It only finalizes the receipt and emits an event.
    function recordExecutionCompletion(bytes32 executionId, bytes32 resultHash)
        external
        onlyRole(KdexitRoles.EXECUTION_RELAYER_ROLE)
        whenNotPaused
    {
        KdexitTypes.ExecutionReceipt storage receipt = _executionReceipts[executionId];
        if (receipt.status == KdexitTypes.ExecutionRequestStatus.None) {
            revert ExecutionNotSubmitted(executionId);
        }
        if (receipt.status != KdexitTypes.ExecutionRequestStatus.Submitted) {
            revert ExecutionNotPending(executionId);
        }

        uint64 finalizedAt = uint64(block.timestamp);
        receipt.finalizedBy = msg.sender;
        receipt.finalizedAt = finalizedAt;
        receipt.resultHash = resultHash;
        receipt.status = KdexitTypes.ExecutionRequestStatus.Completed;

        emit ExecutionCompleted(
            executionId,
            receipt.strategyId,
            receipt.account,
            msg.sender,
            resultHash,
            finalizedAt
        );
    }

    /// @notice Scaffold-only failure recorder for future relayer-driven reconciliation.
    /// @dev This does not perform retries or recovery. It only finalizes the receipt and emits an event.
    function recordExecutionFailure(
        bytes32 executionId,
        bytes32 failureCode,
        bytes32 failureContextHash
    ) external onlyRole(KdexitRoles.EXECUTION_RELAYER_ROLE) whenNotPaused {
        KdexitTypes.ExecutionReceipt storage receipt = _executionReceipts[executionId];
        if (receipt.status == KdexitTypes.ExecutionRequestStatus.None) {
            revert ExecutionNotSubmitted(executionId);
        }
        if (receipt.status != KdexitTypes.ExecutionRequestStatus.Submitted) {
            revert ExecutionNotPending(executionId);
        }

        uint64 finalizedAt = uint64(block.timestamp);
        receipt.finalizedBy = msg.sender;
        receipt.finalizedAt = finalizedAt;
        receipt.failureCode = failureCode;
        receipt.failureContextHash = failureContextHash;
        receipt.status = KdexitTypes.ExecutionRequestStatus.Failed;

        emit ExecutionFailed(
            executionId,
            receipt.strategyId,
            receipt.account,
            msg.sender,
            failureCode,
            failureContextHash,
            finalizedAt
        );
    }

    /// @notice Activates emergency pause.
    /// @dev Scaffold policy: emergency pause must stop new execution request intake immediately.
    function pause() external onlyRole(KdexitRoles.EMERGENCY_PAUSER_ROLE) {
        _pause();
        emit EmergencyPauseStateChanged(true, msg.sender, uint64(block.timestamp));
    }

    /// @notice Lifts emergency pause after admin review.
    /// @dev Scaffold policy: recovery is intentionally more restricted than pause activation.
    function unpause() external onlyRole(KdexitRoles.ADMIN_ROLE) {
        _unpause();
        emit EmergencyPauseStateChanged(false, msg.sender, uint64(block.timestamp));
    }

    function getExecutionReceipt(bytes32 executionId)
        external
        view
        returns (KdexitTypes.ExecutionReceipt memory)
    {
        return _executionReceipts[executionId];
    }

    function isExecutionSubmitted(bytes32 executionId) external view returns (bool) {
        return _executionReceipts[executionId].status == KdexitTypes.ExecutionRequestStatus.Submitted;
    }

    function isEmergencyPaused() external view returns (bool) {
        return paused();
    }

    function canSubmitExecutionRequests() external view returns (bool) {
        return !paused();
    }
}
