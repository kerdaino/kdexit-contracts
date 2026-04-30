# KDEXIT Phase 6 Operational Readiness Note

This note describes what future operational monitoring will need from the
current `kdexit-contracts` scaffold before any live execution environment is
allowed. It is a readiness and observability note only. It does not change
contract logic, authorize production settlement, or imply that asset-moving
execution exists today.

The contracts currently provide enough event and view-function structure for
operators, backend services, and indexers to plan monitoring around:

- strategy authorization changes
- execution request lifecycle transitions
- emergency pause state
- role grants and revocations
- pre-deployment safety checks

## Events To Index

Indexers should consume the KDEXIT-specific events first, then use standard
OpenZeppelin events for framework-level state changes.

### `KdexitStrategyRegistry`

Primary event:

- `StrategyAuthorizationRegistered(bytes32 indexed strategyId, address indexed target, address indexed actor, bool enabled, bytes32 metadataHash, uint64 configuredAt)`

Operational use:

- maintain the latest enabled or disabled state for each `strategyId`
- alert when a production strategy is disabled, re-enabled, or pointed at a new
  target
- compare `metadataHash` with the expected offchain strategy configuration
- record the `actor` that made each strategy authorization change

### `KdexitExecutionController`

Primary execution lifecycle events:

- `ExecutionRequestSubmitted(bytes32 indexed executionId, bytes32 indexed strategyId, address indexed account, address submitter, uint256 amountIn, bytes32 payloadHash, uint64 requestedAt, uint64 submittedAt)`
- `ExecutionCompleted(bytes32 indexed executionId, bytes32 indexed strategyId, address indexed account, address finalizer, bytes32 resultHash, uint64 finalizedAt)`
- `ExecutionFailed(bytes32 indexed executionId, bytes32 indexed strategyId, address indexed account, address finalizer, bytes32 failureCode, bytes32 failureContextHash, uint64 finalizedAt)`

Operational use:

- treat `executionId` as the primary lifecycle and deduplication key
- track submission volume, terminal success count, terminal failure count, and
  per-strategy failure rates
- alert when a submitted request remains non-terminal beyond the expected
  service-level window
- compare `requestedAt`, `submittedAt`, and `finalizedAt` for latency,
  stuck-request, and delayed-relayer monitoring
- reconcile `payloadHash`, `resultHash`, and `failureContextHash` against
  offchain execution records

Primary pause event:

- `EmergencyPauseStateChanged(bool indexed isPaused, address indexed actor, uint64 changedAt)`

Additional OpenZeppelin events to index:

- `Paused(address account)`
- `Unpaused(address account)`

Operational use:

- switch relayer and backend submission pipelines off when paused
- confirm the contract-specific pause event and OpenZeppelin pause event agree
  for the same transaction
- alert when pause is activated, when unpause occurs, and when either action is
  performed by an unexpected address

### Access Control Events

Both deployed contracts inherit OpenZeppelin `AccessControl`. Indexers should
also consume:

- `RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)`
- `RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)`
- `RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole)`

Operational use:

- maintain the current holder set for each role on each contract
- alert on any role assignment that does not match the approved deployment
  manifest
- alert immediately if `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`,
  `EXECUTION_RELAYER_ROLE`, or `EMERGENCY_PAUSER_ROLE` changes unexpectedly
- verify that role changes are initiated by the approved admin or multisig

## Pause State Monitoring

Pause state is an operational gate, not only an incident marker. Monitors should
combine event indexing with periodic view calls.

For `KdexitExecutionController`, monitors should check:

- `isEmergencyPaused()`
- `canSubmitExecutionRequests()`

Expected relationship:

- when `isEmergencyPaused()` is `true`, `canSubmitExecutionRequests()` should be
  `false`
- when `isEmergencyPaused()` is `false`, `canSubmitExecutionRequests()` should
  be `true`

Operational behavior:

- stop new execution request submissions while paused
- continue read-only reconciliation and event indexing while paused
- require explicit operator acknowledgement before resuming backend submission
  after an unpause event
