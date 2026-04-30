// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { KdexitExecutionAuthorization } from "../../src/KdexitExecutionAuthorization.sol";
import { KdexitStrategyRegistry } from "../../src/KdexitStrategyRegistry.sol";
import { KdexitTypes } from "../../src/libraries/KdexitTypes.sol";
import { BaseTest } from "../utils/BaseTest.sol";

contract KdexitExecutionAuthorizationTest is BaseTest {
    event ExecutionAuthorizationConsumed(
        bytes32 indexed digest,
        address indexed wallet,
        bytes32 indexed strategyId,
        address token,
        address adapter,
        uint16 sellBps,
        uint256 maxAmountIn,
        uint256 nonce,
        uint64 deadline,
        address submitter
    );

    event ExecutionAuthorizationRevoked(
        bytes32 indexed digest, address indexed wallet, uint256 indexed nonce
    );

    address internal constant ADMIN = address(0xA11CE);
    address internal constant RELAYER = address(0xAE14A);
    address internal constant TOKEN = address(0x7000);
    address internal constant ADAPTER = address(0xADAA);
    address internal constant STRATEGY_TARGET = address(0xCAFE);

    uint256 internal constant USER_PRIVATE_KEY = 0xA11CE123;
    uint256 internal constant OTHER_PRIVATE_KEY = 0xB0B456;

    bytes32 internal constant STRATEGY_ID = keccak256("kdexit.strategy.alpha");

    KdexitStrategyRegistry internal registry;
    KdexitExecutionAuthorization internal authorizer;
    address internal user;

    function setUp() public {
        user = vm.addr(USER_PRIVATE_KEY);

        registry = new KdexitStrategyRegistry(ADMIN);
        authorizer = new KdexitExecutionAuthorization(address(registry));

        vm.prank(ADMIN);
        registry.setStrategy(
            STRATEGY_ID,
            KdexitTypes.StrategyConfig({
                target: STRATEGY_TARGET, enabled: true, metadata: abi.encodePacked("alpha")
            })
        );
    }

    function testValidSignatureConsumesAuthorization() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);
        bytes32 digest = authorizer.authorizationDigest(authorization);

        vm.expectEmit(true, true, true, true, address(authorizer));
        emit ExecutionAuthorizationConsumed(
            digest,
            authorization.wallet,
            authorization.strategyId,
            authorization.token,
            authorization.adapter,
            authorization.sellBps,
            authorization.maxAmountIn,
            authorization.nonce,
            authorization.deadline,
            RELAYER
        );

        vm.prank(RELAYER);
        bytes32 consumedDigest = authorizer.consumeAuthorization(authorization, signature);

        assertEq(consumedDigest, digest, "digest mismatch");
        assertEq(authorizer.nonces(user), 1, "nonce should increment");
        assertTrue(authorizer.isAuthorizationConsumed(digest), "authorization should be consumed");
    }

    function testInvalidSignerReverts() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(OTHER_PRIVATE_KEY, authorization);
        address other = vm.addr(OTHER_PRIVATE_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitExecutionAuthorization.InvalidAuthorizationSigner.selector,
                other,
                authorization.wallet
            )
        );
        authorizer.consumeAuthorization(authorization, signature);
    }

    function testExpiredAuthorizationReverts() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);

        vm.warp(uint256(authorization.deadline) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitExecutionAuthorization.AuthorizationExpired.selector,
                authorization.deadline,
                block.timestamp
            )
        );
        authorizer.consumeAuthorization(authorization, signature);
    }

    function testReplayProtectionRevertsAfterConsumption() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);

        authorizer.consumeAuthorization(authorization, signature);

        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitExecutionAuthorization.AuthorizationAlreadyConsumed.selector,
                authorizer.authorizationDigest(authorization)
            )
        );
        authorizer.consumeAuthorization(authorization, signature);
    }

    function testRevokedAuthorizationReverts() public {
        KdexitTypes.ExecutionAuthorization memory authorization = _makeAuthorization(0, 1 days);
        bytes memory signature = _signAuthorization(USER_PRIVATE_KEY, authorization);
        bytes32 digest = authorizer.authorizationDigest(authorization);

        vm.prank(user);
        vm.expectEmit(true, true, true, true, address(authorizer));
        emit ExecutionAuthorizationRevoked(digest, user, 0);
        authorizer.revokeAuthorization(authorization);

        assertTrue(authorizer.isAuthorizationRevoked(digest), "authorization should be revoked");

        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitExecutionAuthorization.AuthorizationRevoked.selector, digest
            )
        );
        authorizer.consumeAuthorization(authorization, signature);
    }

    function _makeAuthorization(uint256 nonce, uint64 ttl)
        internal
        view
        returns (KdexitTypes.ExecutionAuthorization memory)
    {
        return KdexitTypes.ExecutionAuthorization({
            wallet: user,
            strategyId: STRATEGY_ID,
            token: TOKEN,
            adapter: ADAPTER,
            chainId: block.chainid,
            sellBps: 2_500,
            maxAmountIn: 10 ether,
            nonce: nonce,
            deadline: uint64(block.timestamp + ttl)
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
