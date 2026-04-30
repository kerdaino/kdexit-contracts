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

    /// @notice User-signed Phase 8 authorization for a future restricted sell path.
    /// @dev This is deliberately not executable calldata. It binds a wallet to one
    /// strategy, token, adapter, chain, nonce, and expiry so later execution logic
    /// cannot reinterpret the signature as broad trading permission.
    struct ExecutionAuthorization {
        address wallet;
        bytes32 strategyId;
        address token;
        address adapter;
        uint256 chainId;
        uint16 sellBps;
        uint256 maxAmountIn;
        uint256 nonce;
        uint64 deadline;
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
