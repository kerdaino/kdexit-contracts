# KDEXIT Phase 4 Event Model

This document defines the scaffold-level event model for KDEXIT contracts so
future backend reconciliation and indexing can be built against a stable shape
before live execution logic exists.

The intent is to make onchain events the canonical timeline for:

- strategy authorization changes
- execution request intake
- execution terminal outcomes
- emergency pause state changes

The contracts still do not move funds or perform real routing. These events are
for coordination and reconciliation only.

## Design Goals

The Phase 4 event model should:

- use a stable `executionId` as the primary correlation key
- allow backend systems to reconstruct the full lifecycle of a request
- keep payload-heavy or sensitive offchain details hashed rather than emitted raw
- distinguish submitted, completed, and failed terminal states
- make pause transitions explicit and easy to index

## Canonical Event Streams

### Strategy Registry Events

Contract:

- `KdexitStrategyRegistry`

Canonical event:

- `StrategyAuthorizationRegistered`

Purpose:

- tells the backend which strategy IDs are recognized onchain
- provides the enabled flag used to decide whether requests are admissible
- provides a metadata hash so the backend can compare offchain config versions

Fields:

- `strategyId`: primary strategy key
- `target`: strategy target or placeholder integration address
- `actor`: admin who registered or updated authorization
- `enabled`: whether the strategy is currently executable
- `metadataHash`: hash of strategy metadata bytes
- `configuredAt`: timestamp of the authorization update

Backend use:

- index the latest authorization state per `strategyId`
- detect config drift between backend strategy definitions and onchain state
- invalidate pending offchain jobs when a strategy is disabled

## Execution Lifecycle Events

Contract:

- `KdexitExecutionController`

The execution lifecycle is keyed by `executionId`.

### `ExecutionRequestSubmitted`

Purpose:

- records that a relayer-authorized execution request was accepted into the
  contract scaffold
- creates the first canonical onchain lifecycle event for the request

Fields:

- `executionId`: primary reconciliation key
- `strategyId`: strategy under which the request was admitted
- `account`: user or account context tied to the request
- `submitter`: relayer address that submitted the request
- `amountIn`: planned input amount from the offchain request
- `payloadHash`: hash of the offchain execution payload
- `requestedAt`: offchain request creation time provided in the request
- `submittedAt`: onchain acceptance timestamp

Backend use:

- map an offchain job to its onchain acknowledgement
- deduplicate retries using `executionId`
- compare `requestedAt` and `submittedAt` for latency and retry analysis

### `ExecutionCompleted`

Purpose:

- records that a submitted execution request reached a scaffold-level terminal
  success state

Important note:

- this does not prove asset movement in the current scaffold
- it only marks the request as completed for future reconciliation and event
  consumption

Fields:

- `executionId`: lifecycle key
- `strategyId`: strategy associated with the request
- `account`: account associated with the request
- `finalizer`: relayer address that recorded completion
- `resultHash`: hash of the offchain execution result or settlement details
- `finalizedAt`: timestamp of completion recording

Backend use:

- mark the request terminal and successful
- resolve the corresponding offchain job
- fetch detailed result data using `resultHash` as the reconciliation pointer

### `ExecutionFailed`

Purpose:

- records that a submitted execution request reached a scaffold-level terminal
  failure state

Important note:

- this does not implement retry logic or recovery semantics
- it only marks the request failed and provides backend-consumable metadata

Fields:

- `executionId`: lifecycle key
- `strategyId`: strategy associated with the request
- `account`: account associated with the request
- `finalizer`: relayer address that recorded failure
- `failureCode`: compact machine-readable failure classification
- `failureContextHash`: hash of richer offchain failure details
- `finalizedAt`: timestamp of failure recording

Backend use:

- mark the request terminal and failed
- drive alerting, retry analysis, and incident dashboards
- reconcile richer error details through the hashed offchain record

## Pause Events

Contract:

- `KdexitExecutionController`

Canonical event:

- `EmergencyPauseStateChanged`

Additional OpenZeppelin events:

- `Paused(address account)`
- `Unpaused(address account)`

Purpose:

- make the protocol pause lifecycle explicit for backend consumers
- give indexers a contract-specific event to consume without depending only on
  generic framework events

Fields:

- `isPaused`: resulting pause state
- `actor`: address that triggered the state change
- `changedAt`: timestamp of the change

Backend use:

- stop relayer pipelines immediately when `isPaused == true`
- resume normal submission only after an `isPaused == false` event
- annotate execution timelines with incident boundaries

## Receipt And Event Relationship

The scaffold stores an `ExecutionReceipt` for each `executionId` and emits events
for the same lifecycle transitions.

That means backend systems can:

- use events as the streaming source of truth
- use receipts as point-in-time verification for reconciliation or replay repair

The intended mapping is:

- `None` -> no accepted request exists
- `Submitted` -> `ExecutionRequestSubmitted` seen
- `Completed` -> `ExecutionCompleted` seen
- `Failed` -> `ExecutionFailed` seen

## Suggested Backend Consumption Rules

The backend should treat:

1. `executionId` as the canonical deduplication key
2. the first accepted `ExecutionRequestSubmitted` as the onchain start of a request
3. `ExecutionCompleted` and `ExecutionFailed` as terminal states
4. pause events as operational gates that stop new submission work
5. `payloadHash`, `resultHash`, and `failureContextHash` as reconciliation
   pointers into richer offchain records

The backend should not treat:

- wallet-linking as an execution authorization signal
- watcher output as equivalent to onchain acceptance
- a terminal event as proof of real settlement until live execution logic exists

## Scaffold-Only Functions Backing The Event Model

The current controller exposes scaffold-only functions for lifecycle recording:

- `submitExecutionRequest(...)`
- `recordExecutionCompletion(...)`
- `recordExecutionFailure(...)`

These functions exist only to define the future lifecycle shape. They do not:

- transfer tokens
- approve spenders
- call routers
- call arbitrary external contracts
- reconcile treasury balances

## Recommended Indexes And Queries

Backend systems should index by:

- `executionId`
- `strategyId`
- `account`
- `submitter` or `finalizer`
- pause state transition time

Useful materialized views later:

- latest strategy authorization per `strategyId`
- execution lifecycle by `executionId`
- terminal failures grouped by `failureCode`
- request latency from `requestedAt` to `submittedAt`
- pause windows affecting execution activity

## Recommended Tests

The first event-model tests should prove:

1. strategy registration emits `StrategyAuthorizationRegistered`
2. execution submission emits `ExecutionRequestSubmitted`
3. completion recording emits `ExecutionCompleted`
4. failure recording emits `ExecutionFailed`
5. pause and unpause emit `EmergencyPauseStateChanged`
6. once terminal, an execution cannot be terminalized again through another event
