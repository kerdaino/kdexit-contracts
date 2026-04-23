// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library KdexitTypes {
    enum ExecutionRequestStatus {
        None,
        Submitted,
        Completed,
        Failed
    }

    struct StrategyConfig {
        address target;
        bool enabled;
        bytes metadata;
    }

    struct ExecutionRequest {
        bytes32 executionId;
        address account;
        bytes32 strategyId;
        uint256 amountIn;
        bytes32 payloadHash;
        uint64 requestedAt;
    }

    struct ExecutionReceipt {
        bytes32 executionId;
        address account;
        bytes32 strategyId;
        uint256 amountIn;
        bytes32 payloadHash;
        uint64 requestedAt;
        address submittedBy;
        uint64 submittedAt;
        address finalizedBy;
        uint64 finalizedAt;
        bytes32 resultHash;
        bytes32 failureCode;
        bytes32 failureContextHash;
        ExecutionRequestStatus status;
    }
}
