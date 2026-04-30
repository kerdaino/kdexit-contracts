// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { IKdexitStrategyRegistry } from "./interfaces/IKdexitStrategyRegistry.sol";
import { KdexitTypes } from "./libraries/KdexitTypes.sol";

/// @title KdexitExecutionAuthorization
/// @notice Phase 8 EIP-712 authorization layer for future internal-beta sell execution.
/// @dev This contract only verifies, revokes, and consumes user intent. It never
/// transfers tokens, sets approvals, calls routers, or executes arbitrary calldata.
contract KdexitExecutionAuthorization is EIP712, Nonces {
    error StrategyRegistryAddressZero();
    error WalletAddressZero();
    error TokenAddressZero();
    error AdapterAddressZero();
    error AuthorizationWrongChain(uint256 expectedChainId, uint256 actualChainId);
    error AuthorizationExpired(uint64 deadline, uint256 currentTime);
    error AuthorizationSellBoundsInvalid();
    error StrategyNotEnabled(bytes32 strategyId);
    error AuthorizationRevoked(bytes32 digest);
    error AuthorizationAlreadyConsumed(bytes32 digest);
    error InvalidAuthorizationSigner(address recovered, address expected);
    error UnauthorizedRevoker(address caller, address wallet);

    /// @dev 10_000 basis points is 100%. Future execution code must interpret
    /// sellBps as a cap, never as permission to exceed maxAmountIn when both are set.
    uint16 public constant MAX_SELL_BPS = 10_000;

    /// @dev Keep this string stable for offchain signers. Changing it invalidates
    /// every existing Phase 8 signature by design.
    bytes32 public constant EXECUTION_AUTHORIZATION_TYPEHASH = keccak256(
        "ExecutionAuthorization(address wallet,bytes32 strategyId,address token,address adapter,uint256 chainId,uint16 sellBps,uint256 maxAmountIn,uint256 nonce,uint64 deadline)"
    );

    IKdexitStrategyRegistry public immutable STRATEGY_REGISTRY;

    mapping(bytes32 digest => bool revoked) private _authorizationRevoked;
    mapping(bytes32 digest => bool consumed) private _authorizationConsumed;

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

    event ExecutionAuthorizationNonceCancelled(address indexed wallet, uint256 indexed nonce);

    constructor(address strategyRegistry_) EIP712("KDEXIT Execution Authorization", "1") {
        if (strategyRegistry_ == address(0)) revert StrategyRegistryAddressZero();
        STRATEGY_REGISTRY = IKdexitStrategyRegistry(strategyRegistry_);
    }

    /// @notice Returns the EIP-712 struct hash for an authorization.
    function hashAuthorization(KdexitTypes.ExecutionAuthorization calldata authorization)
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                EXECUTION_AUTHORIZATION_TYPEHASH,
                authorization.wallet,
                authorization.strategyId,
                authorization.token,
                authorization.adapter,
                authorization.chainId,
                authorization.sellBps,
                authorization.maxAmountIn,
                authorization.nonce,
                authorization.deadline
            )
        );
    }

    /// @notice Returns the full EIP-712 digest that the user signs.
    function authorizationDigest(KdexitTypes.ExecutionAuthorization calldata authorization)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(hashAuthorization(authorization));
    }

    /// @notice Returns whether a concrete signed authorization digest was revoked.
    function isAuthorizationRevoked(bytes32 digest) external view returns (bool) {
        return _authorizationRevoked[digest];
    }

    /// @notice Returns whether a concrete signed authorization digest was consumed.
    function isAuthorizationConsumed(bytes32 digest) external view returns (bool) {
        return _authorizationConsumed[digest];
    }

    /// @notice Verifies an authorization without consuming its nonce.
    /// @dev This is a convenience read for operators and tests. A later execution
    /// path must still call a consuming function before any external effect.
    function verifyAuthorization(
        KdexitTypes.ExecutionAuthorization calldata authorization,
        bytes calldata signature
    ) external view returns (bytes32 digest, address recovered) {
        return _validateAuthorization(authorization, signature);
    }

    /// @notice Consumes a valid authorization so a future execution path can prove user intent.
    /// @dev This function intentionally has no relayer role check because it does
    /// not execute or approve anything. The user signature is the permission being
    /// proven, and nonce consumption is the replay boundary.
    function consumeAuthorization(
        KdexitTypes.ExecutionAuthorization calldata authorization,
        bytes calldata signature
    ) external returns (bytes32 digest) {
        (digest,) = _validateAuthorization(authorization, signature);
        _useCheckedNonce(authorization.wallet, authorization.nonce);
        _authorizationConsumed[digest] = true;

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
            msg.sender
        );
    }

    /// @notice Revokes one exact authorization digest.
    /// @dev Revocation is wallet-controlled and does not consume the nonce, so the
    /// wallet may issue a replacement authorization with the same nonce but different
    /// bounded parameters. This separates revocation from wallet linking or admin policy.
    function revokeAuthorization(KdexitTypes.ExecutionAuthorization calldata authorization)
        external
    {
        if (msg.sender != authorization.wallet) {
            revert UnauthorizedRevoker(msg.sender, authorization.wallet);
        }

        bytes32 digest = authorizationDigest(authorization);
        _authorizationRevoked[digest] = true;

        emit ExecutionAuthorizationRevoked(digest, authorization.wallet, authorization.nonce);
    }

    /// @notice Cancels the caller's next expected nonce without tying it to one authorization.
    /// @dev This is a stronger revocation tool for leaked or ambiguous offchain
    /// intents. It advances the nonce and invalidates every authorization signed
    /// with that nonce.
    function cancelNonce(uint256 nonce) external {
        _useCheckedNonce(msg.sender, nonce);
        emit ExecutionAuthorizationNonceCancelled(msg.sender, nonce);
    }

    function _validateAuthorization(
        KdexitTypes.ExecutionAuthorization calldata authorization,
        bytes calldata signature
    ) internal view returns (bytes32 digest, address recovered) {
        if (authorization.wallet == address(0)) revert WalletAddressZero();
        if (authorization.token == address(0)) revert TokenAddressZero();
        if (authorization.adapter == address(0)) revert AdapterAddressZero();
        if (authorization.chainId != block.chainid) {
            revert AuthorizationWrongChain(authorization.chainId, block.chainid);
        }
        if (authorization.deadline < block.timestamp) {
            revert AuthorizationExpired(authorization.deadline, block.timestamp);
        }
        if (authorization.sellBps > MAX_SELL_BPS) revert AuthorizationSellBoundsInvalid();
        if (authorization.sellBps == 0 && authorization.maxAmountIn == 0) {
            revert AuthorizationSellBoundsInvalid();
        }
        if (!STRATEGY_REGISTRY.isStrategyEnabled(authorization.strategyId)) {
            revert StrategyNotEnabled(authorization.strategyId);
        }

        digest = authorizationDigest(authorization);
        if (_authorizationRevoked[digest]) revert AuthorizationRevoked(digest);
        if (_authorizationConsumed[digest]) revert AuthorizationAlreadyConsumed(digest);
        if (authorization.nonce != nonces(authorization.wallet)) {
            revert InvalidAccountNonce(authorization.wallet, nonces(authorization.wallet));
        }

        recovered = ECDSA.recoverCalldata(digest, signature);
        if (recovered != authorization.wallet) {
            revert InvalidAuthorizationSigner(recovered, authorization.wallet);
        }
    }
}
