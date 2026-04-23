# KDEXIT Phase 4 Threat Model

This document captures the practical security threats for KDEXIT Phase 4 and the
implementation decisions they should drive.

It is intentionally scoped to the current product boundary:

- offchain services still decide and prepare execution
- wallets still own user authorization and account context
- onchain contracts enforce protocol permissions, pause state, and execution entry

The goal is not to eliminate all operational risk in Phase 4. The goal is to
make sure the contract architecture does not silently convert offchain mistakes
or compromised operators into unlimited protocol damage.

## Security Objectives

Phase 4 contracts should preserve the following invariants:

- no one can execute protocol actions without explicit protocol permission
- wallet linkage alone does not authorize execution
- a paused system cannot continue normal execution flows
- duplicate or replayed execution requests cannot be accepted as fresh work
- privileged roles are narrow, revocable, and observable
- token approvals are bounded to the minimum required scope
- retries and failure handling cannot be abused to create repeated execution

## Trust Boundaries

The most important trust boundaries in Phase 4 are:

### Offchain watcher and automation layer

Trusted to monitor conditions and prepare candidate actions, but not trusted to
have unlimited authority over user funds or protocol configuration.

### Wallet layer

Trusted to manage user consent, signing, and wallet-session relationships, but
not treated as equivalent to blanket execution permission.

### Onchain execution contracts

Trusted to enforce the minimum non-bypassable checks:

- caller authorization
- strategy validity
- pause state
- replay protection
- bounded execution semantics

### Admin and emergency operators

Trusted for controlled governance and incident response, but assumed to be
high-impact if compromised or misused.

## Threats And Controls

### 1. Unauthorized Execution

#### Threat

An attacker, compromised operator, or incorrect integration attempts to submit an
execution request that the protocol should not accept.

Examples:

- a random EOA calls the execution controller directly
- a previously trusted operator key is not revoked after compromise
- an internal service submits requests for disabled or unknown strategies
- a wallet-linked address is mistakenly treated as execution-authorized

#### Impact

- unauthorized movement of user funds once execution paths are implemented
- false execution records
- operational confusion and user harm

#### Required Controls

- require a dedicated execution role such as `EXECUTION_OPERATOR`
- reject requests for unregistered or disabled strategy IDs
- separate strategy administration from execution authority
- emit explicit events for accepted and rejected execution attempts where useful
- make authorization checks live onchain rather than depending only on offchain policy

#### Implementation Decisions

- `KdexitExecutionController.submitExecution` must check caller role onchain
- do not infer execution permission from wallet linkage, registry presence, or user enrollment
- support rapid role revocation for compromised operators
- keep the execution role operationally narrow and easy to rotate

#### Test Expectations

- unauthorized callers revert
- authorized callers revert for disabled strategies
- revoked operators lose access immediately

### 2. Overbroad Token Approvals

#### Threat

The protocol, operator, or integrated execution path obtains broader token
approval than is required for a specific action.

Examples:

- unlimited ERC-20 approval to an execution contract or routing target
- approvals granted before a feature is production-ready and then forgotten
- one approval reused across unrelated execution contexts

#### Impact

- fund loss if an approved target is compromised
- hidden escalation from a limited execution bug into full token drain risk

#### Required Controls

- avoid persistent unlimited approvals in Phase 4 where possible
- tie approvals to explicit execution flows, amounts, and targets
- approve only the contract that must spend, not arbitrary downstream actors
- revoke or reduce approvals after use when the design supports it

#### Implementation Decisions

- treat token approval policy as part of the threat model, not a later integration detail
- if temporary approvals are needed, the exact spender and amount must be deterministic
- do not approve strategy registry, watcher, or admin addresses to move tokens
- if wallet-level approvals are needed, document that they are not equivalent to protocol execution rights

#### Test Expectations

- no contract in Phase 4 should require unlimited default approvals just to register or queue execution
- approval scope should be inspectable in tests and deployment review

### 3. Admin Abuse

#### Threat

A privileged admin uses their authority maliciously or carelessly, or the admin
key is compromised.

Examples:

