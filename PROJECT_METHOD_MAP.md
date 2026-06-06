# Tryzub Reservations — Method Map

Method-level map of current behavior. **Source of truth: Swift code.**

**Audience tags:** `staff` · `manager` · `developer` · `all`

**Confirm semantics (current UI — not ambiguous in code):**
- `ReservationHostAction.confirmOnly` → `updateStatus(.confirmed)` → PATCH — **no email**
- `ReservationHostAction.confirmAndSendEmail` → `confirmReservation` → POST `/confirm` — **backend email**
- `createAcceptedManualReservation` → POST — confirmed, **no email**
- `GuestLookupView` → cache-derived operational call-in lookup — **no network while searching**
- `generateGuestManageLink` → POST `/guest-manage-link` — **manual Gmail/Mail MVP**, no email sent
- `ManualEmailDraftService.confirmationDraft` → local text only — no endpoint, no email sent, no status change

---

## ReservationsController

**File:** `Import/ReservationsController.swift`  
**Role:** Workflow coordinator. Owns sync scopes, cursors, `operationState`, notices, mutation guards.

### Operation state snapshot

| Field | Meaning |
| --- | --- |
| `activeSyncIntents` | Startup, manual, automatic, screen-active, reconcile, or diagnostics work by sync scope |
| `mutatingReservationIDs` | Per-reservation PATCH/confirm/hide/restore/hard-delete in flight |
| `reconcilingReservationIDs` | Uncertain mutation is being checked with GET by ID |
| `isCreatingReservation` | Manual create POST in flight |
| `isCheckingImportFailureCount` | Admin/dev failed-import count check in flight |
| `lastNetworkUnavailableAt` | Last offline-like refresh failure notice |

### Lifecycle & refresh

#### `loadIfNeeded(context:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationsListView.performStartupNetworkPass` |
| Business action | App startup — show cache, refresh active operational window |
| Network | Yes → `performActiveWindowRefresh(.startup)` |
| SwiftData | Yes — `syncActiveWindowFull` → `replaceDateWindow` |
| Controller state | `hasAttemptedInitialLoad`, `lastSyncedAt`, notices |
| Endpoint | `GET /managed-reservations?from=today-1&to=today+bookingWindow` |
| Audience | all |
| Name clear? | Yes |

#### `requestManualTodayRefresh(context:source:)`
| Field | Value |
| --- | --- |
| Who calls | Home pull-refresh, toolbar refresh, `refreshDashboard` |
| Business action | Staff manually refreshes the shared operational window |
| Network | Yes — active-window **full replace** (not delta) |
| SwiftData | Yes — replace active date window |
| Controller state | `isSyncing`, scope timestamps, notices; blocked if mutation in flight or 8s cooldown |
| Endpoint | `GET /managed-reservations?from&to` |
| Audience | all |
| Name clear? | Yes |

#### `autoRefreshDashboardIfAllowed(context:isInteractionActive:isAppActive:)`
| Field | Value |
| --- | --- |
| Who calls | `HostBoardView.runAutoRefreshLoop` (60s while visible) |
| Business action | Quiet background active-window refresh while Home is visible |
| Network | Yes — active-window **delta** if cursor exists, else full |
| SwiftData | Delta: upsert only; full: replace active window |
| Controller state | `isAutoRefreshing`; guards: app active, no interaction, not busy, 60s interval, 180s failure cooldown |
| Endpoint | `GET ?from&to` or `GET ?from&to&updated_since={cursor}` |
| Audience | all |
| Name clear? | Yes |

#### `scheduleBecameActive(context:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationScheduleView.task(id: isActive)` |
| Business action | User opens List tab |
| Network | Yes — only if active-window scope stale (>300s) |
| SwiftData | `replaceDateWindow(active window)` |
| Endpoint | `GET /managed-reservations?from&to` paged |
| Audience | all |

#### `requestScheduleRefresh(context:source:)`
| Field | Value |
| --- | --- |
| Who calls | Schedule pull-refresh, toolbar |
| Business action | Manual schedule window refresh |
| Network | Yes — full replace window |
| Endpoint | `GET ?from&to` active window |
| Audience | all |

