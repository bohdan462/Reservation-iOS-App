# Tryzub Reservations Method Map

This map focuses on methods that matter for app behavior, network calls, persistence, lifecycle triggers, and staff workflows.

**Confirm semantics (current UI):**
- **`ReservationHostAction.confirmOnly`** → `updateStatus(..., .confirmed)` → PATCH (no email). UI label: **Confirm Only**.
- **`ReservationHostAction.confirmAndSendEmail`** → `confirmReservation` → POST `/confirm`. UI label: **Confirm + Email**.
- **`createAcceptedManualReservation`** → POST with `status=confirmed` (Home manual add; no email).

**Module layout:** `Import/ReservationsController.swift` (workflow), `Features/Reservations/` (UI shell), `Features/GuestInsights/` (cache-only analytics), `RestaurantSettingsStore.swift` (setup/hours/slots), `Network/ReservationsAPIClient.swift` (REST).

---

## ReservationsController

File: `Tryzub Reservations/Import/ReservationsController.swift`

Method: `init(environment:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationsListView.init(environment:)`.
What user/business action does it represent? App coordinator setup.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Initializes controller state.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.
Method: `loadIfNeeded(context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationsListView.task`.
What user/business action does it represent? Initial app load.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow.
Does it trigger network? Yes, through `performTodayRefresh`.
Does it write SwiftData? Yes, indirectly through `ReservationSyncService.syncToday`.
Does it mutate controller/UI state? Yes: initial-load guard, `lastSyncedAt`, notices, sync state.
What backend endpoint does it eventually use? `GET /managed-reservations?date=today&page=1&per_page=50`.
Is the name clear? Yes.

Method: `refreshAll(context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? No current production call found.
What user/business action does it represent? Alias for schedule refresh.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow alias.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?from=today&to=today+30`, paged.
Is the name clear? No. Suggested later name: `refreshScheduleWindow`.

Method: `refreshDashboard(context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? No current production call found.
What user/business action does it represent? Manual Today refresh.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow alias.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?date=today&page=1&per_page=50`.
Is the name clear? Not ideal. Suggested later name: `refreshToday`.

