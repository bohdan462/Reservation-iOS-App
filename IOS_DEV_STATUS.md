# iOS Reservation App Status

This app is a controlled restaurant pilot client for the private Tryzub Reservations WordPress API.

SwiftData is local cache only. The WordPress backend remains the source of truth. The iOS app does not call the backend import endpoint; Contact Form 7 / Flamingo import is backend-owned.

## 1. Credential Handling

Real WordPress credentials are no longer committed in source.

The app loads API credentials from:

1. `TRYZUB_API_USERNAME` and `TRYZUB_API_PASSWORD` environment variables, if present.
2. The device Keychain, if credentials were entered in the setup screen.

If credentials are missing, the app shows an API credential setup screen and does not create the API client.

Important before TestFlight or restaurant pilot:

- Rotate the WordPress Application Password that was previously exposed in source.
- Enter the new Application Password in the app setup screen.
- Do not commit `LocalCredentials.swift` or `LocalConfig.plist`; both are gitignored as local escape hatches.

## 2. Request Reason Logging

Debug builds print lightweight API request logs without credentials or guest payloads.

Example:

```text
[API] START reason=startup_today method=GET path=/wp-json/tryzub/v1/managed-reservations query=page=1&per_page=50&date=2026-05-19
[API] END reason=startup_today status=200 duration=0.42s path=/wp-json/tryzub/v1/managed-reservations query=page=1&per_page=50&date=2026-05-19
[API] FAIL reason=auto_today error=-1005 duration=30.00s path=/wp-json/tryzub/v1/managed-reservations query=page=1&per_page=50&date=2026-05-19
```

Search query values are redacted in logs.

Current request reasons:

- `startup_today`
- `manual_today`
- `auto_today`
- `failure_count`
- `import_failures_full`
- `schedule_all`
- `review_queues`
- `mutation_patch`
- `mutation_confirm`
- `mutation_create`
- `reconcile_by_id`
- `auto_skip_busy`
- `auto_skip_inactive`
- `auto_skip_cooldown`

Debug logs are also stored in-memory for the Admin / API Diagnostics screen. The store keeps only recent method/path/reason/status/error/duration metadata. It does not store payloads, credentials, or Authorization headers.

## 3. Startup Request Sequence

Startup shows cached SwiftData rows immediately.

Then `ReservationsController.loadIfNeeded(context:)` runs once:

1. Reads latest local sync date for display.
2. Fetches Today only with `GET /managed-reservations?date=YYYY-MM-DD`.
3. Stops the main Today spinner after Today reservations finish.
4. Separately checks form-problem count with `GET /managed-reservations/import-failures?page=1&per_page=1`.

Startup should not call `schedule_all`.

## 4. Manual Refresh Sequence

Today pull-to-refresh and toolbar refresh both call:

```swift
ReservationsController.refreshDashboard(context:)
```

Manual Today refresh logs `reason=manual_today`.

Manual refresh:

- always attempts the backend;
- fetches Today only;
- keeps cached rows visible on failure;
- shows a non-blocking inline error message;
- does not call the import endpoint.

Schedule refresh still uses `reason=schedule_all` and can paginate all managed reservations. This is heavier and should not run on startup.

Review refresh uses `reason=review_queues` and fetches one page each for:

- `status=needs_review`
- `status=new`

## 5. Auto-Refresh Sequence

Today/Host Board runs a 90-second auto-refresh loop while:

- Today screen is visible;
- app `scenePhase` is active;
- no host dialog/sheet is open;
- no reservation refresh is already running;
- no mutation/create is in progress;
- import failure count is not already checking.

Auto-refresh logs:

- `auto_today` when it fetches;
- `auto_skip_busy` when the controller or host UI is busy;
- `auto_skip_inactive` when the app is not active.
- `auto_skip_cooldown` when the backend recently failed and the app is deliberately waiting.

Auto-refresh sleeps before its first attempt, so opening Today does not immediately create a second backend request after startup.

Auto-refresh fetches Today only. It does not show a blocking alert and does not use the main visible spinner.

Cooldown behavior:

- `autoRefreshInterval` is 90 seconds.
- `autoRefreshFailureCooldown` is 120 seconds.
- Startup, manual, or automatic Today refresh failure records a failure timestamp.
- Auto-refresh skips during cooldown.
- Manual refresh still works during cooldown unless another request is already running.

## 6. Import Failure Count Behavior

Import failure count is separate from Today reservation loading.

Today reservations can finish and update `lastSyncedAt` before the form-problem count check finishes.

If count check fails:

- previous count is kept;
- count is not reset to zero;
- a non-blocking form-problem check message can be shown.

The full Import Failures screen loads through `ReservationsController.fetchImportFailures(page:perPage:)`, not by creating API services in the view.