#### `loadScheduleAllPage(context:page:search:perPage:)`
| Field | Value |
| --- | --- |
| Who calls | Schedule "All" scope, search, refresh, load more; every call passes caller context |
| Business action | Paginated reservation search |
| Network | Yes |
| SwiftData | **upsert only** — no deletes |
| Endpoint | `GET /managed-reservations?page&per_page&search` |
| Audience | all |
| Guard | Requires Schedule tab active **and** scope `.all`; blocked calls log `schedule_all_page_blocked` |

#### `reviewBecameActive(context:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationReviewQueueView.task(id: isActive)` |
| Business action | User opens Review tab |
| Network | Yes — only if active-window scope stale (>120s) |
| SwiftData | `replaceDateWindow(active window)` if refresh proceeds |
| Endpoint | `GET /managed-reservations?from&to` paged |
| Audience | all |

#### `requestReviewRefresh(context:source:)`
| Field | Value |
| --- | --- |
| Who calls | Review pull-refresh, toolbar |
| Network | Yes — active-window full refresh |
| SwiftData | replace active date window |
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
| Who calls | No current external call sites found; retained compatibility wrapper |
| Effect | Calls `requestScheduleRefresh(context:source: .manual)` |
| Name clear? | Mostly; current refresh is active-window-backed rather than old schedule-only data |

#### `refreshDashboard(context:)`
| Field | Value |
| --- | --- |
| Who calls | No current external call sites found; Home calls `requestManualTodayRefresh` directly |
| Effect | Calls `requestManualTodayRefresh`, which now refreshes the active window despite stale "today" comments in code |
| Returns | `Bool` success |
| Suggested rename | `refreshActiveWindowFromHome` |

#### `refreshReviewQueues(context:)`
| Field | Value |
| --- | --- |
| Who calls | No current external call sites found; retained compatibility wrapper |
| Effect | Calls `requestReviewRefresh(context:source: .manual)`, which now uses active-window refresh |

### Local cache helper

#### `save(_:context:)`
| Field | Value |
| --- | --- |
| Who calls | No current external call sites found |
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
| Guest lookup prefill | Optional `ManualReservationPrefill`; still posts `source_type=manual_call_in` and requires local phone confirmation when source is `callInGuestLookup` |

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

#### `ManualEmailDraftService.confirmationDraft(reservation:manageLink:)`
| Field | Value |
| --- | --- |
| Who calls | `ReservationDetailView` after a manage link exists |
| Endpoint | None |
| Email | **Does not send** — copies reviewed draft text to pasteboard |
| SwiftData | None |
| Status change | None |

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
| Endpoint | `GET /managed-reservations/import-failures?page=1&per_page=1` |
| Audience | manager+ capability; explicit admin/dev or diagnostics check only |
| SwiftData | No |

#### `fetchImportFailures(page:perPage:)`
| Field | Value |
| --- | --- |
| Who calls | `ImportFailuresView` |
| Endpoint | `GET /managed-reservations/import-failures` |
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
| `publishOperationState` | Mirrors active scopes and busy flags into one diagnostics/future-UI snapshot |

---

## ReservationSyncService

**File:** `Import/ReservationImportService.swift`

| Method | Network | SwiftData write | Deletes orphans? | Called by controller? |
| --- | --- | --- | --- | --- |
| `syncActiveWindowFull` | `GET ?from&to` paged | `replaceDateWindow` | **Yes** in active window | Yes — normal startup/manual/stale activation |
| `syncActiveWindowChanges` | `GET ?from&to&updated_since=` paged | `upsert` if non-empty | **No** | Yes — auto only |
| `syncTodayFull` | `GET ?date=today` | `replaceDateScope` | **Yes** (today) | **Legacy/private/diagnostic only. Do not use for normal Home/List/Review activation.** |
| `syncTodayChanges(since:)` | `GET ?date=today&updated_since=` | `upsert` if non-empty | **No** | **Legacy/private/diagnostic only. Normal delta is active-window scoped with `from` and `to`.** |
| `syncScheduleWindowFull` | `GET ?from&to` paged | `replaceDateWindow` | **Yes** in window | Legacy/private path |
| `syncReviewQueues` | 2× status GET | `replaceReviewQueue` | **No** | Legacy/private path/diagnostic understanding |
| `syncAllReservations` | All pages | `upsert` | No | **No** — diagnostics-capable only |
| `syncToday` / `syncScheduleWindow` | Wrappers | Same as full | — | Legacy aliases; future code should prefer active-window full/delta unless a diagnostic explicitly needs the old scope. |
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

