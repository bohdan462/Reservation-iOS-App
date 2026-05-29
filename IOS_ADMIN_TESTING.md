# iOS Admin / Testing Screen

## 1. Purpose

The Admin / API Diagnostics screen is for controlled restaurant pilot testing and developer troubleshooting.

It helps verify API reachability, request flow, SwiftData cache state, and notice behavior without disturbing real reservations.

## 2. Access

Open:

`More -> API & App Diagnostics`

The screen is shown only when the app role has `canViewDeveloperDiagnostics`.

## 3. Safe Tests

The screen includes safe GET tests (via `AdminFetchTest`):

**Restaurant / public endpoints**
- Test `ping` — `GET /ping` (no auth)
- Test `restaurant_setup` — `GET /restaurant-setup`
- Test `restaurant_hours` — `GET /restaurant-hours`
- Test `restaurant_day_availability` — `GET /restaurant-day-availability`
- Test `reservation_slots` — `GET /reservation-slots` (public, no auth)
- Test `reservation_analytics_summary` — `GET /reservation-analytics/summary`

**Reservation sync endpoints**
- Test `startup_today`
- Test `manual_today`
- Test `failure_count`
- Test `schedule_window`
- Test `review_queues`
- Test `import_failures_full`
- Test fetch by managed reservation ID

These tests read from the backend and summarize decoded results. They do not create, confirm, cancel, seat, or email reservations.

## 4. Dangerous Tests Not Implemented

The screen intentionally does not include automatic mutation tests.

Not implemented here:

- confirm reservation;
- cancel reservation;
- seat reservation;
- no-show reservation;
- create fake reservation;
- send confirmation email;
- block/unblock time slots;
- PATCH restaurant setup or hours;
- call backend import endpoint.

Any real mutation must happen through the normal reservation workflow with explicit staff action.

## 5. Request Log Viewer

The screen shows the recent in-memory API request log.

Each log event includes:

- time;
- request reason;
- method;
- sanitized path/query;
- status or error;
- duration;
- outcome.

The log does not include:

- credentials;
- Authorization header;
- raw reservation payloads;
- guest notes;
- full search text.

Search query values are redacted.

## 6. API Health Checks

The API Health section shows:

- base URL;
- credential-present status;
- current role;
- last sync time;
- last failed request;
- last failed request reason.

The app does not expose the WordPress Application Password.

The diagnostics screen also shows sync scope snapshots:

- Today scope;
- Schedule window scope;
- Review queues scope;
- failure-count scope;
- single-reservation reconciliation scopes after they run.

Each scope can show last attempt, success, failure, in-flight state, and cooldown.

## 7. Endpoint Contract Checklist

The **Endpoint Contract Checklist** section marks endpoints that succeeded during the current session (green checkmark when `APIRequestLogStore` has a successful call):

- `GET /ping`
- `GET /restaurant-setup`
- `GET /restaurant-hours`
- `GET /restaurant-day-availability`
- `GET /reservation-slots`
- `GET /restaurant-blocked-slots`
- `GET /reservation-analytics/summary`
- `GET /managed-reservations?date=YYYY-MM-DD`
- `GET /managed-reservations`
- `GET /managed-reservations/{id}`
- `PATCH /managed-reservations/{id}`
- `POST /managed-reservations`
- `POST /managed-reservations/{id}/confirm`
- `GET /managed-reservations/import-failures`
- `POST /restaurant-blocked-slots`
- `DELETE /restaurant-blocked-slots`

Also shown: **NOT USED: POST /managed-reservations/import** — should stay **Clean** during normal app use.

## 8. Cache Stats

The SwiftData Cache section shows:

- total cached reservations;
- Today cached reservations;
- new count;
- needs-review count;
- confirmed count;
- without-table count;
- latest local sync timestamp.

SwiftData remains local cache only. The WordPress backend remains source of truth.

## 9. Notification Center Preview

The admin screen shows current app notices.

Examples:

- refresh failed;
- auto-refresh failed;
- mutation did not sync;
- confirmation email failed;
- form problem check failed;
- admin test result.

Notices can be dismissed or cleared.

## 10. Manual Test Checklist

- [ ] Open the screen as developer.
- [ ] Confirm credentials show as present without exposing password.
- [ ] Run `Test ping`.
- [ ] Run `Test restaurant_setup`.
- [ ] Run `Test restaurant_hours`.
- [ ] Run `Test restaurant_day_availability`.
- [ ] Run `Test reservation_slots`.
- [ ] Run `Test reservation_analytics_summary`.
- [ ] Run `Test startup_today`.
- [ ] Run `Test manual_today`.
- [ ] Run `Test failure_count`.
- [ ] Run `Test schedule_window`.
- [ ] Run `Test review_queues`.
- [ ] Run `Test import_failures_full`.
- [ ] Enter a known reservation ID and run fetch by ID.
- [ ] Confirm request logs show reason, endpoint, status/error, and duration.
- [ ] Confirm no payloads or credentials appear in logs.
- [ ] Confirm notices appear in the notification preview.
- [ ] Confirm endpoint checklist marks successful calls during the session.
- [ ] Confirm `POST /managed-reservations/import` stays clean/not used.

## 11. Known Limitations

- Request logs are in-memory only and clear when the app process restarts.
- Safe tests are GET-focused.
- Schedule tests use the current 30-day schedule window.
- There is no backend test mode yet.
- There is no fake-reservation generator.
- There is no automatic email test.
- There is no full production diagnostics/export workflow.
