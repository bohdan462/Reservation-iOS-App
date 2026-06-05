# Tryzub Reservations — Method Map

Method-level map of current behavior. **Source of truth: Swift code.**

**Audience tags:** `staff` · `manager` · `developer` · `all`

**Confirm semantics (current UI — not ambiguous in code):**
- `ReservationHostAction.confirmOnly` → `updateStatus(.confirmed)` → PATCH — **no email**
- `ReservationHostAction.confirmAndSendEmail` → `confirmReservation` → POST `/confirm` — **backend email**
- `createAcceptedManualReservation` → POST — confirmed, **no email**
- `generateGuestManageLink` → POST `/guest-manage-link` — **manual Mail MVP**, no email sent

---

## ReservationsController

**File:** `Import/ReservationsController.swift`  
**Role:** Workflow coordinator. Owns sync scopes, cursors, notices, mutation guards.

### Lifecycle & refresh

#### `loadIfNeeded(context:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationsListView.task` |
| Business action | App startup — show cache, refresh today if needed |
| Network | Yes → `performTodayRefresh(.startup)` |
| SwiftData | Yes — `syncTodayFull` → `replaceDateScope` |
| Controller state | `hasCompletedInitialLoad`, `lastSyncedAt`, notices |
| Endpoint | `GET /managed-reservations?date=today&per_page=50` |
| Audience | all |
| Name clear? | Yes |

#### `requestManualTodayRefresh(context:source:)`
| Field | Value |
| --- | --- |
| Who calls | Home pull-refresh, toolbar refresh, `refreshDashboard` |
| Business action | Staff manually refreshes today board |
| Network | Yes — today **full replace** (not delta) |
| SwiftData | Yes — replace today scope |
| Controller state | `isSyncing`, scope timestamps, notices; blocked if mutation in flight or 8s cooldown |
| Endpoint | `GET /managed-reservations?date=today` |
| Audience | all |
| Name clear? | Yes |

#### `autoRefreshDashboardIfAllowed(context:isInteractionActive:isAppActive:)`
| Field | Value |
| --- | --- |
| Who calls | `HostBoardView.runAutoRefreshLoop` (60s while visible) |
| Business action | Quiet background today refresh |
| Network | Yes — **delta** if cursor exists, else full |
| SwiftData | Delta: upsert only; full: replace today |
| Controller state | `isAutoRefreshing`; guards: app active, no interaction, not busy, 60s interval, 180s failure cooldown |
| Endpoint | `GET ?date=today` or `&updated_since={cursor}` |
| Audience | all |
| Name clear? | Yes |

#### `scheduleBecameActive(context:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationScheduleView.task(id: isActive)` |
| Business action | User opens List tab |
| Network | Yes — only if schedule scope stale (>300s) |
| SwiftData | `replaceDateWindow(today..today+30)` |
| Endpoint | `GET /managed-reservations?from&to` paged |
| Audience | all |

#### `requestScheduleRefresh(context:source:)`
| Field | Value |
| --- | --- |
| Who calls | Schedule pull-refresh, toolbar |
| Business action | Manual schedule window refresh |
| Network | Yes — full replace window |
| Endpoint | `GET ?from&to` |
| Audience | all |

#### `loadScheduleAllPage(context:page:search:perPage:)`
| Field | Value |
| --- | --- |
| Who calls | Schedule "All" scope, search, load more |
| Business action | Paginated reservation search |
| Network | Yes |
| SwiftData | **upsert only** — no deletes |
| Endpoint | `GET /managed-reservations?page&per_page&search` |
| Audience | all |

#### `reviewBecameActive(context:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationReviewQueueView.task(id: isActive)` |
| Business action | User opens Review tab |
| Network | Yes — if stale (>120s) |
| SwiftData | `replaceReviewQueue` — upsert only, **no deletes** |
| Endpoint | `GET ?status=needs_review` + `GET ?status=new` |
| Audience | all |

