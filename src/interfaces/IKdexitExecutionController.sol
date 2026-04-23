// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {KdexitTypes} from "../libraries/KdexitTypes.sol";

interface IKdexitExecutionController {
    event ExecutionRequestSubmitted(
        bytes32 indexed executionId,
        bytes32 indexed strategyId,
        address indexed account,
        address submitter,
        uint256 amountIn,
        bytes32 payloadHash,
        uint64 requestedAt,
        uint64 submittedAt
    );

    event ExecutionCompleted(
        bytes32 indexed executionId,
        bytes32 indexed strategyId,
        address indexed account,
        address finalizer,
        bytes32 resultHash,
        uint64 finalizedAt
    );

    event ExecutionFailed(
        bytes32 indexed executionId,
        bytes32 indexed strategyId,
        address indexed account,
        address finalizer,
        bytes32 failureCode,
        bytes32 failureContextHash,
        uint64 finalizedAt
    );

    event EmergencyPauseStateChanged(
        bool indexed isPaused, address indexed actor, uint64 changedAt
    );

    function submitExecutionRequest(KdexitTypes.ExecutionRequest calldata request) external;

    /// @notice Scaffold-only completion marker for future reconciliation flows.
    function recordExecutionCompletion(bytes32 executionId, bytes32 resultHash) external;

    /// @notice Scaffold-only failure marker for future reconciliation flows.
    function recordExecutionFailure(
        bytes32 executionId,
        bytes32 failureCode,
        bytes32 failureContextHash
    ) external;

    function getExecutionReceipt(bytes32 executionId)
        external
        view
        returns (KdexitTypes.ExecutionReceipt memory);

    function isExecutionSubmitted(bytes32 executionId) external view returns (bool);

    /// @notice Returns true when emergency pause is active.
    function isEmergencyPaused() external view returns (bool);

    /// @notice Returns true when scaffold-level execution request intake is available.
    function canSubmitExecutionRequests() external view returns (bool);
}
