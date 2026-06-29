# iOS lifecycle and sync

**Status:** Current source of truth  
**Branch:** `audit-current-state`  
**Last reviewed:** 2026-06-24

## Rules

1. **Backend** `GET /managed-reservations` (active window) is reservation truth for sync.
2. **SwiftData** mirrors server; never authoritative.
3. **No** `POST /import` in normal workflow (not exposed in client for refresh).
4. Mutations go through `ReservationsController` → `ReservationMutationService` → upsert/delete local row.
5. **Offline / degraded:** mutations are blocked when network is unavailable; saved cache stays visible. **No offline manual create/edit queue** in V1.

## Sync metadata persistence

`ReservationsController` persists active-window sync state in **UserDefaults** (not server truth):

| Key / field | Purpose |
|-------------|---------|
| `tryzub.sync.serverCursors.v1` | Per-scope `server_time` cursor for `updated_since` delta GETs |
| Scope success timestamps | Last successful refresh per scope (feeds freshness TTL / header trust) |
| Active window bounds metadata | Last known window bounds for reconcile on relaunch |

**SwiftData** holds reservation rows. **`lastSyncedAt`**, **`lastFreshnessCheckedAt`**, and **`cacheTrustSource`** are controller presentation fields rehydrated from local DB / persisted scope success — not authoritative server state.

This persistence resumes delta/full policy after relaunch. It is **not** offline mutation support or a sync-when-online queue.

## Startup (cache-first)

```
beginStartupPresentation
  → releaseStartupUIFromLocalCacheIfAvailable (onAppear, if rows exist)
  → performStartupNetworkPass (once)
       → performStartupActiveWindowRefresh
            skip | full | delta per policy
  → scheduleHistoryPrefetchWhenReady (deferred, ≤1/12h)
  → startDeferredRestaurantSetupIfNeeded
```

**States:** `startupPresentationState` — checking cache, empty loading, showing cached refreshing, ready, failed.

**UI gate:** `StartupRootView` shows loading until `hasReleasedStartupUI`.

## Active-window sync (primary path)

All normal refresh converges on:

```
performActiveWindowRefresh(scope)
  → ReservationSyncService.syncActiveWindowFull | syncActiveWindowChanges
  → ReservationRepository.replaceDateWindowYielding | upsertYielding
```

**Window bounds:** `activeReservationWindowQueryBounds()` — yesterday through +120 days (`ReservationPresentation.swift`).

### Full sync

- **Network:** `GET /managed-reservations?from=&to=`
- **SwiftData:** `replaceDateWindowYielding` — upsert all + **delete** local IDs in window not in response (non-hidden)
- **Triggers:** Manual refresh (forced), startup (no cache/cursor), tab activation if stale, auto when no cursor + stale, auto bounded-full policy

### Delta sync

- **Network:** `GET` with `updated_since` cursor
- **SwiftData:** upsert only — **never deletes**
- **Triggers:** Auto-refresh when cursor exists; background startup delta

### Automatic bounded-full policy

Automatic active-window refresh normally uses delta when a server cursor exists. To prevent ghost rows from living forever after backend cancel/hide/move/hard-delete, the controller forces a full active-window replace when:

- no successful full active-window refresh has been recorded in the controller session,
- 5 successful automatic active-window deltas have completed since the last successful full, or
- the last successful full active-window refresh is older than 2 hours.

Successful full refresh resets the delta count and records the full timestamp. Failed refreshes do not reset counters. Delta remains upsert-only; full remains `replaceDateWindowYielding`.

## Manual refresh

| Entry | Method | Behavior |
|-------|--------|----------|
| Host pull-to-refresh | `requestManualTodayRefresh` | Forced full active window |
| Bookings pull/toolbar | `requestScheduleRefresh` | Forced full (same window path) |
| Cooldown | 8s | Prevents hammering |

Blocked when: mutation in flight, `isSyncing`, interaction active (sheets).

## Auto refresh (60s loops)

| Owner | Gating | Calls |
|-------|--------|-------|
| `HostBoardView` | `isVisible && isAppActive` where `isAppActive` = scene active **and selected date is today** | `autoRefreshDashboardIfAllowed` |
| Bookings | `isActive` + `scenePhase == .active` | Same |

**Coalescing:** `activeWindowRefreshTask` — same scope awaits in-flight; different scope may skip.

**Auto guards:** skip if busy, interaction open, 60s since last attempt, 180s after failure. With cursor, delta runs even if scope “fresh” (TTL does not suppress delta).

**Foreground / privacy unlock (`b910bd1`):** `ReservationsListView` calls `autoRefreshDashboardIfAllowed` when app becomes active or privacy cover dismisses — same active-window path as loops above.

**Host status UI:** `HomeServiceStatusPresenter` already shows **Last sync** / **Checked** / Saved data / offline state (not “Updated”). Do not add a second stale-warning layer without device-proven gap.

**Asymmetry risk:** Bookings auto-syncs on past dates; Host does not. See OPEN_WORK P1-1.

## Tab activation

| Tab | On activate |
|-----|-------------|
| Bookings | `scheduleBecameActive` — full if scope stale (>300s) |
| Bookings | Also starts 60s loop |
| Host | Intelligence/floor coordinator; 60s loop when today |

## Other network paths (not active-window)

| Path | Writes | Deletes |
|------|--------|---------|
| History prefetch | Upsert | No |
| Schedule All pagination | Upsert | No |
| Schedule date filter GET | Upsert | No |
| Cancelled/hidden admin lists | Upsert | No |
| Detail reconcile GET by id | Upsert | No |
| Floor plan refresh | In-memory store | No |

## SwiftData write behavior

### `isContentEquivalent`

`ReservationRecord.isContentEquivalent(to:)` skips `update(from:)` when compared fields match.

`ReservationRecord.isContentEquivalent(to:)` compares all server-backed fields written by `update(from:)`, including confirmation/reminder timestamps, supersession, source/creator metadata, hidden metadata, status, notes, `tableName`, `createdAt`, `apiUpdatedAt`, and `confirmedAt`.

### Mutation local update

Successful PATCH/POST upserts response DTO. `markScopesTouched` marks active window fresh, review/schedule stale.

Optimistic `updateStatus` may write SwiftData before server returns.

## Cancellation

`prepareForLogout` / `cancelOwnedTasksForSessionEnd` cancels: startup pass, history prefetch, active window refresh, availability tasks.

View `.task(id:)` loops cancel when tab hidden or identity changes.

## Traces

- `StartupPolicyTrace` — startup decisions
- `ActiveWindowFreshnessTrace` — full/delta/skip
- `MultiDeviceSyncTrace` — host filter, sync scope
- `SwiftDataTrace` / `[NOOP_REFRESH_TRACE]` — zero-write refreshes

## Dead code (do not use)

Still present in codebase; **no callers**:

- `performTodayRefresh`, `performScheduleWindowRefresh`, `performReviewQueuesRefresh`
- `ReservationSyncService.syncAllReservations`, `syncToday*`, `syncReviewQueues`

## Related docs

- [IOS_ARCHITECTURE.md](./IOS_ARCHITECTURE.md)
- [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md)
- [OPEN_WORK.md](./OPEN_WORK.md)
