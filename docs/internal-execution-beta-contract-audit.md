# KDEXIT Current Contracts Implementation And Capability Audit

This audit inventories the current `kdexit-contracts` workspace as of the
Phase 6 operational-readiness stage. Its goal is to prepare practical planning
for a tightly controlled internal execution beta without overstating what the
contracts can do today.

The current system is a Foundry-first smart contract scaffold with meaningful
access control, pause control, strategy registry state, execution request
recording, lifecycle events, and receipt storage. It is not yet a live execution
system. It does not move assets, validate user-signed execution intent, manage
token approvals, perform swaps, settle results, or enforce beta participant
authorization.

## 1. Everything Currently Implemented And Working

The workspace currently implements:

- a Foundry project configured for Solidity `0.8.24`
- OpenZeppelin imports through `@openzeppelin/=lib/openzeppelin-contracts/`
- `KdexitStrategyRegistry`
- `KdexitExecutionController`
- `IKdexitStrategyRegistry`
- `IKdexitExecutionController`
- `KdexitRoles`
- `KdexitTypes`
- unit tests for the registry and execution controller
- documentation for architecture, roles, threat model, pause model, event model,
  Phase 5 alignment, and Phase 6 operational readiness

Implemented registry capabilities:

- deploys with a nonzero `defaultAdmin`
- grants `DEFAULT_ADMIN_ROLE` to the constructor admin
- grants KDEXIT `ADMIN_ROLE` to the constructor admin
- stores strategy configuration by `strategyId`
- supports updating strategy `target`, `enabled`, and `metadata`
- exposes `getStrategy(strategyId)`
- exposes `isStrategyEnabled(strategyId)`
- emits `StrategyAuthorizationRegistered` on strategy configuration writes
- hashes metadata as `keccak256(config.metadata)` in the emitted event
- restricts `setStrategy(...)` to `ADMIN_ROLE`

Implemented execution-controller capabilities:

- deploys with a nonzero default admin
- deploys with a nonzero strategy registry address
- stores an immutable `STRATEGY_REGISTRY` reference
- grants `DEFAULT_ADMIN_ROLE` and `ADMIN_ROLE` to the constructor admin
- grants `EMERGENCY_PAUSER_ROLE` when a nonzero pauser is supplied
- accepts scaffold-level execution requests from `EXECUTION_RELAYER_ROLE`
- rejects execution requests while paused
- rejects zero execution IDs
- rejects zero account addresses
- rejects duplicate execution IDs after initial submission
- rejects requests for strategies that are not enabled in the registry
- stores an `ExecutionReceipt` for each accepted `executionId`
- emits `ExecutionRequestSubmitted` when a request is accepted
- records scaffold-level completion from an authorized execution relayer
- records scaffold-level failure from an authorized execution relayer
- rejects terminal lifecycle recording for unknown execution IDs
- rejects lifecycle finalization unless the receipt is still `Submitted`
- emits `ExecutionCompleted` and `ExecutionFailed`
- supports emergency pause by `EMERGENCY_PAUSER_ROLE`
- supports unpause by `ADMIN_ROLE`
- emits `EmergencyPauseStateChanged` in addition to OpenZeppelin pause events
- exposes `getExecutionReceipt(executionId)`
- exposes `isExecutionSubmitted(executionId)`
- exposes `isEmergencyPaused()`
- exposes `canSubmitExecutionRequests()`

The current lifecycle state machine is:

1. `None`
2. `Submitted`
3. `Completed` or `Failed`

`Completed` and `Failed` are terminal scaffold states. They currently mean only
that a relayer recorded a terminal result. They do not prove asset movement or
settlement.

## 2. Everything Scaffold-Only

The following pieces are real code but scaffold-only in meaning:

- `submitExecutionRequest(...)`
- `recordExecutionCompletion(...)`
- `recordExecutionFailure(...)`
- `ExecutionReceipt`
- `ExecutionRequestSubmitted`
- `ExecutionCompleted`
- `ExecutionFailed`
- `payloadHash`
- `resultHash`
- `failureCode`
- `failureContextHash`
- strategy `target`
- strategy `metadata`

