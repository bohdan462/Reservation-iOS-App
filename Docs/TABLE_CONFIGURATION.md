# Table Configuration (iOS)

**Branch:** `intelligence`

## Sources of truth

| Layer | Owns |
|-------|------|
| **Backend `RestaurantSetup`** | Booking policy, hours, slot interval, `largePartyReviewThreshold`, max online party — **not** per-table capacity |
| **`HostTableConfigStore`** | Canonical **local** iOS table inventory (shared per app session) |
| **`ReservationRecord.tableName`** | Assigned table string on the reservation row (backend PATCH) |
| **`ReservationTableOptionsStore`** | Legacy fallback chip names **only when structured inventory is empty** |

## `HostTableConfigStore` (canonical local inventory)

Persisted in UserDefaults (`tryzub.hostIntelligence.tableConfig.v1`). Each `RestaurantTableConfig` includes:

- **name** — matches reservation `tableName` when assigned
- **capacity** — seat count for advisory fit/mismatch
- **section** — optional grouping
- **active** — included in chips and intelligence when true
- **combinable tables** — pair combinations for large-party fit
- **sort order** — chip and display ordering

Edited via **Host Intelligence → Manage Table Inventory** (`HostTableConfigView`).

## Import path (not a competing source)

**`HostTableCapacityTextParser`**:

- **Import:** text like `A1:4` → parses → writes **`HostTableConfigStore`**
- **Export:** `exportText(from:)` round-trips structured inventory for display/sync
- Restaurant Settings **“Import table capacity text”** is a quick-setup path into the same store

## Assignment chips

```
HostTableConfigStore (active tables)
        ↓
TableAssignmentOptionsBuilder.assignmentTableNames(legacyFallback:)
        ↓
TableAssignmentSheet chip grid
```

- When structured inventory has active tables → chips come from inventory (sorted)
- When inventory is empty → fallback to `ReservationTableOptionsStore` legacy names
- Staff may always type any table string manually — **manual override allowed**

## Intelligence (advisory only)

```
HostTableConfigStore
        ↓
HostTableIntelligenceSupport → fit, mismatch, combinations
        ↓
Host engine / slot context → pressure signals
```

- Capacity mismatch and table-fit suggestions **warn** — they do **not block** assign/save
- Suggestions **never auto-assign** a table
- Manual reservation form slot banner uses the same inventory for advisory context

## Large party thresholds

| Setting | Default | Role |
|---------|---------|------|
| Backend `largePartyReviewThreshold` | **7** | Operational review policy (`RestaurantSetup`) |
| Host `largePartyThreshold` | **7** (new installs) | Advisory slot/table pressure (`HostIntelligenceSettings`) |
| Guest draft `largePartyMinimumPartySize` | **7** | Large-party draft kind visibility only |

**Note:** Existing persisted Host Intelligence settings keep whatever value staff saved until reset or edited.

## Staff rules

- Staff is the final operator for table assignment and guest messaging
- Backend stores **table name only** on the reservation; seat counts stay on-device
- See also `Docs/LOCAL_MODEL_INTELLIGENCE.md` for guest draft table flags
