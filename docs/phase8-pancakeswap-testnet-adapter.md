# KDEXIT Phase 8 PancakeSwap Testnet Adapter Scaffold

This note documents the first PancakeSwap-compatible restricted sell adapter
scaffold for KDEXIT internal beta planning.

Status:

- EVM only
- BNB Chain / BSC testnet focused
- disabled by default
- no mainnet deployment
- no public execution
- no production router address defaults

## Components

New contracts and interfaces:

- `KdexitPancakeSwapRestrictedSellAdapter`
- `IPancakeSwapV2RouterLike`

The adapter conforms to `IKdexitRestrictedSellAdapter` and accepts only the
existing `RestrictedSellParams` shape.

## Router Assumptions

The adapter is scoped to a PancakeSwap-v2-compatible exact-input token sell:

- `swapExactTokensForTokens`
- two-token path only: `tokenIn -> tokenOut`
- recipient is `params.user`
- minimum output is `params.minAmountOut`
- deadline is `params.deadline`

It does not support:

- arbitrary calldata
- generic router execution
- multi-hop routing
- dynamic router selection
- native asset paths
- fee extraction
- treasury routing

## Disabled By Default

`testnetExecutionEnabled` starts as `false`.

An admin can call `setTestnetExecutionEnabled(true)` for a controlled testnet
experiment, but enabling the adapter does not bypass the existing model:

- the adapter must still be allowlisted by `KdexitRestrictedExecutionController`
- tokens must still be allowlisted by `KdexitRestrictedExecutionController`
- the restricted execution controller must still be unpaused
- a relayer must still pass the controller gate
- a valid EIP-712 user authorization is still expected before execution

## Chain Scope

The adapter is deployed with one immutable `SUPPORTED_CHAIN_ID`. It reverts if
called on any other chain.

For BSC testnet, deploy with the BSC testnet chain ID in the deployment
manifest. No mainnet chain ID or router address is hard-coded in the contract.

## Router Allowlisting

The router address is immutable and provided at construction. This is deliberate:
the adapter cannot be pointed at arbitrary routers after deployment.

Router choice must be handled in deployment review, and the adapter address
itself must still be allowlisted in the restricted execution controller.

## Token Allowlisting

The adapter does not maintain its own token allowlist. Token policy remains in
`KdexitRestrictedExecutionController`, where both `tokenIn` and `tokenOut` must
be allowlisted before preparation.

This keeps token policy centralized in the restricted execution layer.

## Slippage Requirement

`minAmountOut` is required and must be nonzero. The adapter passes it directly
to the PancakeSwap-compatible router. If output is below the minimum, the router
is expected to revert.

Future production work must add settlement tests against the exact router and
token set selected for beta.

## Token Approval Notes

This scaffold does not add an approval helper and does not create unlimited
allowances. That is intentional.

Before real testnet execution, KDEXIT still needs a reviewed allowance model
that answers:

- where `tokenIn` is held before router execution
- who grants the router allowance
- whether allowance is exact, temporary, or permit-based
- how allowance is revoked or bounded after execution
- how nonstandard tokens are excluded

Persistent unlimited approvals are not safe for production and are not added
here.

## Why Arbitrary Calldata Is Forbidden

Arbitrary calldata would let a relayer or misconfigured backend turn this
adapter into a general router caller. That would bypass the restricted adapter
model and make auditing the execution path much harder.

This scaffold only constructs the single exact-input router call from strict
parameters:

- `amountIn`
- `minAmountOut`
- `[tokenIn, tokenOut]`
- `user`
- `deadline`

No caller-provided bytes payload is accepted.

## Separation From Other Adapters

Adapter categories remain separate:

- local mock adapter: test-only simulation under `test/mocks`
- PancakeSwap testnet adapter: disabled-by-default scaffold under `src/adapters`
- future production adapter: separate reviewed implementation, not included here

The mock adapter tests remain in place and are not replaced by this scaffold.