#### `requestReviewRefresh(context:source:)`
| Field | Value |
| --- | --- |
| Who calls | Review pull-refresh, toolbar |
| Network | Yes — review queues |
| SwiftData | upsert-only review queue |
| Audience | all |

#### `loadCancelledReservations(context:force:)`
| Field | Value |
| --- | --- |
| Who calls | `CancelledReservationsView.task` / refresh |
| Business action | Load cancelled archive for More screen |
| Network | Yes — if stale (300s) or forced |
| SwiftData | upsert only |
| Endpoint | `GET ?status=cancelled&from=-30d&to=+60d` |
| Audience | all (view in More) |

#### `refreshScheduleWindowCache(context:)`
| Field | Value |
| --- | --- |
| Who calls | verify in code — alias to schedule refresh |
| Name clear? | Yes |

#### `refreshDashboard(context:)`
| Field | Value |
| --- | --- |
| Who calls | verify in code — wraps manual today refresh |
| Returns | `Bool` success |
| Suggested rename | `refreshToday` |

#### `refreshReviewQueues(context:)`
| Field | Value |
| --- | --- |
| Who calls | verify in code — alias to `requestReviewRefresh` |

### Local cache helper

#### `save(_:context:)`
| Field | Value |
| --- | --- |
| Who calls | verify in code — `onCreated` callbacks |
| Network | No |
| SwiftData | `upsert` single DTO |
| Name clear? | **Misleading** — suggest `upsertServerReservationIntoCache` |
| Risk | May be redundant after create paths that already upsert |

### Restaurant operations (delegate to API client)

| Method | Endpoint | Audience | SwiftData |
| --- | --- | --- | --- |
| `loadRestaurantSetup` | `GET /restaurant-setup` | manager+ | No — `@Published restaurantSetup` |
| `updateRestaurantSetup` | `PATCH /restaurant-setup` | manager+ | No |
| `loadRestaurantHours` | `GET /restaurant-hours` | manager+ | No |
| `updateRestaurantHours` | `PATCH /restaurant-hours` | manager+ | No |
| `loadRestaurantDayAvailability` | `GET /restaurant-day-availability` | manager+ | No |
| `updateRestaurantDayAvailability` | `PATCH` | manager+ | No |
| `loadReservationSlots` | `GET /reservation-slots` (public) | all (forms) | No |
| `loadRestaurantBlockedSlots` | `GET /restaurant-blocked-slots` | manager+ | No |
| `loadReservationAnalyticsSummary` | `GET /reservation-analytics/summary` | manager+ | No |

All throw `actionAlreadyInProgress` if overlapping load/save flags set.

### Mutations

#### `createReservation(_:context:)`
| Field | Value |
| --- | --- |
| Who calls | **No production UI caller found** |
| Endpoint | `POST /managed-reservations` |
| SwiftData | upsert |
| Audience | manager+ (capability) |
| Name clear? | Yes but **dead path** — UI uses `createAcceptedManualReservation` |
| Risk | Duplicate of accepted-manual create with different notice text |

#### `createAcceptedManualReservation(_:context:)`
| Field | Value |
| --- | --- |
| Who calls | `ManualReservationFormView`, `ImportFailuresView` repair, More manual create |
| Business action | Call-in / manual reservation already confirmed |
| Endpoint | `POST /managed-reservations` |
| Email | **No** — notice says no email sent |
| SwiftData | upsert |
| Controller state | `isCreatingReservation` |
| Audience | manager+ |
| Name clear? | Yes |

#### `updateReservation(id:request:context:)`
| Field | Value |
| --- | --- |
| Who calls | Edit form, table sheet, hide, restore, internal status updates |
| Endpoint | `PATCH /managed-reservations/{id}` |
| SwiftData | upsert |
| Reconcile | Yes on uncertain network failure |
| Controller state | `actionInProgressIDs` |
| Audience | staff+ (edit); hide needs manager+ for hidden screen |