Method: `requestManualTodayRefresh(context:source:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `HomeDashboardView.refreshable`, Home toolbar refresh, `refreshDashboard`.
What user/business action does it represent? Staff manually refreshes Today.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow.
Does it trigger network? Yes, if guards allow.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: sync flags, scope state, notices.
What backend endpoint does it eventually use? `GET /managed-reservations?date=today&page=1&per_page=50`.
Is the name clear? Yes.

Method: `scheduleBecameActive(context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationScheduleView.task(id: isActive)`.
What user/business action does it represent? User opens Schedule tab.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/lifecycle.
Does it trigger network? Yes, only if schedule scope is stale.
Does it write SwiftData? Yes, indirectly when it fetches.
Does it mutate controller/UI state? Yes, when it fetches.
What backend endpoint does it eventually use? `GET /managed-reservations?from=today&to=today+30`, paged.
Is the name clear? Yes.

Method: `requestScheduleRefresh(context:source:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationScheduleView.refreshable`, Schedule toolbar refresh, `refreshAll`.
What user/business action does it represent? Staff manually refreshes Schedule.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?from=today&to=today+30`, paged.
Is the name clear? Yes.

Method: `reviewBecameActive(context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationReviewQueueView.task(id: isActive)`.
What user/business action does it represent? User opens Review tab.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/lifecycle.
Does it trigger network? Yes, only if review scope is stale.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?status=needs_review` and `GET /managed-reservations?status=new`.
Is the name clear? Yes.

Method: `requestReviewRefresh(context:source:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationReviewQueueView.refreshable`, Review toolbar refresh, `refreshReviewQueues`.
What user/business action does it represent? Staff manually refreshes review/new queues.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?status=needs_review` and `GET /managed-reservations?status=new`.
Is the name clear? Yes.

Method: `autoRefreshDashboardIfAllowed(context:isInteractionActive:isAppActive:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `HostBoardView.runAutoRefreshLoop`.
What user/business action does it represent? Background Today refresh while host board is visible.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/lifecycle.
Does it trigger network? Yes, if app/interaction/busy/cooldown guards allow.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: auto-refresh flags, scope state, notices on failure.
What backend endpoint does it eventually use? `GET /managed-reservations?date=today&page=1&per_page=50`.
Is the name clear? Yes.

Method: `performTodayRefresh(context:mode:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `loadIfNeeded`, `requestManualTodayRefresh`, `autoRefreshDashboardIfAllowed`.
What user/business action does it represent? Shared implementation for Today fetch.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private helper.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?date=today&page=1&per_page=50`.
Is the name clear? Yes.

Method: `refreshReviewQueues(context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? No current production call found.
What user/business action does it represent? Manual review refresh alias.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow alias.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?status=needs_review` and `GET /managed-reservations?status=new`.
Is the name clear? Yes, but redundant with `requestReviewRefresh`.

Method: `performScheduleWindowRefresh(context:force:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `scheduleBecameActive`, `requestScheduleRefresh`.
What user/business action does it represent? Shared implementation for Schedule fetch.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private helper.
Does it trigger network? Yes, unless not forced and fresh.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?from=today&to=today+30`, paged.
Is the name clear? Yes.

Method: `performReviewQueuesRefresh(context:force:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `reviewBecameActive`, `requestReviewRefresh`.
What user/business action does it represent? Shared implementation for Review/New fetch.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private helper.
Does it trigger network? Yes, unless not forced and fresh.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations?status=needs_review` and `GET /managed-reservations?status=new`.
Is the name clear? Yes.

Method: `save(_:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `HomeDashboardView` and `ReservationMoreView` pass it as `onCreated` after failed-import manual create.
What user/business action does it represent? Local cache save for a DTO already returned by server.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Persistence/cache helper.
Does it trigger network? No.
Does it write SwiftData? Yes, indirectly through `ReservationSyncService.saveReservation`.
Does it mutate controller/UI state? Yes, notices and touched scopes.
What backend endpoint does it eventually use? None.
Is the name clear? No. Suggested later name: `upsertServerReservationIntoCache`. Also check whether this call is redundant after create.

Method: `isActionInProgress(for:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationNavigationRow`, `HostBoardReservationRow`, `ReservationDetailView`.
What user/business action does it represent? Disable UI for a reservation mutation already in progress.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `createReservation(_:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ManualReservationFormView` through closures from Today, Schedule, More, ImportFailures.
What user/business action does it represent? Staff creates a manual reservation or fixes a failed import by creating a managed reservation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/mutation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: `isCreatingReservation`, errors, notices, scope freshness.
What backend endpoint does it eventually use? `POST /managed-reservations`.
Is the name clear? Yes.

Method: `updateReservation(id:request:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ManualReservationFormView` (Home create), `ReservationEditFormView` closure, `TableAssignmentSheet` closures, `updateStatus`, hide/restore flows.
What user/business action does it represent? Staff updates reservation fields on the server.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/mutation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: action IDs, errors, notices, scope freshness.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}`.
Is the name clear? Yes.

Method: `updateStatus(reservation:status:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationNavigationRow`, `HostBoardView`, `ReservationDetailView`.
What user/business action does it represent? Seat, complete, cancel, no-show, or any status-only update.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow convenience.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly through `updateReservation`.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}`.
Is the name clear? Yes.

Important special case:
- Calling `updateStatus(..., status: .confirmed)` is **Confirm Only** (PATCH, no email).
- The primary confirm UI uses this path via `ReservationHostAction.confirmOnly`.

Method: `createAcceptedManualReservation(_:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `HomeDashboardView` manual create closure (accepted call-in reservations).
What user/business action does it represent? Staff adds a manual reservation already marked confirmed.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/mutation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: `isCreatingReservation`, errors, notices, scope freshness.
What backend endpoint does it eventually use? `POST /managed-reservations` with `status=confirmed`.
Is the name clear? Yes.

Method: `confirmReservation(reservation:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Row/detail/host board when staff chooses **Confirm + Email**.
What user/business action does it represent? Confirm reservation and send/attempt confirmation email.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: action IDs, errors, notices, scope freshness.
What backend endpoint does it eventually use? `POST /managed-reservations/{id}/confirm`.
Is the name clear? No. Suggested later name: `confirmReservationAndSendEmail`.

Critical note:
- Use **`confirmOnly`** / `updateStatus(..., .confirmed)` for PATCH confirm without email.
- This method is only for **Confirm + Email**.

Method: `loadHiddenReservations(context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Hidden Reservations screen refresh.
What user/business action does it represent? Load backend-hidden rows for archive view.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/API fetch wrapper.
Does it trigger network? Yes.
Does it write SwiftData? Yes, upserts returned rows.
Does it mutate controller/UI state? No directly.
What backend endpoint does it eventually use? `GET /managed-reservations?include_hidden=1`.
Is the name clear? Yes.

Method: `hideWrongEntry(reservation:reason:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ReservationDetailView`, `ReservationEditFormView`.
What user/business action does it represent? Soft-hide test/duplicate manual entry.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/mutation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: action IDs, errors, notices, scope freshness.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}` with `is_hidden=true`.
Is the name clear? Yes.

Method: `restoreHiddenReservation(reservation:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Hidden Reservations restore action.
What user/business action does it represent? Unhide a previously hidden reservation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/mutation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: action IDs, errors, notices, scope freshness.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}` with `is_hidden=false`.
Is the name clear? Yes.

Method: `loadRestaurantSetup(context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `RestaurantSettingsStore`, diagnostics tests.
What user/business action does it represent? Fetch restaurant setup config.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API fetch wrapper.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No directly.
What backend endpoint does it eventually use? `GET /restaurant-setup`.
Is the name clear? Yes.

Method: `updateRestaurantSetup(request:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `RestaurantSettingsStore.saveRestaurantSetup`.
What user/business action does it represent? Staff saves setup changes.
Does it trigger network? Yes.
What backend endpoint does it eventually use? `PATCH /restaurant-setup`.

Method: `loadRestaurantHours(from:to:)` / `updateRestaurantHours(request:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `RestaurantSettingsStore` weekly hours views.
What backend endpoint does it eventually use? `GET/PATCH /restaurant-hours`.

Method: `loadRestaurantDayAvailability(date:)` / `updateRestaurantDayAvailability(date:request:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `RestaurantSettingsStore`, Home availability.
What backend endpoint does it eventually use? `GET/PATCH /restaurant-day-availability?date=`.

Method: `loadReservationSlots(date:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Forms, settings, diagnostics.
What backend endpoint does it eventually use? `GET /reservation-slots?date=` (public, no auth).

Method: `loadRestaurantBlockedSlots(date:)` / `loadReservationAnalyticsSummary(from:to:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `RestaurantSettingsStore`, diagnostics.
What backend endpoint does it eventually use? `GET /restaurant-blocked-slots`, `GET /reservation-analytics/summary`.

Method: `refreshImportFailureCount(reason:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? No direct production call found; `perform*Refresh` calls `refreshImportFailureCountIfNeeded`.
What user/business action does it represent? Refresh the failed-form count.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow alias.
Does it trigger network? Yes, if freshness/capability guards allow.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: count/error/scope/notice.
What backend endpoint does it eventually use? `GET /managed-reservations/import-failures?page=1&per_page=1`.
Is the name clear? Yes.

Method: `refreshImportFailureCountIfNeeded(force:reason:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `performTodayRefresh`, `performScheduleWindowRefresh`, `performReviewQueuesRefresh`, `refreshImportFailureCount`.
What user/business action does it represent? Keep failed-form count reasonably fresh for manager/developer.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/helper.
Does it trigger network? Yes, if capability/freshness/busy guards allow.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `GET /managed-reservations/import-failures?page=1&per_page=1`.
Is the name clear? Yes.

Method: `fetchImportFailures(page:perPage:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `ImportFailuresView.loadFailures`.
What user/business action does it represent? Manager/developer opens failed import list.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Public workflow/API fetch wrapper.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: count/error/scope.
What backend endpoint does it eventually use? `GET /managed-reservations/import-failures`.
Is the name clear? Yes.

Method: `reconcileReservation(id:context:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `updateReservation` and `confirmReservation` after uncertain network failures.
What user/business action does it represent? Check server truth for one reservation after a possibly-applied mutation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Recovery helper.
Does it trigger network? Yes.
Does it write SwiftData? Yes, indirectly.
Does it mutate controller/UI state? Yes: scope state.
What backend endpoint does it eventually use? `GET /managed-reservations/{id}`.
Is the name clear? Yes.

Method: `clearErrorMessage()`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? No direct production call found.
What user/business action does it represent? Clear controller error.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `clearNoticeMessage()`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? No direct production call found.
What user/business action does it represent? Clear legacy notice message.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? None.
Is the name clear? The name is clear, but the state may be legacy.

Method: `clearImportFailureCountError()`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? No direct production call found.
What user/business action does it represent? Clear import failure count error.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `dismissNotice(_:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `AppNoticeOverlay`, `NoticeDetailRow`.
What user/business action does it represent? User dismisses one notice.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `clearAllNotices()`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `AppNoticeOverlay`, `DeveloperDiagnosticsView`.
What user/business action does it represent? User clears notice list.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `runAdminFetchTest(_:reservationID:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `DeveloperDiagnosticsView.run`.
What user/business action does it represent? Developer runs safe API diagnostics.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Developer-only workflow/API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: notices only.
What backend endpoint does it eventually use? GET-only: `/ping`, `/restaurant-setup`, `/restaurant-hours`, `/restaurant-day-availability`, `/reservation-slots`, `/reservation-analytics/summary`, `/managed-reservations`, `/managed-reservations/{id}`, `/managed-reservations/import-failures`.
Is the name clear? Yes.

Method: `todayScope()`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Controller refresh/scope helpers.
What user/business action does it represent? Build today's sync-scope key.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `scheduleWindow()`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Schedule refresh, scope helpers, diagnostics.
What user/business action does it represent? Defines the 30-day schedule fetch window.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? Used to build `GET /managed-reservations?from=&to=`.
Is the name clear? Yes.

Method: `scheduleScope()`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Schedule refresh helpers.
What user/business action does it represent? Build schedule sync-scope key.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `allowManualAttempt(for:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `requestManualTodayRefresh`.
What user/business action does it represent? Prevent refresh button spam.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: manual attempt timestamps.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `isScopeFresh(_:freshnessInterval:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Schedule, review, import count refreshes.
What user/business action does it represent? Skip non-forced fetches when data is fresh or in cooldown.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `beginScope(_:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? All scoped refresh/reconcile/count helpers.
What user/business action does it represent? Mark a scope as in-flight.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private sync-state helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: sync scope state/snapshots.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `markScopeSuccess(_:)`, `markScopeFailure(_:cooldown:)`, `markScopeCancelled(_:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Refresh/reconcile/import count methods.
What user/business action does it represent? Record result of a scoped operation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private sync-state helpers.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: sync scope state/snapshots.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `markScopeStale(_:)`, `markScopeRecentlyTouched(_:)`, `markScopesTouched(after:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Mutation and local-save paths.
What user/business action does it represent? Invalidate or refresh freshness after a reservation changes.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private sync-state helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: scope state/snapshots.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `publishSyncScopeSnapshots()`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Scope state helpers.
What user/business action does it represent? Publish sync scope state for diagnostics.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private UI/diagnostic helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `postRefreshFailureNotice(mode:error:)`, `postMutationFailureNotice(title:message:)`, `postNotice(...)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? Controller workflows.
What user/business action does it represent? User-visible feedback.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: notices/errors.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `clearScopedMessages(for:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `performTodayRefresh`.
What user/business action does it represent? Clear stale notices for a refresh source.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `errorLogCode(_:)`
File: `Tryzub Reservations/Import/ReservationsController.swift`
Who calls this? `postRefreshFailureNotice`.
What user/business action does it represent? Convert errors to compact notice/debug codes.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private diagnostic helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

## ReservationMutationService

File: `Tryzub Reservations/Services/ReservationMutationService.swift`

Method: `init(client:repository:)`
File: `Tryzub Reservations/Services/ReservationMutationService.swift`
Who calls this? `ReservationsController` mutation/reconcile methods.
What user/business action does it represent? Per-operation mutation service setup.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `updateReservation(id:request:)`
File: `Tryzub Reservations/Services/ReservationMutationService.swift`
Who calls this? `ReservationsController.updateReservation`.
What user/business action does it represent? Server-first reservation update.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service operation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, through repository upsert.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}`.
Is the name clear? Yes.

Method: `createReservation(_:)`
File: `Tryzub Reservations/Services/ReservationMutationService.swift`
Who calls this? `ReservationsController.createReservation`.
What user/business action does it represent? Server-first manual reservation creation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service operation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, through repository upsert.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? `POST /managed-reservations`.
Is the name clear? Yes.

Method: `confirmReservation(id:)`
File: `Tryzub Reservations/Services/ReservationMutationService.swift`
Who calls this? `ReservationsController.confirmReservation`.
What user/business action does it represent? Confirm reservation and send/attempt confirmation email.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service operation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, through repository upsert of `response.data`.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? `POST /managed-reservations/{id}/confirm`.
Is the name clear? No. Suggested later name: `confirmReservationAndSendEmail`.

Method: `reconcileReservation(id:)`
File: `Tryzub Reservations/Services/ReservationMutationService.swift`
Who calls this? `ReservationsController.reconcileReservation`.
What user/business action does it represent? Fetch server truth for one reservation after uncertain failure.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service recovery operation.
Does it trigger network? Yes.
Does it write SwiftData? Yes, through repository upsert.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? `GET /managed-reservations/{id}`.
Is the name clear? Yes.

## ReservationSyncService

File: `Tryzub Reservations/Import/ReservationImportService.swift`

Method: `init(client:repository:)`
File: `Tryzub Reservations/Import/ReservationImportService.swift`
Who calls this? `ReservationsController` refresh/cache methods.
What user/business action does it represent? Per-operation sync service setup.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes, but the file path says import and is stale.

Method: `syncAllReservations(reason:)`
File: `Tryzub Reservations/Import/ReservationImportService.swift`
Who calls this? No current production call found.
What user/business action does it represent? Fetch all managed reservations matching optional default filters.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service sync operation.
Does it trigger network? Yes.
Does it write SwiftData? Yes.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? Paged `GET /managed-reservations`.
Is the name clear? Yes.

Method: `syncToday(reason:)`
File: `Tryzub Reservations/Import/ReservationImportService.swift`
Who calls this? `ReservationsController.performTodayRefresh`.
What user/business action does it represent? Fetch today's reservations into cache.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service sync operation.
Does it trigger network? Yes.
Does it write SwiftData? Yes.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? `GET /managed-reservations?date=today&page=1&per_page=50`.
Is the name clear? Yes.

Method: `syncScheduleWindow(from:to:reason:)`
File: `Tryzub Reservations/Import/ReservationImportService.swift`
Who calls this? `ReservationsController.performScheduleWindowRefresh`.
What user/business action does it represent? Fetch 30-day schedule into cache.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service sync operation.
Does it trigger network? Yes.
Does it write SwiftData? Yes.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? Paged `GET /managed-reservations?from=&to=`.
Is the name clear? Yes.

Method: `syncReviewQueues(reason:)`
File: `Tryzub Reservations/Import/ReservationImportService.swift`
Who calls this? `ReservationsController.performReviewQueuesRefresh`.
What user/business action does it represent? Fetch reservations needing review/new attention.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service sync operation.
Does it trigger network? Yes.
Does it write SwiftData? Yes.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? `GET /managed-reservations?status=needs_review` and `GET /managed-reservations?status=new`.
Is the name clear? Mostly. Suggested later name if product language changes: `syncPendingReviewReservations`.

Method: `saveReservation(_:)`
File: `Tryzub Reservations/Import/ReservationImportService.swift`
Who calls this? `ReservationsController.save`.
What user/business action does it represent? Upsert a server DTO into local cache.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Persistence/cache service operation.
Does it trigger network? No.
Does it write SwiftData? Yes.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

## ImportFailureService

File: `Tryzub Reservations/Services/ImportFailureService.swift`

Method: `init(client:)`
File: `Tryzub Reservations/Services/ImportFailureService.swift`
Who calls this? `ReservationsController.refreshImportFailureCountIfNeeded`, `ReservationsController.fetchImportFailures`.
What user/business action does it represent? Per-operation import failure service setup.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `fetchImportFailures(page:perPage:reason:)`
File: `Tryzub Reservations/Services/ImportFailureService.swift`
Who calls this? `ReservationsController`.
What user/business action does it represent? Fetch failed public-form import records.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Service API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? `GET /managed-reservations/import-failures`.
Is the name clear? Yes.

## ReservationsAPIClient

File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`

Method: `init(baseURL:username:applicationPassword:session:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `Tryzub_ReservationsApp`; previews.
What user/business action does it represent? API client setup.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `fetchReservations(page:perPage:date:from:to:status:search:retryCount:reason:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? Sync service, controller diagnostics, protocol extension.
What user/business action does it represent? Fetch one page of managed reservations.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? `GET /managed-reservations`.
Is the name clear? Yes.

Method: `fetchAllReservations(perPage:date:from:to:status:search:reason:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `ReservationSyncService.syncAllReservations`, `syncScheduleWindow`.
What user/business action does it represent? Fetch all pages for a filter/window.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API operation.
Does it trigger network? Yes, possibly multiple GETs.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? Paged `GET /managed-reservations`.
Is the name clear? Yes.

Method: `fetchReservation(id:retryCount:reason:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `ReservationMutationService.reconcileReservation`, controller diagnostics.
What user/business action does it represent? Fetch one reservation by backend ID.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? `GET /managed-reservations/{id}`.
Is the name clear? Yes.

Method: `updateReservation(id:request:reason:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `ReservationMutationService.updateReservation`.
What user/business action does it represent? PATCH reservation changes to backend.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}`.
Is the name clear? Yes.

Method: `createReservation(_:reason:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `ReservationMutationService.createReservation`.
What user/business action does it represent? Create manual managed reservation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? `POST /managed-reservations`.
Is the name clear? Yes.

Method: `confirmReservation(id:reason:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `ReservationMutationService.confirmReservation`.
What user/business action does it represent? Call backend confirm/email workflow.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? `POST /managed-reservations/{id}/confirm`.
Is the name clear? No. Suggested later name: `confirmReservationAndSendEmail`.

Method: `fetchImportFailures(page:perPage:reason:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `ImportFailureService`, controller diagnostics.
What user/business action does it represent? Fetch failed import diagnostics.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? `GET /managed-reservations/import-failures`.
Is the name clear? Yes.

Method: `managedReservationsURL()`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? API client methods.
What user/business action does it represent? Build managed reservations base endpoint.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private API helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? `/managed-reservations`.
Is the name clear? Yes.

Method: `makeURL(path:queryItems:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `fetchImportFailures`.
What user/business action does it represent? Build URL with query.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private API helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? Any caller-specific endpoint.
Is the name clear? Yes.

Method: `makeRequest(url:method:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? API client GET/POST helpers.
What user/business action does it represent? Build authenticated JSON request.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private API helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? Caller-specific.
Is the name clear? Yes.

Method: `makeJSONRequest(url:method:body:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `updateReservation`, `createReservation`.
What user/business action does it represent? Build authenticated JSON request with encoded body.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private API helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}` or `POST /managed-reservations`.
Is the name clear? Yes.

Method: `makeAuthHeader()`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `makeRequest`.
What user/business action does it represent? Create Basic auth header.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private API helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? All API endpoints.
Is the name clear? Yes.

Method: `perform(_:retryCount:reason:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? All API operation methods.
What user/business action does it represent? Execute request, validate response, log, retry transient errors if requested.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private API operation.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? Caller-specific.
Is the name clear? Yes.

Method: `validate(response:data:)`
File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`
Who calls this? `perform`.
What user/business action does it represent? Convert HTTP status/body to success or `ReservationAPIError`.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private API helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? Caller-specific.
Is the name clear? Yes.

## ReservationRepository

File: `Tryzub Reservations/Services/ReservationRepository.swift`

Method: `init(context:)`
File: `Tryzub Reservations/Services/ReservationRepository.swift`
Who calls this? `ReservationsController`.
What user/business action does it represent? Per-operation repository setup for SwiftData context.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Persistence setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `latestLocalSyncDate()`
File: `Tryzub Reservations/Services/ReservationRepository.swift`
Who calls this? `ReservationsController.loadIfNeeded`.
What user/business action does it represent? Show whether cache has prior sync data.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Persistence operation.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `upsert(_ reservation:)`
File: `Tryzub Reservations/Services/ReservationRepository.swift`
Who calls this? Services.
What user/business action does it represent? Save one server DTO into cache.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Persistence operation.
Does it trigger network? No.
Does it write SwiftData? Yes.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `upsert(_ reservations:)`
File: `Tryzub Reservations/Services/ReservationRepository.swift`
Who calls this? `upsert(_ reservation:)`, sync/mutation services.
What user/business action does it represent? Save server DTOs into cache keyed by remote ID.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Persistence operation.
Does it trigger network? No.
Does it write SwiftData? Yes.
Does it mutate controller/UI state? No direct controller state mutation.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

## Main Views

### ReservationsListView

Method: `init(environment:)`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `Tryzub_ReservationsApp`.
What user/business action does it represent? Root reservation UI setup.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Creates `ReservationsController`.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Root tabs, notice overlay, initial load task.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition.
Does it trigger network? Yes, via `.task` calling `loadIfNeeded`.
Does it write SwiftData? Indirectly through initial load.
Does it mutate controller/UI state? Yes, selected tab and controller lifecycle.
What backend endpoint does it eventually use? Initial `GET /managed-reservations?date=today`.
Is the name clear? SwiftUI standard.

Method: `visibleNotices`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `body`.
What user/business action does it represent? Scope notices by current tab.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

### HomeDashboardView

Method: `todayReservations`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `body`.
What user/business action does it represent? Show today's cached reservations.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Home tab, manual create, failed imports, manual refresh.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Yes, through refresh/create/import-failure actions.
Does it write SwiftData? Indirectly through controller create/refresh/save.
Does it mutate controller/UI state? Yes: sheet state and controller state via calls.
What backend endpoint does it eventually use? `GET /managed-reservations?date=today`, `POST /managed-reservations`, `GET /managed-reservations/import-failures`.
Is the name clear? SwiftUI standard.

### ReservationScheduleView

Method: `displayedReservations`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `sections`, `body`.
What user/business action does it represent? Local schedule filtering/search.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `sections`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `body`.
What user/business action does it represent? Group displayed reservations by date.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Schedule tab, activation refresh, manual refresh, create reservation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Yes, through activation/manual refresh/create.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes: search/scope/sheet state and controller state via calls.
What backend endpoint does it eventually use? `GET /managed-reservations?from=&to=`, `POST /managed-reservations`.
Is the name clear? SwiftUI standard.

### ReservationReviewQueueView

Method: `queueReservations`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `body`.
What user/business action does it represent? Local filter for New or Needs Review queue.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Mostly. Suggested later name if queue becomes combined: `pendingReviewReservations`.

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Review tab, activation refresh, manual refresh, row actions.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Yes, through activation/manual refresh and row mutations.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes: scope/search and controller state via calls.
What backend endpoint does it eventually use? `GET /managed-reservations?status=needs_review`, `GET /managed-reservations?status=new`, row mutation endpoints.
Is the name clear? SwiftUI standard.

Method: `reviewContext(for:)`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `body` when building review rows.
What user/business action does it represent? Show booking pressure context for a pending reservation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

### ReservationMoreView

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? More tab operations and diagnostics navigation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Not directly; child views/actions do.
Does it write SwiftData? Indirectly through manual create/import fix.
Does it mutate controller/UI state? Yes: sheet state and controller calls through child closures.
What backend endpoint does it eventually use? `POST /managed-reservations`, `GET /managed-reservations/import-failures`, diagnostics GETs.
Is the name clear? SwiftUI standard.

### ReservationNavigationRow

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? Schedule and Review lists.
What user/business action does it represent? Row display plus actions/navigation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Yes, through action handlers.
Does it write SwiftData? Indirectly through controller mutations.
Does it mutate controller/UI state? Yes: local pending action/sheet/detail state and controller mutation state.
What backend endpoint does it eventually use? `POST /managed-reservations/{id}/confirm`, `PATCH /managed-reservations/{id}`.
Is the name clear? Yes.

Method: `availableActions`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `body`.
What user/business action does it represent? Determine allowed row actions.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `handleAction(_:)`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? Buttons, context menu, swipe actions.
What user/business action does it represent? Route selected row action.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Sometimes, by starting `perform`.
Does it write SwiftData? Indirectly when `perform` runs.
Does it mutate controller/UI state? Yes: pending dialog/table sheet and controller calls.
What backend endpoint does it eventually use? Confirm endpoint or PATCH endpoint depending on action.
Is the name clear? Yes.

Method: `perform(_:)`
File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
Who calls this? `handleAction`, confirmation dialog.
What user/business action does it represent? Execute selected row action.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Yes for confirm/status updates.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `POST /managed-reservations/{id}/confirm` for confirm; `PATCH /managed-reservations/{id}` for seat/cancel/complete/no-show/table.
Is the name clear? Yes.

Confirm routing:
- `.confirmOnly` → `updateStatus(..., .confirmed)` (PATCH, no email).
- `.confirmAndSendEmail` → `confirmReservation` (POST `/confirm`).

### HostBoardView

Method: `body`
File: `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Today board layout, auto-refresh task, action dialogs/sheets.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Yes, through auto refresh and action handlers.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes: local board state and controller state via calls.
What backend endpoint does it eventually use? Today GET, confirm POST, update PATCH.
Is the name clear? SwiftUI standard.

Method: `warningArea(snapshot:)`
File: `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
Who calls this? `body`.
What user/business action does it represent? Show form/review/no-table warnings.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `wideBoard(snapshot:)`, `compactBoard(snapshot:)`, `compactReservations(from:)`
File: `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
Who calls this? `body`.
What user/business action does it represent? Responsive host-board presentation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helpers.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No, except compact picker state is read by `compactReservations`.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `handleAction(_:reservation:)`
File: `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
Who calls this? `HostBoardColumn` / `HostBoardReservationRow`.
What user/business action does it represent? Route board action to table sheet, confirmation dialog, or mutation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Sometimes, by starting `perform`.
Does it write SwiftData? Indirectly when `perform` runs.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? Confirm endpoint or PATCH endpoint depending on action.
Is the name clear? Yes.

Method: `perform(_:on:)`
File: `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
Who calls this? `handleAction`, confirmation dialog.
What user/business action does it represent? Execute board action.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Yes for confirm/status updates.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? `POST /managed-reservations/{id}/confirm` for confirm; `PATCH /managed-reservations/{id}` for status/table.
Is the name clear? Yes.

Confirm routing:
- `.confirmOnly` → `updateStatus(..., .confirmed)` (PATCH, no email).
- `.confirmAndSendEmail` → `confirmReservation` (POST `/confirm`).

Method: `runAutoRefreshLoop()`
File: `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
Who calls this? `HostBoardView.task(id: isVisible && isAppActive)`.
What user/business action does it represent? Passive Today refresh while host board is active.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Private lifecycle helper.
Does it trigger network? Yes, through controller if allowed.
Does it write SwiftData? Indirectly.
Does it mutate controller/UI state? Yes, through controller.
What backend endpoint does it eventually use? `GET /managed-reservations?date=today&page=1&per_page=50`.
Is the name clear? Yes.

### HostBoardSnapshot

Method: `init(reservations:)`
File: `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
Who calls this? `HostBoardView.body`.
What user/business action does it represent? Build board buckets/counts from cached today rows.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI data helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

### ReservationRowView

Method: `init(...)`
File: `Tryzub Reservations/Features/Reservations/ReservationRowView.swift`
Who calls this? `ReservationNavigationRow`, `HostBoardReservationRow`, previews.
What user/business action does it represent? Row UI setup.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ReservationRowView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Render compact/wide reservation row.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? SwiftUI standard.

Method: `shortDateLabel(from:)`, `tableText`, `isMuted`, `rowBackground`, `rowStroke`
File: `Tryzub Reservations/Features/Reservations/ReservationRowView.swift`
Who calls this? `ReservationRowView`.
What user/business action does it represent? Row presentation formatting.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helpers.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

### ReservationActionButtons

Method: `ReservationHostAction.availableActions(for:capabilities:includeSecondary:)`
File: `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift`
Who calls this? `ReservationActionButtons.actions`, row context menus.
What user/business action does it represent? Determine available staff actions by status/capability.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI/business helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None directly.
Is the name clear? Yes.

Method: `ReservationHostAction.dialogTitle(for:)`, `dialogMessage(for:)`
File: `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift`
Who calls this? Confirmation dialogs in rows/detail/host board.
What user/business action does it represent? Explain action before staff commits.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `ReservationActionButtons.body`
File: `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Render action buttons/menu.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition.
Does it trigger network? No directly; calls `onAction` on tap.
Does it write SwiftData? No directly.
Does it mutate controller/UI state? Mutates local `pendingInlineAction`.
What backend endpoint does it eventually use? Depends on parent action handling.
Is the name clear? SwiftUI standard.

Method: `actionButton(_:compact:isPrimary:)`, `title(for:compact:)`, `handleTap(_:)`, `accessibilityLabel(for:)`
File: `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift`
Who calls this? `ReservationActionButtons`.
What user/business action does it represent? Button presentation and inline confirmation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helpers.
Does it trigger network? `handleTap` can call `onAction`, which may trigger network in parent.
Does it write SwiftData? No directly.
Does it mutate controller/UI state? Mutates local `pendingInlineAction`.
What backend endpoint does it eventually use? Depends on parent action handling.
Is the name clear? Yes.

Confirm routing:
- **Confirm Only** and **Confirm + Email** are separate actions with distinct dialogs.
- Inline compact buttons may show both when status is `new` or `needs_review`.

Method: `TableAssignmentSheet.save()`
File: `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift`
Who calls this? Save toolbar button in `TableAssignmentSheet`.
What user/business action does it represent? Staff saves table assignment.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Yes, through `onSave` closure.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes: local saving/error state; controller state through closure.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}`.
Is the name clear? Yes.

### ReservationDetailView

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ReservationDetailView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Reservation detail screen, edit/action sheets/dialogs.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Yes, through action/edit/table closures.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes: local sheet/action/error state and controller state through calls.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}`, `POST /managed-reservations/{id}/confirm`.
Is the name clear? SwiftUI standard.

Method: `detailContent(isWide:)`
File: `Tryzub Reservations/Features/Reservations/ReservationDetailView.swift`
Who calls this? `body`.
What user/business action does it represent? Responsive detail layout.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `handleAction(_:)`
File: `Tryzub Reservations/Features/Reservations/ReservationDetailView.swift`
Who calls this? `ReservationHeroCard` action buttons.
What user/business action does it represent? Route detail action to table sheet, confirmation dialog, or mutation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Sometimes, by starting `perform`.
Does it write SwiftData? Indirectly when `perform` runs.
Does it mutate controller/UI state? Yes.
What backend endpoint does it eventually use? Confirm endpoint or PATCH endpoint depending on action.
Is the name clear? Yes.

Method: `perform(_:allowSeatWithoutTable:)`
File: `Tryzub Reservations/Features/Reservations/ReservationDetailView.swift`
Who calls this? `handleAction`, confirmation dialog.
What user/business action does it represent? Execute detail quick action.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Yes for confirm/status updates.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes: local saving/action state and controller state.
What backend endpoint does it eventually use? `POST /managed-reservations/{id}/confirm` for confirm; `PATCH /managed-reservations/{id}` for status/table.
Is the name clear? Yes.

Confirm routing:
- `.confirmOnly` → `updateStatus(..., .confirmed)` (PATCH, no email).
- `.confirmAndSendEmail` → `confirmReservation` (POST `/confirm`).

### ReservationEditFormView

Method: `init(reservation:onSave:onHide:)`
File: `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift`
Who calls this? `ReservationDetailView` edit sheet.
What user/business action does it represent? Seed edit form from current record; wire save and hide callbacks.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI setup.
Does it trigger network? No directly.
Does it write SwiftData? No directly.
Does it mutate controller/UI state? Mutates local form state.
What backend endpoint does it eventually use? Save → PATCH; Hide → PATCH `is_hidden=true`.
Is the name clear? Yes.

Method: `save()` / save confirmation flow
File: `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift`
Who calls this? Edit form Save toolbar button.
What user/business action does it represent? Staff reviews old → new field diff, then PATCHes if changed.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Yes, through `onSave` after confirmation.
Does it write SwiftData? Indirectly through controller.
What backend endpoint does it eventually use? `PATCH /managed-reservations/{id}`.
Is the name clear? Yes.

Shared with create: `ReservationFormContent`, `ReservationFormDraft`, slot loading via `RestaurantSettingsStore.ensureDateOperations`.

Method: `init(failure:onCreateReservation:)`
File: `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift`
Who calls this? Home, Schedule, More, ImportFailureDetail.
What user/business action does it represent? Seed manual reservation form, optionally from a failed import.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI setup.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Mutates local form state.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Manual create form with review confirmation before POST.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Yes, through Save → confirmation alert → `createAcceptedManualReservation` or `createReservation`.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes: local form/saving/error state and controller state through closure.
What backend endpoint does it eventually use? `POST /managed-reservations`.
Is the name clear? Yes.

Method: `createReservation()`
File: `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift`
Who calls this? Create toolbar button.
What user/business action does it represent? Validate form and submit manual create request.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Yes, through `onCreateReservation`.
Does it write SwiftData? Indirectly through controller.
Does it mutate controller/UI state? Yes: local saving/error state; controller state through closure.
What backend endpoint does it eventually use? `POST /managed-reservations`.
Is the name clear? Yes.

Method: `parseDate`, `parseTime`, `formatDate`, `formatTime`
File: `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift`
Who calls this? Manual form init/create.
What user/business action does it represent? Convert failed-import/form date-time values to backend strings and back.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI/data formatting helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None, but output is sent to POST.
Is the name clear? Yes.

### ImportFailuresView

Method: `body`
File: `Tryzub Reservations/Features/Reservations/ImportFailuresView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Failed imports list and navigation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Yes, through `.task`, `.refreshable`, toolbar refresh.
Does it write SwiftData? No directly; create-fixed flow writes through manual create.
Does it mutate controller/UI state? Yes: local loading/error/failures and controller import count.
What backend endpoint does it eventually use? `GET /managed-reservations/import-failures`, and create flow uses `POST /managed-reservations`.
Is the name clear? Yes.

Method: `loadFailures()`
File: `Tryzub Reservations/Features/Reservations/ImportFailuresView.swift`
Who calls this? `.task`, `.refreshable`, toolbar refresh.
What user/business action does it represent? Load failed form-import records.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI workflow helper.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: local loading/error/failures and controller import count.
What backend endpoint does it eventually use? `GET /managed-reservations/import-failures`.
Is the name clear? Yes.

Method: `ImportFailureDetailView.body`
File: `Tryzub Reservations/Features/Reservations/ImportFailuresView.swift`
Who calls this? SwiftUI after selecting a failed import.
What user/business action does it represent? Inspect failed import and create fixed reservation.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? Only through nested manual create link/closure.
Does it write SwiftData? Indirectly through create flow.
Does it mutate controller/UI state? Indirectly through create flow.
What backend endpoint does it eventually use? `POST /managed-reservations` if fixed reservation is created.
Is the name clear? SwiftUI standard.

### DeveloperDiagnosticsView

Method: `body`
File: `Tryzub Reservations/Features/Reservations/DeveloperDiagnosticsView.swift`
Who calls this? SwiftUI.
What user/business action does it represent? Developer diagnostics dashboard.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Developer UI composition.
Does it trigger network? Only through explicit test buttons.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: local test state and notices/log store.
What backend endpoint does it eventually use? GET-only diagnostics endpoints.
Is the name clear? SwiftUI standard.

Method: `run(_:)`
File: `Tryzub Reservations/Features/Reservations/DeveloperDiagnosticsView.swift`
Who calls this? Diagnostic test buttons.
What user/business action does it represent? Developer runs one safe GET test.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Developer workflow helper.
Does it trigger network? Yes.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes: local result state and controller notices.
What backend endpoint does it eventually use? `GET /managed-reservations`, `GET /managed-reservations/{id}`, or `GET /managed-reservations/import-failures`.
Is the name clear? Yes.

Method: `didCallManualImportEndpoint`
File: `Tryzub Reservations/Features/Reservations/DeveloperDiagnosticsView.swift`
Who calls this? Endpoint checklist section.
What user/business action does it represent? Check if forbidden import endpoint appeared in logs.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Developer diagnostic helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

### AppNoticeOverlay

Method: `body`
File: `Tryzub Reservations/Features/Reservations/AppNoticeOverlay.swift`
Who calls this? SwiftUI from `ReservationsListView`.
What user/business action does it represent? Show latest notice, auto-dismiss, open notice list.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI composition/workflow trigger.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Yes, through dismiss/clear callbacks.
What backend endpoint does it eventually use? None.
Is the name clear? SwiftUI standard.

Method: `NoticeDetailRow.body`
File: `Tryzub Reservations/Features/Reservations/AppNoticeOverlay.swift`
Who calls this? App notice list and diagnostics notice section.
What user/business action does it represent? Render one notice with optional dismiss button.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? Through optional dismiss callback only.
What backend endpoint does it eventually use? None.
Is the name clear? SwiftUI standard.

## Presentation Helpers

File: `Tryzub Reservations/Features/Reservations/ReservationPresentation.swift`

Method: `Date.reservationDateString()` / `Date.reservationDateString()`
File: `Tryzub Reservations/Features/Reservations/ReservationPresentation.swift`
Who calls this? Controller scopes/fetches, record presentation/status helpers.
What user/business action does it represent? Create backend/local date key for today.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? Formatting helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? Used in query params for today fetches.
Is the name clear? Yes.

Method: `ReservationRecord.matchesSearch(_:)`
File: `Tryzub Reservations/Features/Reservations/ReservationPresentation.swift`
Who calls this? Schedule and Review search filters.
What user/business action does it represent? Local cached search by guest/contact/table/notes.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

Method: `ReservationRecord.sortedChronologically`, `sortedForHostBoard`, `sortedNewestFirst`, `sortedByCreatedAtAscending`, `dateSections`
File: `Tryzub Reservations/Features/Reservations/ReservationPresentation.swift`
Who calls this? Home, Schedule, Review, HostBoard.
What user/business action does it represent? Restaurant-facing row ordering/grouping.
Is it public workflow, private helper, API operation, persistence operation, or UI helper? UI/business helper.
Does it trigger network? No.
Does it write SwiftData? No.
Does it mutate controller/UI state? No.
What backend endpoint does it eventually use? None.
Is the name clear? Yes.

## RestaurantSettingsStore

File: `Tryzub Reservations/Features/Reservations/RestaurantSettingsStore.swift`

Central store for restaurant configuration UI and date-scoped slot/availability loading. Delegates network calls to `ReservationsController` / `ReservationsAPIClient`.

Key methods:
- `loadInitialSettings()` — bootstrap setup on More → Settings open.
- `loadRestaurantSetup()` / `saveRestaurantSetup()` — GET/PATCH setup.
- `loadRestaurantHours()` / `saveRestaurantHours()` — weekly hours.
- `loadDayAvailability(date:)` / `saveDayAvailability(date:)` — per-day overrides.
- `loadReservationSlots(date:)` — slot preview for forms and blocked-slots UI.
- `loadBlockedSlots(date:)` / `blockSlots` / `unblockSlots` / `unblockAllSlots` — blocked time management.
- `ensureDateOperations(date:force:)` — owns slot + availability load lifecycle (prevents stuck spinners on date change).
- `loadReservationAnalyticsSummary(from:to:)` — business analytics chart data.
- `suggestedServiceDates`, `suggestedTimes`, `defaultServiceSlot` — form defaults.

Embedded views: `RestaurantSettingsView`, `WeeklyHoursView`, `TodayAvailabilityView`, `BlockedTimeSlotsView`, `BusinessAnalyticsView`.

## GuestInsights (read-only, cache-only)

Files: `Tryzub Reservations/Features/GuestInsights/`

No network calls. Derives guest memory from cached `ReservationRecord` rows.

Key types:
- `GuestInsightsController` — builds insights for a guest identity.
- `GuestIdentityResolver` — matches phone/email/name across reservations.
- `GuestReservationIntentDeduper` — dedupes repeat booking intents.
- `RegularGuestsController` / `RegularGuestsView` — More → Guest Memory list.
- `GuestInsightsView` — detail preview card + full insights (Swift Charts preferences, visit history, warnings).

Entry points: More → Guest Memory; reservation Detail → guest insights preview card.