The controller records accepted requests and terminal outcomes, but it does not
execute the payload represented by `payloadHash`. The registry records strategy
configuration, but it does not verify target code, route safety, token lists,
chain support, price bounds, slippage bounds, or settlement behavior.

The current scaffold is useful for integration planning because it gives backend
systems stable keys and events:

- `executionId` for deduplication and lifecycle correlation
- `strategyId` for strategy gating and operational grouping
- `account` for user or wallet context
- hashes for offchain payload, result, and failure records
- pause state for relayer gating
- role events for operational monitoring

It is not yet sufficient for live execution, even in a beta, because the
critical authorization and asset-safety controls are still absent.

## 3. Everything Intentionally Not Implemented

The workspace intentionally does not implement:

- token custody
- token transfers
- ERC-20 approval flows
- swap routing
- DEX or aggregator integrations
- treasury accounting
- fee accounting
- settlement verification
- slippage checks
- price-oracle checks
- deadline or expiry checks
- user signature validation
- EIP-712 typed execution authorization
- per-account nonce management
- relayer allowlists beyond OpenZeppelin role membership
- relayer rate limits
- chain-specific execution policy
- beta participant allowlists
- strategy target validation
- strategy-specific parameter validation
- calldata execution
- batch execution
- cross-chain execution
- upgradeability
- deployment scripts
- production deployment manifests
- multisig setup
- integration tests
- invariant tests
- formal verification

This is deliberate and healthy for the current phase. The contracts establish
the control-plane boundary before adding asset-moving logic.

## 4. Current Contract Architecture

The architecture has two core contracts:

- `KdexitStrategyRegistry`
- `KdexitExecutionController`

The registry is the onchain source of truth for whether a strategy ID is known
and enabled. The execution controller is the onchain source of truth for whether
an execution request was accepted into the scaffold lifecycle and how that
request terminated.

Supporting modules:

- `KdexitRoles` defines shared role identifiers.
- `KdexitTypes` defines strategy, request, receipt, and status types.
- `IKdexitStrategyRegistry` defines the registry event and view/write surface.
- `IKdexitExecutionController` defines the execution lifecycle events and
  controller surface.

External dependency:

- OpenZeppelin `AccessControl`
- OpenZeppelin `Pausable`

Architecture boundaries:

- offchain services decide, prepare, simulate, and reconcile
- wallets or product systems manage user authorization and account context
- contracts enforce role checks, pause checks, strategy-enabled checks, duplicate
  request protection, lifecycle state, and canonical events

The current architecture is intentionally a control plane, not an onchain
trading engine.

## 5. Current Registry And Execution-Controller Responsibilities

`KdexitStrategyRegistry` currently owns:

- strategy ID registration through `setStrategy(...)`
- strategy enabled/disabled state
- strategy target address storage
- strategy metadata storage
- strategy metadata hash event emission
- read access for strategy configuration
- read access for strategy enabled checks

The registry does not own:

- strategy validation beyond storage
- target contract interface checks
- target code existence checks
- chain support checks
- token support checks
- execution authorization
- execution result validation

`KdexitExecutionController` currently owns:

- role-gated execution request intake
- pause-gated execution request intake
- strategy-enabled gate through `STRATEGY_REGISTRY.isStrategyEnabled(...)`
- duplicate `executionId` rejection
- receipt creation
- completion recording
- failure recording
- receipt reads
- pause and unpause state
- lifecycle events

The controller does not own:

- user permission checks
- user signatures
- token approvals
- fund movement
- swap execution
- route validation
- settlement verification
- offchain payload decoding
- beta allowlisting
- relayer-specific policy beyond role membership

## 6. Current Role And Permission Model

Current role identifiers:

- OpenZeppelin `DEFAULT_ADMIN_ROLE`
- `KdexitRoles.ADMIN_ROLE`
- `KdexitRoles.EXECUTION_RELAYER_ROLE`
- `KdexitRoles.EMERGENCY_PAUSER_ROLE`

Current registry permissions:

- constructor admin receives `DEFAULT_ADMIN_ROLE`
- constructor admin receives `ADMIN_ROLE`
- only `ADMIN_ROLE` can call `setStrategy(...)`
- OpenZeppelin `DEFAULT_ADMIN_ROLE` administers role grants and revocations
  unless changed through AccessControl admin mechanics

