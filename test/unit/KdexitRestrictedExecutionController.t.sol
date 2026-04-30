// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {KdexitRestrictedExecutionController} from "../../src/KdexitRestrictedExecutionController.sol";
import {KdexitStrategyRegistry} from "../../src/KdexitStrategyRegistry.sol";
import {KdexitRoles} from "../../src/access/KdexitRoles.sol";
import {KdexitTypes} from "../../src/libraries/KdexitTypes.sol";
import {BaseTest} from "../utils/BaseTest.sol";

contract KdexitRestrictedExecutionControllerTest is BaseTest {
    event RestrictedSellExecutionPrepared(
        bytes32 indexed preparationId,
        address indexed user,
        bytes32 indexed strategyId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address adapter,
        bytes32 adapterId,
        uint64 deadline,
        address submitter,
        uint64 preparedAt
    );

    address internal constant ADMIN = address(0xA11CE);
    address internal constant PAUSER = address(0xA055E);
    address internal constant RELAYER = address(0xAE14A);
    address internal constant NON_RELAYER = address(0xB0B);
    address internal constant USER = address(0xACC0);
    address internal constant TOKEN_IN = address(0x7001);
    address internal constant TOKEN_OUT = address(0x7002);
    address internal constant ADAPTER = address(0xADAA);
    address internal constant UNKNOWN_ADAPTER = address(0xADBB);
    address internal constant STRATEGY_TARGET = address(0xCAFE);

    bytes32 internal constant STRATEGY_ID = keccak256("kdexit.strategy.alpha");
    bytes32 internal constant ADAPTER_ID = keccak256("kdexit.adapter.mock");

    KdexitStrategyRegistry internal registry;
    KdexitRestrictedExecutionController internal controller;

    function setUp() public {
        registry = new KdexitStrategyRegistry(ADMIN);
        controller = new KdexitRestrictedExecutionController(ADMIN, PAUSER, address(registry));

        vm.startPrank(ADMIN);
        registry.setStrategy(
            STRATEGY_ID,
            KdexitTypes.StrategyConfig({
                target: STRATEGY_TARGET,
                enabled: true,
                metadata: abi.encodePacked("alpha")
            })
        );
        controller.grantRole(KdexitRoles.EXECUTION_RELAYER_ROLE, RELAYER);
        controller.setAdapterAllowed(ADAPTER, ADAPTER_ID, true);
        controller.setTokenAllowed(TOKEN_IN, true);
        controller.setTokenAllowed(TOKEN_OUT, true);
        vm.stopPrank();
    }

    function testPrepareRestrictedSellExecutionEmitsEvent() public {
        KdexitTypes.RestrictedSellParams memory params = _makeParams();
        vm.warp(1_700_000_000);
        params.deadline = uint64(block.timestamp + 1 hours);

        bytes32 expectedPreparationId = keccak256(
            abi.encode(
                params.user,
                params.strategyId,
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                params.minAmountOut,
                params.adapter,
                ADAPTER_ID,
                params.deadline,
                RELAYER,
                uint64(block.timestamp),
                block.chainid
            )
        );

        vm.prank(RELAYER);
        vm.expectEmit(true, true, true, true, address(controller));
        emit RestrictedSellExecutionPrepared(
            expectedPreparationId,
            params.user,
            params.strategyId,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            params.minAmountOut,
            params.adapter,
            ADAPTER_ID,
            params.deadline,
            RELAYER,
            uint64(block.timestamp)
        );
        bytes32 preparationId = controller.prepareRestrictedSellExecution(params);

        assertEq(preparationId, expectedPreparationId, "preparation id mismatch");
    }

    function testNonAllowlistedAdapterRejected() public {
        KdexitTypes.RestrictedSellParams memory params = _makeParams();
        params.adapter = UNKNOWN_ADAPTER;

        vm.prank(RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitRestrictedExecutionController.AdapterNotAllowed.selector,
                UNKNOWN_ADAPTER
            )
        );
        controller.prepareRestrictedSellExecution(params);
    }

    function testNonAllowlistedTokenRejected() public {
        address unknownToken = address(0x7003);
        KdexitTypes.RestrictedSellParams memory params = _makeParams();
        params.tokenOut = unknownToken;

        vm.prank(RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitRestrictedExecutionController.TokenNotAllowed.selector,
                unknownToken
            )
        );
        controller.prepareRestrictedSellExecution(params);
    }

    function testPausedStateBlocksExecutionPreparation() public {
        vm.prank(PAUSER);
        controller.pause();

        vm.prank(RELAYER);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        controller.prepareRestrictedSellExecution(_makeParams());
    }

    function testOnlyAuthorizedRelayerCanPrepareExecution() public {
        vm.prank(NON_RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_RELAYER,
                KdexitRoles.EXECUTION_RELAYER_ROLE
            )
        );
        controller.prepareRestrictedSellExecution(_makeParams());
    }

    function _makeParams() internal view returns (KdexitTypes.RestrictedSellParams memory) {
        return KdexitTypes.RestrictedSellParams({
            user: USER,
            strategyId: STRATEGY_ID,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            amountIn: 1 ether,
            minAmountOut: 900 ether,
            adapter: ADAPTER,
            deadline: uint64(block.timestamp + 1 days)
        });
    }
}