- keep an incident timeline that includes the pause actor, unpause actor,
  transaction hashes, block numbers, and timestamps

Alert conditions:

- pause activated on any production deployment
- unpause performed without a matching incident-resolution approval
- pause state event disagrees with the latest view-function result after indexer
  finality
- backend relayer attempts to submit or finalize execution requests while pause
  is active

## Role-Change Monitoring

Role monitoring should be deployment-specific because the same role name may
exist on both the registry and controller.

Roles currently defined by `KdexitRoles`:

- `ADMIN_ROLE`
- `EXECUTION_RELAYER_ROLE`
- `EMERGENCY_PAUSER_ROLE`

OpenZeppelin role:

- `DEFAULT_ADMIN_ROLE`

Operational monitors should track role holders per contract address:

- `KdexitStrategyRegistry`: expected admin roles for strategy configuration
- `KdexitExecutionController`: expected admin, relayer, and emergency pauser
  roles for execution lifecycle operations

Alert conditions:

- any role grant or revoke outside an approved change window
- any role granted to an externally owned account when the deployment manifest
  requires a multisig, service account, or controlled signer
- loss of all valid holders for an admin or emergency role
- role changes emitted by an unexpected sender
- `RoleAdminChanged` emitted on a production deployment

Operational records should store:

- contract address
- role identifier
- account added or removed
- sender
- transaction hash
- block number
- timestamp
- approval reference or incident reference

## Execution Request Lifecycle Monitoring

The execution lifecycle is intentionally simple in the current scaffold:

1. `None`
2. `Submitted`
3. `Completed` or `Failed`

Monitoring should treat `Completed` and `Failed` as terminal scaffold states.
They are not proof of asset settlement until live execution logic is separately
implemented, reviewed, and approved.

Indexers should build a per-`executionId` record from:

- `ExecutionRequestSubmitted`
- `ExecutionCompleted`
- `ExecutionFailed`
- `getExecutionReceipt(bytes32 executionId)`
- `isExecutionSubmitted(bytes32 executionId)`

Operational checks:

- every terminal event must have a prior submitted event
- no `executionId` should have more than one terminal state
- submitted requests should terminally resolve within the expected service-level
  window
- terminal state from events should match `getExecutionReceipt(executionId)`
- `strategyId`, `account`, `amountIn`, `payloadHash`, and timestamps should
  match the approved offchain request record
- `finalizer` should be an approved execution relayer
- failure codes should map to a known operational taxonomy

Alert conditions:

- duplicate submission attempt observed through reverted transaction monitoring
- submitted request remains pending beyond the configured threshold
- unexpected finalizer or submitter
- strategy disabled after request submission but before terminal handling
- high failure rate for a strategy, account segment, or relayer
- receipt state diverges from indexed event state

## Before Any Deployment

Before any deployment, operators should verify the contract, configuration, and
monitoring surface together. A deployment should not proceed on contract
compilation alone.

Required checks:

- compile and test the exact commit being deployed
- confirm no unreviewed contract logic changes are included
- record deployed bytecode, constructor arguments, chain ID, deployment
  transaction, and contract addresses
- confirm `KdexitStrategyRegistry` is deployed before
  `KdexitExecutionController`
- confirm the controller constructor points to the intended strategy registry
- verify the default admin, KDEXIT admin, emergency pauser, and execution
  relayer addresses against the deployment manifest
- confirm any admin or emergency role expected to be a multisig is a multisig
  address, not an unapproved externally owned account
- confirm initial strategy authorization state and metadata hashes
- confirm pause state is the intended launch state
- verify indexers are configured for KDEXIT events, OpenZeppelin pause events,
  and OpenZeppelin access-control events
- verify alert routing for pause, role changes, disabled strategies, failed
  executions, and stuck submitted requests
- run a dry-run or testnet event ingestion check before production deployment
- document rollback, pause, unpause, and incident communication procedures

Go/no-go signoff should include engineering, security, operations, and product
owners. Until live execution logic is separately approved, deployment readiness
only means the scaffold can be observed and reconciled; it does not mean
production asset movement is enabled.