Current controller permissions:

- constructor admin receives `DEFAULT_ADMIN_ROLE`
- constructor admin receives `ADMIN_ROLE`
- constructor pauser receives `EMERGENCY_PAUSER_ROLE` if nonzero
- `EXECUTION_RELAYER_ROLE` is required for `submitExecutionRequest(...)`
- `EXECUTION_RELAYER_ROLE` is required for `recordExecutionCompletion(...)`
- `EXECUTION_RELAYER_ROLE` is required for `recordExecutionFailure(...)`
- `EMERGENCY_PAUSER_ROLE` is required for `pause()`
- `ADMIN_ROLE` is required for `unpause()`

Important current limitation:

- `ADMIN_ROLE` is a KDEXIT operational/admin role, but role administration itself
  is still governed by OpenZeppelin `DEFAULT_ADMIN_ROLE`
- there is no dedicated strategy-admin role separate from broader `ADMIN_ROLE`
- there is no signer-verifier or user-consent role
- there is no beta-operator role distinct from execution relayer
- there is no onchain allowlist for internal beta users, accounts, tokens, or
  strategies beyond the strategy registry

## 7. Current Emergency Pause Model

The execution controller inherits OpenZeppelin `Pausable`.

Current pause behavior:

- `pause()` can be called only by `EMERGENCY_PAUSER_ROLE`
- `unpause()` can be called only by `ADMIN_ROLE`
- `submitExecutionRequest(...)` is blocked by `whenNotPaused`
- `recordExecutionCompletion(...)` is blocked by `whenNotPaused`
- `recordExecutionFailure(...)` is blocked by `whenNotPaused`
- read functions remain available while paused
- pause emits OpenZeppelin `Paused(address)`
- unpause emits OpenZeppelin `Unpaused(address)`
- both pause transitions also emit `EmergencyPauseStateChanged`

Current pause model strengths:

- pause and unpause are separated
- emergency pauser cannot unpause by default
- relayers cannot submit new requests while paused
- lifecycle finalization is also blocked while paused
- read-only observability remains available

Current pause model limitations:

- the registry is not pausable
- strategy updates can still occur while the controller is paused
- there is no protocol-wide pause registry across future modules
- there is no delayed unpause, timelock, approval reference, or multisig
  enforcement in contract code
- pause does not revoke relayer role or disable strategies automatically
- pause only protects functions that exist today

For internal beta, every future asset-moving function should be pause-gated, and
the team should decide explicitly whether strategy changes remain allowed during
pause as a recovery action.

## 8. Current Event And Reconciliation Model

Current KDEXIT-specific events:

- `StrategyAuthorizationRegistered`
- `ExecutionRequestSubmitted`
- `ExecutionCompleted`
- `ExecutionFailed`
- `EmergencyPauseStateChanged`

Current OpenZeppelin events to index:

- `RoleGranted`
- `RoleRevoked`
- `RoleAdminChanged`
- `Paused`
- `Unpaused`

Current reconciliation keys:

- `executionId`: primary execution lifecycle key
- `strategyId`: strategy grouping and registry lookup key
- `account`: user or account context
- `payloadHash`: pointer to offchain request details
- `resultHash`: pointer to offchain result details
- `failureCode`: machine-readable failure category
- `failureContextHash`: pointer to richer offchain failure details

Current reconciliation model:

- index `ExecutionRequestSubmitted` as the accepted scaffold start
- index `ExecutionCompleted` or `ExecutionFailed` as terminal scaffold outcome
- verify event state against `getExecutionReceipt(executionId)`
- use registry events to reconstruct strategy state over time
- use role events to reconstruct privileged access over time
- use pause events and view functions to gate operational services

Current event model limitations:

- no event is emitted for reverted duplicate submission attempts
- no event guarantees actual token movement
- no event guarantees settlement
- no event binds a user signature to the request
- no event includes chain-specific or contract-domain replay binding beyond the
  transaction's chain context
- no event exposes decoded execution parameters because payload details remain
  offchain behind hashes

