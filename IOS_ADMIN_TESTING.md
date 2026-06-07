# iOS Admin / Testing Guide

Matches current `DeveloperDiagnosticsView`, `ReservationsController.runAdminFetchTest`, and admin-only cleanup flows.

**Source of truth:** Swift code in `Tryzub Reservations/`.

---

## 1. Purpose

Controlled pilot testing and developer troubleshooting:

- API reachability and auth
- Request flow and endpoint contract coverage
- SwiftData cache state vs server
- Notice behavior
- Safe read-only probes without disturbing live reservations

**Not a backend test mode.** No fake data generator. No automated mutation suite.

---

## 2. Access & role requirements

| Tool | Path | Required capability | Effective role today |
| --- | --- | --- | --- |
| API & App Diagnostics | More → API & App Diagnostics | `canViewDeveloperDiagnostics` | **Developer only** |
| Failed Imports | More → Failed Imports | `canViewFailedImports` | Manager + Developer |
| Hidden Reservations | More → Hidden Reservations | `canViewHiddenReservations` | Manager + Developer |
| Hard delete | Hidden screen row action | `canHardDeleteReservations` | **Developer only** |
| Restaurant settings | More → Operations | `canManageRestaurantSettings` | Manager + Developer |
| Business analytics | More → Business Analytics | `canViewAnalytics` | Manager + Developer |
| Guest Lookup / Book Call-In | Guests tab | `canCreateManualReservations` for create | Manager + Developer |
| Guest manage link | Detail → More menu | `canGenerateGuestManageLinks` | Manager + Developer |

**Role note:** `Tryzub_ReservationsApp` uses `AppRoleStore` and `RoleSelectionView`. The selectable pilot roles are **Manager** and **Developer**; `staff` still exists in the capability model but is not selectable today. Switching role in More recreates the root reservation shell with the selected capability set.

---

## 3. Safe tests (GET only)

Implemented as `AdminFetchTest` buttons in `DeveloperDiagnosticsView`. Each posts pass/fail notice; no SwiftData writes.

### Restaurant / public

| Button | Endpoint | Auth |
| --- | --- | --- |
| Test `ping` | `GET /ping` | None |
| Test `restaurant_setup` | `GET /restaurant-setup` | Protected |
| Test `restaurant_hours` | `GET /restaurant-hours` | Protected |
| Test `restaurant_day_availability` | `GET /restaurant-day-availability?date=today` | Protected |
| Test `reservation_slots` | `GET /reservation-slots?date=today` | **Public** |
| Test `reservation_analytics_summary` | `GET /reservation-analytics/summary` | Protected |

### Reservations

These buttons are manual diagnostics probes. They are not the normal startup/tab refresh contract. Normal Host/Bookings refresh uses the shared active-window path documented below.

| Button | Endpoint |
| --- | --- |
| Test `startup_today` | `GET /managed-reservations?date=today` (retry 0) |
| Test `manual_today` | Same (retry 1) |
| Test `failure_count` | `GET /managed-reservations/import-failures?page=1&per_page=1` |
| Test `schedule_window` | `GET ?from=today&to=today+30` |
| Test `review_queues` | `GET ?status=needs_review` + `?status=new` |
| Test `import_failures_full` | `GET /managed-reservations/import-failures?page=1&per_page=50` |
| Test fetch by ID | `GET /managed-reservations/{id}` — enter ID in field |

**These do not:** create, confirm, cancel, seat, hide, block slots, or send email.

---

## 4. Dangerous tests — intentionally NOT automated

Diagnostics **Danger Zone** copy states mutations must use normal staff workflow only.

| Action | Why not automated |
| --- | --- |
| Confirm / Confirm + Email | Changes live reservation + may email guest |
| Cancel / no-show / seat | Status mutations |
| Manual create | Creates server row |
| Hide / restore | Changes visibility |
| Block / unblock slots | Changes availability |
| PATCH restaurant setup/hours | Changes restaurant config |
| Hard delete | Irreversible |
| `POST /managed-reservations/import` | **Forbidden** in iOS workflow |
| Email send test | No isolated test endpoint |

---

## 5. Request log viewer

**Source:** `APIRequestLogStore` — in-memory ring buffer, **100 events**, cleared on app restart.

Each event includes:

- timestamp
- `ReservationAPIRequestReason`
- HTTP method
- sanitized path/query (`search` redacted)
- status code or error
- duration
- outcome (success / failure / skip / cancelled)
- optional response snippet (PII redacted)

**Never logged:** credentials, Authorization header, full guest payloads.

**DEBUG only:** `ReservationAPILogger` also prints to Xcode console.

---

## 6. Endpoint contract checklist

Marks green check when `APIRequestLogStore.hasSuccessfulCall(containing:)` matches during session:

