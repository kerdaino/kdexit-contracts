// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {KdexitExecutionAuthorization} from "../../src/KdexitExecutionAuthorization.sol";
import {KdexitExecutionController} from "../../src/KdexitExecutionController.sol";
import {KdexitRestrictedExecutionController} from "../../src/KdexitRestrictedExecutionController.sol";
import {KdexitStrategyRegistry} from "../../src/KdexitStrategyRegistry.sol";
import {KdexitRoles} from "../../src/access/KdexitRoles.sol";
import {KdexitTypes} from "../../src/libraries/KdexitTypes.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockRestrictedSellAdapter} from "../mocks/MockRestrictedSellAdapter.sol";
import {BaseTest} from "../utils/BaseTest.sol";

contract KdexitLocalMockExecutionFlowTest is BaseTest {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant PAUSER = address(0xA055E);
    address internal constant RELAYER = address(0xAE14A);
    address internal constant NON_RELAYER = address(0xB0B);
    address internal constant STRATEGY_TARGET = address(0xCAFE);

    uint256 internal constant USER_PRIVATE_KEY = 0xA11CE123;
    uint256 internal constant SELL_AMOUNT = 10 ether;
    uint256 internal constant MOCK_AMOUNT_OUT = 950 ether;

    bytes32 internal constant STRATEGY_ID = keccak256("kdexit.strategy.alpha");
    bytes32 internal constant ADAPTER_ID = keccak256("kdexit.adapter.local-mock");
    bytes32 internal constant FAILURE_CODE = keccak256("MOCK_ROUTE_FAILED");

    KdexitStrategyRegistry internal registry;
    KdexitExecutionAuthorization internal authorizer;
    KdexitRestrictedExecutionController internal restrictedController;
    KdexitExecutionController internal executionController;
    MockRestrictedSellAdapter internal adapter;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    address internal user;

    function setUp() public {
        user = vm.addr(USER_PRIVATE_KEY);

        registry = new KdexitStrategyRegistry(ADMIN);
        authorizer = new KdexitExecutionAuthorization(address(registry));
        restrictedController =
            new KdexitRestrictedExecutionController(ADMIN, PAUSER, address(registry));
        executionController = new KdexitExecutionController(ADMIN, PAUSER, address(registry));
        adapter = new MockRestrictedSellAdapter(ADAPTER_ID, MOCK_AMOUNT_OUT);
        tokenIn = new MockERC20("Mock Token In", "MTI", 18);
        tokenOut = new MockERC20("Mock Token Out", "MTO", 18);

        tokenIn.mint(user, 100 ether);

        vm.startPrank(ADMIN);
        registry.setStrategy(
            STRATEGY_ID,
            KdexitTypes.StrategyConfig({
                target: STRATEGY_TARGET,
                enabled: true,
                metadata: abi.encodePacked("alpha")
            })
        );
        restrictedController.grantRole(KdexitRoles.EXECUTION_RELAYER_ROLE, RELAYER);
        executionController.grantRole(KdexitRoles.EXECUTION_RELAYER_ROLE, RELAYER);
        restrictedController.setAdapterAllowed(address(adapter), ADAPTER_ID, true);
        restrictedController.setTokenAllowed(address(tokenIn), true);
        restrictedController.setTokenAllowed(address(tokenOut), true);
        vm.stopPrank();
    }

    function testSuccessfulSimulatedSellExecution() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);
        KdexitTypes.RestrictedSellParams memory params = _makeParams();
        bytes32 executionId = keccak256("kdexit.local.execution.success");

        vm.startPrank(RELAYER);
        bytes32 authorizationDigest = authorizer.consumeAuthorization(authorization, signature);
        bytes32 preparationId = restrictedController.prepareRestrictedSellExecution(params);

        executionController.submitExecutionRequest(
            _makeExecutionRequest(executionId, preparationId)
        );
        uint256 amountOut = adapter.executeRestrictedSell(params);
        bytes32 resultHash = keccak256(
            abi.encode(authorizationDigest, preparationId, amountOut, "MOCK_SETTLED")
        );
        executionController.recordExecutionCompletion(executionId, resultHash);
        vm.stopPrank();

        KdexitTypes.ExecutionReceipt memory receipt =
            executionController.getExecutionReceipt(executionId);
        assertEq(uint256(uint8(receipt.status)), 2, "receipt should be completed");
        assertEq(receipt.resultHash, resultHash, "result hash mismatch");
        assertEq(amountOut, MOCK_AMOUNT_OUT, "mock amount out mismatch");
        assertEq(tokenIn.balanceOf(user), 100 ether, "mock flow must not move token in");
        assertEq(tokenOut.balanceOf(user), 0, "mock flow must not mint token out");
    }

    function testSimulatedExecutionFailureRecordsFailure() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);
        KdexitTypes.RestrictedSellParams memory params = _makeParams();
        bytes32 executionId = keccak256("kdexit.local.execution.failure");

        adapter.setMockResult(false, 0, FAILURE_CODE);

        vm.startPrank(RELAYER);
        bytes32 authorizationDigest = authorizer.consumeAuthorization(authorization, signature);
        bytes32 preparationId = restrictedController.prepareRestrictedSellExecution(params);

        executionController.submitExecutionRequest(
            _makeExecutionRequest(executionId, preparationId)
        );
        uint256 amountOut = adapter.executeRestrictedSell(params);
        bytes32 failureContextHash =
            keccak256(abi.encode(authorizationDigest, preparationId, amountOut, "MOCK_FAILED"));
        executionController.recordExecutionFailure(executionId, FAILURE_CODE, failureContextHash);
        vm.stopPrank();

        KdexitTypes.ExecutionReceipt memory receipt =
            executionController.getExecutionReceipt(executionId);
        assertEq(uint256(uint8(receipt.status)), 3, "receipt should be failed");
        assertEq(receipt.failureCode, FAILURE_CODE, "failure code mismatch");
        assertEq(
            receipt.failureContextHash, failureContextHash, "failure context hash mismatch"
        );
        assertEq(amountOut, 0, "failed mock execution should return zero");
    }

    function testReplayProtectionBlocksSecondMockExecution() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);

        vm.prank(RELAYER);
        authorizer.consumeAuthorization(authorization, signature);

        vm.prank(RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitExecutionAuthorization.AuthorizationAlreadyConsumed.selector,
                authorizer.authorizationDigest(authorization)
            )
        );
        authorizer.consumeAuthorization(authorization, signature);
    }

    function testPausedStateBlocksMockExecutionPreparation() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);

        vm.prank(RELAYER);
        authorizer.consumeAuthorization(authorization, signature);

        vm.prank(PAUSER);
        restrictedController.pause();

        vm.prank(RELAYER);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        restrictedController.prepareRestrictedSellExecution(_makeParams());
    }

    function testUnauthorizedRelayerRejected() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);

        vm.prank(NON_RELAYER);
        authorizer.consumeAuthorization(authorization, signature);

        vm.prank(NON_RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                NON_RELAYER,
                KdexitRoles.EXECUTION_RELAYER_ROLE
            )
        );
        restrictedController.prepareRestrictedSellExecution(_makeParams());
    }

    function _makeAuthorization(uint256 nonce, uint64 ttl)
        internal
        view
        returns (KdexitTypes.ExecutionAuthorization memory)
    {
        return KdexitTypes.ExecutionAuthorization({
            wallet: user,
            strategyId: STRATEGY_ID,
            token: address(tokenIn),
            adapter: address(adapter),
            chainId: block.chainid,
            sellBps: 2_500,
            maxAmountIn: SELL_AMOUNT,
            nonce: nonce,
            deadline: uint64(block.timestamp + ttl)
        });
    }

    function _makeParams() internal view returns (KdexitTypes.RestrictedSellParams memory) {
        return KdexitTypes.RestrictedSellParams({
            user: user,
            strategyId: STRATEGY_ID,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            amountIn: SELL_AMOUNT,
            minAmountOut: 900 ether,
            adapter: address(adapter),
            deadline: uint64(block.timestamp + 1 days)
        });
    }

    function _makeExecutionRequest(bytes32 executionId, bytes32 preparationId)
        internal
        view
        returns (KdexitTypes.ExecutionRequest memory)
    {
        return KdexitTypes.ExecutionRequest({
            executionId: executionId,
            account: user,
            strategyId: STRATEGY_ID,
            amountIn: SELL_AMOUNT,
            payloadHash: preparationId,
            requestedAt: uint64(block.timestamp)
        });
    }

    function _signAuthorization(
        uint256 privateKey,
        KdexitTypes.ExecutionAuthorization memory authorization
    ) internal view returns (bytes memory) {
        bytes32 digest = authorizer.authorizationDigest(authorization);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