## 9. Current Test Coverage And Verified Behaviors

Current unit test coverage includes:

- registry constructor grants admin roles
- registry rejects `setStrategy(...)` from non-admin callers
- registry stores strategy config
- registry emits `StrategyAuthorizationRegistered`
- registry `isStrategyEnabled(...)` reflects stored enabled state
- controller constructor sets registry reference
- controller constructor grants admin, pauser, and relayer roles in the tested
  setup
- controller starts unpaused
- controller pause and unpause update state
- controller emits `EmergencyPauseStateChanged`
- controller rejects pause from non-pauser
- controller rejects unpause from non-admin
- controller rejects request submission from non-relayer
- controller rejects request submission while paused
- controller stores receipt on request submission
- controller emits `ExecutionRequestSubmitted`
- controller records completion
- controller emits `ExecutionCompleted`
- controller records failure
- controller emits `ExecutionFailed`

Verification performed during this audit:

- `forge test --offline`
- result: 12 tests passed, 0 failed, 0 skipped

Note on the test command:

- plain `forge test` panicked in this local environment while Foundry attempted
  to initialize an external signature lookup client
- `forge test --offline` avoided that external path and completed successfully

Current testing gaps:

- no integration tests yet
- no invariant tests yet
- no fuzz tests yet
- no deployment script tests
- no disabled-strategy submission test
- no duplicate `executionId` test
- no zero execution ID test
- no zero account test
- no completion/failure tests for unknown execution IDs
- no completion/failure tests for already terminal receipts
- no tests for role revocation effects
- no tests for optional zero emergency pauser constructor behavior
- no tests for registry updates from enabled to disabled
- no tests for OpenZeppelin `Paused`, `Unpaused`, or access-control events
- no tests covering production-like role manifests or multisig assumptions

## 10. Current Security Assumptions And Trust Boundaries

Current security assumptions:

- the constructor admin is trusted
- `DEFAULT_ADMIN_ROLE` holders are trusted to manage roles safely
- `ADMIN_ROLE` holders are trusted to manage strategy configuration and unpause
- `EMERGENCY_PAUSER_ROLE` holders are trusted to pause quickly and narrowly
- `EXECUTION_RELAYER_ROLE` holders are trusted to submit and finalize scaffold
  execution records honestly
- offchain systems are trusted to build payloads, store payload details, classify
  failures, and reconcile event hashes
- users are not currently represented by contract-level authorization
- strategy metadata is meaningful only to offchain consumers

Current trust boundaries:

- strategy registry controls strategy-enabled state but not strategy safety
- execution controller controls request admission but not execution correctness
- relayers can create scaffold records but cannot move funds because no
  asset-moving logic exists
- admins can grant relayer roles and configure strategies, so admin compromise is
  high impact
- pausers can halt controller lifecycle writes but cannot recover alone
- watchers and product services remain offchain and should not be treated as
  contract authorities unless explicitly granted roles

Current security strengths:

- role checks are enforced on privileged write paths
- pause blocks current execution-lifecycle write paths
- duplicate execution IDs are rejected after submission
- strategy-enabled state gates request submission
- zero execution IDs and zero account addresses are rejected
- terminal lifecycle states cannot be finalized again

Current security limitations:

- no user authorization validation
- no request signature validation
- no domain separation for signed payloads
- no nonce system beyond global `executionId` uniqueness
- no amount, token, spender, or target safety checks
- no settlement checks
- no external-call safety because external execution does not exist yet
- no multisig enforcement
- no time delay or expiry
- no slippage or price protection
- no beta access controls

## 11. Current Operational Monitoring Expectations

Operational monitoring should currently expect to track:

- strategy authorization changes
- strategy enabled/disabled state
- strategy target changes
- strategy metadata hash changes
- execution request submissions
- execution completion/failure terminal states
- pending submitted requests that do not terminally resolve
- pause and unpause transitions
- role grants, revocations, and admin-role changes
- receipt state versus event state

Minimum event streams:

