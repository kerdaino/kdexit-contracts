# KDEXIT Phase 4 Contract Architecture

This document describes the intended Phase 4 contract architecture for KDEXIT.
It is aligned with the current product direction and preserves the core Phase 3
boundary: decisioning and operational orchestration remain primarily offchain,
while onchain contracts provide controlled protocol state, authorization points,
and verifiable execution records.

## Phase 4 Design Goal

Phase 4 introduces a smart contract control plane without turning KDEXIT into a
fully onchain trading engine. The contracts should define:

- which strategies are recognized by the protocol
- which execution requests are allowed to enter the protocol path
- which privileged actors can manage configuration or stop the system
- which events and state transitions external services can trust

It should not yet implement:

- full swap routing
- treasury accounting
- relayer coordination logic
- upgradeability patterns

## Core Onchain Components

### `KdexitStrategyRegistry`

The strategy registry is the canonical onchain record of strategy identifiers and
their high-level configuration. In Phase 4 it should be responsible for:

- registering supported strategy IDs
- enabling or disabling strategies
- storing minimal metadata needed for validation and indexing
- emitting clear events when strategy configuration changes

The registry should not compute signals, prices, routes, or allocations.

### `KdexitExecutionController`

The execution controller is the protocol entrypoint for approved execution
requests. In Phase 4 it should be responsible for:

- accepting execution requests that match a registered strategy
- enforcing pause checks and authorization checks
- validating the minimum request shape before execution proceeds
- emitting execution lifecycle events that offchain systems can monitor
- serving as the future integration point for settlement and routing modules

The execution controller should not yet contain production swap logic, treasury
distribution, relayer markets, or complex batching.

## Execution Contract Responsibilities

The execution contract layer should stay narrow in Phase 4. Its role is to be a
trustable coordination boundary, not the full business engine.

Primary responsibilities:

- verify that a submitted action references a valid and enabled strategy
- verify that the caller has the required protocol permission
- reject actions when the system is paused
- persist or emit the minimum execution data needed for auditing
- expose deterministic events for downstream watcher and indexer services

Deliberately out of scope:

- signal generation
- market scanning
- quote selection
- route optimization
- wallet session management
- cross-service retries and job scheduling

## What Stays Offchain vs Onchain

### Onchain

Only the parts that benefit from protocol-level verification or shared state
should move onchain in Phase 4:

- strategy registration state
- enabled or disabled status for executable strategies
- execution acceptance and protocol event emission
- protocol role enforcement
- emergency pause state

### Offchain

The following responsibilities should remain offchain, consistent with the Phase
3 product boundary:

- market monitoring and signal detection
- deciding when a user should exit
- route discovery and quote comparison
- building calldata or execution payloads
- relayer or operator coordination
- retries, backoff, and operational scheduling
- user notifications and operator dashboards
- analytics and reporting pipelines

This split keeps the contracts small, easier to audit, and easier to evolve while
the product still depends on fast iteration in execution logic.

## Watcher Service Responsibilities

The watcher service remains the automation brain around the protocol. It should:

- monitor supported strategies and offchain market conditions
- determine when exit criteria have been met under the current product rules
- read onchain registry state to ensure a strategy is still active
- prepare candidate execution requests for the execution layer
- observe contract events for accepted, paused, or rejected actions
- trigger operational alerts when protocol state changes unexpectedly
- maintain replay protection and job deduplication at the service layer

The watcher should not receive broad onchain powers beyond the minimum role
needed to submit approved execution requests, if that role exists at all.

## Wallet Layer Responsibilities

The wallet layer continues to own the user-facing signing and custody boundary.
It should:

- manage user authorization and signing flows
- hold or coordinate the wallet permissions required for execution
- present execution intent, confirmations, and safety messaging to users
- enforce account-specific policy outside the contracts when needed
- map protocol actions back to the user account or managed wallet context

The wallet layer should remain the place where product-specific account logic
lives, rather than pushing that complexity into the execution controller.

## Privileged Roles

Phase 4 should keep privileged roles small and explicit. A practical initial
model is:

### `DEFAULT_ADMIN` or owner-equivalent

- sets initial trusted roles
- updates critical protocol configuration
- can rotate admin and operator permissions

This role should be held by a highly controlled multisig in production.

### `STRATEGY_ADMIN`

- registers new strategy IDs
- enables or disables strategies
- updates strategy metadata

This role should not be able to bypass pause protections or move funds by itself.

### `EXECUTION_OPERATOR`

- submits approved execution requests
- triggers execution entrypoints during normal operation

This role should be operationally constrained and easy to revoke.

### `PAUSER`

- triggers emergency pause immediately

This role exists to minimize response time during incidents.

### `UNPAUSER` or admin-only unpause

- lifts pause after investigation and approval

Unpause should be more restricted than pause.

## Emergency Pause Policy

Emergency pause should cover actions that could amplify harm during an incident.
At minimum, the following actions should require the system to be unpaused:

- submitting new execution requests
- invoking any execution path that could move user funds
- enabling new strategies
- modifying execution-critical configuration

Actions that may remain available while paused:

- reading state
- viewing execution history
- viewing registry configuration
- pausing additional dependent modules if later introduced

Actions that should usually stay restricted to admin even during pause:

- unpausing the system
- rotating privileged roles
- applying post-incident configuration changes

The scaffold-level execution controller follows this policy explicitly:

- `submitExecutionRequest(...)` is unavailable while paused
- receipt and registry read functions remain available while paused
- `pause()` is emergency-only
- `unpause()` is admin-only

For the full implementation-facing pause matrix, see
[Phase 4 Emergency Pause Model](./phase4-emergency-pause-model.md).

## Alignment With Phase 3 Boundaries

The key carryover from Phase 3 is that KDEXIT is still an offchain-orchestrated
product with onchain enforcement, not a fully autonomous onchain strategy system.

Phase 3 boundary retained in Phase 4:

- offchain systems decide and prepare
- wallet systems authorize and present to users
- onchain contracts validate, record, and gate execution

That means Phase 4 should improve trust, auditability, and operational safety
without prematurely hard-coding product logic that is still evolving.

## Recommended Next Documentation

After this architecture baseline, the next useful docs would be:

1. role-permission matrix
2. execution request schema and event model
3. pause and incident response runbook
4. strategy lifecycle spec from registration to deprecation
