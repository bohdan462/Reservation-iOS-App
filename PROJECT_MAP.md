# Tryzub Reservations Project Map

This is a one-restaurant internal iOS app. The WordPress plugin REST API is the source of truth. SwiftData is a local cache. The app reads managed reservations, creates manual reservations, PATCHes staff updates, confirms with or without email, soft-hides test/duplicate rows, and manages restaurant setup/hours/slots through protected endpoints. The iOS app must not call `POST /managed-reservations/import` during normal workflow.

**REST base:** `https://tryzubchicago.com/wp-json/tryzub/v1`

---

## 0. Current App Structure (2026)

### Source tree

```
Tryzub Reservations/
├── Tryzub_ReservationsApp.swift       # Entry, credentials gate, SwiftData container
├── App/
│   ├── AppCredentials.swift           # AppCredentialStore (env + Keychain)
│   ├── AppEnvironment.swift           # apiClient, role, AppCapabilities
│   └── AppNotice.swift
├── Core/Roles/AppUserRole.swift       # staff | manager | developer
├── Features/
│   ├── GuestInsights/                 # Read-only guest memory (6 files)
│   │   ├── GuestInsightsController.swift
│   │   ├── GuestInsightsModels.swift
│   │   ├── GuestInsightsView.swift    # Swift Charts preferences
│   │   ├── GuestIdentityResolver.swift
│   │   ├── GuestReservationIntentDeduper.swift
│   │   ├── RegularGuestsController.swift
│   │   └── RegularGuestsView.swift    # More → Guest Memory
│   └── Reservations/                  # Main UI (18 files)
│       ├── ReservationsListView.swift # Tab shell: Home · List · Review · More
│       ├── HostBoardView.swift        # Home service dashboard + ServiceLoadChart
│       ├── ReservationDetailView.swift
│       ├── ManualReservationFormView.swift  # Create + ReservationEditFormView
│       ├── ReservationRowView.swift
│       ├── ReservationSharedUI.swift  # Design tokens, charts, shared components
│       ├── ReservationActionButtons.swift
│       ├── ReservationPresentation.swift
│       ├── RestaurantSettingsStore.swift    # Setup, hours, availability, blocked slots, analytics
│       ├── DeveloperDiagnosticsView.swift
│       ├── ImportFailuresView.swift
│       ├── ReservationFloatingTabBar.swift
│       ├── HiddenReservationsStore.swift
│       └── …
├── Import/
│   ├── ReservationsController.swift   # Workflow coordinator
│   └── ReservationImportService.swift # ReservationSyncService (file name is legacy)
├── Network/
│   ├── ReservationsAPIClient.swift
│   ├── ReservationDTO.swift
│   ├── ReservationsResponse.swift
│   ├── ReservationAPIError.swift      # ReservationAPIDiagnostics
│   └── APIRequestLogStore.swift
├── Persistence/ReservationRecord.swift
├── Preview/ReservationPreviewData.swift
└── Services/
    ├── ReservationRepository.swift
    ├── ReservationMutationService.swift
    └── ImportFailureService.swift
```

### Tab shell — `ReservationsListView`

| Tab | Label | Primary view | Notes |
| --- | --- | --- | --- |
| `.home` | Home | `HomeDashboardView` → `HostBoardView` | Date picker, stats + chart, seated/upcoming lists |
| `.schedule` | List | `ReservationScheduleView` | Upcoming window or paginated All + search |
| `.review` | Review | `ReservationReviewQueueView` | Default **Pending** = `new` + `needs_review`, oldest first |
| `.more` | More | `ReservationMoreView` | Settings, analytics, guest memory, diagnostics |

All four tabs stay **mounted** (opacity / hit-testing toggle) to avoid tab-switch lag.

### Key screens

| Screen | File | Purpose |
| --- | --- | --- |
| Home dashboard | `HostBoardView.swift` | Service stats, guests-by-time chart, seated + reservation previews |
| Detail | `ReservationDetailView.swift` | Layered cards: hero, actions, contact, notes, metadata, service load, guest insights |
| Edit | `ManualReservationFormView.swift` | `ReservationEditFormView` — save diff confirmation, hide button |
| New manual | `ManualReservationFormView.swift` | Create with review confirmation before POST |
| Guest insights | `GuestInsightsView.swift` | Preferences charts, history, warnings (cache only) |
| Restaurant settings | `RestaurantSettingsStore.swift` | Setup, weekly hours, today availability, blocked slots |
| Business analytics | `RestaurantSettingsStore.swift` | `GET /reservation-analytics/summary` |
| Developer diagnostics | `DeveloperDiagnosticsView.swift` | Full API log, endpoint checklist, safe GET tests |
| Hidden reservations | `ReservationsListView.swift` | Archive of soft-hidden rows |

### Shared UI — `ReservationSharedUI.swift`

- **Tokens:** `TryzubColors`, `TryzubTypography`, `TryzubSpacing`, `ReservationLayout`, `ReservationUIStyle`
- **Charts (Swift Charts):** `ServiceLoadChart`, `ServiceTimeline` / `ServiceTimelineSlot`
- **Components:** `TryzubSectionCard`, `ReservationServiceCard`, `ReservationChoiceChip`, `BottomSafeActionBar`, `ReservationFormChangeReview`
- **Slot grids:** `ReservationSlotGridStyle` — consistent chip spacing app-wide

### Confirm semantics (staff actions)

| UI action | Controller / API | Email |
| --- | --- | --- |
| **Confirm Only** | `updateStatus(.confirmed)` → PATCH | No |
| **Confirm + Email** | `confirmReservation` → POST `/confirm` | Yes (backend) |
| Manual add (Home) | `createAcceptedManualReservation` → POST | No |

### Hide reservation

- PATCH `is_hidden=true` via `hideWrongEntry` / `restoreHiddenReservation`
- `HiddenReservationsStore` filters lists; **More → Hidden Reservations** for archive
- Available in Detail (More menu) and Edit form (Hide button)

### Restaurant API endpoints (protected unless noted)

| Method | Path | Used by |
| --- | --- | --- |
| GET | `/ping` | Diagnostics (no auth) |
| GET/PATCH | `/restaurant-setup` | Controller, settings |
| GET/PATCH | `/restaurant-hours` | Settings |
| GET/PATCH | `/restaurant-day-availability?date=` | Settings, Home availability |
| GET | `/reservation-slots?date=` | Public; forms + settings preview (no auth) |
| GET/POST/DELETE | `/restaurant-blocked-slots` | Settings |
| GET | `/reservation-analytics/summary` | Business analytics |
| GET/PATCH/POST | `/managed-reservations` … | Controller (reservations CRUD) |
| POST | `/managed-reservations/{id}/confirm` | Confirm + email only |
| GET | `/managed-reservations/import-failures` | Import failures |

