# Reservation Activity History (iOS)

**Status:** Current source of truth  
**Branch:** `audit-current-state`  
**Audit date:** 2026-07-01  
**Backend schema:** 1.15.0 (delivery truth); activity unchanged at 1.7.0+  
**Rule:** Shipped — read-only display; backend writes all events.

Backend owns activity history. Mutation endpoints write activity automatically. iOS **reads** history for display. iOS **does not** create activity rows or POST a separate activity log.

## Endpoints

| Endpoint | iOS use |
|----------|---------|
| `GET /managed-reservations/{id}/activity?page=&per_page=` | Reservation Detail history + full history sheet |
| `GET /activity?date=YYYY-MM-DD&page=&per_page=` | More → Activity History (service-day feed) |
| `GET /activity?from=&to=` | API client supports range; UI uses single-date picker today |

Protected — same Basic auth as managed reservations.

## DTOs

**File:** `Network/ReservationActivityDTO.swift`

- `ReservationActivityDTO` — `id`, `reservationId`, `eventType`, `summary`, `actorName`, `actorRole`, `source`, `createdAt`, `metadata` (`[String: JSONValue]?`)
- `ReservationActivityResponseDTO` — per-reservation paginated envelope
- `ReservationActivityFeedResponseDTO` — day feed with `summary` chip counts

Optional mutation sidecar (traces only, not shown to staff):

- `MutationActivityResultDTO` — `created`, `eventTypes` on PATCH/POST responses

## iOS architecture

```text
ReservationsAPIClient.fetchReservationActivity / fetchActivityFeed
  → ReservationActivityStore (in-memory cache, 90s TTL, in-flight dedup)
  → ReservationActivityViewStateBuilder (staff-safe rows)
  → UI
```

**Store:** `Features/Reservations/ActivityHistory/ReservationActivityStore.swift`  
**Mounted:** `@StateObject` in `ReservationsTabShell`; `.environmentObject` to views.

### Cache rules

- Per-reservation cache key: `reservationID`
- Feed cache key: `date` (`YYYY-MM-DD`)
- TTL ~90 seconds; pull-to-refresh and `force: true` bypass TTL
- **No SwiftData persistence** — history is not invented from local cache

### Invalidation

After successful mutations, `ReservationsController.markScopesTouched` posts `ReservationActivityInvalidation`. Visible detail/feed screens refetch; hidden screens rely on TTL/stale mark.

iOS never writes activity on mutation.

## UI placement

### Reservation Detail

- `ReservationActivityHistorySection` — last 5 events, "Show all" sheet
- Fetches on detail open only (`.task(id: reservationID)`)
- Empty: *"No history yet. New changes will appear here."*
- Failed: retry button; does not block editing

### More → Business → Activity History

- `ActivityHistoryView` — date picker, summary chips, latest changes
- Optional guest name from active-window SwiftData cache when reservation is cached
- Empty: *"No changes recorded for this date yet."*

### Full history sheet

- `ReservationHistoryView` — paginated, grouped by day, pull to refresh

## Privacy / staff display

- Primary text: backend `summary` (e.g. "Table assigned: A6.")
- Subtitle: actor name/role + optional cached guest name on feed only
- **Do not** show raw `metadata` blobs in normal UI
- No phone, email, message bodies, or tokens in activity rows

## Auto-confirm events (history only)

- Backend may write `auto_confirmed` activity when auto-confirm runs.
- Timeline rows may show `AutoConfirmedBadge` on those events — **decorative / historic**.
- **Current-state auto-confirm sparkle** on list, host, and detail uses **`confirmationSource == .autoConfirm`** on the reservation DTO — **not** `ReservationActivityStore.hasBackendAutoConfirmEvidence` (unused).
- Do not fetch activity to decide whether a row is auto-confirmed today.

See [EMAIL_DELIVERY_TRUTH.md](./EMAIL_DELIVERY_TRUTH.md) §7.

## No backfill limitation

Reservations untouched before backend 1.7.0 deploy have **no history** until the next mutation after deploy. Empty state copy explains this; do not show "backend missing" unless there is a real error.

## Traces (DEBUG)

| Trace | Meaning |
|-------|---------|
| `[ACTIVITY_API_TRACE]` | API start/complete with count and duration |
| `[ACTIVITY_STORE_TRACE]` | Cache hit vs fetch decision |
| `[ACTIVITY_DETAIL_TRACE]` | Detail loaded/empty |
| `[ACTIVITY_MUTATION_TRACE]` | Optional backend `activity` sidecar on mutation response |

## Related docs

- [DOCS_INDEX.md](./DOCS_INDEX.md) — start here for current documentation
- [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md) — endpoint fetch timing, active-window refresh
- [DIAGNOSTICS_AND_TESTING.md](./DIAGNOSTICS_AND_TESTING.md) — manual verification checklist
- [EMAIL_DELIVERY_TRUTH.md](./EMAIL_DELIVERY_TRUTH.md) — delivery vs activity for auto-confirm
- [refactor.md](./refactor.md) — ownership map