- `StrategyAuthorizationRegistered`
- `ExecutionRequestSubmitted`
- `ExecutionCompleted`
- `ExecutionFailed`
- `EmergencyPauseStateChanged`
- `Paused`
- `Unpaused`
- `RoleGranted`
- `RoleRevoked`
- `RoleAdminChanged`

Minimum view checks:

- `getStrategy(strategyId)`
- `isStrategyEnabled(strategyId)`
- `getExecutionReceipt(executionId)`
- `isExecutionSubmitted(executionId)`
- `isEmergencyPaused()`
- `canSubmitExecutionRequests()`
- `hasRole(role, account)` inherited from OpenZeppelin

Operational monitoring is currently readiness monitoring, not live settlement
monitoring. There is no onchain asset movement to observe.

## 12. Current Deployment Assumptions

Current deployment assumptions:

- registry must be deployed before the controller
- controller constructor must receive the intended registry address
- default admin must be nonzero
- controller registry address must be nonzero
- emergency pauser may be zero at deployment, in which case no pauser is granted
  automatically
- relayer role must be granted after deployment by an account with the relevant
  admin authority
- strategy configuration must be set after registry deployment by `ADMIN_ROLE`
- deployment artifacts and manifests are not yet implemented
- multisig ownership is expected for real environments but is not enforced by
  this repository
- the repository does not yet provide production deployment scripts
- the repository does not yet provide chain-specific config

Before any real deployment, operators should record:

- commit hash
- Foundry version
- compiler settings
- chain ID
- constructor arguments
- deployed addresses
- role holder manifest
- strategy manifest
- pause launch state
- indexer configuration
- alert routing
- rollback and emergency procedures

# INTERNAL EXECUTION BETA GAP ANALYSIS

This section describes what is still missing before the contracts can support a
tightly controlled internal execution beta. The short version: the current
contracts are not ready to move assets. They are ready to inform the shape of
the beta execution layer.

## 1. Missing Before Internal Execution Beta

Before an internal execution beta, the contracts need at minimum:

- user execution authorization
- request signature validation or equivalent wallet-controlled consent
- domain-separated typed data
- expiry/deadline checks
- token and amount specification
- bounded token approval design
- actual execution path or controlled adapter call
- settlement/result validation
- relayer restrictions beyond simple role membership
- beta account allowlisting or equivalent internal access gate
- supported token allowlist
- supported strategy allowlist with stricter semantics
- supported target/adapter allowlist
- per-account or per-intent nonce protection
- stronger tests, including integration and invariants
- deployment scripts and manifests
- incident runbooks
- monitoring connected to real alert routes
- explicit go/no-go review from engineering, security, operations, and product

The beta should not be treated as merely "grant a relayer role and submit real
payloads." That would put all meaningful safety in offchain convention, which is
not enough once assets can move.

## 2. Missing Authorization Model

The current authorization model only answers:

- is the caller an admin?
- is the caller an execution relayer?
- is the caller an emergency pauser?
- is the strategy enabled?

It does not answer:

- did the user authorize this execution?
- did the user authorize this token?
- did the user authorize this amount?
- did the user authorize this strategy?
- did the user authorize this target?
- did the user authorize this deadline?
- did the user authorize this chain and contract?
- is the user part of the internal beta?
- is the account still eligible at execution time?

An internal beta needs a clear authorization model that separates:

- protocol operator authorization
- user execution authorization
- strategy authorization
- token/spender authorization
- beta eligibility

Recommended direction:

- use EIP-712 typed data for user execution intents
- bind signatures to chain ID and controller address
- bind signatures to account, strategy, token in, token out if applicable,
  amount, minimum output or acceptable result, deadline, nonce, and execution ID
- require the relayer to submit an already-authorized intent
- keep relayer role separate from user consent

## 3. Missing Execution Permission Flow

The current flow is:

1. relayer calls `submitExecutionRequest(...)`
2. controller checks role, pause state, duplicate ID, nonzero account, and
   strategy enabled
3. controller stores a receipt and emits an event
4. relayer later records completion or failure

Missing beta flow:

1. user or controlled internal account authorizes a specific execution intent
2. backend verifies eligibility and simulates the execution
3. relayer submits the intent and execution data
4. contract verifies role, pause state, beta eligibility, signature, nonce,
   deadline, strategy, token, amount, and target