- `GET /ping`
- `GET /restaurant-setup`
- `GET /restaurant-hours`
- `GET /restaurant-day-availability`
- `GET /reservation-slots`
- `GET /restaurant-blocked-slots`
- `GET /reservation-analytics/summary`
- `GET /managed-reservations?date=YYYY-MM-DD`
- `GET /managed-reservations?from=YYYY-MM-DD&to=YYYY-MM-DD`
- `GET /managed-reservations`
- `GET /managed-reservations/{id}`
- `PATCH /managed-reservations/{id}`
- `POST /managed-reservations`
- `POST /managed-reservations/{id}/confirm`
- `POST /managed-reservations/{id}/guest-manage-link`
- `GET /managed-reservations/import-failures`
- `POST /restaurant-blocked-slots`
- `DELETE /restaurant-blocked-slots`

**Import monitor:** `NOT USED: POST /managed-reservations/import` — must stay **Clean** during normal use.

---

## 7. API health & sync scopes

**API Health section shows:**

- base URL
- credentials present (not password)
- current role
- last sync time
- last failed request + reason

**Sync scope snapshots** (per `ReservationSyncScope`):

- Active window, Today legacy/diagnostic, Schedule window legacy/diagnostic, Cancelled window, Hidden reservations, Review queues legacy/diagnostic, Import failure count, per-reservation reconcile
- last attempt / success / failure / in-flight / cooldown

**Operation State section shows:**

- startup sync
- manual refresh
- quiet auto-refresh
- create/mutation/reconcile IDs
- failed-import count loading
- last offline notice

Use these to debug stale data without guessing.

---

## 8. SwiftData cache stats

Shows:

- total cached reservations
- today count
- new / needs_review / confirmed counts
- without-table count
- latest local `lastSyncedAt`

**Reminder:** Cache is not truth. After server-side changes outside the app, pull-to-refresh or wait for auto-refresh.

---

## 9. Feature-specific testing

### Hidden reservations

| Step | Expected |
| --- | --- |
| Hide a test manual row (Detail or Edit) | PATCH `is_hidden=true`; row disappears from Host/Bookings |
| Open More → Hidden Reservations | GET `include_hidden=1`; row appears with reason |
| Restore | PATCH `is_hidden=false`; row returns to normal lists |
| Hard delete (developer only) | DELETE `force=1`; row gone locally and on server |

**Staff should hide mistakes. Developers hard-delete only test noise.**

### Import failures

| Step | Expected |
| --- | --- |
| Open Failed Imports (manager/developer) | GET full import-failures list |
| Open failure detail → repair form | Creates via `createAcceptedManualReservation` |
| Home Form Problems badge | Visible when the selected role has `canViewFailedImports`; fetch is lazy/gated, not part of normal reservation refresh |

### Guest manage link

| Step | Expected |
| --- | --- |
| Open confirmed reservation (manager+) | Detail → More → Generate manage link |
| Tap generate | POST `/guest-manage-link`; URL on pasteboard |
| Copy link | More → Copy manage link; URL on pasteboard |
| Copy draft | More → Copy confirmation draft; local text on pasteboard |
| Notice | “Review it in Gmail before sending.” |
| Verify | **No** `confirmationEmailSentAt` change; **no** Mail sheet auto-opens |
| Paste in Gmail/Mail | Manual MVP confirmation workflow |

### Guest Lookup / Call-In

| Step | Expected |
| --- | --- |
| Open Guests tab | Cached guest lookup appears; no backend guest table is fetched |
| Type 1 letter | No results yet; search activates at 2 name characters or 4 phone digits |
| Search by phone digits | Results prioritize matching phone |
| Tap Book Call-In | Manual form opens with name/phone/email prefilled |
| Phone confirmed unchecked | Add Reservation stays disabled / blocked |
| Check Phone confirmed with caller | Valid call-in can be created through `POST /managed-reservations` as `manual_call_in` |
| Airplane mode | Cached guest results remain visible; create actions are disabled/blocked |
| API log while typing | No GET/POST requests from search typing |

### Confirm Only vs Confirm + Email

| Step | Expected |
| --- | --- |
| Confirm Only on `new` row | PATCH only; no email notice |
| Confirm + Email (usable email) | POST `/confirm`; notice reflects `emailStatus` |
| Confirm + Email disabled | Row without usable email — button disabled in dialog |

### `updated_since` / `server_time`

| Step | Expected |
| --- | --- |
| Launch app; allow startup pass to finish | One `active_window` full refresh appears with `from` and `to`; response `server_time` is stored in memory |
| Keep Home visible and app foreground | Quiet auto-refresh uses `active_window_delta` if a cursor exists |
| Check request log | `active_window_delta` includes `from`, `to`, and `updated_since`; empty deltas upsert nothing and never delete cache rows |
| Kill app; reopen Home; wait 60s | Cursor lost — first auto may full-replace the active window; app does not invent a cursor from device time |
| Manual pull-refresh | Active window full refresh — not delta |

### No-internet testing

| Step | Expected |
| --- | --- |
| Enable airplane mode on Home | Cached reservations still visible |
| Pull refresh | Warning notice “No internet connection / showing saved data”; no crash |
| Restore network; refresh | Success notice; data updates |

### Mutation failure / reconcile

