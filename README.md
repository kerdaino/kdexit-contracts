# KDEXIT Phase 4 Contracts

This repository contains the Phase 4 smart contract workspace scaffold for KDEXIT.

The workspace is intentionally Foundry-first and minimal. It establishes the protocol
surface area and folder layout without implementing production trading logic yet.

## Documentation

- [Phase 4 Contract Architecture](./docs/phase4-architecture.md)
- [Phase 4 Emergency Pause Model](./docs/phase4-emergency-pause-model.md)
- [Phase 4 Event Model](./docs/phase4-event-model.md)
- [Phase 4 Threat Model](./docs/phase4-threat-model.md)
- [Phase 4 Minimal Role Model](./docs/phase4-role-model.md)

## Planned Core Contracts

- `KdexitStrategyRegistry`
- `KdexitExecutionController`

## Current Scope

- Foundry workspace layout
- Placeholder contract boundaries
- Basic protocol types, OpenZeppelin-based access scaffolding, and pause controls
- Empty directories for tests, scripts, deployments, ABI output, and generated artifacts

## Not Yet Implemented

- Swap routing
- Treasury flows
- Relayer execution paths
- Upgradeability
- Production deployment scripts
- Full test coverage

## Next Manual Setup

1. Install Foundry if it is not already available.
2. Install `openzeppelin-contracts` into `lib/` so the scaffold imports resolve.
3. Implement the final role-granting and deployment flow from the Phase 4 role model.
4. Extend the execution request schema and reconciliation lifecycle from the Phase 4 spec.
5. Add unit, integration, and invariant test suites.