- enabling a malicious strategy target
- assigning execution rights to an unsafe operator
- unpausing too early after an incident
- changing execution-critical configuration without review

#### Impact

- protocol compromise without any low-level contract bug
- silent expansion of blast radius
- loss of user trust and incident containment failure

#### Required Controls

- minimize admin powers and split them by function
- use separate roles for strategy management, execution, pause, and unpause
- prefer multisig control for top-level admin in production
- emit events for all privileged configuration changes
- make dangerous changes reviewable and reversible

#### Implementation Decisions

- `DEFAULT_ADMIN` should not be the routine execution role
- `PAUSER` should be easier to use than `UNPAUSER`
- strategy enablement and operator assignment should both be explicit onchain actions
- maintain an implementation checklist requiring review of every function reachable by admin roles

#### Test Expectations

- admin-only functions reject non-admin callers
- role boundaries are enforced exactly as documented
- pause and unpause privileges are not accidentally merged unless intentionally designed

### 4. Replay Or Duplicate Execution Attempts

#### Threat

A valid execution request is submitted more than once, either maliciously or due
to retries, race conditions, or duplicated offchain jobs.

Examples:

- the watcher retries after a timeout but the first transaction later lands
- the same signed request is relayed twice
- an operator intentionally resubmits an old execution payload

#### Impact

- duplicated exits
- repeated state transitions
- repeated downstream token movement once execution is implemented

#### Required Controls

- include a unique execution identifier or nonce in each request
- track request consumption onchain
- reject already-consumed execution IDs
- bind any signed payload to chain ID, contract address, and expiry
- require deterministic replay protection independent of watcher correctness

#### Implementation Decisions

- add `executionId` or per-account nonce semantics to `KdexitTypes.ExecutionRequest`
- mark an execution request consumed before any external effect if external calls are later introduced
- distinguish between "failed but consumable" and "retryable" states explicitly
- do not rely only on transaction hashes for deduplication

#### Test Expectations

- exact duplicate requests revert
- expired requests revert
- requests signed or created for another chain or contract revert if signature-based flows are later added

### 5. Paused Or Emergency State Misuse

#### Threat

The pause mechanism is bypassed, used inconsistently, or abused to lock the
system unnecessarily.

Examples:

- execution entrypoints forget to check pause state
- an operator can modify configuration while paused in a way that worsens an incident
- a pauser freezes the protocol maliciously or accidentally
- unpause is performed by the same low-trust actor who initiated pause

#### Impact

- incident blast radius grows because pause is ineffective
- protocol stuck in an unusable state
- governance confusion during recovery

#### Required Controls

- all execution-moving entrypoints must be pause-gated
- execution-critical config changes should also be pause-aware
- pause and unpause powers should be separated or more tightly constrained on unpause
- pause state changes must emit events with actor identity

#### Implementation Decisions

- treat pause checks as a top-level invariant for every state-changing execution path
- decide explicitly which admin actions remain allowed while paused
- define whether strategy disablement is allowed during pause; in most cases it should be
- restrict unpause to higher-assurance governance, ideally multisig plus incident review

#### Test Expectations

- paused contracts reject execution submission
- allowed paused-state admin actions continue to work only where intended
- unpause cannot be called by a plain operator or pauser unless deliberately authorized

For the scaffold-specific allowed and blocked actions during incident
containment, see [Phase 4 Emergency Pause Model](./phase4-emergency-pause-model.md).

### 6. Wallet Linking Is Not Execution Permission

#### Threat

The system confuses wallet linkage, user enrollment, or session association with
permission to trigger execution.

Examples:

- a linked wallet is allowed to submit execution directly without operator authorization
- an offchain service assumes that because a wallet opted into KDEXIT, any linked actor may execute
- a wallet-management integration exposes more authority than the protocol intended

#### Impact

- accidental privilege escalation through product integration
- hard-to-detect gaps between wallet UX and contract security assumptions

#### Required Controls

- explicitly model wallet linkage and execution authorization as different states
- require protocol permission in addition to any wallet relationship
- document execution authority at the contract boundary, not only in product docs
- ensure frontends and operators surface the distinction clearly

#### Implementation Decisions