---

## 1. App Startup / Dependency Setup

### Entry Point

`Tryzub Reservations/Tryzub_ReservationsApp.swift`

- `Tryzub_ReservationsApp` owns `@StateObject private var credentialStore = AppCredentialStore()`.
- The SwiftData container is attached at the scene level with `.modelContainer(for: ReservationRecord.self)`.
- If credentials exist, the app creates `ReservationsListView(environment:)`.
- If credentials are missing, it shows `CredentialsSetupView`.

### Credentials

`Tryzub Reservations/App/AppCredentials.swift`

- `AppCredentialStore` first checks environment variables:
  - `TRYZUB_API_USERNAME`
  - `TRYZUB_API_PASSWORD`
- If environment credentials are missing, it loads from Keychain.
- Saved credentials are stored in the device Keychain using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

### AppEnvironment

`Tryzub Reservations/App/AppEnvironment.swift`

`AppEnvironment` is created in `Tryzub_ReservationsApp.swift` after credentials are available:

- `apiClient`: `ReservationsAPIClient`
- `role`: currently hardcoded to `.developer`
- `capabilities`: derived from `AppCapabilities.capabilities(for: role)`

Brutally practical note: role/capabilities are probably more structure than this MVP needs, but they do keep diagnostics and failed import tools out of staff mode if the role is changed later.

### API Client

Created in `Tryzub_ReservationsApp.swift`:

- Base URL: `https://tryzubchicago.com/wp-json/tryzub/v1`
- Auth: WordPress username + application password
- Concrete type: `ReservationsAPIClient`
- Exposed through protocol: `ReservationsAPIClientProtocol`

The API client is shared by being stored in `AppEnvironment`. It is not recreated per request.

### SwiftData

`ReservationRecord` is the only SwiftData model configured in the app scene.

SwiftData is cache only. It should not be treated as source of truth or as proof that a mutation succeeded.

### Controller Injection

`Tryzub Reservations/Features/Reservations/ReservationsListView.swift`

- `ReservationsListView.init(environment:)` creates `@StateObject ReservationsController(environment:)`.
- The controller is injected into child views using `.environmentObject(controller)`.
- Child views read SwiftData with `@Query` and call controller workflow methods.

### Shared Globally

- `AppCredentialStore`: app-scoped credential state.
- `AppEnvironment`: value passed into root and some child views.
- `ReservationsAPIClient`: one shared API client inside `AppEnvironment`.
- `ReservationsController`: one root `@StateObject` under `ReservationsListView`.
- SwiftData `ModelContainer` / environment `ModelContext`.
- `APIRequestLogStore.shared`: singleton debug request log.

### Created Per Operation

These are created repeatedly inside controller methods:

- `ReservationRepository(context:)`
- `ReservationSyncService(client:repository:)`
- `ReservationMutationService(client:repository:)`
- `ImportFailureService(client:)`
- `URLRequest`

That is acceptable for the MVP. The per-operation services are thin wrappers; the real shared dependency is the API client.

## 2. Screen Layer

### ReservationsListView

File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`

Purpose:
- Root reservation UI.
- Owns the tab selection.
- Creates and injects `ReservationsController`.
- Shows the global `AppNoticeOverlay`.

Data read:
- `selectedTab`
- `controller.notices`
- `modelContext`

Controller calls:
- `.task`: `controller.loadIfNeeded(context:)`
- Overlay callbacks: `dismissNotice`, `clearAllNotices`

Lifecycle / triggers:
- `.task` runs initial load once through the controller guard.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing shell.

### TodayDashboardView → HomeDashboardView

File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift` (`HomeDashboardView`)

Purpose:
- Home tab container.
- Queries cached reservations for the selected service date and passes rows to `HostBoardView`.
- Presents manual reservation and failed import sheets.

Data read:
- `@Query` all `ReservationRecord`, sorted by date/time.
- Filters with `reservation.isToday`.
- Controller state: `lastSyncedAt`, `isSyncing`, `importFailureCount`, `capabilities`.
- `scenePhase`.

Controller calls:
- `.refreshable`: `requestManualTodayRefresh(context:)`
- Toolbar refresh: `requestManualTodayRefresh(context:)`
- Manual create sheet: `createReservation(_:context:)`
- Failed import create path: `createReservation(_:context:)`
- Failed import `onCreated`: `save(_:context:)`

Lifecycle / triggers:
- Pull to refresh.
- Toolbar refresh button.
- Manual create button.
- Failed imports button.
- Sheets for manual reservation and import failures.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing. Failed imports should be manager/developer only, already controlled by capabilities.

### ReservationScheduleView

File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`

Purpose:
- Schedule tab.
- Shows upcoming/all cached reservations, grouped by date.
- Supports local search.

Data read:
- `@Query` all `ReservationRecord`.
- `scope`: upcoming/all.
- `searchText`.
- Controller state: `isSyncing`, `capabilities`.

Controller calls:
- `.task(id: isActive)`: `scheduleBecameActive(context:)`
- `.refreshable`: `requestScheduleRefresh(context:)`
- Toolbar refresh: `requestScheduleRefresh(context:)`
- Manual create sheet: `createReservation(_:context:)`

Lifecycle / triggers:
- Schedule tab activation.
- Pull to refresh.
- Toolbar refresh.
- Create button.
- Search changes filter locally only.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing.

### ReservationReviewQueueView

File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`

Purpose:
- Review tab for `new` and `needs_review` records.
- Uses segmented scope rather than one combined "New/Pending" queue.

Data read:
- `@Query` all `ReservationRecord`.
- `scope`: `.new` or `.needsReview`.
- `searchText`.

Controller calls:
- `.task(id: isActive)`: `reviewBecameActive(context:)`
- `.refreshable`: `requestReviewRefresh(context:)`
- Toolbar refresh: `requestReviewRefresh(context:)`

Lifecycle / triggers:
- Review tab activation.
- Pull to refresh.
- Toolbar refresh.
- Search changes filter locally only.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing, but the current split queue may not match the desired "New/Pending" workflow.