5. contract marks the intent consumed before external effects
6. contract performs the narrow allowed execution or calls a vetted adapter
7. contract verifies minimum settlement conditions
8. contract emits deterministic lifecycle and settlement events
9. backend reconciles onchain result with offchain simulation

The missing permission flow is the difference between "recording that something
was requested" and "being allowed to move assets."

## 4. Missing Token Approval Model

There is no token approval model today.

An internal beta must define:

- who owns the funds
- which contract or adapter may spend funds
- whether approvals are user-granted, permit-based, temporary, or preapproved
- whether Permit2 or ERC-2612 is supported
- maximum allowance scope
- approval revocation expectations
- unsupported token behavior
- fee-on-transfer and nonstandard ERC-20 policy
- native asset policy

Safest beta stance:

- avoid unlimited approvals
- prefer per-execution permit or bounded allowance where possible
- allow only explicitly supported ERC-20 tokens
- reject unsupported tokens
- reject arbitrary spender targets
- bind token, spender, amount, and deadline into the signed user intent
- do not let strategy metadata imply token approval authority

## 5. Missing Relayer Restrictions

Today, any holder of `EXECUTION_RELAYER_ROLE` can submit and finalize scaffold
requests for any enabled strategy and any nonzero account.

For beta, relayers should be constrained by:

- allowlisted relayer addresses
- role revocation runbook
- optional per-relayer strategy permissions
- optional per-relayer account or beta cohort permissions
- request signature verification
- deadline checks
- rate limits at the service level
- monitoring of submission volume and failure rate
- requirement that finalization matches actual execution effects, not relayer
  assertion alone

The relayer should be a delivery mechanism, not a source of truth for user
authorization or settlement.

## 6. Missing Replay And Idempotency Protections

Current protection:

- global `executionId` uniqueness prevents exact reuse after an accepted
  scaffold submission
- terminal receipts cannot be finalized twice

Still missing:

- user nonce tracking
- per-account nonce tracking
- signature replay protection
- chain ID binding for signed intents
- verifying-contract binding for signed intents
- expiry/deadline enforcement
- cancellation support
- replay protection across failed transactions that revert before state changes
- clear semantics for retryable versus consumed failures
- protection against the same user intent being represented by multiple
  execution IDs

For beta, the safest rule is:

- one user intent maps to one execution ID and one consumed nonce
- mark intent consumed before any external asset-moving call
- terminal settlement events must be idempotent
- retries must require either the same consumed execution record or a fresh user
  authorization, depending on the failure class

## 7. Missing Settlement And Reconciliation Protections

Today, completion is a relayer-recorded scaffold state. The contract does not
prove settlement.

Missing settlement protections:

- actual balance-delta checks
- minimum output checks
- recipient checks
- token in/out checks
- slippage checks
- deadline checks
- adapter return-data validation
- handling of partial fills
- handling of fee-on-transfer tokens
- handling of tokens that do not return booleans
- handling of failed external calls
- stuck-funds recovery policy
- result event that includes enough data to reconcile settlement

For beta, completion should mean more than "relayer says completed." It should
mean the contract verified the minimum settlement properties that matter for the
specific execution path.

## 8. Missing Event Guarantees

Current events are good for scaffold reconciliation but incomplete for live
execution.

Missing event guarantees:

- event emitted when a user intent is consumed
- event emitted when execution starts, if execution is separated from request
  intake
- event emitted with concrete token, amount, recipient, and adapter data where
  safe to expose
- event emitted with settlement amount and asset identifiers
- event emitted for cancellation if supported
- event emitted for expiry or non-execution if represented onchain
- event emitted for adapter or execution-path configuration changes
- event semantics that distinguish submitted, executing, settled, failed,
  cancelled, expired, and possibly refunded states

For beta, events should allow operators to answer:

- who authorized the execution?
- who relayed it?
- what strategy was used?
- what assets and amounts were involved?
- what minimum settlement constraint applied?
- what actually settled?
- which nonce or intent was consumed?
- why did execution fail, if it failed?

## 9. Remaining Testing Gaps

Before beta, tests should cover:

