# KDEXIT Phase 5 Alignment Note

This note keeps `kdexit-contracts` and `kdexit-web` aligned on readiness language
as Phase 5 product work begins. It describes the current scaffold boundary only;
it does not authorize live execution or require new contract logic.

## Current Shared State

### Simulation only

`kdexit-web` should continue to treat exit flows as simulation-only user
experiences unless a separately approved internal beta execution gate exists.
Frontend copy, backend jobs, and operator dashboards should not imply that a
submitted action will move assets onchain.

### Contract scaffold ready

`kdexit-contracts` now provides a minimal scaffold that can support integration
planning:

- `KdexitStrategyRegistry` stores strategy authorization state and emits
  strategy configuration events.
- `KdexitExecutionController` records scaffold-level execution requests and
  terminal reconciliation states.
- role checks, strategy-enabled checks, duplicate request protection, and
  emergency pause controls exist at the scaffold layer.
- emitted events give `kdexit-web` and backend services stable keys for
  indexing, reconciliation, and UI state mapping.

This means the contract surface is ready for web and backend alignment work, not
for production settlement.

### Execution still disabled

The current contracts do not execute trades, route swaps, custody funds,
distribute treasury balances, coordinate relayers, or prove settlement. A
completed execution receipt is only a recorded scaffold state. It must not be
shown in `kdexit-web` as proof that assets moved.

Until the execution gate is explicitly approved, the web app should keep live
execution controls disabled or hidden behind internal-only safeguards. Any
request IDs, payload hashes, and receipt states should be presented as
simulation, dry-run, or reconciliation artifacts.

## Readiness Mapping

| Readiness state | `kdexit-contracts` meaning | `kdexit-web` meaning |
| --- | --- | --- |
| Simulation only | No asset-moving logic exists. Events and receipts are coordination records. | Users can preview, simulate, or review exit outcomes, but cannot trigger live execution. |
| Contract scaffold ready | Registry, controller, roles, pause checks, and event shapes are available for integration planning. | Web and backend can map strategy state, request IDs, receipt statuses, and pause state to UI and operator workflows. |
| Execution still disabled | No production routing, settlement, relayer market, or treasury flow is implemented or approved. | Execution buttons remain disabled, hidden, or internal-only, and product copy avoids live-execution claims. |

## Before Internal Beta Execution

Internal beta execution should not be allowed until all of the following are
complete and explicitly approved:

- final execution architecture, including routing, settlement, custody, and
  relayer responsibilities
- audited or internally reviewed contract changes for any asset-moving logic
- deployment plan with chain, addresses, role holders, multisig ownership, and
  emergency pause procedures
- backend execution service that can build, submit, monitor, retry, and
  reconcile real execution attempts safely
- `kdexit-web` gating that separates simulation, internal beta, and public
  availability states
- operator runbooks for pause, rollback, failed execution handling, and user
  communication
- test coverage across unit, integration, invariant, and web/backend readiness
  paths
- explicit go/no-go approval from product, engineering, and security owners

Until those conditions are met, Phase 5 should use the current scaffold as an
alignment and reconciliation target only.