### ReservationMoreView

File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`

Purpose:
- Secondary operations: manual create, failed imports, diagnostics, duplicate-resolution instructions.

Data read:
- Controller capabilities.

Controller calls:
- Manual create: `createReservation(_:context:)`
- Failed imports path: `fetchImportFailures`, `createReservation`, `save`

Lifecycle / triggers:
- Button opens manual create sheet.
- Navigation links open import failures / diagnostics.

Direct services/API/repositories:
- None.

Audience:
- Mixed. Manual create can be restaurant-facing for managers. Developer diagnostics are developer-only. Failed imports are manager/developer.

### ReservationNavigationRow

File: `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`

Purpose:
- Schedule/review row wrapper around `ReservationRowView`.
- Provides actions, swipe actions, context menu, details navigation, and table assignment.

Data read:
- `reservation`
- Controller capabilities and action state.

Controller calls:
- Confirm action: `confirmReservation(reservation:context:)`
- Seat/cancel/complete/no-show: `updateStatus(reservation:status:context:)`
- Table assignment: `updateReservation(id:request:context:)`

Lifecycle / triggers:
- Buttons.
- Swipe actions.
- Context menu.
- Confirmation dialog.
- Table assignment sheet.
- Details navigation.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing.

### HostBoardView

File: `Tryzub Reservations/Features/Reservations/HostBoardView.swift`

Purpose:
- Today host board.
- Splits today reservations into upcoming, seated, review, and summary counts.
- Runs the auto-refresh loop while visible and active.

Data read:
- Passed-in today reservations.
- `lastSyncedAt`, `isSyncing`, `failedImportCount`.
- Controller capabilities/action state.
- Local interaction state.

Controller calls:
- Auto refresh: `autoRefreshDashboardIfAllowed(context:isInteractionActive:isAppActive:)`
- Confirm action: `confirmReservation(reservation:context:)`
- Seat/complete/cancel/no-show: `updateStatus(reservation:status:context:)`
- Table assignment: `updateReservation(id:request:context:)`

Lifecycle / triggers:
- `.task(id: isVisible && isAppActive)` starts a loop.
- Loop sleeps 60 seconds, then asks the controller whether auto-refresh is allowed.
- Buttons and context menus trigger mutations.
- Confirmation dialog for destructive actions.
- Sheet for table assignment.

Direct services/API/repositories:
- None.

Audience:
- Core restaurant-facing screen.

Important risk:
- `HostBoardSnapshot.upcoming` includes `new`, `needs_review`, and `confirmed` for today, regardless of whether the reservation time has passed. That is good for not hiding active reservations by time. The next marker uses current time only to choose which upcoming row is "next".

### ReservationRowView

File: `Tryzub Reservations/Features/Reservations/ReservationRowView.swift`

Purpose:
- Pure reservation row presentation.

Data read:
- A `ReservationRecord`.
- Row context.
- Optional context note.

Controller calls:
- None.

Lifecycle / triggers:
- None.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing.

### ReservationDetailView

File: `Tryzub Reservations/Features/Reservations/ReservationDetailView.swift`

Purpose:
- Reservation details, edit sheet, quick actions, contact links, notes, email status, operational metadata.

Data read:
- A live `ReservationRecord`.
- Controller capabilities/action/error state.

Controller calls:
- Edit save: `updateReservation(id:request:context:)`
- Table assignment: `updateReservation(id:request:context:)`
- Confirm action: `confirmReservation(reservation:context:)`
- Seat/complete/cancel/no-show: `updateStatus(reservation:status:context:)`

Lifecycle / triggers:
- Toolbar edit button.
- Action buttons.
- Confirmation dialog.
- Edit sheet.
- Table assignment sheet.
- Phone/email links.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing, but `ReservationOperationalCard` is developer/sync info and should probably be hidden outside manager/developer modes before staff pilot.

### ReservationEditFormView

File: `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift`

Purpose:
- Edit form for reservation fields (shared `ReservationFormContent` with create).
- Save shows old → new diff confirmation before PATCH.
- Hide button for test/duplicate rows (soft-hide via backend).

Data read:
- `ReservationFormDraft` initialized from `ReservationRecord`; `originalDraft` for diff.

Controller calls:
- Indirect through `onSave` → `updateReservation`
- `hideWrongEntry` for soft-hide

Lifecycle / triggers:
- Save button → diff confirmation → PATCH.
- Back navigation only (no duplicate Cancel toolbar on edit).

Audience:
- Restaurant-facing for staff who can edit.

### ManualReservationFormView

File: `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift`

Purpose:
- Create a manual reservation.
- Can also prefill from an `ImportFailureDTO`.

Data read:
- Local form state.
- Optional failed import snapshot.

Controller calls:
- Indirect through `onCreateReservation`, provided by parent views.

Lifecycle / triggers:
- Save toolbar button calls private `createReservation()`.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing manager workflow.

Risk:
- Email is required by the form. If call-in guests do not provide email but the backend requires one, this blocks staff unless a policy/placeholder is added intentionally.

### ReservationActionButtons

File: `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift`

Purpose:
- Reusable action menu/buttons for confirm, seat, table assignment, complete, cancel, no-show.

Data read:
- `ReservationRecord`
- `AppCapabilities`
- `isBusy`

Controller calls:
- None directly. Calls `onAction`.

Lifecycle / triggers:
- Button taps.
- Menu taps.
- `.task(id: pendingInlineAction)` clears inline confirmation after 3 seconds.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing.

Critical naming note:
- `ReservationHostAction.confirmOnly` → PATCH `status=confirmed` (no email).
- `ReservationHostAction.confirmAndSendEmail` → POST `/managed-reservations/{id}/confirm`.
- UI labels: **Confirm Only** / **Confirm + Email**.

### TableAssignmentSheet

File: `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift`

Purpose:
- Assign/update table name via bottom sheet (not popover).

Data read:
- Local `tableName` state initialized from `ReservationRecord`.

Controller calls:
- Indirect through `onSave`.

Lifecycle / triggers:
- Toolbar Save in sheet navigation bar.

Direct services/API/repositories:
- None.

Audience:
- Restaurant-facing.

### ImportFailuresView

File: `Tryzub Reservations/Features/Reservations/ImportFailuresView.swift`

Purpose:
- Shows failed Flamingo import records from the backend.
- Lets manager/developer create a fixed manual reservation from a failed submission.

Data read:
- Local `failures`, `isLoading`, `errorMessage`.
- Controller through `@EnvironmentObject`.

Controller calls:
- `.task`: `fetchImportFailures(page:perPage:)`
- `.refreshable`: `fetchImportFailures(page:perPage:)`
- Toolbar refresh: `fetchImportFailures(page:perPage:)`
- Create fixed reservation path: parent-provided `createReservation`

Lifecycle / triggers:
- Initial `.task`.
- Pull to refresh.
- Toolbar refresh.
- Navigation to failure detail.
- Manual create from failed import.

Direct services/API/repositories:
- None. It goes through `ReservationsController`.

Audience:
- Manager/developer only. Not normal staff host-board work.

### DeveloperDiagnosticsView

File: `Tryzub Reservations/Features/Reservations/DeveloperDiagnosticsView.swift`

Purpose:
- Debug API health, request log, sync scopes, SwiftData cache counts, and endpoint checklist.

Data read:
- `APIRequestLogStore.shared`
- `@Query` reservations
- Controller state
- `AppEnvironment`

Controller calls:
- `runAdminFetchTest(_:reservationID:)`
- Notice dismiss/clear through `NoticeDetailRow`

Lifecycle / triggers:
- Buttons run explicit safe GET tests.
- Clear log and clear notices buttons mutate only local debug state.

Direct services/API/repositories:
- None.

Audience:
- Developer-only.

Safety:
- Current diagnostics tests use GET endpoints only. They do not confirm, cancel, seat, create, or import reservations.

### AppNoticeOverlay

File: `Tryzub Reservations/Features/Reservations/AppNoticeOverlay.swift`

Purpose:
- Displays the newest scoped notice and a sheet with notice history.

Data read:
- `[AppNotice]`.

Controller calls:
- Indirect callbacks: dismiss, clear all.

Lifecycle / triggers:
- `.task(id: notice.id)` auto-dismisses:
  - success/info after 3 seconds
  - warning/error after 5 seconds
- Button opens details sheet.
- Dismiss button removes one notice.

Direct services/API/repositories:
- None.

Audience:
- Global restaurant-facing feedback, but the volume/scope count may be too much for staff.

## 3. Controller Layer

File: `Tryzub Reservations/Import/ReservationsController.swift`

`ReservationsController` is the main app coordinator. It owns sync state, mutation state, notices, failed import count, and sync-scope freshness tracking. It is large but understandable if treated as the app's single workflow coordinator.

### View-Facing Workflow Methods

- `loadIfNeeded(context:)`
- `refreshDashboard(context:)`
- `requestManualTodayRefresh(context:source:)`
- `scheduleBecameActive(context:)`
- `requestScheduleRefresh(context:source:)`
- `reviewBecameActive(context:)`
- `requestReviewRefresh(context:source:)`
- `refreshReviewQueues(context:)`
- `autoRefreshDashboardIfAllowed(context:isInteractionActive:isAppActive:)`
- `isActionInProgress(for:)`
- `createReservation(_:context:)`
- `updateReservation(id:request:context:)`
- `updateStatus(reservation:status:context:)`
- `confirmReservation(reservation:context:)`
- `refreshImportFailureCount(reason:)`
- `refreshImportFailureCountIfNeeded(force:reason:)`
- `fetchImportFailures(page:perPage:)`
- `dismissNotice(_:)`
- `clearAllNotices()`
- `clearErrorMessage()`
- `clearNoticeMessage()`
- `clearImportFailureCountError()`
- `runAdminFetchTest(_:reservationID:)`

### Public But More Internal Than Workflow

- `refreshAll(context:)`: currently aliases schedule refresh. The name is misleading.
- `save(_:context:)`: saves a DTO to cache through sync service. Used after failed-import manual create, but create already upserts. This is suspicious/duplicative.
- `reconcileReservation(id:context:)`: recovery helper after uncertain mutation failures. Public because controller methods call it internally and it could be useful to views, but it is not a normal staff action.

### Private Helpers

- `performTodayRefresh(context:mode:)`
- `performScheduleWindowRefresh(context:force:)`
- `performReviewQueuesRefresh(context:force:)`
- `todayScope()`
- `scheduleWindow()`
- `scheduleScope()`
- `allowManualAttempt(for:)`
- `isScopeFresh(_:freshnessInterval:)`
- `beginScope(_:)`
- `markScopeSuccess(_:)`
- `markScopeFailure(_:cooldown:)`
- `markScopeCancelled(_:)`
- `markScopeStale(_:)`
- `markScopeRecentlyTouched(_:)`
- `markScopesTouched(after:)`
- `publishSyncScopeSnapshots()`
- `postRefreshFailureNotice(mode:error:)`
- `postMutationFailureNotice(title:message:)`
- `postNotice(...)`
- `clearScopedMessages(for:)`
- `errorLogCode(_:)`

### Methods That Trigger Network Requests

- `loadIfNeeded` -> today GET
- `refreshDashboard` -> today GET
- `requestManualTodayRefresh` -> today GET
- `scheduleBecameActive` -> schedule GET pages if stale
- `requestScheduleRefresh` -> schedule GET pages
- `reviewBecameActive` -> two review GETs if stale
- `requestReviewRefresh` -> two review GETs
- `autoRefreshDashboardIfAllowed` -> today GET if allowed
- `createReservation` -> POST `managed-reservations`
- `updateReservation` -> PATCH `managed-reservations/{id}`
- `updateStatus` -> PATCH `managed-reservations/{id}`
- `confirmReservation` -> POST `managed-reservations/{id}/confirm`
- `refreshImportFailureCountIfNeeded` -> GET `managed-reservations/import-failures`
- `fetchImportFailures` -> GET `managed-reservations/import-failures`
- `reconcileReservation` -> GET `managed-reservations/{id}`
- `runAdminFetchTest` -> safe GET endpoints only

### Methods That Write SwiftData Indirectly

- `loadIfNeeded` through `performTodayRefresh`
- `requestManualTodayRefresh` through `performTodayRefresh`
- `scheduleBecameActive` / `requestScheduleRefresh`
- `reviewBecameActive` / `requestReviewRefresh`
- `autoRefreshDashboardIfAllowed`
- `save`
- `createReservation`
- `updateReservation`
- `updateStatus`
- `confirmReservation`
- `reconcileReservation`

### Controller State

UI state:
- `errorMessage`
- `noticeMessage` (currently appears mostly legacy/unused)
- `notices`
- `importFailureCount`
- `importFailureCountError`

Sync state:
- `isSyncing`
- `isAutoRefreshing`
- `lastSyncedAt`
- `isCheckingImportFailureCount`
- `syncScopeSnapshots`
- `lastAutoRefreshAttemptAt`
- `lastAutoRefreshFailureAt`
- `manualAttemptByScope`
- `syncStateByScope`
- `hasAttemptedInitialLoad`

Mutation state:
- `actionInProgressIDs`
- `isCreatingReservation`
- `hasActiveMutation`

Configuration:
- `environment`
- refresh/cooldown intervals

### Confusing Names To Document Or Rename Later

Do not rename now, but these names slow down tracing:

- `confirmReservation`: currently means confirm and send/attempt email via `POST /managed-reservations/{id}/confirm`.
- `ReservationHostAction.confirm`: UI text sometimes says "Confirm" even though action sends email.
- `refreshAll`: currently requests the schedule window, not all reservations.
- `refreshDashboard`: today refresh alias; "dashboard" is less precise than "today".
- `ReservationImportService.swift`: file contains `ReservationSyncService`, not an import operation.
- `save(_:context:)`: generic local cache save; easy to mistake for server save.
- `reviewQueues`: name is okay internally, but restaurant workflow probably wants "New/Pending".
- `noticeMessage`: likely legacy state.

## 4. Service Layer

### ReservationSyncService

File: `Tryzub Reservations/Import/ReservationImportService.swift`

Protocol: `ReservationSyncServiceProtocol`

What it fetches/saves:
- `syncAllReservations`: fetches all pages of managed reservations with optional filters, upserts all returned DTOs.
- `syncToday`: fetches first page of today's reservations, upserts returned DTOs.
- `syncScheduleWindow`: fetches all pages from `from` to `to`, upserts all returned DTOs.
- `syncReviewQueues`: fetches first page of `needs_review` and first page of `new`, upserts combined rows.
- `saveReservation`: local upsert only.

Who calls it:
- `ReservationsController`.

Does it call API:
- Yes, except `saveReservation`.

Does it call repository:
- Yes, every method upserts returned DTOs or the provided DTO.

Is the name accurate:
- The type name `ReservationSyncService` is accurate.
- The file/folder path `Import/ReservationImportService.swift` is stale and misleading.

Overengineering note:
- For this MVP, the service mostly forwards calls from controller to API + repository. It is harmless, but it adds a layer to trace.

### ImportFailureService

File: `Tryzub Reservations/Services/ImportFailureService.swift`

What it fetches:
- Failed import records from `GET /managed-reservations/import-failures`.

Who calls it:
- `ReservationsController.refreshImportFailureCountIfNeeded`
- `ReservationsController.fetchImportFailures`

Does it call API:
- Yes.

Does it call repository:
- No.

Is the name accurate:
- Yes. It fetches failed import diagnostics, not the dangerous import endpoint.

### ReservationMutationService

File: `Tryzub Reservations/Services/ReservationMutationService.swift`

#### updateReservation

Who calls it:
- `ReservationsController.updateReservation`
- Indirectly `updateStatus`

Endpoint:
- `PATCH /managed-reservations/{id}`

Does it upsert returned DTO:
- Yes.

Workflow:
- Update table, status, notes, date/time, party size, duplicate/superseded fields, or guest/contact fields.

#### createReservation

Who calls it:
- `ReservationsController.createReservation`

Endpoint:
- `POST /managed-reservations`

Does it upsert returned DTO:
- Yes.

Workflow:
- Manual call-in reservation or fixed reservation created from a failed import.

#### confirmReservation

Who calls it:
- `ReservationsController.confirmReservation`

Endpoint:
- `POST /managed-reservations/{id}/confirm`

Does it upsert returned DTO:
- Yes, `response.data`.

Workflow:
- Confirm and send/attempt backend confirmation email.

Critical naming note:
- This is not the same as "confirm without email".
- Plain confirm without email should be `PATCH /managed-reservations/{id}` with `{ "status": "confirmed" }`.

#### reconcileReservation

Who calls it:
- `ReservationsController.reconcileReservation`
- Called after uncertain mutation failures.

Endpoint:
- `GET /managed-reservations/{id}`

Does it upsert returned DTO:
- Yes.

Workflow:
- Refresh one reservation after a timeout/network-loss case where the server may have applied the mutation.

## 5. API Layer

File: `Tryzub Reservations/Network/ReservationsAPIClient.swift`

Base path:
- `https://tryzubchicago.com/wp-json/tryzub/v1`