#### `updateStatus(reservation:status:context:)`
| Field | Value |
| --- | --- |
| Who calls | Confirm Only, seat, complete, cancel, no-show handlers |
| Endpoint | PATCH with `status` only |
| **Confirm Only** | `status: .confirmed` — **no email** |
| Audience | manager+ for confirm/cancel; staff for seat/complete |

#### `confirmReservation(reservation:context:)`
| Field | Value |
| --- | --- |
| Who calls | Confirm + Email handlers only |
| Endpoint | `POST /managed-reservations/{id}/confirm` |
| Email | Backend — notices per `emailStatus` |
| SwiftData | upsert `response.data` |
| Reconcile | Yes on uncertain failure |
| Audience | manager+ |
| Name clear? | **Misleading alone** — means "confirm **and send email**"; suggest `confirmReservationAndSendEmail` |

#### `hideWrongEntry(reservation:reason:context:)`
| Field | Value |
| --- | --- |
| Who calls | Detail More menu, `ReservationEditFormView` |
| Endpoint | PATCH `is_hidden=true`, `hidden_reason` |
| Audience | manager+ (soft cleanup) |
| Risk | Staff should use hide, not hard delete |

#### `restoreHiddenReservation(reservation:context:)`
| Field | Value |
| --- | --- |
| Who calls | Hidden reservations screen |
| Endpoint | PATCH `is_hidden=false` |
| Audience | manager+ |

#### `hardDeleteReservation(reservation:context:cleanupReason:)`
| Field | Value |
| --- | --- |
| Who calls | `HiddenReservationsView` only |
| Endpoint | `DELETE /managed-reservations/{id}?force=1` |
| SwiftData | `deleteReservation(remoteID:)` after server OK |
| Audience | **developer only** |
| Risk | Irreversible — admin test cleanup only |

#### `generateGuestManageLink(reservation:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationDetailView` More menu |
| Endpoint | `POST /managed-reservations/{id}/guest-manage-link` |
| Email | **Does not send** — notice: copy into manual confirmation email |
| SwiftData | None |
| Audience | manager+ |
| MVP | Manual Gmail/Mail workflow |

#### `reconcileReservation(id:context:)`
| Field | Value |
| --- | --- |
| Who calls | `updateReservation`, `confirmReservation` on uncertain errors |
| Endpoint | `GET /managed-reservations/{id}` |
| SwiftData | upsert |
| Audience | internal recovery |

### Hidden & import failures

#### `loadHiddenReservations(context:)`
| Field | Value |
| --- | --- |
| Who calls | `HiddenReservationsView` |
| Endpoint | `GET /managed-reservations?include_hidden=1` |
| SwiftData | upsert all; returns filtered `isHidden == true` |
| Audience | manager+ — throws `permissionDenied` otherwise |

#### `refreshImportFailureCount` / `refreshImportFailureCountIfNeeded`
| Field | Value |
| --- | --- |
| Endpoint | `GET /import-failures?page=1&per_page=1` |
| Audience | manager+ capability; triggered after main refreshes |
| SwiftData | No |

#### `fetchImportFailures(page:perPage:)`
| Field | Value |
| --- | --- |
| Who calls | `ImportFailuresView` |
| Endpoint | `GET /import-failures` |
| Audience | manager+ capability |

### Diagnostics & notices

#### `runAdminFetchTest(_:reservationID:)`
| Field | Value |
| --- | --- |
| Who calls | `DeveloperDiagnosticsView.run` |
| Network | GET only per `AdminFetchTest` case |
| SwiftData | No |
| Audience | **developer only** |
| Endpoints | See IOS_ADMIN_TESTING.md |

#### `isActionInProgress(for:)`
| Field | Value |
| --- | --- |
| Who calls | Row views, detail, host board |
| Network | No |
| UI | Disables action buttons for that reservation |

#### `dismissNotice` / `clearAllNotices` / `clearErrorMessage` / etc.
| Field | Value |
| --- | --- |
| Audience | all / developer for clear all in diagnostics |

