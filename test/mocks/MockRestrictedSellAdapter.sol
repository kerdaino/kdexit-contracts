// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IKdexitRestrictedSellAdapter} from "../../src/interfaces/IKdexitRestrictedSellAdapter.sol";
import {KdexitTypes} from "../../src/libraries/KdexitTypes.sol";

/// @title MockRestrictedSellAdapter
/// @notice Local test-only adapter that simulates restricted sell outcomes.
/// @dev This mock never transfers tokens, sets approvals, calls routers, or takes
/// custody. It only emits deterministic events and returns configured fake output.
contract MockRestrictedSellAdapter is IKdexitRestrictedSellAdapter {
    bytes32 public immutable override adapterId;
    bool public shouldSucceed = true;
    uint256 public mockedAmountOut;
    bytes32 public failureCode;

    event MockRestrictedSellSucceeded(
        address indexed user,
        bytes32 indexed strategyId,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint64 deadline,
        address caller
    );

    event MockRestrictedSellFailed(
        address indexed user,
        bytes32 indexed strategyId,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes32 failureCode,
        address caller
    );

    constructor(bytes32 adapterId_, uint256 mockedAmountOut_) {
        adapterId = adapterId_;
        mockedAmountOut = mockedAmountOut_;
    }

    function setMockResult(bool shouldSucceed_, uint256 mockedAmountOut_, bytes32 failureCode_)
        external
    {
        shouldSucceed = shouldSucceed_;
        mockedAmountOut = mockedAmountOut_;
        failureCode = failureCode_;
    }

    function executeRestrictedSell(KdexitTypes.RestrictedSellParams calldata params)
        external
        override
        returns (uint256 amountOut)
    {
        if (!shouldSucceed || mockedAmountOut < params.minAmountOut) {
            bytes32 resolvedFailureCode = failureCode == bytes32(0)
                ? keccak256("MOCK_RESTRICTED_SELL_FAILED")
                : failureCode;
            emit MockRestrictedSellFailed(
                params.user,
                params.strategyId,
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                params.minAmountOut,
                resolvedFailureCode,
                msg.sender
            );
            return 0;
        }

        emit MockRestrictedSellSucceeded(
            params.user,
            params.strategyId,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            mockedAmountOut,
            params.deadline,
            msg.sender
        );
        return mockedAmountOut;
    }
}
