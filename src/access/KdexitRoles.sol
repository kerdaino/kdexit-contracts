// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Role identifiers for the minimal KDEXIT Phase 4 access model.
library KdexitRoles {
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant EXECUTION_RELAYER_ROLE = keccak256("EXECUTION_RELAYER_ROLE");
    bytes32 internal constant EMERGENCY_PAUSER_ROLE = keccak256("EMERGENCY_PAUSER_ROLE");
}