**Config:** Base URL from app entry; Basic auth; one-at-a-time request serializer; 15s request timeout; 30s resource timeout; GET retry capped at one retry for timeout/connection-lost; non-GET no retry; logs to `APIRequestLogStore` (100 events).

### Endpoint method table

| Client method | HTTP | Path | Auth | Default retry |
| --- | --- | --- | --- | --- |
| `ping` | GET | `/ping` | Public | caller / max 1 |
| `fetchReservations` | GET | `/managed-reservations` | Protected | caller / ≥1 |
| `fetchAllReservations` | GET | `/managed-reservations` (paged) | Protected | caller |
| `fetchReservation` | GET | `/managed-reservations/{id}` | Protected | 1 |
| `createReservation` | POST | `/managed-reservations` | Protected | 0 |
| `updateReservation` | PATCH | `/managed-reservations/{id}` | Protected | 0 |
| `confirmReservation` | POST | `.../confirm` | Protected | 0 |
| `createGuestManageLink` | POST | `.../guest-manage-link` | Protected | 0 |
| `hardDeleteReservation` | DELETE | `...?force=1` | Protected | 0 |
| `fetchImportFailures` | GET | `.../import-failures` | Protected | caller / max 1 |
| `fetchRestaurantSetup` | GET | `/restaurant-setup` | Protected | caller / max 1 |
| `updateRestaurantSetup` | PATCH | `/restaurant-setup` | Protected | 0 |
| `fetchRestaurantHours` | GET | `/restaurant-hours` | Protected | caller / max 1 |
| `updateRestaurantHours` | PATCH | `/restaurant-hours` | Protected | 0 |
| `fetchRestaurantDayAvailability` | GET | `/restaurant-day-availability` | Protected | caller / max 1 |
| `updateRestaurantDayAvailability` | PATCH | same | Protected | 0 |
| `fetchReservationSlots` | GET | `/reservation-slots` | **Public** | caller / max 1 |
| `fetchRestaurantBlockedSlots` | GET | `/restaurant-blocked-slots` | Protected | caller / max 1 |
| `createRestaurantBlockedSlots` | POST | `/restaurant-blocked-slots` | Protected | 0 |
| `deleteRestaurantBlockedSlots` | DELETE | body slots | Protected | 0 |
| `deleteAllRestaurantBlockedSlots` | DELETE | `?date=` | Protected | 0 |
| `fetchReservationAnalyticsSummary` | GET | `/reservation-analytics/summary` | Protected | caller / max 1 |

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

## GuestLookupStore

**Files:** `Features/Guests/GuestLookupModels.swift`, `Features/Guests/GuestLookupStore.swift`, `Features/Guests/GuestLookupView.swift`

| Method / path | Behavior |
| --- | --- |
| `GuestLookupStore.updateCache(records:cacheKey:)` | Builds lightweight profiles from cached non-hidden `ReservationRecord` rows only when cache freshness changes |
| `GuestLookupStore.updateSearch(_:)` | Local search only; activates at 2 name characters or 4 phone digits |
| Identity priority | Phone digits, then email, then weak name-only rows kept separate |
| Create handoff | `GuestLookupResult.prefill` → `ManualReservationFormView(prefill:)` |
| Network | None while searching; create still goes through `createAcceptedManualReservation` |
| Explicit non-goal | Does not use Guest Insights / Regular Guests clustering and does not create backend guest tables |

---

## Major view lifecycle methods

### ReservationsListView
| Trigger | Method / effect |
| --- | --- |
| `.task` | `performStartupNetworkPass` behind launch overlay |
| `tabContainer` | Mount all tabs; toggle visibility |
| `visibleNotices` | Tab-filter notice sources |

