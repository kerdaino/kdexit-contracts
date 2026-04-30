// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {KdexitTypes} from "../libraries/KdexitTypes.sol";

/// @title IKdexitRestrictedSellAdapter
/// @notice Interface for future reviewed sell adapters used by the internal beta.
/// @dev This interface is intentionally narrow. The current Phase 8 Step 2
/// controller does not call adapters yet; it only allowlists adapter addresses
/// for later restricted integration work.
interface IKdexitRestrictedSellAdapter {
    /// @notice Stable identifier for the adapter implementation or route family.
    function adapterId() external view returns (bytes32);

    /// @notice Future restricted sell hook. Not called by the current scaffold.
    /// @dev Implementations must not be treated as approved merely because they
    /// implement this interface. The adapter address must also be allowlisted by
    /// the restricted execution controller before any future execution path uses it.
    function executeRestrictedSell(KdexitTypes.RestrictedSellParams calldata params)
        external
        returns (uint256 amountOut);
}