## 6A. Notice / Notification Behavior

Normal refresh failures now become small non-blocking notices instead of large blocking alerts or loud full-width warning blocks.

Notice sources:

- `startup`
- `manualToday`
- `autoToday`
- `schedule`
- `review`
- `mutation`
- `email`
- `credentials`
- `importFailures`
- `admin`

Scope rules:

- Today shows startup/manual/auto Today notices.
- Schedule shows Schedule notices.
- Review shows Review notices.
- Mutation and email notices are global because staff actions may need attention.
- Auto-refresh failures are quiet and do not take over Schedule or Review.

The top-right notice badge can be tapped to open a compact notice list with source, request reason, time, and error code when available.

## 6B. Admin / Diagnostic Screen

Developer users can open `More -> API & App Diagnostics`.

The admin screen shows:

- API base URL and credential-present status;
- current role/capability context;
- last successful sync and last failed request;
- in-memory request log viewer;
- safe GET tests for Today, Schedule, Review, failure count, import failures, and fetch-by-ID;
- SwiftData cache counts;
- current notices;
- endpoint checklist, including `POST /managed-reservations/import` as explicitly not used.

Admin tests do not mutate real reservations by default. There are no confirm/cancel/seat/create/email-send tests in this screen.

## 7. SwiftData Performance Changes

Repository upsert now fetches existing local records once per batch, builds a dictionary by `remoteID`, updates/inserts rows, and saves once.

This replaced the previous one-SwiftData-fetch-per-DTO behavior.

Date formatting for reservation row display now uses cached shared formatters instead of creating new `DateFormatter` instances for every row render.

HostBoard now computes its upcoming/seated/review/no-table snapshot once per render path instead of repeatedly filtering and sorting the same array.

Remaining possible optimization:

- Today, Schedule, and Review still use broad `@Query` reads and local filtering. This is acceptable for pilot-sized data but should eventually move toward predicate-backed queries per screen.

## 8. Dead Code Removed

Removed:

- stale `DIAGNOSTIC_REPORT.md`;
- legacy `ReservationImportService` typealias;
- unused `refreshToday`, `refreshUpcoming`, and `refreshNeedsReview` controller helpers;
- unused `syncUpcoming` and `syncNeedsReview` sync helpers;
- unused HostBoard `done` computed property.

## 9. Current Endpoint Use

The app calls:

- `GET /managed-reservations?date=YYYY-MM-DD`
- `GET /managed-reservations`
- `GET /managed-reservations/{id}`
- `PATCH /managed-reservations/{id}`
- `POST /managed-reservations`
- `POST /managed-reservations/{id}/confirm`
- `GET /managed-reservations/import-failures`

The app does not call:

- `POST /managed-reservations/import`

## 10. Remaining Known Limitations

- No waitlist.
- No table map.
- No full offline mutation queue.
- No reminder UI.
- No inbound email reply UI.
- No production auth flow beyond WordPress Application Password in Keychain.
- Schedule refresh still uses the heavier all-reservations path.
- Device-level credential setup is simple and internal-pilot oriented.
- Admin screen safe tests are GET-focused; mutation testing remains manual through normal app flows.
- Request logs are in-memory only and reset when the app process exits.

## 11. Manual Test Checklist

- [ ] App launches and cached rows appear immediately.
- [ ] Missing credentials show the setup screen.
- [ ] Saved credentials persist through app relaunch.
- [ ] Startup logs one `startup_today` request.
- [ ] Startup does not log `schedule_all`.
- [ ] Startup may log one `failure_count` after Today finishes.
- [ ] Today main spinner stops after Today reservations finish, not after form-problem count.
- [ ] Pull-to-refresh on Today logs `manual_today`.
- [ ] Toolbar refresh on Today logs `manual_today`.
- [ ] Auto-refresh logs `auto_today` about every 90 seconds while active.
- [ ] Auto-refresh logs skip reasons while app is inactive or UI/mutations are busy.
- [ ] After a startup/manual failure, auto-refresh logs `auto_skip_cooldown` instead of immediately retrying.
- [ ] Schedule refresh still works and logs `schedule_all`.
- [ ] Review refresh logs `review_queues` and fetches new/review only.
- [ ] Confirm logs `mutation_confirm`.
- [ ] PATCH status/table/notes logs `mutation_patch`.
- [ ] Create manual reservation logs `mutation_create`.
- [ ] Uncertain mutation failure attempts `reconcile_by_id` once.
- [ ] Failed network keeps cached rows visible.
- [ ] No blocking modal refresh alert appears for normal refresh failure.
- [ ] Small notice badge appears for scoped refresh/action errors.
- [ ] More -> API & App Diagnostics shows request logs and safe GET test results.
- [ ] iOS does not call the backend import endpoint.
- [ ] App builds.