Auth:
- Basic Authorization header from WordPress username and application password.

Session behavior:
- `waitsForConnectivity = false`
- request timeout: 8 seconds
- resource timeout: 12 seconds
- reload ignoring local cache
- max connections per host: 2

### Public API Methods

| Method | HTTP | Endpoint | Request reason | Retry behavior |
| --- | --- | --- | --- | --- |
| `fetchReservations(page:perPage:date:from:to:status:search:retryCount:reason:)` | GET | `/managed-reservations?page=&per_page=&date=&from=&to=&status=&search=` | Caller supplied. Common values: `startup_today`, `manual_today`, `auto_today`, `schedule_window`, `review_queues` | Uses caller `retryCount`; most app flows pass `0`; some diagnostics pass `1` |
| `fetchAllReservations(perPage:date:from:to:status:search:reason:)` | GET | Same `/managed-reservations`, paged until `totalPages` | Caller supplied | Each page currently uses default `retryCount = 0` |
| `fetchReservation(id:retryCount:reason:)` | GET | `/managed-reservations/{id}` | Usually `reconcile_by_id` | Uses caller `retryCount`; default concrete value is `1`, reconcile passes `0` |
| `updateReservation(id:request:reason:)` | PATCH | `/managed-reservations/{id}` | `mutation_patch` | No retry by default |
| `createReservation(_:reason:)` | POST | `/managed-reservations` | `mutation_create` | No retry by default |
| `confirmReservation(id:reason:)` | POST | `/managed-reservations/{id}/confirm` | `mutation_confirm` | No retry by default |
| `fetchImportFailures(page:perPage:reason:)` | GET | `/managed-reservations/import-failures?page=&per_page=` | `failure_count` or `import_failures_full` | Explicit retry `0` |

