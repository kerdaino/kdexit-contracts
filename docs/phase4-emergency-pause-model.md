# KDEXIT Phase 4 Emergency Pause Model

This document defines the emergency pause model for the KDEXIT Phase 4 contract
scaffold. It is intended to be practical for implementation, review, and test
planning.

The goal is simple: when an incident is suspected, KDEXIT must be able to stop
new execution-path activity immediately without hiding state, blocking audit
visibility, or granting broad recovery powers to low-trust operators.

## Design Goal

Emergency pause is a containment control, not a recovery shortcut.

During emergency conditions, the protocol should:

- stop all execution-moving writes
- preserve read access for monitoring, reconciliation, and user visibility
- keep recovery authority narrower than normal admin authority where practical
- avoid introducing hidden bypass paths for operators, watchers, or linked wallets

## Current Contract Mapping

The Phase 4 scaffold currently expresses this model in
`KdexitExecutionController` as follows:

- `pause()` is callable only by `EMERGENCY_PAUSER_ROLE`
- `unpause()` is callable only by `ADMIN_ROLE`
- `submitExecutionRequest(...)` is blocked by `whenNotPaused`
- read helpers such as `getExecutionReceipt(...)`, `isExecutionSubmitted(...)`,
  `isEmergencyPaused()`, and `canSubmitExecutionRequests()` remain callable

This is intentionally conservative. The scaffold treats pause as a hard stop on
execution intake, while leaving indexing and operational visibility available.

## What Must Stop When Paused

The following actions should not be callable during emergency pause:

- submitting new execution requests
- invoking any future function that can move user funds
- invoking any future settlement, routing, relay, or reconciliation write path
  that advances execution state
- invoking any future batch-processing path that could accept or trigger work

Implementation rule:

- every state-changing function on the execution path should be explicitly
  reviewed and either gated by pause or intentionally documented as safe during
  pause

For the current scaffold, this means:

- `submitExecutionRequest(...)` must remain unavailable while paused

## What Must Remain Readable When Paused

Emergency pause must not blind operators, users, or backend systems. The
following must stay readable:

- strategy registry state
- execution receipt history
- execution submission status checks
- current pause status
- historical events, including pause and unpause events

For the current scaffold, the following remain callable during pause:

- `getExecutionReceipt(...)`
- `isExecutionSubmitted(...)`
- `isEmergencyPaused()`
- `canSubmitExecutionRequests()`
- `getStrategy(...)`
- `isStrategyEnabled(...)`

This allows watchers, dashboards, reconciliation tooling, and users to inspect
state while the protocol is contained.

## What Should Not Be Callable During Emergency Conditions

Emergency conditions should not become a pretext for broad privileged activity.
The following actions should not be callable by routine operators during a pause:

- normal execution submission
- watcher-initiated onchain writes
- relayer-driven retries
- any user-triggered execution shortcut
- any wallet-linking-based authorization flow

The following actions should also remain unavailable to the emergency pauser:

- unpausing the protocol
- rotating roles
- enabling new strategies
- changing execution-critical configuration
- submitting or approving execution requests

This preserves the intended separation:

- emergency pauser can stop the system fast
- admin can review and recover deliberately
- watcher and relayer services cannot bypass the emergency state

## Allowed Actions While Paused

The minimum safe set of allowed actions during pause is:

- read-only contract calls
- event indexing and reconciliation reads
- emergency pause itself, if already-active pause needs to be reaffirmed through operations
- controlled admin recovery actions that are explicitly documented and do not
  advance execution flow

In the current scaffold, the only state-changing action intentionally allowed
while paused is:

- `unpause()` by `ADMIN_ROLE`

Future design note:

- if strategy disablement during pause is later needed for containment, it should
  be added explicitly and documented as an allowed recovery action, not assumed
  implicitly

## Role Expectations During Pause

### `END_USER`

- can keep reading contract state
- must not gain any emergency execution path

### `WATCHER_SIMULATOR`

- can keep observing state and indexing events
- can continue offchain analysis and incident reporting
- must not submit execution requests or retries while paused

### `EXECUTION_RELAYER`

- can monitor pause state and halt operational pipelines
- must not submit new requests while paused

### `EMERGENCY_PAUSER`

- can activate containment fast
- must not restore normal operations alone

### `ADMIN`

- can review the incident and decide when recovery is acceptable
- can unpause once the protocol is ready to resume
- should not use pause recovery as a bypass for normal security checks

## Wallet-Linking Separation

Emergency conditions do not change the wallet-linking rule.

Even while paused or during recovery:

- linked wallets are not execution operators
- product enrollment is not execution authorization
- watcher or relayer systems must not infer emergency powers from wallet context

This remains a hard boundary from the Phase 4 threat model.

## Implementation Checklist

Any future contract extension should be checked against this pause model:

1. Does the function move execution state forward?
2. Does the function affect funds directly or indirectly?
3. Does the function modify execution-critical config?
4. Should this function be callable during incident containment?
5. If yes, is that exception documented explicitly?

If the answer is uncertain, the function should default to not callable while
paused until a narrower rule is documented.

## Recommended Tests

The first pause-focused tests should prove:

1. `submitExecutionRequest(...)` reverts while paused
2. `getExecutionReceipt(...)` continues to work while paused
3. `isExecutionSubmitted(...)` continues to work while paused
4. only `EMERGENCY_PAUSER_ROLE` can call `pause()`
5. only `ADMIN_ROLE` can call `unpause()`
6. pause does not create any alternate execution path for users, watchers, or relayers

## Future Extension Rules

When more execution logic is added later:

- all execution-moving functions should be pause-gated by default
- any exception must be narrowly scoped and explicitly documented
- pause should remain a protocol-wide signal that operators and backends can
  depend on without ambiguity