### Private helpers (documented for sync understanding)

| Method | Purpose |
| --- | --- |
| `performTodayRefresh` | Today full or delta implementation |
| `performScheduleWindowRefresh` | Schedule full replace + cursor |
| `performReviewQueuesRefresh` | Review upsert |
| `updateServerCursor` / `serverCursor` | Store `server_time` per scope |
| `markScopesTouched` | Invalidate schedule/review after mutation |
| `postNotice` / `postRefreshFailureNotice` / `postOfflineNotice` | Notice pipeline |

---

## ReservationSyncService

**File:** `Import/ReservationImportService.swift`

| Method | Network | SwiftData write | Deletes orphans? | Called by controller? |
| --- | --- | --- | --- | --- |
| `syncTodayFull` | `GET ?date=today` | `replaceDateScope` | **Yes** (today) | Yes — startup/manual |
| `syncTodayChanges(since:)` | `GET ?updated_since=` | `upsert` if non-empty | **No** | Yes — auto only |
| `syncScheduleWindowFull` | `GET ?from&to` paged | `replaceDateWindow` | **Yes** in window | Yes |
| `syncReviewQueues` | 2× status GET | `replaceReviewQueue` | **No** | Yes |
| `syncAllReservations` | All pages | `upsert` | No | **No** — diagnostics-capable only |
| `syncToday` / `syncScheduleWindow` | Wrappers | Same as full | — | Yes (aliases) |
| `saveReservation` | None | `upsert` one | No | Via `controller.save` |

---

## ReservationMutationService

**File:** `Services/ReservationMutationService.swift`

| Method | Endpoint | SwiftData after success |
| --- | --- | --- |
| `updateReservation` | PATCH `/{id}` | upsert |
| `createReservation` | POST | upsert |
| `confirmReservation` | POST `/{id}/confirm` | upsert `response.data` |
| `createGuestManageLink` | POST `/{id}/guest-manage-link` | none |
| `hardDeleteReservation` | DELETE `?force=1` | `deleteReservation` |
| `reconcileReservation` | GET `/{id}` | upsert |

---

## ReservationRepository

**File:** `Services/ReservationRepository.swift`

| Method | Deletes local rows? | Notes |
| --- | --- | --- |
| `upsert` | No | Match `remoteID` |
| `replaceDateScope` | Yes — date scope orphans (preserves hidden if `includeHidden: false`) | Server truth for one date |
| `replaceDateWindow` | Yes — window orphans | Schedule sync |
| `replaceReviewQueue` | **No** | Upsert only |
| `deleteReservation` | Yes — single row | After hard delete |
| `latestLocalSyncDate` | No | Max `lastSyncedAt` for UI |

---

## ImportFailureService

**File:** `Services/ImportFailureService.swift`

#### `fetchImportFailures(page:perPage:reason:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationsController.fetchImportFailures` |
| Endpoint | `GET /managed-reservations/import-failures` |
| Network | Yes |
| SwiftData | No |
| Audience | manager+ via controller guard |

Thin pass-through to API client.

---

## ReservationsAPIClient

**File:** `Network/ReservationsAPIClient.swift`

**Config:** Base URL from app entry; Basic auth; 30s/60s timeouts; GET retry floor ≥1; logs to `APIRequestLogStore` (100 events).

### Endpoint method table