Not implemented:
- `POST /managed-reservations/import` is not implemented in the iOS API client and is not part of normal workflow.

### Request Reasons

`ReservationAPIRequestReason` values:

- `unspecified`
- `startup_today`
- `manual_today`
- `auto_today`
- `auto_skip_cooldown`
- `failure_count`
- `import_failures_full`
- `schedule_window`
- `review_queues`
- `mutation_patch`
- `mutation_confirm`
- `mutation_create`
- `reconcile_by_id`
- `manual_skip_busy`
- `manual_skip_cooldown`
- `scope_skip_in_flight`
- `auto_skip_busy`
- `auto_skip_inactive`

### Sanitized Logging

`ReservationAPILogger` records:

- outcome: started, succeeded, failed, cancelled, skipped
- reason
- method
- sanitized path/query
- status/error/duration
- skip message

What it sanitizes:

- Removes scheme, host, port, user, and password from logged URLs.
- Redacts the `search` query value as `<redacted>`.
- Does not log request payloads.
- Does not log headers.

Authorization safety:

- `Authorization` is set in `makeRequest`.
- Logging receives the `URLRequest`, but only reads method and URL path/query.
- The Authorization header is never printed or stored by the logger.

Search safety:

- `search` query values are redacted in logs.

## 6. Repository / Persistence Layer