- all current unit gaps listed above
- user signature verification
- invalid signature rejection
- wrong chain/domain rejection
- expired intent rejection
- nonce replay rejection
- duplicate execution ID rejection
- revoked relayer rejection
- disabled strategy rejection
- unsupported token rejection
- unsupported target rejection
- pause behavior across every asset-moving function
- external-call failure behavior
- settlement minimum enforcement
- balance-delta checks
- event ordering and payload correctness
- role revocation effects
- multisig or deployment-manifest assumptions where testable
- integration tests for registry plus controller plus adapter
- invariant tests for no unauthorized execution, no double consumption, and no
  execution while paused
- fuzz tests for malformed requests and boundary amounts

The current test suite is useful but too small for live execution.

## 10. Operational Or Security Blockers

Current blockers to internal live execution:

- no user authorization model
- no token approval model
- no execution implementation
- no settlement verification
- no relayer policy beyond role membership
- no beta allowlist
- no deployment scripts
- no integration or invariant tests
- no multisig manifest
- no production monitoring deployment
- no incident response process tied to real addresses
- no security review of asset-moving logic because that logic does not exist

These are blockers, not polish items.

## 11. Absolute Requirements Before Any Live Execution

Before any live execution is allowed, even internally, the system must have:

- explicit internal beta scope and chain
- explicit supported token list
- explicit supported strategy list
- explicit supported execution path
- user-signed or otherwise wallet-controlled execution authorization
- replay protection
- deadline protection
- bounded token approval model
- relayer role with documented custody and revocation
- pause coverage for every execution-moving entrypoint
- settlement verification
- event model sufficient for reconciliation
- integration tests
- invariant tests for the critical safety properties
- deployment script and manifest
- multisig or approved controlled signer setup for admin powers
- monitoring for events, pause, roles, failures, stuck executions, and balances
- emergency pause and recovery runbooks
- written go/no-go approval

## 12. Safe Deferrals Until After Internal Beta

The following can likely remain deferred if the internal beta is tightly scoped:

- cross-chain execution
- broad token support
- arbitrary strategy adapters
- public user access
- public relayer marketplace
- complex batching
- automated strategy discovery
- treasury fee distribution
- upgradeability, if the beta can redeploy and migrate safely instead
- advanced keeper networks
- decentralized governance
- partial-fill support, if forbidden during beta
- native asset support, if ERC-20-only beta is acceptable
- multiple DEX or aggregator integrations, if one vetted path is enough
- advanced analytics, beyond minimum operational monitoring

The beta should be intentionally narrow. Scope discipline is a safety control.

# RECOMMENDED EXECUTION-BETA CONTRACT ROADMAP

This section proposes the smallest practical route from the current scaffold to
a controlled internal execution beta.

## Safest Minimal Internal Execution Contract Scope

The safest beta scope is:

- one chain
- one controller deployment
- one registry deployment
- one or very few strategies
- one vetted execution adapter or direct execution path
- explicit supported ERC-20 token list
- no arbitrary calldata execution
- no cross-chain flow
- no public user access
- no public relayer set
- no batching unless strictly required
- no upgradeability unless the team has a tested upgrade process

The beta contract surface should add only what is required to execute one
well-understood internal flow safely.

Minimum new contract concepts:

- typed user execution intent
- nonce or consumed-intent tracking
- beta participant/account allowlist or equivalent internal eligibility check
- supported token policy
- supported adapter or target policy
- bounded execution function
- settlement verification
- richer settlement event

## Smallest Possible Execution Surface

Recommended minimal write functions:

- configure supported beta tokens
- configure supported execution adapter or target
- configure beta account eligibility, if handled onchain
- submit and execute a signed internal beta intent
- pause
- unpause
- admin recovery for stuck funds, if assets can ever remain in the contract

Avoid adding:

- arbitrary executor calls
- generic multicall
- operator-supplied target addresses
- unbounded bytes execution against arbitrary targets
- open-ended batch execution
- strategy-defined spenders
- relayer-controlled settlement assertions without contract verification

The core execution function should be narrow enough that a reviewer can answer:

