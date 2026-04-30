# KDEXIT Phase 8 Restricted Execution Adapter Scaffold

This note documents the internal-beta restricted execution adapter model. It is
the safety layer before any router integration. It does not implement swaps,
arbitrary external calls, broad admin transfers, custody vault logic, or dynamic
router support.

## New Components

Contracts and interfaces:

- `KdexitRestrictedExecutionController`
- `IKdexitRestrictedSellAdapter`

Shared type:

- `KdexitTypes.RestrictedSellParams`

The restricted execution controller prepares future sell execution requests. It
does not execute them. Preparation means the request passed the current beta
allowlist checks and an event was emitted for backend reconciliation.

## Strict Sell Parameters

`RestrictedSellParams` contains:

- `user`
- `strategyId`
- `tokenIn`
- `tokenOut`
- `amountIn`
- `minAmountOut`
- `adapter`
- `deadline`

The struct intentionally does not include arbitrary calldata. Future adapter
payloads must be designed per adapter and reviewed separately.

## Adapter Allowlisting

Adapters are allowlisted by admin using:

- `setAdapterAllowed(adapter, adapterId, true)`
- `setAdapterAllowed(adapter, adapterId, false)`

Allowlisting records:

- adapter address
- stable adapter identifier
- allowed/removed event history

Events:

- `RestrictedSellAdapterAllowed`
- `RestrictedSellAdapterRemoved`

Adapter allowlisting is required because a future execution path must never
treat user-provided adapter addresses as trusted. Implementing
`IKdexitRestrictedSellAdapter` is not enough. The address must be explicitly
approved by the restricted execution controller.

## Token Allowlisting

Tokens are allowlisted by admin using:

- `setTokenAllowed(token, true)`
- `setTokenAllowed(token, false)`

Events:

- `RestrictedSellTokenAllowed`
- `RestrictedSellTokenRemoved`

Both `tokenIn` and `tokenOut` must be allowlisted. This keeps internal beta
execution planning constrained to reviewed assets and avoids accidental support
for nonstandard, malicious, or operationally unsupported tokens.

## Preparation Flow

1. Admin allowlists a reviewed adapter address and adapter ID.
2. Admin allowlists internal-beta `tokenIn` and `tokenOut` assets.
3. Admin enables a strategy in `KdexitStrategyRegistry`.
4. Admin grants `EXECUTION_RELAYER_ROLE` to a controlled relayer account.
5. Relayer calls `prepareRestrictedSellExecution(params)`.
6. The controller checks:
   - caller has `EXECUTION_RELAYER_ROLE`
   - controller is not paused
   - user, token, and adapter addresses are nonzero
   - amount in is nonzero
   - deadline has not expired
   - strategy is enabled
   - adapter is allowlisted
   - token in and token out are allowlisted
7. The controller emits `RestrictedSellExecutionPrepared`.

No adapter call occurs. No token movement occurs. No approval occurs.

## Why This Is Not Arbitrary Execution

This scaffold is not arbitrary execution because:

- callers cannot provide calldata to execute
- admin cannot sweep tokens
- relayers cannot choose unapproved adapters
- relayers cannot choose unapproved tokens
- strategy existence alone is not enough
- adapter interface support alone is not enough
- preparation is pause-gated
- preparation is role-gated
- the controller only emits an event

Future live execution must also require a valid EIP-712 user authorization from
`KdexitExecutionAuthorization` before moving any assets.

## Why Adapter Allowlisting Is Required

Routers and adapters are high-trust integration points. A bad adapter can route
to the wrong market, ignore slippage, mishandle nonstandard tokens, send output
to the wrong recipient, or make unsafe external calls.

The internal beta must therefore support only reviewed adapter addresses. A
later router integration should be added one adapter at a time, with tests for
that exact adapter and route family.

## Deferred Until Later

Still not implemented:

- real DEX swaps
- PancakeSwap or Uniswap integration
- token transfers
- token approvals
- custody
- arbitrary router selection
- generic multicall execution
- adapter-specific calldata payloads
- settlement verification

This layer exists so KDEXIT can add those pieces later behind a narrow,
observable, allowlisted boundary.