File: `Tryzub Reservations/Services/ReservationRepository.swift`

SwiftData model:
- `ReservationRecord`

Who calls it:
- `ReservationSyncService`
- `ReservationMutationService`
- `ReservationsController.loadIfNeeded` for latest local sync date

Upsert behavior:

1. Fetches all local `ReservationRecord` rows.
2. Builds a dictionary keyed by `record.remoteID`.
3. For each DTO:
   - If `dto.id` already exists, update that record.
   - Otherwise insert `ReservationRecord(from: dto)`.
4. Saves the `ModelContext`.

Server identity key:
- `ReservationDTO.id` -> `ReservationRecord.remoteID`

Duplicate risk:
- There is no SwiftData uniqueness constraint on `remoteID`.
- Normal upsert avoids inserting a duplicate when a matching `remoteID` exists.
- If duplicates already exist locally with the same `remoteID`, the dictionary keeps one of them and the extra duplicate rows can remain.

Cache-only rule:
- Repository writes are cache updates after server fetch/mutation responses.
- The repository should not be used to pretend a server mutation succeeded.

## 7. DTO / Model Layer

### ReservationDTO

File: `Tryzub Reservations/Network/ReservationDTO.swift`

Fields:

- `id`
- `sourceSubmissionId`
- `guestName`
- `email`
- `phone`
- `reservationDate`
- `reservationTime`
- `partySize`
- `guestNotes`
- `staffNotes`
- `status`
- `tableName`
- `createdAt`
- `updatedAt`
- `confirmedAt`
- `confirmationEmailSentAt`
- `reminderEmailSentAt`
- `supersededById`

Backend mapping:

- `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`
- `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase`
- Swift `sourceSubmissionId` maps to backend `source_submission_id`.
- Swift `reservationDate` maps to backend `reservation_date`.
- Swift `reservationTime` maps to backend `reservation_time`.

Fields that must not be renamed casually:

- All DTO/request property names that map to backend fields through snake_case conversion.
- Status raw values: `needs_review`, `no_show`, etc.
- Confirm response fields: `email_status`, `email_error`, `data`.

Optional fields:

- `sourceSubmissionId`
- `guestNotes`
- `staffNotes`
- `tableName`
- `updatedAt`
- `confirmedAt`
- `confirmationEmailSentAt`
- `reminderEmailSentAt`
- `supersededById`

Date/time handling:

- `reservationDate` is a string, expected `yyyy-MM-dd`.
- `reservationTime` is a string, expected `HH:mm:ss`.
- `createdAt` and related timestamps are strings, expected roughly `yyyy-MM-dd HH:mm:ss`.
- Sorting mostly relies on string order, which is safe only if backend formats stay consistent.
- No timezone conversion is centralized.

### ReservationRecord

File: `Tryzub Reservations/Persistence/ReservationRecord.swift`

SwiftData cache model fields mostly mirror `ReservationDTO`.

Important behavior:

- `remoteID` stores backend `id`.
- `sourceSubmissionID` stores `0` when backend `sourceSubmissionId` is nil.
- Empty optional strings are normalized to nil.
- `status` is stored as raw string.
- `statusValue` maps unknown stored values to `.new`.
- `ReservationDTO.operationalStatus` maps active reservations on past dates to `.completed` before storing.
- `ReservationRecord.statusValue` also maps active records on past dates to `.completed`.

Risk:
- Auto-completing past-date active reservations in the local model can hide unresolved operational work if staff need to see stale active reservations later.

### ReservationStatus

File: `Tryzub Reservations/Network/ReservationDTO.swift`

Raw values:

- `new`
- `needs_review`
- `confirmed`
- `seated`
- `completed`
- `cancelled`
- `no_show`

Decode behavior:
- Unknown backend status decodes as `.needsReview`.

Record behavior:
- Unknown stored status decodes as `.new`.

### Request / Response Types

Files:
- `Tryzub Reservations/Network/ReservationDTO.swift`
- `Tryzub Reservations/Network/ReservationsResponse.swift`

Create request:
- `ReservationCreateRequest`
- Encoded snake_case.
- Used with `POST /managed-reservations`.

Update request:
- `ReservationUpdateRequest`
- Encoded snake_case.
- Used with `PATCH /managed-reservations/{id}`.
- Optional properties allow partial updates.

Confirm response:
- `ReservationConfirmResponse`
- Contains `success`, `emailStatus`, `emailError`, `message`, `data`.
- `emailStatus` maps `already_sent` to `.alreadySent`.
- Unknown email status maps to `.unknown`.

Import failure DTOs:
- `ImportFailureDTO`
- `ImportFailureReservationSnapshot`
- `JSONValue`
- `failureId` maps from backend JSON key `id` via explicit `CodingKeys`.

## Lifecycle / Event Flow Map

### 1. App Launch