- do not use wallet linkage as an allowlist key for execution entrypoints
- if user-specific consent is later represented onchain, it should still not replace protocol role checks by itself
- maintain a separate schema for wallet association versus executable authorization

#### Test Expectations

- linked or enrolled wallets without operator permission cannot execute
- execution authorization logic does not accidentally read wallet-linking state as a grant

### 7. Failure And Retry Abuse

#### Threat

Failures, retries, and partial operational recovery are abused to repeat or force
execution behavior that should happen at most once.

Examples:

- repeated retries after soft failures cause multiple accepted executions
- an operator intentionally toggles between failure paths to bypass dedupe
- a failed downstream step leaves the system in an ambiguous state that can be exploited

#### Impact

- duplicate execution
- denial of service through job amplification
- inconsistent onchain versus offchain execution state

#### Required Controls

- define whether failures are terminal or retryable before implementation
- record execution lifecycle states in a way the watcher can interpret deterministically
- make retries depend on an explicit new request ID or new nonce when appropriate
- limit how much the contract accepts as the same logical attempt

#### Implementation Decisions

- choose a simple lifecycle such as `Pending -> Consumed` for Phase 4 unless richer semantics are necessary
- avoid ambiguous partial-state transitions in the initial contract design
- if a request is accepted onchain, offchain systems should treat that as authoritative for dedupe
- retries should usually create a new execution ID rather than resubmitting the same logical request blindly

#### Test Expectations

- duplicate retries revert once a request is consumed
- failure-path events are unambiguous enough for the watcher to stop or regenerate work correctly

## Cross-Cutting Design Decisions

The threats above point to a few implementation choices that should be decided
early because they affect nearly every function:

### 1. Explicit Role Model

Use separate roles for:

- admin
- strategy management
- execution operator
- pauser
- unpauser

Do not compress these into a single convenience role in production.

### 2. Replay-Protected Execution Requests

Every accepted execution request should include enough context to make replay
impossible across:

- repeated submissions
- different chains
- different contract deployments
- different expiry windows

### 3. Minimal Approval Surface

Do not grant permissions or token approvals to components that do not directly
need them. Keep approval scope bounded by:

- amount
- spender
- lifetime
- execution context

### 4. Pause As A Real Safety Control

Pause should not be decorative. It must be enforced consistently on every
execution-critical write path and supported by monitoring, alerts, and tests.

### 5. Observable Security Events

Security-critical transitions should emit events for:

- role grants and revocations
- strategy enable and disable
- pause and unpause
- execution accepted or rejected
- replay rejection or duplicate detection if instrumented

Observability is part of the control model because the watcher and operations
stack depend on these events for fast incident response.

## Implementation Checklist

When Phase 4 contract work starts, the implementation should satisfy the
following checklist:

1. Execution entrypoints require an explicit protocol role.
2. Strategy existence and enabled state are checked onchain.
3. Execution requests include replay-protection data.
4. Consumed requests cannot be accepted again.
5. Pause blocks every execution-moving path.
6. Unpause is more restricted than pause.
7. Wallet linkage is not used as execution authorization.
8. No unnecessary unlimited token approvals are introduced.
9. Every privileged action emits a reviewable event.
10. Tests cover role abuse, replay, pause behavior, and retry edge cases.

## Recommended Test Categories

The first security-focused tests for this repo should include:

### Unit Tests

- role-gated execution submission
- disabled strategy rejection
- duplicate execution rejection
- pause and unpause permission checks
- wallet-linking state not affecting execution authorization

### Integration Tests

- watcher submits a valid execution request once and only once
- revoked operator can no longer submit
- paused system rejects operational flows while preserving read access

### Invariant Tests

- unauthorized callers can never consume an execution request
- consumed execution IDs are never accepted twice
- paused state prevents all execution-moving calls

## Open Decisions To Resolve Before Production Logic

These items should be settled before implementing real asset movement:

1. exact execution request schema, including nonce or `executionId`
2. final role model and whether AccessControl or custom auth is preferred
3. whether retries reuse a logical request ID or always mint a new one
4. how token approval scope is bounded for each execution path
5. which admin actions remain available while paused
