// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {KdexitExecutionController} from "../../src/KdexitExecutionController.sol";
import {KdexitStrategyRegistry} from "../../src/KdexitStrategyRegistry.sol";
import {KdexitRoles} from "../../src/access/KdexitRoles.sol";
import {KdexitTypes} from "../../src/libraries/KdexitTypes.sol";
import {BaseTest} from "../utils/BaseTest.sol";

contract KdexitExecutionControllerTest is BaseTest {
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

    address internal constant ADMIN = address(0xA11CE);
    address internal constant PAUSER = address(0xA055E);
    address internal constant RELAYER = address(0xAE14A);
    address internal constant NON_RELAYER = address(0xB0B);
    address internal constant ACCOUNT = address(0xACC0);
    address internal constant STRATEGY_TARGET = address(0xCAFE);

    bytes32 internal constant STRATEGY_ID = keccak256("kdexit.strategy.alpha");
    bytes32 internal constant EXECUTION_ID = keccak256("kdexit.execution.001");
    bytes32 internal constant PAYLOAD_HASH = keccak256("payload");
    bytes32 internal constant RESULT_HASH = keccak256("result");
    bytes32 internal constant FAILURE_CODE = keccak256("SIMULATION_REJECTED");
    bytes32 internal constant FAILURE_CONTEXT_HASH = keccak256("failure-context");

    KdexitStrategyRegistry internal registry;
    KdexitExecutionController internal controller;

    function setUp() public {
        registry = new KdexitStrategyRegistry(ADMIN);
        controller = new KdexitExecutionController(ADMIN, PAUSER, address(registry));

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
        vm.stopPrank();
    }

    function testDeploymentInitializesRolesAndRegistryReference() public view {
        assertEq(
            address(controller.STRATEGY_REGISTRY()),
            address(registry),
            "strategy registry reference mismatch"
        );
        assertTrue(
            controller.hasRole(controller.DEFAULT_ADMIN_ROLE(), ADMIN), "default admin missing"
        );
        assertTrue(controller.hasRole(KdexitRoles.ADMIN_ROLE, ADMIN), "admin role missing");
        assertTrue(
            controller.hasRole(KdexitRoles.EMERGENCY_PAUSER_ROLE, PAUSER), "pauser role missing"
        );
        assertTrue(
            controller.hasRole(KdexitRoles.EXECUTION_RELAYER_ROLE, RELAYER), "relayer role missing"
        );
        assertFalse(controller.isEmergencyPaused(), "controller should start unpaused");
    }

    function testPauseAndUnpauseChangeLifecycleState() public {
        vm.warp(1_700_000_100);
        vm.prank(PAUSER);
        vm.expectEmit(true, true, false, true, address(controller));
        emit EmergencyPauseStateChanged(true, PAUSER, uint64(block.timestamp));
        controller.pause();

        assertTrue(controller.isEmergencyPaused(), "pause flag should be active");
        assertFalse(
            controller.canSubmitExecutionRequests(), "submission should be unavailable while paused"
        );

        vm.warp(1_700_000_200);
        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, true, address(controller));
        emit EmergencyPauseStateChanged(false, ADMIN, uint64(block.timestamp));
        controller.unpause();

        assertFalse(controller.isEmergencyPaused(), "pause flag should be cleared");
        assertTrue(
            controller.canSubmitExecutionRequests(), "submission should be available after unpause"
        );
    }

    function testPauseRevertsForNonPauser() public {
        vm.prank(NON_RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_RELAYER,
                KdexitRoles.EMERGENCY_PAUSER_ROLE
            )
        );
        controller.pause();
    }

    function testUnpauseRevertsForNonAdmin() public {
        vm.prank(PAUSER);
        controller.pause();

        vm.prank(RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                RELAYER,
                KdexitRoles.ADMIN_ROLE
            )
        );
        controller.unpause();
    }

    function testSubmitExecutionRequestRevertsForNonRelayer() public {
        KdexitTypes.ExecutionRequest memory request = _makeRequest(EXECUTION_ID);

        vm.prank(NON_RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_RELAYER,
                KdexitRoles.EXECUTION_RELAYER_ROLE
            )
        );
        controller.submitExecutionRequest(request);
    }

    function testSubmitExecutionRequestRevertsWhilePaused() public {
        vm.prank(PAUSER);
        controller.pause();

        vm.prank(RELAYER);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        controller.submitExecutionRequest(_makeRequest(EXECUTION_ID));
    }

    function testSubmitExecutionRequestEmitsEventAndStoresReceipt() public {
        KdexitTypes.ExecutionRequest memory request = _makeRequest(EXECUTION_ID);

        vm.warp(1_700_000_300);
        vm.prank(RELAYER);
        vm.expectEmit(true, true, true, true, address(controller));
        emit ExecutionRequestSubmitted(
            request.executionId,
            request.strategyId,
            request.account,
            RELAYER,
            request.amountIn,
            request.payloadHash,
            request.requestedAt,
            uint64(block.timestamp)
        );
        controller.submitExecutionRequest(request);

        KdexitTypes.ExecutionReceipt memory receipt = controller.getExecutionReceipt(EXECUTION_ID);
        assertEq(receipt.executionId, request.executionId, "execution id mismatch");
        assertEq(receipt.account, request.account, "account mismatch");
        assertEq(receipt.strategyId, request.strategyId, "strategy mismatch");
        assertEq(receipt.submittedBy, RELAYER, "submitter mismatch");
        assertEq(
            uint256(uint8(receipt.status)),
            uint256(uint8(KdexitTypes.ExecutionRequestStatus.Submitted)),
            "receipt status mismatch"
        );
    }

    function testRecordExecutionCompletionEmitsEvent() public {
        KdexitTypes.ExecutionRequest memory request = _makeRequest(EXECUTION_ID);

        vm.prank(RELAYER);
        controller.submitExecutionRequest(request);

        vm.warp(1_700_000_400);
        vm.prank(RELAYER);
        vm.expectEmit(true, true, true, true, address(controller));
        emit ExecutionCompleted(
            request.executionId,
            request.strategyId,
            request.account,
            RELAYER,
            RESULT_HASH,
            uint64(block.timestamp)
        );
        controller.recordExecutionCompletion(request.executionId, RESULT_HASH);

        KdexitTypes.ExecutionReceipt memory receipt = controller.getExecutionReceipt(EXECUTION_ID);
        assertEq(
            uint256(uint8(receipt.status)),
            uint256(uint8(KdexitTypes.ExecutionRequestStatus.Completed)),
            "completion status mismatch"
        );
        assertEq(receipt.resultHash, RESULT_HASH, "result hash mismatch");
    }

    function testRecordExecutionFailureEmitsEvent() public {
        bytes32 executionId = keccak256("kdexit.execution.002");
        KdexitTypes.ExecutionRequest memory request = _makeRequest(executionId);

        vm.prank(RELAYER);
        controller.submitExecutionRequest(request);

        vm.warp(1_700_000_500);
        vm.prank(RELAYER);
        vm.expectEmit(true, true, true, true, address(controller));
        emit ExecutionFailed(
            request.executionId,
            request.strategyId,
            request.account,
            RELAYER,
            FAILURE_CODE,
            FAILURE_CONTEXT_HASH,
            uint64(block.timestamp)
        );
        controller.recordExecutionFailure(
            request.executionId, FAILURE_CODE, FAILURE_CONTEXT_HASH
        );

        KdexitTypes.ExecutionReceipt memory receipt = controller.getExecutionReceipt(executionId);
        assertEq(
            uint256(uint8(receipt.status)),
            uint256(uint8(KdexitTypes.ExecutionRequestStatus.Failed)),
            "failure status mismatch"
        );
        assertEq(receipt.failureCode, FAILURE_CODE, "failure code mismatch");
        assertEq(
            receipt.failureContextHash,
            FAILURE_CONTEXT_HASH,
            "failure context hash mismatch"
        );
    }

    function _makeRequest(bytes32 executionId)
        internal
        pure
        returns (KdexitTypes.ExecutionRequest memory)
    {
        return KdexitTypes.ExecutionRequest({
            executionId: executionId,
            account: ACCOUNT,
            strategyId: STRATEGY_ID,
            amountIn: 1 ether,
            payloadHash: PAYLOAD_HASH,
            requestedAt: 1_700_000_000
        });
    }
}
