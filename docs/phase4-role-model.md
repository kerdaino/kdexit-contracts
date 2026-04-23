# KDEXIT Phase 4 Minimal Privileged Role Model

This document defines the conservative role model for KDEXIT Phase 4 contracts
and backend interaction.

It is implementation-facing and intentionally minimal. The goal is to create a
role boundary that is easy to enforce onchain, easy to reason about offchain,
and aligned with the current product boundary:

- end users authorize and own wallet context
- offchain services monitor, decide, and prepare work
- onchain contracts validate protocol permissions and pause state
- no backend integration receives more authority than it strictly needs

This document does not implement multisig infrastructure or real execution
logic. It defines the security model those future implementations should follow.

## Design Principles

The Phase 4 role model should preserve these principles:

- wallet-linking is never treated as execution permission
- observation and simulation are separated from execution authority
- emergency powers are narrower than admin powers
- execution authority is operational, revocable, and not equivalent to governance
- the smallest possible number of roles should exist in Phase 4

## Role Set

The minimal conservative role set is:

1. `END_USER`
2. `WATCHER_SIMULATOR`
3. `EXECUTION_RELAYER` (future-facing, likely unused at first)
4. `ADMIN`
5. `EMERGENCY_PAUSER`

Only `ADMIN` and `EMERGENCY_PAUSER` are privileged from day one.
`EXECUTION_RELAYER` is defined now so the system does not accidentally assign
its future powers to another role later.
`WATCHER_SIMULATOR` remains an offchain role model concept and is intentionally
not represented as an onchain write role in the current scaffold.

## Core Separation Rule

Wallet-linking, wallet enrollment, and product membership must remain completely
separate from execution authorization.

That means:

- a linked wallet is not an execution operator
- an enrolled user is not a privileged backend actor
- a watcher observing a user account is not allowed to execute on that account
- future relayer permission must come from explicit protocol authorization, not
  from wallet metadata or application-level linkage state

This separation is a direct requirement from the Phase 4 threat model and should
be enforced in contract interfaces, backend checks, and product documentation.

## Role Definitions

### `END_USER`

This is the user or user-controlled wallet context interacting with the KDEXIT
product.

Can do:

- link or unlink wallets at the product layer
- authorize product-level participation and wallet permissions offchain
- sign user-facing messages or transaction intents when the product requires it
- read public contract state and events

Must never be allowed to do:

- administer protocol roles
- pause or unpause the protocol
- register or enable strategies as a privileged actor
- submit backend-style execution requests solely because a wallet is linked
- inherit protocol execution permission from wallet-linking state

Implementation guidance:

- do not model `END_USER` as a privileged contract role in Phase 4
- if future user consent is represented onchain, keep it separate from operator authorization
- contract entrypoints should not assume `msg.sender` is safe to execute merely because it maps to a known user

### `WATCHER_SIMULATOR`

This is the offchain service that monitors conditions, simulates outcomes,
prepares candidate actions, and informs downstream systems.

Can do:

- read strategy registry state
- read pause state and role-related events
- monitor market conditions and evaluate product rules offchain
- prepare candidate execution payloads or proposals
- simulate or score candidate actions offchain
- deduplicate jobs and manage retries offchain

Must never be allowed to do:

- change onchain protocol configuration
- grant itself or others protocol roles
- bypass pause state
- submit privileged execution onchain unless it is separately and explicitly authorized as another role
- rely on wallet-linking as proof of execution permission

Implementation guidance:

- treat watcher access as read-heavy by default
- if the watcher later also becomes a relayer in some deployments, that must be an explicit dual assignment, not an implicit assumption
- do not give the watcher admin credentials for convenience

### `EXECUTION_RELAYER`

This is the future backend actor that may submit approved execution requests to
the execution controller once real execution logic exists.

In the current Phase 4 scaffold, this role is defined but should remain narrowly
scoped and may remain unassigned until needed.

Can do:

- submit execution requests to the execution controller once that path exists
- trigger only the specific execution entrypoints explicitly exposed by the protocol
- operate only while the protocol is unpaused

Must never be allowed to do:

- register, enable, or disable strategies unless separately granted admin powers, which should be avoided
- rotate roles
- pause or unpause the protocol
- bypass replay protection or execution validation
- derive permission from wallet-linking, watcher status, or product enrollment

Implementation guidance:

- keep `EXECUTION_RELAYER` separate from `WATCHER_SIMULATOR`, even if the same team operates both services
- the relayer should have no write permissions beyond execution submission
- role revocation should immediately disable relayer submissions
- if signature-based execution is added later, the relayer still should not be treated as a governance or admin actor

### `ADMIN`

This is the protocol governance and configuration authority.

Can do:

- assign and revoke protocol roles
- configure or update execution-critical protocol settings
- register strategies
- enable or disable strategies
- perform controlled recovery actions defined by protocol policy
- unpause the protocol if unpause authority remains with admin

Must never be allowed to do:

- be the default operational execution actor in normal system flow
- rely on hidden backend conventions instead of explicit onchain actions
- use wallet-linking or product enrollment state as a substitute for authorization checks
- bypass replay protection, pause checks, or other contract invariants

