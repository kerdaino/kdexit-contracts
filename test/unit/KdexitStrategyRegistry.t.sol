// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {KdexitStrategyRegistry} from "../../src/KdexitStrategyRegistry.sol";
import {KdexitRoles} from "../../src/access/KdexitRoles.sol";
import {KdexitTypes} from "../../src/libraries/KdexitTypes.sol";
import {BaseTest} from "../utils/BaseTest.sol";

contract KdexitStrategyRegistryTest is BaseTest {
    event StrategyAuthorizationRegistered(
        bytes32 indexed strategyId,
        address indexed target,
        address indexed actor,
        bool enabled,
        bytes32 metadataHash,
        uint64 configuredAt
    );

    address internal constant ADMIN = address(0xA11CE);
    address internal constant NON_ADMIN = address(0xB0B);

    bytes32 internal constant STRATEGY_ID = keccak256("kdexit.strategy.alpha");
    address internal constant STRATEGY_TARGET = address(0xCAFE);

    KdexitStrategyRegistry internal registry;

    function setUp() public {
        registry = new KdexitStrategyRegistry(ADMIN);
    }

    function testDeploymentSetsAdminRoles() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), ADMIN), "default admin missing");
        assertTrue(
            registry.hasRole(KdexitRoles.ADMIN_ROLE, ADMIN), "kdexit admin role missing"
        );
    }

    function testSetStrategyRevertsForNonAdmin() public {
        KdexitTypes.StrategyConfig memory config = KdexitTypes.StrategyConfig({
            target: STRATEGY_TARGET,
            enabled: true,
            metadata: abi.encodePacked("alpha")
        });

        vm.prank(NON_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_ADMIN,
                KdexitRoles.ADMIN_ROLE
            )
        );
        registry.setStrategy(STRATEGY_ID, config);
    }

    function testSetStrategyEmitsAuthorizationEventAndStoresConfig() public {
        bytes memory metadata = abi.encodePacked("alpha");
        KdexitTypes.StrategyConfig memory config = KdexitTypes.StrategyConfig({
            target: STRATEGY_TARGET,
            enabled: true,
            metadata: metadata
        });

        vm.warp(1_700_000_000);
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true, address(registry));
        emit StrategyAuthorizationRegistered(
            STRATEGY_ID,
            STRATEGY_TARGET,
            ADMIN,
            true,
            keccak256(metadata),
            uint64(block.timestamp)
        );
        registry.setStrategy(STRATEGY_ID, config);

        KdexitTypes.StrategyConfig memory stored = registry.getStrategy(STRATEGY_ID);
        assertEq(stored.target, STRATEGY_TARGET, "strategy target mismatch");
        assertTrue(stored.enabled, "strategy should be enabled");
        assertTrue(registry.isStrategyEnabled(STRATEGY_ID), "strategy enabled view mismatch");
    }
}
