// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPancakeSwapV2RouterLike
/// @notice Minimal PancakeSwap-v2-compatible router surface for a simple exact-input sell.
/// @dev This is intentionally not a generic router interface. The adapter scaffold
/// only needs the canonical token-for-token exact-input path for BSC testnet work.
interface IPancakeSwapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