Implementation guidance:

- this role should be high-assurance and used rarely
- separate routine operations from governance wherever possible
- all admin actions should emit explicit events
- avoid assigning `ADMIN` to hot wallets or backend services

### `EMERGENCY_PAUSER`

This is the incident-response role used to stop damage quickly.

Can do:

- trigger emergency pause
- halt execution-moving paths immediately

Must never be allowed to do:

- unpause the system unless there is an explicitly documented exception, which is not recommended
- assign or revoke roles
- modify strategies or execution configuration
- submit or approve normal execution requests

Implementation guidance:

- this role should be easier to invoke than admin but much narrower
- pause should be available quickly during incident response
- unpause should remain more restricted than pause
- event emission for pause actions is mandatory for operational monitoring
- emergency pause should stop execution-moving paths but not read-only inspection

## Permission Matrix

This matrix describes the intended minimum permission set.

### `END_USER`

- Onchain write permissions: none by default in the privileged model
- Offchain permissions: product enrollment, wallet authorization, user approvals
- Sensitive notes: wallet-linking does not imply protocol role membership

### `WATCHER_SIMULATOR`

- Onchain write permissions: none by default
- Offchain permissions: monitoring, simulation, candidate preparation, dedupe, alerting
- Sensitive notes: can observe and prepare, but not execute unless separately assigned `EXECUTION_RELAYER`

### `EXECUTION_RELAYER`

- Onchain write permissions: execution submission only, once implemented
- Offchain permissions: delivery of already-approved execution requests
- Sensitive notes: no governance, no strategy administration, no pause control

### `ADMIN`

- Onchain write permissions: role management, strategy management, critical config, controlled unpause
- Offchain permissions: governance workflows and change management
- Sensitive notes: high-impact role, should not be used for routine automation

### `EMERGENCY_PAUSER`

- Onchain write permissions: pause only
- Offchain permissions: incident response initiation
- Sensitive notes: narrow, fast, and intentionally unable to restore normal operation alone

## Multisig Guidance

No multisig infrastructure should be implemented yet in this repository. Still,
the target custody model should be documented now so role assignments do not
drift into unsafe patterns.

Roles that should later become multisig-controlled:

- `ADMIN`
- the authority that can unpause, if unpause remains part of admin

Role that may later become multisig-controlled depending on operational model:

- `EMERGENCY_PAUSER`

Roles that generally should not require multisig because they are either
non-privileged or operationally narrow:

- `END_USER`
- `WATCHER_SIMULATOR`
- `EXECUTION_RELAYER`

Even where multisig is not required, those roles should still be revocable,
auditable, and isolated from admin credentials.

## Alignment With Phase 3 And Phase 4 Boundaries

This role model preserves the prior architecture boundary:

- users authorize and own wallet context
- watcher systems decide and prepare offchain
- relayers, if introduced, only deliver authorized execution
- contracts enforce protocol permissions and emergency state
- admins govern configuration but do not act as day-to-day operators

That keeps KDEXIT from collapsing into a single trusted backend role with both
decision power and execution power, which is exactly the failure mode the Phase 4
threat model is trying to avoid.

## Implementation Requirements

When translating this role model into contracts and backend policy, the system
should satisfy these requirements:

1. Wallet-linking state must never be queried as an execution authorization source.
2. Watcher and relayer permissions must be modeled as separate concerns.
3. Admin actions must emit explicit events.
4. Pause must gate every execution-moving path.
5. Emergency pauser must not be able to unpause by default.
6. Admin should not be used as the routine execution path.
7. Unassigned future roles should remain unassigned rather than collapsed into broader ones.

## Recommended Contract Mapping

The current scaffold can evolve toward this mapping:

- `KdexitStrategyRegistry`
  - writable by `ADMIN`
  - readable by all roles

- `KdexitExecutionController`
  - writable by `EXECUTION_RELAYER` only for execution submission, once implemented
  - pause-gated
  - readable by all roles

- pause control
  - callable by `EMERGENCY_PAUSER`
  - unpause callable by `ADMIN` or a dedicated future unpause authority

For the detailed paused-state behavior expected from those contracts, see
[Phase 4 Emergency Pause Model](./phase4-emergency-pause-model.md).

This keeps the contract surface small and avoids encoding offchain service logic
directly into the contracts.

## Recommended Tests

The first permission-focused tests should prove:

1. linked users cannot execute privileged actions
2. watcher-only actors cannot submit execution
3. relayer-only actors cannot administer strategies or roles
4. pauser-only actors can pause but cannot unpause or administer
5. admin can manage config but is not implicitly treated as a watcher or relayer in backend policy

## Open Decisions

These choices remain for later implementation, but they should not change the
role separation described above:

1. whether `ADMIN` is implemented as `Ownable`, `AccessControl`, or a custom role manager
2. whether unpause remains part of `ADMIN` or becomes a separate high-assurance role
3. whether `EXECUTION_RELAYER` is introduced immediately or only when live execution is added