### HomeDashboardView / HostBoardView
| Trigger | Effect |
| --- | --- |
| `.task(id: isVisible && isAppActive)` | `runAutoRefreshLoop` → `autoRefreshDashboardIfAllowed` |
| `.task(id: isVisible)` | `runClockLoop` |
| `.task(id: isVisible-date)` | controller `ensureAvailabilitySummary` after startup deferral |
| `.refreshable` | `requestManualTodayRefresh` |
| `handleAction` / `perform` | Route to controller; confirm dialog |

### ReservationScheduleView
| Trigger | Effect |
| --- | --- |
| `.task(id: isActive)` | `scheduleBecameActive` → active-window freshness check |
| `.refreshable` | Upcoming: active-window refresh; All: `loadScheduleAllPage` |
| Load more / search | `loadScheduleAllPage` only when active and scope `.all` |

### ReservationReviewQueueView
| Trigger | Effect |
| --- | --- |
| `.task(id: isActive)` | `reviewBecameActive` → active-window freshness check |
| `.refreshable` | active-window refresh |

### GuestLookupView
| Trigger | Effect |
| --- | --- |
| `.task(id: cacheKey)` | Rebuild cached lookup profiles only when the visible cache snapshot changes |
| Search typing | Debounced local search against cached profiles; no API call |
| Book Call-In | Opens `ManualReservationFormView(prefill:)` and requires phone confirmation before create |

### ReservationDetailView
| Trigger | Effect |
| --- | --- |
| `perform(_:)` | `updateStatus` / `confirmReservation` / table PATCH |
| `generateGuestManageLink` | POST guest-manage-link; pasteboard |
| Copy confirmation draft | Local `ManualEmailDraftService` text; pasteboard only |
| Edit sheet | `ReservationEditFormView` → PATCH |
| Hide | `hideWrongEntry` |

### ManualReservationFormView / ReservationEditFormView
| Trigger | Effect |
| --- | --- |
| Create save | Confirmation alert → `createAcceptedManualReservation` |
| Guest lookup prefill | Optional `ManualReservationPrefill`; still creates `manual_call_in` and requires local phone confirmation for lookup-prefilled calls |
| Edit save | Diff review → `updateReservation` PATCH |
| Hide | `hideWrongEntry` |
| Slot load | `ensureDateOperations` or controller slot fetch |

### HiddenReservationsView
| Trigger | Effect |
| --- | --- |
| `.task` | `loadHiddenReservationsPage(page: 1)` lazily |
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
| `refreshDashboard` | `refreshActiveWindowFromHome` | Name sounds Home-only, but current flow refreshes the shared active window |
| `ReservationImportService.swift` | `ReservationSyncService.swift` | File name legacy |

---

## Network failure behavior (controller-level)

| Scenario | Behavior |
| --- | --- |
| Offline on refresh | Warning notice; cache stays visible; 60s offline notice cooldown |
| Refresh failure | Error notice; scope failure timestamp; cooldown before retry |
| Mutation failure | Staff-safe error notice; action ID cleared in `defer` |
| Uncertain mutation | "Checking reservation" notice; affected ID enters reconcile state; GET by ID; success/failure notice |
| Empty delta | No upsert; no delete; cursor still updated if server returns `server_time` |

---

## Current Task / Memory / UI-Blocking Audit

