# Table & Floor Plan Configuration (iOS)

**Branch:** `intelligence`  
**Status:** Backend floor layout and table assignments are canonical. Local table inventory is legacy advisory fallback only.

## Sources of truth

| Domain | Canonical owner | iOS read path |
|--------|-----------------|---------------|
| **Restaurant table layout** (keys, labels, capacity, sections, positions) | Backend `restaurant_tables` + floor-plan tables | `FloorPlanStore` via `GET /restaurant-tables`, `GET /floor-plan?date=` |
| **Per-date table assignments** | Backend `reservation_table_assignments` | `FloorPlanStore` via `GET /floor-plan?date=` |
| **Assignment mutation** | Backend | `PATCH /managed-reservations/{id}/tables` |
| **Reservation display field** | Backend `ReservationDTO.tableName` | SwiftData `ReservationRecord.tableName` — compatibility/display only |
| **Local table inventory** | **Not canonical** — UserDefaults advisory | `HostTableConfigStore` — chips, host intelligence fit, manual form hints |
| **Legacy chip names** | **Not canonical** | `ReservationTableOptionsStore` — only when structured local inventory is empty |

**Staff rule:** Configure production tables through **Floor tab → Edit Layout** (backend `PUT /restaurant-tables`). Assign tables through **Floor Plan** or assignment sheets that route through `TableAssignmentCoordinator` when backend layout exists.

## Backend endpoints (canonical)

| Endpoint | Purpose |
|----------|---------|
| `GET /restaurant-tables` | Active restaurant table inventory (`table_key`, label, capacity, section, combinable) |
| `PUT /restaurant-tables` | Save layout from Floor Plan edit mode |
| `GET /floor-plan?date=YYYY-MM-DD` | Per-date floor state: tables + reservation assignments |
| `PATCH /managed-reservations/{id}/tables` | Assign or clear tables by `table_key`; backend checks same-time/seated conflicts |

### Backend concepts

- **`table_key`** — stable identity (e.g. `a6`). Assignment mutations use keys, not free-text labels.
- **Labels** — display only; staff may see "A6" while the key is `a6`.
- **Per-date assignments** — backend-owned; iOS reads via floor-plan, does not invent layout locally.
- **409 conflicts** — backend rejects overlapping seated/same-time assignments; iOS surfaces staff-safe copy.

## iOS assignment path (production)

```text
TableAssignmentCoordinator
  ├─ hasBackendLayout + known table_key
  │    → FloorPlanStore.assign → PATCH /managed-reservations/{id}/tables
  └─ else (no layout / unknown label)
       → legacy PATCH /managed-reservations/{id} with tableName string
```

**Call sites:** `FloorPlanView`, `HostBoardView`, `ReservationDetailView`, `TableAssignmentSheet`.

The **preferred path** is always `PATCH .../tables` when `FloorPlanStore.hasBackendLayout` is true.

## `ReservationRecord.tableName`

- Cached display string from reservation DTO after sync or mutation.
- Updated when canonical assignment succeeds (from backend response).
- **Not** the preferred mutation input when floor layout exists.
- Legacy `tableName` PATCH remains for migration/offline-layout edge cases only.

## Legacy: `HostTableConfigStore` (advisory / compatibility)

**File:** `Features/HostIntelligence/HostTableConfigStore.swift`  
**Storage:** UserDefaults `tryzub.hostIntelligence.tableConfig.v1`

Still used for:

- Host intelligence table-fit / capacity advisory (`HostTableIntelligenceSupport`)
- Assignment chip names when backend layout unavailable (`TableAssignmentOptionsBuilder`)
- Manual reservation form slot banners
- More → Host Intelligence Settings → Manage Table Inventory (developer/migration UI)

**Not used for:** canonical floor layout, backend assignment writes, or production table configuration when backend floor exists.

`HostBoardView` prefers `floorPlanStore.viewState.tables` for engine input when backend layout is loaded.

## Legacy: `ReservationTableOptionsStore`

- UserDefaults chip-name fallback when `HostTableConfigStore` has no active tables.
- Compatibility only.

## Legacy: `HostTableCapacityTextParser`

- Parses text like `A1:4` into `HostTableConfigStore`.
- Restaurant Settings "Import table capacity text" is a **quick local setup** path.
- **Not** a competing source of truth when backend tables exist.
- Documented as migration/fallback; production staff should use Floor Plan edit layout.

## Intelligence (advisory only)

```text
Backend floor tables (preferred) or HostTableConfigStore (fallback)
  → HostTableIntelligenceSupport → fit, mismatch, combinations
  → HostIntelligenceEngine → advisory signals only
```

- Capacity mismatch warnings **do not block** assign/save.
- Suggestions **never auto-assign** a table.

## Large party thresholds

| Setting | Default | Role |
|---------|---------|------|
| Backend `largePartyReviewThreshold` | **7** | Operational review policy (`RestaurantSetup`) |
| Host `largePartyThreshold` | **7** (new installs) | Advisory slot/table pressure |
| Guest draft `largePartyMinimumPartySize` | **7** | Large-party draft kind visibility |

## Staff rules

- Staff is the final operator for table assignment.
- Backend owns floor layout and per-date assignments.
- Local inventory and capacity text import are **fallback/migration** tools only.
- See `Docs/LOCAL_MODEL_INTELLIGENCE.md` for guest draft table flags (advisory context only).
