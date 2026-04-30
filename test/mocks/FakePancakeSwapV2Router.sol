// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPancakeSwapV2RouterLike} from "../../src/interfaces/IPancakeSwapV2RouterLike.sol";

/// @title FakePancakeSwapV2Router
/// @notice Local fake router for adapter scaffold tests only.
/// @dev This fake does not transfer tokens. It only checks the simple exact-input
/// path and returns configured amounts so adapter behavior can be tested safely.
contract FakePancakeSwapV2Router is IPancakeSwapV2RouterLike {
    error FakeRouterInsufficientOutput(uint256 amountOut, uint256 amountOutMin);
    error FakeRouterInvalidPath();

    uint256 public amountOut;

    event FakeSwapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to,
        uint256 deadline
    );

    constructor(uint256 amountOut_) {
        amountOut = amountOut_;
    }

    function setAmountOut(uint256 amountOut_) external {
        amountOut = amountOut_;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        if (path.length != 2 || path[0] == address(0) || path[1] == address(0)) {
            revert FakeRouterInvalidPath();
        }
        if (amountOut < amountOutMin) {
            revert FakeRouterInsufficientOutput(amountOut, amountOutMin);
        }

        emit FakeSwapExactTokensForTokens(
            amountIn, amountOutMin, path[0], path[1], to, deadline
        );

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }
}