| Client method | HTTP | Path | Auth | Default retry |
| --- | --- | --- | --- | --- |
| `ping` | GET | `/ping` | Public | ≥1 |
| `fetchReservations` | GET | `/managed-reservations` | Protected | caller / ≥1 |
| `fetchAllReservations` | GET | `/managed-reservations` (paged) | Protected | caller |
| `fetchReservation` | GET | `/managed-reservations/{id}` | Protected | 1 |
| `createReservation` | POST | `/managed-reservations` | Protected | 0 |
| `updateReservation` | PATCH | `/managed-reservations/{id}` | Protected | 0 |
| `confirmReservation` | POST | `.../confirm` | Protected | 0 |
| `createGuestManageLink` | POST | `.../guest-manage-link` | Protected | 0 |
| `hardDeleteReservation` | DELETE | `...?force=1` | Protected | 0 |
| `fetchImportFailures` | GET | `.../import-failures` | Protected | ≥1 |
| `fetchRestaurantSetup` | GET | `/restaurant-setup` | Protected | ≥1 |
| `updateRestaurantSetup` | PATCH | `/restaurant-setup` | Protected | 0 |
| `fetchRestaurantHours` | GET | `/restaurant-hours` | Protected | ≥1 |
| `updateRestaurantHours` | PATCH | `/restaurant-hours` | Protected | 0 |
| `fetchRestaurantDayAvailability` | GET | `/restaurant-day-availability` | Protected | ≥1 |
| `updateRestaurantDayAvailability` | PATCH | same | Protected | 0 |
| `fetchReservationSlots` | GET | `/reservation-slots` | **Public** | ≥1 |
| `fetchRestaurantBlockedSlots` | GET | `/restaurant-blocked-slots` | Protected | ≥1 |
| `createRestaurantBlockedSlots` | POST | `/restaurant-blocked-slots` | Protected | 0 |
| `deleteRestaurantBlockedSlots` | DELETE | body slots | Protected | 0 |
| `deleteAllRestaurantBlockedSlots` | DELETE | `?date=` | Protected | 0 |
| `fetchReservationAnalyticsSummary` | GET | `/reservation-analytics/summary` | Protected | ≥1 |

**List query params:** `page`, `per_page`, `date`, `from`, `to`, `status`, `search`, `updated_since`, `include_hidden=1`

**Not implemented:** `POST /managed-reservations/import`

---

## RestaurantSettingsStore

**File:** `Features/Reservations/RestaurantSettingsStore.swift`  
Delegates network to `ReservationsController` (or API via controller wrappers).

| Method | Action | Lazy? |
| --- | --- | --- |
| `loadInitialSettings` | Bootstrap setup on settings entry | On first open |
| `loadRestaurantSetup` / `saveRestaurantSetup` | GET/PATCH setup | — |
| `loadRestaurantHours` / `saveRestaurantHours` | Weekly hours | Per screen `.task` |
| `loadDayAvailability` / `saveDayAvailability` | Per-date overrides | On date pick |
| `loadReservationSlots` | Slot preview | Via `ensureDateOperations` |
| `loadBlockedSlots` / `blockSlots` / `unblockSlots` / `unblockAllSlots` | Blocked CRUD | Via `ensureDateOperations` |
| `refreshDateOperations` | All three GETs for a date | — |
| `ensureDateOperations(date:force:)` | Task-owned load; anti-stuck-spinner | **Key lifecycle method** |
| `loadReservationAnalyticsSummary` | Analytics chart data | BusinessAnalyticsView `.task` |
| `suggestedServiceDates` / `suggestedTimes` / `defaultServiceSlot` | Form defaults | No network |

**Audience:** manager+ for settings screens (capability-gated in More nav).

---

## HiddenReservationsStore

**File:** `Features/Reservations/HiddenReservationsStore.swift`

#### `isHidden(_:)`
| Field | Value |
| --- | --- |
| Who calls | All list filters |
| Network | No |
| Logic | Returns `reservation.isHidden` from server-synced field |
| Risk | No local hide set — purely server truth |

---

## GuestInsightsController

**File:** `Features/GuestInsights/GuestInsightsController.swift`

#### `analyze(selected:allReservations:)`
| Field | Value |
| --- | --- |
| Who calls | `GuestInsightsView`, preview card |
| Network | **None** |
| SwiftData | **Read only** — scans passed `[ReservationRecord]` |
| Business action | Guest memory: identity match, intent dedupe, preferences, watchouts |
| Audience | all |
| Performance risk | Scans full cache on detail — verify dataset size on busy nights |

