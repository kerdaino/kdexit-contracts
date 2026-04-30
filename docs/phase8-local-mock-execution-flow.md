# KDEXIT Phase 8 Local Mock Execution Flow

This note documents the local mock execution lifecycle used for internal beta
testing. It is test-only scaffolding. It does not integrate PancakeSwap,
Uniswap, any production router, or any production token approval flow.

## Test-Only Components

Local mocks:

- `test/mocks/MockERC20.sol`
- `test/mocks/MockRestrictedSellAdapter.sol`

Integration tests:

- `test/integration/KdexitLocalMockExecutionFlow.t.sol`

The mock ERC-20 exists only to provide concrete token addresses and balances in
local tests. The mock restricted sell adapter does not transfer tokens, set
allowances, custody assets, or call external routers.

## Simulated Lifecycle

The local test flow exercises the intended future pipeline:

1. User signs an EIP-712 `ExecutionAuthorization`.
2. Relayer consumes the authorization through `KdexitExecutionAuthorization`.
3. Relayer prepares a restricted sell request through
   `KdexitRestrictedExecutionController`.
4. Relayer submits a scaffold execution request through
   `KdexitExecutionController`.
5. Test invokes `MockRestrictedSellAdapter.executeRestrictedSell(...)`.
6. The mock adapter emits a local success or failure event.
7. Relayer records simulated completion or failure on
   `KdexitExecutionController`.

This validates the pipeline shape:

- signature verification
- nonce/replay protection
- adapter and token allowlists
- relayer gating
- pause gating
- mock adapter result handling
- scaffold receipt completion/failure recording

## What The Mock Adapter Does

`MockRestrictedSellAdapter` accepts `RestrictedSellParams`, then:

- emits `MockRestrictedSellSucceeded` and returns a configured fake output
  amount when configured to succeed
- emits `MockRestrictedSellFailed` and returns zero when configured to fail or
  when the fake output is below `minAmountOut`

It does not:

- transfer `tokenIn`
- mint `tokenOut`
- call a DEX
- call a router
- decode arbitrary calldata
- hold funds
- charge fees

## Settlement And Result Recording

Settlement is simulated by recording hashes in the existing execution receipt:

- success records `resultHash`
- failure records `failureCode` and `failureContextHash`

These hashes are local reconciliation artifacts only. They are not proof of real
asset settlement.

## Why This Exists

The local mock flow lets KDEXIT test the operational lifecycle before real
adapters exist:

- can the user authorization be consumed once?
- can a restricted sell be prepared only through allowlisted assets and adapter?
- can the mock adapter produce success and failure signals?
- can the scaffold execution controller record terminal outcomes?
- do pause and relayer restrictions stop the pipeline where expected?

## Still Not Implemented

This phase still does not implement:

- PancakeSwap integration
- Uniswap integration
- production ERC-20 approvals
- mainnet or testnet deployment
- generic swap execution
- multi-hop routing
- arbitrary token movement
- custody
- fee extraction
- real settlement verification

The mock flow is a lab bench for the execution pipeline, not a production
execution path.