- what assets can move?
- who authorized the movement?
- who can relay it?
- where can assets go?
- what minimum result must hold?
- what state prevents replay?
- what happens if the external call fails?

## Safest Approval Model

Recommended approval model:

- prefer per-intent permit-style authorization when available
- bind approval to token, amount, spender, nonce, deadline, chain ID, and
  controller address
- avoid persistent unlimited approvals
- allow only supported tokens
- allow only vetted spenders/adapters
- make approval failure a hard revert
- require explicit user consent for any amount increase or retry that changes
  execution parameters

If persistent approvals are unavoidable for internal beta:

- cap token list tightly
- cap beta accounts tightly
- document spender addresses
- monitor allowances
- provide a revocation runbook
- do not support arbitrary downstream spenders

## Pause And Kill-Switch Expectations

Pause expectations:

- every execution-moving function must use pause protection
- every adapter path must respect controller pause state
- relayer services must stop submitting immediately when paused
- read functions and reconciliation must remain available
- unpause must require higher assurance than pause
- pause and unpause must emit indexable events

Additional kill-switch expectations:

- ability to disable a strategy
- ability to disable a token
- ability to disable an adapter
- ability to revoke relayer role
- ability to remove beta eligibility
- clear runbook for which switch to use in which incident

The emergency pauser should be able to stop execution quickly. The admin or
multisig should be required to restore normal operation.

## Relayer Restrictions

Recommended beta relayer model:

- small fixed relayer set
- no public relayer onboarding
- relayers hold only `EXECUTION_RELAYER_ROLE`
- relayers cannot manage strategies
- relayers cannot manage token support
- relayers cannot pause or unpause unless separately approved for emergency
  operations, which should be avoided
- relayers cannot execute without a valid user intent
- relayers cannot choose arbitrary targets or spenders
- relayer addresses are monitored for unexpected volume, failures, and
  destination changes

The relayer should never be able to create user consent by itself.

## Supported Chain Scope

Recommended internal beta chain scope:

- start with one chain only
- use one deployed registry and one deployed controller
- bind all signed intents to the chain ID
- bind all signed intents to the verifying controller address
- maintain one deployment manifest for the beta
- avoid cross-chain state, bridging, or multi-chain replay complexity

Expanding to additional chains should require a separate deployment review and a
separate manifest.

## Execution Paths That Should Remain Forbidden

Forbidden during internal beta:

- arbitrary calldata execution
- arbitrary token support
- arbitrary spender approval
- arbitrary strategy target execution
- cross-chain execution
- userless execution
- execution without deadline
- execution without nonce or consumed-intent tracking
- execution while paused
- relayer-only authorization
- settlement recorded only by relayer assertion
- batch execution over mixed users or mixed strategies unless separately
  designed and tested
- partial fills unless explicitly modeled
- upgrades during active beta without a tested and approved process

## Deployment And Testing Stages

Recommended stages:

1. Current scaffold hardening
   - add missing unit tests for duplicate IDs, disabled strategies, zero fields,
     terminal-state rejection, and role revocation
   - add integration tests for registry plus controller flows
   - add invariant tests for current lifecycle rules

2. Beta authorization prototype
   - add typed intent structure
   - add signature/domain/nonce/deadline verification
   - add tests for invalid signatures, replay, expiry, and wrong domain

3. Minimal execution adapter
   - add one vetted execution path
   - add supported token and target policy
   - add settlement verification
   - add pause coverage and external-call failure tests

4. Testnet deployment rehearsal
   - deploy registry, controller, and adapter using scripts
   - grant roles from a manifest
   - configure one strategy and one token
   - run event ingestion, role monitoring, pause monitoring, and reconciliation

5. Internal beta dry run
   - use controlled accounts and small amounts
   - exercise success, failure, pause, revoke, disable strategy, and disable
     token flows
   - verify runbooks and alert routing

6. Internal execution beta go/no-go
   - require engineering, security, operations, and product signoff
   - freeze deployment manifest
   - freeze supported scope
   - define maximum exposure
   - monitor continuously during the beta window

The recommended contract strategy is not to build a generalized execution
platform first. Build the narrowest internally useful execution path, prove the
authorization and settlement model, and only then widen the surface.