#### `RegularGuestsController`
| Field | Value |
| --- | --- |
| Who calls | `RegularGuestsView` |
| Network | None |
| Logic | Clusters guests from `@Query` reservations in memory |

#### `GuestIdentityResolver` / `GuestReservationIntentDeduper`
| Field | Value |
| --- | --- |
| Network | None |
| Notes | Placeholder emails excluded from identity matching |

---

## Major view lifecycle methods

### ReservationsListView
| Trigger | Method / effect |
| --- | --- |
| `.task` | `loadIfNeeded`, `loadRestaurantSetup` |
| `tabContainer` | Mount all tabs; toggle visibility |
| `visibleNotices` | Tab-filter notice sources |

### HomeDashboardView / HostBoardView
| Trigger | Effect |
| --- | --- |
| `.task(id: isVisible && isAppActive)` | `runAutoRefreshLoop` → `autoRefreshDashboardIfAllowed` |
| `.task(id: isVisible)` | `runClockLoop` |
| `.task(id: isVisible-date)` | `loadTodayAvailabilitySummary` — **direct apiClient** |
| `.refreshable` | `requestManualTodayRefresh` |
| `handleAction` / `perform` | Route to controller; confirm dialog |

### ReservationScheduleView
| Trigger | Effect |
| --- | --- |
| `.task(id: isActive)` | `scheduleBecameActive` |
| `.refreshable` | `requestScheduleRefresh` |
| Load more / search | `loadScheduleAllPage` |

### ReservationReviewQueueView
| Trigger | Effect |
| --- | --- |
| `.task(id: isActive)` | `reviewBecameActive` |
| `.refreshable` | `requestReviewRefresh` |

### ReservationDetailView
| Trigger | Effect |
| --- | --- |
| `perform(_:)` | `updateStatus` / `confirmReservation` / table PATCH |
| `generateGuestManageLink` | POST guest-manage-link; pasteboard |
| Edit sheet | `ReservationEditFormView` → PATCH |
| Hide | `hideWrongEntry` |

### ManualReservationFormView / ReservationEditFormView
| Trigger | Effect |
| --- | --- |
| Create save | Confirmation alert → `createAcceptedManualReservation` |
| Edit save | Diff review → `updateReservation` PATCH |
| Hide | `hideWrongEntry` |
| Slot load | `ensureDateOperations` or controller slot fetch |

### HiddenReservationsView
| Trigger | Effect |
| --- | --- |
| `.task` | `loadHiddenReservations` |
| Restore | `restoreHiddenReservation` |
| Hard delete | `hardDeleteReservation` (developer) |

### DeveloperDiagnosticsView
| Trigger | Effect |
| --- | --- |
| Test buttons | `runAdminFetchTest` |
| Checklist | Reads `APIRequestLogStore.hasSuccessfulCall` |

### ImportFailuresView
| Trigger | Effect |
| --- | --- |
| `.task` | `fetchImportFailures` |
| Repair create | `createAcceptedManualReservation` |

---

## Misleading names — rename candidates (do not rename now)

| Current name | Suggested | Why |
| --- | --- | --- |
| `confirmReservation` | `confirmReservationAndSendEmail` | Implies email endpoint |
| `save(_:context:)` | `upsertServerReservationIntoCache` | Not a server save |
| `createReservation` (controller) | Remove or merge with `createAcceptedManualReservation` | Dead UI path |
| `refreshDashboard` | `refreshToday` | Only refreshes today |
| `ReservationImportService.swift` | `ReservationSyncService.swift` | File name legacy |

---

## Network failure behavior (controller-level)

| Scenario | Behavior |
| --- | --- |
| Offline on refresh | Warning notice; cache stays visible; 60s offline notice cooldown |
| Refresh failure | Error notice; scope failure timestamp; cooldown before retry |
| Mutation failure | Error notice; action ID cleared in `defer` |
| Uncertain mutation | Reconcile GET by ID; success/failure notice |
| Empty delta | No upsert; no delete; cursor still updated if server returns `server_time` |
