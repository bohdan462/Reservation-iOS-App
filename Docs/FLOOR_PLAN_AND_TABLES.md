# Floor plan and tables

**Status:** Current source of truth (supersedes `TABLE_CONFIGURATION.md`)  
**Branch:** `audit-current-state`  
**Audit date:** 2026-06-14

## Source of truth

| Layer | Canonical? | Storage |
|-------|------------|---------|
| Backend `restaurant_tables` + `floor-plan` | **Yes** | Server |
| `PATCH /managed-reservations/{id}/tables` | **Yes** for assignment | Server |
| `FloorPlanStore` | Cache of backend layout | In-memory + optional SwiftData DTO save |
| `ReservationRecord.tableName` | Legacy string field | SwiftData mirror |
| `HostTableConfigStore` | **Advisory only** | UserDefaults |

## Canonical assignment flow

When `FloorPlanStore.hasBackendLayout` and table key resolves:

```
FloorPlanStore.assign / TableAssignmentCoordinator
  → PATCH /managed-reservations/{id}/tables
  → refresh floor plan
  → upsert reservation from response
```

## Legacy fallback

When layout missing or key unresolved:

```
PATCH /managed-reservations/{id}  (tableName field)
```

**Risks:** No 409 conflict checks; can diverge from floor plan truth.

**Stabilization:** Block legacy when backend layout exists (OPEN_WORK P1-2).

## Floor tab lifecycle

- `FloorPlanView` + `FloorPlanStore`
- Load on appear / date change
- Auto-refresh every 60s when tab active **and date is today**
- `FreshnessCoordinator` wired from session

## Host intelligence advisory tables

`HostTableConfigStore` supplies capacity hints for deterministic engine. **Never** overrides backend assignments.

## Large party / table config

Documented thresholds in settings; intelligence uses advisory counts only.

## Related docs

- [README.md](./README.md) — backend floor endpoints
- [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md)
- [OPEN_WORK.md](./OPEN_WORK.md) P1-2

## Historical

`TABLE_CONFIGURATION.md` — merge complete; keep file with pointer only.
