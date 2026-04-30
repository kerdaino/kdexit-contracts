# KDEXIT Phase 8 Execution Authorization

This note documents the first internal-beta execution authorization layer. It
adds user-signed EIP-712 intent verification only. It does not add swaps,
arbitrary execution, token approvals, custody, router integrations, or relayer
private-key flow.

## Contract

New contract:

- `KdexitExecutionAuthorization`

Supporting type:

- `KdexitTypes.ExecutionAuthorization`

The contract verifies and consumes a user authorization for a future restricted
sell flow. Consumption means the user intent was proven and the nonce was used.
It does not mean a sell occurred.

## Typed Authorization

The signed EIP-712 struct is:

- `wallet`: user wallet that must have signed the authorization
- `strategyId`: strategy identifier that must be enabled in
  `KdexitStrategyRegistry`
- `token`: token address the future sell path may act on
- `adapter`: allowed future adapter or router identifier
- `chainId`: chain where the authorization is valid
- `sellBps`: maximum sell percentage in basis points
- `maxAmountIn`: maximum token amount the future flow may use
- `nonce`: current wallet nonce in the authorizer contract
- `deadline`: final timestamp at which the authorization is valid

`sellBps` and `maxAmountIn` are caps. Future execution code must treat them as
upper bounds, not instructions to sell more than is safe. If both are set, both
must be respected.

## Lifecycle

1. The user signs an `ExecutionAuthorization` using EIP-712 typed data.
2. A backend or operator may call `verifyAuthorization(...)` to check the
   signature without consuming it.
3. A backend or future restricted execution path calls `consumeAuthorization(...)`.
4. The contract checks:
   - wallet is nonzero
   - token is nonzero
   - adapter is nonzero
   - signed chain ID equals `block.chainid`
   - deadline has not expired
   - sell bounds are valid
   - strategy is enabled in the registry
   - authorization digest has not been revoked
   - authorization digest has not already been consumed
   - nonce equals the wallet's current nonce
   - recovered signer equals `wallet`
5. The wallet nonce is consumed.
6. `ExecutionAuthorizationConsumed` is emitted.

No token is transferred. No approval is set. No adapter is called.

## Replay Protection And Nonces

Replay protection is per wallet and uses OpenZeppelin `Nonces`.

- each wallet starts at nonce `0`
- a valid consumed authorization increments the wallet nonce
- the same signed authorization cannot be consumed twice
- any authorization with an old nonce becomes invalid after nonce consumption

The nonce is also part of the EIP-712 signed data, so a signature cannot be
silently replayed under another nonce.

## Expiration

Every authorization includes `deadline`.

The authorizer rejects the authorization when:

- `deadline < block.timestamp`

Internal beta systems should use short deadlines and should not queue execution
work near expiry.

## Revocation

There are two user-controlled revocation tools:

- `revokeAuthorization(authorization)` revokes one exact EIP-712 digest without
  consuming the nonce.
- `cancelNonce(nonce)` consumes the caller's current nonce and invalidates every
  authorization signed with that nonce.

Only the wallet in the authorization can revoke that authorization. Admins,
linked wallets, watchers, and relayers cannot revoke on the user's behalf in
this first layer.

## Separation Of Concerns

This layer intentionally separates:

- wallet linking: not represented in this contract
- strategy existence: checked only through `KdexitStrategyRegistry`
- execution authorization: proven only by the user's EIP-712 signature
- execution delivery: not implemented here
- token approvals: not implemented here
- settlement: not implemented here

A linked wallet is not enough. An enabled strategy is not enough. A relayer is
not enough. Future execution must require a valid consumed user authorization
plus its own execution and settlement checks.

## Restrictions

The authorization cannot become arbitrary execution permission because it binds:

- a single wallet
- a single strategy ID
- a single token
- a single adapter
- a single chain ID
- bounded sell parameters
- one nonce
- one deadline
- this authorizer contract through the EIP-712 domain

The contract does not accept arbitrary calldata, does not call the adapter, and
does not grant any admin execution path.

## Internal Beta Notes

Before this authorization layer is connected to live execution, KDEXIT still
needs:

- restricted execution adapter design
- supported token policy
- supported adapter policy
- settlement verification
- pause integration for the asset-moving path
- relayer restrictions
- integration and invariant tests around execution

This Phase 8 layer is only the first safe authorization boundary.