1. `Tryzub_ReservationsApp` starts.
2. `AppCredentialStore` loads credentials from environment or Keychain.
3. If missing, `CredentialsSetupView` is shown.
4. If present, `AppEnvironment` is created with `ReservationsAPIClient` and role `.developer`.
5. Scene-level SwiftData model container is available for `ReservationRecord`.
6. `ReservationsListView` creates `ReservationsController`.
7. `ReservationsListView.task` calls `controller.loadIfNeeded(context:)`.
8. Controller checks local cache latest sync date through `ReservationRepository.latestLocalSyncDate()`.
9. Controller calls `performTodayRefresh(mode: .startup)`.
10. `ReservationSyncService.syncToday(reason: .startupToday)` calls API.
11. API calls `GET /managed-reservations?date=today&page=1&per_page=50`.
12. DTOs decode using `convertFromSnakeCase`.
13. Repository upserts `ReservationRecord` rows.
14. SwiftData `@Query` updates views.
15. Controller updates sync state/notices.

### 2. Today Manual Refresh

1. User pulls to refresh or taps toolbar refresh in Today.
2. `TodayDashboardView` calls `controller.requestManualTodayRefresh(context:)`.
3. Guards run:
   - no active mutation
   - no active reservation refresh
   - manual cooldown for today scope has expired
   - scope not already in flight
4. Controller sets `isSyncing = true`.
5. `ReservationSyncService.syncToday(reason: .manualToday)` runs.
6. API calls `GET /managed-reservations?date=today&page=1&per_page=50`.
7. Repository upserts returned DTOs.
8. Controller sets `lastSyncedAt`, marks scope success, sets `isSyncing = false`.
9. Success notice: "Reservations updated".
10. Controller may refresh import failure count if stale.
11. Failure notice: "Refresh failed"; cached data remains visible.

### 3. Today Auto Refresh

1. `HostBoardView.task(id: isVisible && isAppActive)` starts while Today is visible and app is active.
2. Loop sleeps 60 seconds.
3. It calls `controller.autoRefreshDashboardIfAllowed(...)`.
4. Guards skip when:
   - app inactive
   - host interaction active
   - refresh already active
   - mutation active
   - import failure count is being checked
   - auto interval has not passed
   - failure cooldown active
5. Controller calls `performTodayRefresh(mode: .automatic)`.
6. API calls `GET /managed-reservations?date=today&page=1&per_page=50`.
7. Success updates cache and sync state without posting a success notice.
8. Timeout/cancel/failure:
   - cancellation marks scope cancelled and returns false.
   - failure marks scope failure and sets auto failure cooldown.
   - warning notice: "Auto-refresh failed".

### 4. Schedule Activation

1. User opens Schedule tab.
2. `ReservationScheduleView.task(id: isActive)` calls `scheduleBecameActive(context:)`.
3. Controller checks freshness for 30-day schedule scope.
4. If fresh, it uses cached SwiftData only.
5. If stale, it calls `performScheduleWindowRefresh(force: false)`.
6. Window is today through 30 days from now.
7. API calls paged `GET /managed-reservations?from=today&to=today+30`.
8. Repository upserts returned DTOs.
9. Manual pull/toolbar refresh uses the same endpoint but forces refresh.

### 5. Review/New Activation

1. User opens Review tab.
2. `ReservationReviewQueueView.task(id: isActive)` calls `reviewBecameActive(context:)`.
3. Controller checks 120-second freshness for `reviewQueues`.
4. If stale, `ReservationSyncService.syncReviewQueues(reason: .reviewQueues)` runs.
5. API calls:
   - `GET /managed-reservations?status=needs_review&page=1&per_page=50`
   - `GET /managed-reservations?status=new&page=1&per_page=50`
6. Repository upserts combined rows.
7. UI currently displays either New or Review via segmented control.
8. Current sorting uses `createdAt` ascending inside the selected segment.

MVP note:
- Desired "New/Pending" should likely show both `new` and `needs_review` together, oldest submitted first.

### 6. Confirm Without Email

Expected workflow:

1. UI action should issue `PATCH /managed-reservations/{id}` with `status = confirmed`.
2. No confirmation email should be sent.
3. Returned DTO should be upserted.

Current code path:

- Generic path exists: `ReservationsController.updateStatus(reservation:status:.confirmed,context:)` would PATCH `status=confirmed`.
- `ReservationEditView` can also save status `.confirmed` through `updateReservation`.
- There is no obvious host-board/review primary button for "Confirm without email".
- The visible primary confirm action calls `confirmReservation`, which uses the confirm-email endpoint.

### 7. Confirm + Email

Current workflow:

1. UI action from `ReservationActionButtons` / row / detail calls `ReservationsController.confirmReservation`.
2. Controller creates `ReservationMutationService`.
3. Service calls `ReservationsAPIClient.confirmReservation`.
4. API calls `POST /managed-reservations/{id}/confirm`.
5. Backend confirms and sends/attempts confirmation email.
6. Response decodes as `ReservationConfirmResponse`.
7. Service upserts `response.data`.
8. Controller posts notice based on `emailStatus`:
   - `sent`: success "Reservation confirmed" / "Email sent."
   - `already_sent`: info
   - `failed`: warning and staff follow-up message
   - `skipped`: info with backend message
   - `unknown`: info

Important:
- Backend `sent` means the backend accepted or attempted sending. It does not prove Gmail inbox delivery.

### 8. Update Reservation

1. User edits detail form, assigns table, changes status, or uses quick action.
2. View calls `controller.updateReservation` or `controller.updateStatus`.
3. Controller guards against duplicate action for the same remote ID.
4. `ReservationMutationService.updateReservation` calls API.
5. API calls `PATCH /managed-reservations/{id}`.
6. Returned DTO is upserted.
7. Controller marks scopes touched/stale and posts success notice.
8. On uncertain network failure, controller calls `reconcileReservation`.
9. On definite failure, no local fake success is written.

### 9. Manual Create

1. User opens manual form from Today/Schedule/More or failed import detail.
2. `ManualReservationFormView.createReservation()` validates name/email/phone.
3. Form builds `ReservationCreateRequest`.
4. Parent closure calls `controller.createReservation`.
5. `ReservationMutationService.createReservation` calls API.
6. API calls `POST /managed-reservations`.
7. Returned DTO is upserted.
8. Controller posts success notice "Manual reservation created".
9. Failure shows form error and controller notice; no local fake reservation is created.

### 10. Import Failure Count

1. Only visible when `capabilities.canViewFailedImports` is true.
2. Count can refresh after reservation refreshes through `refreshImportFailureCountIfNeeded`.
3. Freshness interval: 300 seconds.
4. Endpoint: `GET /managed-reservations/import-failures?page=1&per_page=1`.
5. UI displays count in Today toolbar/banners and More.
6. Full list endpoint uses `per_page=100`.