| File / area | Confirmed or suspected | Risk | Fix now? | Recommended fix |
| --- | --- | --- | --- | --- |
| `Features/GuestInsights/RegularGuestsView.swift` | Partly mitigated | Broad `@Query` still observes cached reservations, but `RegularGuestsStore` now caches clustered summaries and debounces search display updates. | Later | Move analysis to lightweight snapshots/off-main work if cache grows further. |
| `Features/GuestInsights/RegularGuestsController.swift` | Confirmed | `exactAndStrongClusters` performs pairwise matching across records; cost grows quickly with cache size. | Later | Pre-index by phone/email/name keys before pairwise fallback. |
| `Features/GuestInsights/GuestInsightsView.swift` | Partly mitigated | Report is now computed into state keyed by selected reservation/cache freshness instead of as a body computed property. | Later | Avoid passing broad SwiftData arrays by using lightweight snapshots. |
| `Features/Reservations/ReservationsListView.swift` root `@Query pendingReviewRows` | Mitigated | Narrowed to active window and pending statuses, but still updates while all tabs are mounted. | Later | Keep unless badge count becomes janky; then publish count from controller/cache snapshot. |
| `HomeDashboardView` active-window `@Query` | Mitigated | Active-window query observes upserts and filters selected date in computed property. | Later | Current scope is acceptable; avoid expanding to all history. |
| `ReservationScheduleView.displayedReservations` | Mitigated | Filters/sorts active-window cache in body; All mode uses local page IDs and repository lookup. | Later | Keep All mode explicit; consider section snapshots if active window grows beyond pilot scale. |
| `HostBoardView.runAutoRefreshLoop` / `runClockLoop` | Mitigated | Async loops exist, but `.task(id:)` cancels them as visibility/app-active changes. | Later | Keep `isVisible` guards; never start loops from hidden tabs. |
| `HostBoardView` availability task | Mitigated | `.task(id:)` can restart on date/launch state changes; controller de-dupes and cancels by date. | Later | Keep controller cache; avoid view-local availability state. |
| `ManualReservationFormView.ensureSlotLoad` | Confirmed | Stores a `slotLoadTask` and cancels on disappear/date change; still does view-level slot/cache orchestration. | Later | Move to form view model after UI polish stabilizes. |
| `RestaurantSettingsStore.dateOperationsTask` | Mitigated | Long-lived task is stored and cancelled/replaced for date operations. | Later | Keep as store-owned; ensure all future paths clear save/loading flags in `defer`. |
| `ReservationsController` availability task dictionaries | Mitigated | Date-keyed task dictionaries can leak if not cleared; current `defer` clears summary tasks and GET task catch/success paths clear per-date tasks. | Later | Add tests around cancellation/throw paths if test target appears. |
| `ReservationRepository.records(remoteIDs:)` | Confirmed | Fetches one SwiftData descriptor per ID; schedule All page lookup can be N queries. | Later | Add batched remote-ID lookup when SwiftData predicate ergonomics allow. |
| `ServiceLoadChart`, `ServiceTimelineGraph`, `GuestInsightBarChart` | Mitigated | Chart/Geometry math can produce NaN if domains/dimensions are bad; current code clamps finite sizes and max denominators. | Later | Continue requiring `tryzubFinite*` helpers for new chart/GeometryReader code. |
| `More` navigation | Confirmed fixed | Nested path-based stacks caused `AnyNavigationPath` comparison crash for Cancelled details. | Done | Cancelled detail now uses parent typed path; avoid nested mixed path types under More. |

---

## Add/Edit Reservation Correctness Audit

| Requirement | Current state |
| --- | --- |
| Shared create/edit logic | `ManualReservationFormView` and `ReservationEditFormView` share `ReservationFormContent`, `ReservationFormDraft`, `ReservationFormValidator`, and `ReservationInputNormalizer`. |
| Guest name | Trim/collapse whitespace before request; required. |
| Phone | Visible input allows common formatting; request sends normalized digits; invalid lengths fail locally. |
| Email | Optional; normalized/trimmed/lowercased; validated only when non-empty. |
| Date/time | Date submits `YYYY-MM-DD`; time submits normalized backend-accepted time; changing date reloads/revalidates slots. |
| Today/past time | Validator blocks past selected times for today and applies setup lead time when setup has loaded. |
| Closed date | Form blocks dates whose backend slot response says closed; first uncached date still requires a slot fetch. |
| Notes/table | Guest notes, staff notes, and table trim before request; optional fields remain visible. |
| Backend failure | Form stays open; controller posts staff-safe error; no local reservation is inserted before server success. |
| Offline/degraded | Create/edit buttons are disabled or blocked through controller degraded state. |

---

## Semantic Labeling Contract

| Concept | Meaning | Display rule |
| --- | --- | --- |
| Status badge | Lifecycle: new, review, confirmed, seated, completed, cancelled, no-show | Keep separate from notes. |
| Needs Review | Attention state/reason | May show as status/attention, never as Guest Notes or Staff Notes. |
| Guest Notes | Guest-provided note text | Show only when `guest_notes` exists. |
| Staff Notes | Internal staff note text | Show only when `staff_notes` exists. |
| Seated duration | Local UI timing until backend provides `seated_at` | `localSeatedAtByReservationID` is cache/UI-only and should be replaced by server `seated_at` later. |
