# iOS Reservation App Status

## Current Fetch Architecture

`ReservationsController` is the app-facing network coordinator. SwiftUI views call controller methods only; they do not create API clients, URLRequests, or network services directly.

The app calls these backend endpoints:

- `GET /managed-reservations?date=YYYY-MM-DD`
- `GET /managed-reservations`
- `GET /managed-reservations/{id}`
- `PATCH /managed-reservations/{id}`
- `POST /managed-reservations`
- `POST /managed-reservations/{id}/confirm`
- `GET /managed-reservations/import-failures`

The iOS app does not call `POST /managed-reservations/import`. Backend auto-import happens server-side after Contact Form 7 / Flamingo intake.

## Startup Refresh Behavior

On app launch, cached SwiftData reservations are shown immediately by the query-backed views.

`ReservationsController.loadIfNeeded(context:)` still guards with `hasAttemptedInitialLoad`, reads the latest local sync date for display, and always attempts one fresh Today refresh. It no longer skips the Today fetch because the cache is fresh.

Startup refresh calls `refreshDashboard(context:)` internally in startup mode, which fetches Today only through `ReservationSyncService.syncToday()`.

## Manual Refresh Behavior

Today pull-to-refresh and the toolbar refresh button both call `ReservationsController.refreshDashboard(context:)`.

Manual Today refresh always attempts the backend, regardless of local cache freshness. If it fails, cached rows remain visible and an inline message is shown.

Schedule refresh still calls `refreshAll(context:)`. This is intentionally heavier because it may paginate all managed reservations. Startup does not call this path.

Review refresh calls `refreshReviewQueues(context:)`, which syncs only `needs_review` and `new` reservations instead of refreshing all reservations.

## Auto-Refresh Behavior

Today/Host Board runs a controlled auto-refresh loop every 90 seconds while the Today tab is visible.

Auto-refresh is skipped when:

- `isSyncing` is true
- any reservation mutation is in progress
- manual reservation creation is in progress
- import failure count check is in progress
- a host interaction/dialog/sheet is open

Auto-refresh fetches Today only. Failure does not present a blocking modal alert; it shows an inline stale-data message and keeps cached data visible.

## Mutation Behavior

Mutations are server-first:

- PATCH status/details sends to server, decodes the returned DTO, then upserts into SwiftData.
- Create sends to server, decodes the created DTO, then upserts into SwiftData.
- Confirm calls the backend confirm endpoint, decodes email status and returned DTO, then upserts into SwiftData.

Mutations are guarded with `actionInProgressIDs` per reservation. Manual create is guarded with `isCreatingReservation`.

After uncertain PATCH/confirm network failures, reconciliation uses `GET /managed-reservations/{id}` with `retryCount: 0` to avoid hidden retry loops.

## SwiftData Role

SwiftData is a local cache only. The server remains the source of truth.

Repository upsert uses server `id` / `remoteID`. Successful server responses overwrite local cached records.

## Request Locking / Sequencing Rules

- `refreshDashboard` is guarded by `isSyncing`.
- `refreshAll` is guarded by `isSyncing`.
- `refreshReviewQueues` is guarded by `isSyncing`.
- import failure count is guarded by `isCheckingImportFailureCount`.
- full ImportFailuresView loading is guarded by its local `isLoading`.
- reservation mutations are guarded by `actionInProgressIDs`.
- manual create is guarded by `isCreatingReservation`.
- auto-refresh skips instead of queuing if the app is busy.

## Network Failure Behavior

Refresh failure keeps cached rows visible and sets a non-blocking inline error message.

Mutation failure sets a visible controller error message. The app does not pretend a failed mutation succeeded.

Confirm can return `email_status: failed` while the reservation itself is confirmed. The UI shows that staff must follow up manually.

Import failure count errors do not reset the previous count to zero.

## Remaining Known Limitations

- No waitlist yet.
- No full table map yet.
- No full offline mutation queue yet.
- No reminder UI yet.
- No inbound email reply capture yet.
- Auth is still WordPress application password based for the pilot.
- Schedule refresh still uses the heavier all-reservations path.

## Files Changed

- `Tryzub Reservations/Import/ReservationsController.swift`
- `Tryzub Reservations/Import/ReservationImportService.swift`
- `Tryzub Reservations/Network/ReservationsAPIClient.swift`
- `Tryzub Reservations/Services/ReservationMutationService.swift`
- `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
- `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
- `Tryzub Reservations/Features/Reservations/ImportFailuresView.swift`
- `IOS_DEV_STATUS.md`

## Manual Test Checklist

- App launches and cached Today rows appear immediately.
- Startup makes one fresh Today fetch.
- Pull-to-refresh on Today hits the same path as toolbar refresh.
- Today refresh uses `GET /managed-reservations?date=YYYY-MM-DD`.
- Schedule refresh still works.
- Review refresh loads only new/review queues.
- Today auto-refresh runs about every 90 seconds when visible.
- Auto-refresh skips during confirm, seat, cancel, create, or table assignment.
- Refresh failure keeps cached rows visible and shows an inline message.
- No blocking modal alert appears for normal refresh failure.
- Confirm still calls `POST /managed-reservations/{id}/confirm`.
- PATCH still upserts returned DTOs.
- Create still upserts returned DTOs.
- Failed imports screen loads through `ReservationsController`.
- iOS does not call the backend import endpoint.