### 11. Developer Diagnostics

Available tests:

- startup today GET
- manual today GET
- failure count GET
- schedule window GET
- review queues GETs
- import failures full GET
- fetch by ID GET

Endpoints hit:

- `GET /managed-reservations`
- `GET /managed-reservations/{id}`
- `GET /managed-reservations/import-failures`

Safety:
- Diagnostics do not mutate real reservations.
- There are no diagnostic confirm/cancel/create/import mutation tests.
- Diagnostics include a checklist row warning that `POST /managed-reservations/import` is not used.

## Protocols / Dependency Injection

### ReservationsAPIClientProtocol

Concrete implementation:
- `ReservationsAPIClient`

Who depends on it:
- `AppEnvironment`
- `ReservationSyncService`
- `ReservationMutationService`
- `ImportFailureService`
- `ReservationsController.runAdminFetchTest` through `environment.apiClient`

Why it helps:
- Easy to mock API responses in tests/previews if a fake client is added.
- Keeps services from depending on concrete networking.

MVP judgment:
- Useful and should stay.

Trace cost:
- Low. The protocol mirrors the concrete client closely.

### ReservationRepositoryProtocol

Concrete implementation:
- `ReservationRepository`

Who depends on it:
- `ReservationSyncService`
- `ReservationMutationService`

Why it helps:
- Allows service-level tests without SwiftData if a fake repository is added.

MVP judgment:
- Slightly overengineered for a tiny app, but harmless.

Trace cost:
- Low.

### ReservationMutationServiceProtocol

Concrete implementation:
- `ReservationMutationService`

Who depends on it:
- No production code stores this protocol as a dependency. The controller instantiates the concrete type.

Why it helps:
- Potential tests.

MVP judgment:
- Currently overengineering. Harmless, but not buying much until the controller receives a service dependency instead of constructing one.

Trace cost:
- Mild. It adds a name without adding runtime flexibility.

### ReservationSyncServiceProtocol

Concrete implementation:
- `ReservationSyncService`

Who depends on it:
- No production code stores this protocol as a dependency. The controller instantiates the concrete type.

Why it helps:
- Potential tests.

MVP judgment:
- Currently overengineering. The service itself is useful as a boundary; the protocol is optional.

Trace cost:
- Mild.

### ImportFailureServiceProtocol

Concrete implementation:
- `ImportFailureService`

Who depends on it:
- No production code stores this protocol as a dependency.

Why it helps:
- Potential tests.

MVP judgment:
- Overengineering for MVP. Harmless.

Trace cost:
- Mild.

### AppEnvironment

Concrete implementation:
- Struct created in app startup.

Who depends on it:
- `ReservationsListView`
- `ReservationsController`
- Child views often receive it only to pass along to detail/diagnostics.

Why it helps:
- Bundles API client, role, capabilities.
- Avoids global API client.

MVP judgment:
- Useful enough. Could be simpler, but not a cleanup priority.

### AppCapabilities

Concrete implementation:
- Struct derived from `AppUserRole`.

Who depends on it:
- Controller exposes `capabilities`.
- Views use capabilities to show/hide actions.

Why it helps:
- Prevents staff-only sessions from seeing dangerous/admin actions if role is configured.

MVP judgment:
- More SaaS-ish than needed while role is hardcoded to `.developer`.
- Keep it for now because ripping it out creates risk and it guards diagnostics/import failures.

Trace cost:
- Medium. It makes the UI conditional, but the conditions are readable.

## Architecture Quality Audit

### What Is Good

- Clear separation between views, controller, services, API client, repository, and DTO/cache models.
- Mutations are server-first. The app does not locally pretend a create/update/confirm succeeded.
- SwiftData is used as a cache that redraws views through `@Query`.
- API logging has request reasons and sanitized URL logging.
- Credentials are not hardcoded in source and can live in Keychain.
- Diagnostics are read-only and useful for a developer/manager.
- `POST /managed-reservations/import` is not implemented in the iOS client.
- Reconcile-after-uncertain-network-failure is practical for real restaurant Wi-Fi.

### What Is Messy

- `ReservationsController` is large and mixes workflow, sync state, mutation state, notice state, diagnostics, and freshness policy.
- File/folder naming still says import where the active service is sync/cache.
- `confirmReservation` name is ambiguous because it means confirm plus email.
- `refreshAll` does not refresh all reservations.
- There are multiple refresh entry points and freshness scopes; safe, but hard to trace.
- Views have many lifecycle triggers: root `.task`, tab activation `.task`, host-board auto-refresh `.task`, pull refresh, toolbar refresh, sheets.
- Notices are heavily scoped. Good for debugging, maybe noisy for staff.
- Role/capability infrastructure is more than a one-restaurant MVP needs while the role is hardcoded.
- `save(_:context:)` after manual create from failed import looks redundant because create already upserts.

### What Is Dangerous

- Any visible "Confirm" label that actually sends email can cause staff to email guests accidentally.
- There is no first-class "Confirm without email" action despite that being a core workflow.
- Views do not create API clients/services directly now; keep it that way.
- Child views do trigger network through controller: schedule activation, review activation, import failures `.task`, host board auto-refresh.
- `ReservationEditView` and `ManualReservationFormView` use stale `@State` copies while sheets are open.
- SwiftData has no unique constraint on `remoteID`.
- Local status auto-completion for past dates can hide active stale reservations in some contexts.
- Email `sent` is not inbox delivery.
- Search query is redacted in logs, but staff-entered search still goes to backend when API search is used. Current visible search is local only.

### What Should Not Be Touched Before MVP

- Offline mutation queue.
- Incremental sync with `after_id` or `updated_since`.
- SMS/reminders.
- Inbound email capture.
- PostgreSQL/SaaS architecture.
- Advanced roles/permissions.
- New backend endpoints.
- Public form rebuild, except for fixing duplicate submission behavior if it is actively creating bad restaurant data.

### What Should Be Cleaned Before MVP

1. Make confirm semantics explicit in UI/docs: "Confirm only" must PATCH status; "Confirm + Email" must call confirm endpoint.
2. Make Review/New show the actual pending work queue staff need: `new` + `needs_review`, oldest submitted first.
3. Keep active today reservations visible after their reservation time until staff seats/completes/cancels/no-shows them.
4. Make staff notes prominent in detail and rows where operationally relevant.
5. Simplify/label refresh and diagnostics paths so staff do not have to understand sync scopes.