| Step | Expected |
| --- | --- |
| Simulate timeout during PATCH (verify in code / Network Link Conditioner) | Uncertain failure → reconcile GET by ID |
| During reconcile | Operation State shows affected reservation ID in Reconciling IDs |
| Reconcile succeeds | “Server state refreshed” style notice |
| Reconcile fails | “Could not update reservation” / “Confirmation uncertain” |

---

## 10. TestFlight boss-testing checklist

### Boss should test (manager role)

- [ ] Credentials screen saves and app loads reservations
- [ ] Home shows today seated + upcoming; date picker works
- [ ] Pull-to-refresh updates list
- [ ] Open reservation detail — contact tap-to-call/email works
- [ ] **Confirm Only** on a test `new` reservation (no guest email needed)
- [ ] **Seat** and **assign table** on confirmed row
- [ ] **Complete** seated row
- [ ] Create manual call-in reservation — appears as confirmed, no email sent
- [ ] Edit reservation time/party — save diff confirmation works
- [ ] Hide obvious test duplicate — gone from lists
- [ ] Bookings tab shows upcoming reservations; search in All scope
- [ ] Guests tab searches cached guests by name/phone without network calls
- [ ] Guest result → Book Call-In prefills manual form and requires phone confirmation
- [ ] Bookings → Needs Review shows pending queue
- [ ] Generate guest manage link — paste into Mail manually
- [ ] Notices appear and dismiss; app usable during slow network

### Boss should NOT test

- [ ] API & App Diagnostics screen
- [ ] Hard delete
- [ ] Failed Imports repair flow
- [ ] Restaurant settings / blocked slots changes (unless trained)
- [ ] Confirm + Email on real guest without coordination
- [ ] Any DELETE or bulk operations

### Developer should test (before giving boss build)

- [ ] All safe GET tests pass
- [ ] Endpoint checklist turns green during session
- [ ] `POST /import` stays **Clean**
- [ ] Request log has no credentials or raw PII
- [ ] Scope snapshots show reasonable cooldowns after failures
- [ ] Hidden → restore → hard delete on test row only
- [ ] `active_window_delta` appears in auto-refresh log after initial sync and includes `from`, `to`, and `updated_since`
- [ ] Manager role: API Diagnostics and hard delete hidden; Failed Imports visible
- [ ] Staff role is not selectable in the current pilot picker; if enabled later, confirm create/confirm/cancel are hidden and seat still works

---

## 11. Do not use during normal service

Staff on a live floor should **never** use these casually:

| Item | Risk |
| --- | --- |
| API & App Diagnostics | Confusing; not operational UI |
| Hard delete | Permanent data loss |
| Failed Imports repair | Creates real reservations from bad form data |
| Confirm + Email | Sends real guest email without staff intent |
| Restaurant settings / blocked slots | Changes service capacity mid-shift |
| Business analytics | Read-only but distracts; not service UI |
| Developer test buttons | Fire real GET traffic; clutter logs |
| Hidden screen hard delete | Irreversible cleanup |
| Manual create during rush | Without manager oversight |

**Normal service path:** Home → Detail → Confirm Only / Seat / Table / Complete. Use **hide** for mistakes, not delete.

---

## 12. Notices and notification behavior

The app uses `controller.notices` as an in-session notice center:

- The floating notice overlay shows the newest notice for the current visible tab context.
- Tapping the overlay opens a notice sheet.
- More → Notices opens the same current notice list.
- Success and info notices auto-dismiss after about **4 seconds**.
- Warning and error notices stay visible until staff dismisses them or clears all.
- The controller keeps the latest **20 current notices** in memory.
- Notices are not persisted; history is lost on force quit/relaunch.

Examples:

- refresh failed / auto-refresh failed
- offline warning
- mutation did not sync
- confirmation email failed / sent / skipped
- hide / restore / create success
- admin test pass/fail
- manage link ready / failed

Developer diagnostics can show extra request reason / error code / developer details for the same notices. Manager-facing notices stay staff-readable.

---

## 13. Known limitations

- Request logs in-memory only — lost on force quit
- Safe tests are GET-focused
- Schedule test uses fixed 30-day window from today
- No backend test mode flag
- No fake-reservation generator
- No automatic Mail send test
- Cursors not persisted across app restart
- Staff role exists in code but is not selectable in the current pilot role picker
- Guest Memory / Regulars may be expensive on large caches and should be refactored before broad historical usage
- Add/Edit forms share validation/normalization but still need final visual polish

---

## 14. Manual developer checklist (full)

- [ ] Open diagnostics as developer
- [ ] Credentials show present; password not exposed
- [ ] Run all safe GET tests; all pass on production API
- [ ] Fetch by known reservation ID
- [ ] Verify log: reason, method, path, status, duration
- [ ] Verify no payloads/credentials in log
- [ ] Endpoint checklist greens after session
- [ ] Import endpoint stays Clean
- [ ] Scope snapshots update after refresh failures
- [ ] Cache counts match expectation after active-window sync
- [ ] Hide → restore → hard delete on test ID only
- [ ] Guest manage link POST appears in log; pasteboard works
- [ ] Confirm + Email POST `/confirm` appears only when explicitly tested
- [ ] Airplane mode → offline notice → recovery refresh
