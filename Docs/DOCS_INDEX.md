# Tryzub Reservations — documentation index

**Branch audited:** `audit-current-state`  
**Audit date:** 2026-06-14  
**Purpose:** Stabilization branch — docs match **current Swift code**, not old handoffs.

## Source of truth (read these first)

| Doc | Scope |
|-----|--------|
| [AUDIT_CURRENT_STATE.md](./AUDIT_CURRENT_STATE.md) | Full technical audit, risks, doc migration, stabilization order |
| [OPEN_WORK.md](./OPEN_WORK.md) | V1 stabilization backlog only |
| [IOS_ARCHITECTURE.md](./IOS_ARCHITECTURE.md) | App entry, session, tabs, stores, controllers |
| [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md) | Startup, cache-first, active-window sync, refresh loops |
| [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md) | Staff workflows: confirm, email, seat, cancel, hide, manual create |
| [FLOOR_PLAN_AND_TABLES.md](./FLOOR_PLAN_AND_TABLES.md) | Backend floor plan, table assignment, legacy paths |
| [INTELLIGENCE.md](./INTELLIGENCE.md) | Backend intelligence APIs + iOS boundaries |
| [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md) | Host board intelligence, deterministic engine, local model wording |
| [DIAGNOSTICS_AND_TESTING.md](./DIAGNOSTICS_AND_TESTING.md) | Developer diagnostics, TestFlight checklist |
| [ACTIVITY_HISTORY.md](./ACTIVITY_HISTORY.md) | Read-only activity history |
| [LOCAL_MODEL_INTELLIGENCE.md](./LOCAL_MODEL_INTELLIGENCE.md) | On-device LLM boundaries (wording only) |

## Backend contract

| Doc | Scope |
|-----|--------|
| [README.md](./README.md) | WordPress plugin API, DB schema 1.7.0, routes, import rules |

## Reference / secondary (update as needed)

| Doc | Status |
|-----|--------|
| [PROJECT_MAP.md](./PROJECT_MAP.md) | UPDATE_REQUIRED — good iOS map, confirm flow section stale |
| [PROJECT_METHOD_MAP.md](./PROJECT_METHOD_MAP.md) | UPDATE_REQUIRED — method index; drifts quickly |
| [ARCHITECTURE_DIAGRAMS.md](./ARCHITECTURE_DIAGRAMS.md) | UPDATE_REQUIRED — diagrams valuable; audit bullets stale |
| [IOS_ADMIN_TESTING.md](./IOS_ADMIN_TESTING.md) | SUPERSEDED by DIAGNOSTICS_AND_TESTING.md |
| [TABLE_CONFIGURATION.md](./TABLE_CONFIGURATION.md) | MERGED into FLOOR_PLAN_AND_TABLES.md |
| [BACKEND_INTELLIGENCE.md](./BACKEND_INTELLIGENCE.md) | MERGE into INTELLIGENCE.md (duplicate) |

## Historical

| Location | Contents |
|----------|----------|
| [ARCHIVE/](./ARCHIVE/) | Handoffs, refactor log, runtime proposal |
