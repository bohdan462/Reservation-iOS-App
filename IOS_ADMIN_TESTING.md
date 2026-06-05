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
| Failed Imports | More → Failed Imports | `canViewFailedImports` **AND** `canViewDeveloperDiagnostics` | **Developer only** (UI quirk) |
| Hidden Reservations | More → Hidden Reservations | `canViewHiddenReservations` | Manager + Developer |
| Hard delete | Hidden screen row action | `canHardDeleteReservations` | **Developer only** |
| Restaurant settings | More → Operations | `canManageRestaurantSettings` | Manager + Developer |
| Business analytics | More → Business Analytics | `canViewAnalytics` | Manager + Developer |
| Guest manage link | Detail → More menu | `canGenerateGuestManageLinks` | Manager + Developer |

**Production note:** `Tryzub_ReservationsApp` hardcodes `role: .developer`. Before boss TestFlight, switch to `.manager` or `.staff` to test real gating.

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

| Button | Endpoint |
| --- | --- |
| Test `startup_today` | `GET /managed-reservations?date=today` (retry 0) |
| Test `manual_today` | Same (retry 1) |
| Test `failure_count` | `GET /import-failures?page=1&per_page=1` |
| Test `schedule_window` | `GET ?from=today&to=today+30` |
| Test `review_queues` | `GET ?status=needs_review` + `?status=new` |
| Test `import_failures_full` | `GET /import-failures?page=1&per_page=50` |
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
- `GET /managed-reservations`
- `GET /managed-reservations/{id}`
- `PATCH /managed-reservations/{id}`
- `POST /managed-reservations`
- `POST /managed-reservations/{id}/confirm`
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

- Today, Schedule window, Review queues, Import failure count, per-reservation reconcile
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
| Hide a test manual row (Detail or Edit) | PATCH `is_hidden=true`; row disappears from Home/List/Review |
| Open More → Hidden Reservations | GET `include_hidden=1`; row appears with reason |
| Restore | PATCH `is_hidden=false`; row returns to normal lists |
| Hard delete (developer only) | DELETE `force=1`; row gone locally and on server |

**Staff should hide mistakes. Developers hard-delete only test noise.**

### Import failures

| Step | Expected |
| --- | --- |
| Open Failed Imports (developer UI today) | GET full import-failures list |
| Open failure detail → repair form | Creates via `createAcceptedManualReservation` |
| Home Form Problems badge | Visible only when developer caps both true |

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

### Confirm Only vs Confirm + Email

| Step | Expected |
| --- | --- |
| Confirm Only on `new` row | PATCH only; no email notice |
| Confirm + Email (usable email) | POST `/confirm`; notice reflects `emailStatus` |
| Confirm + Email disabled | Row without usable email — button disabled in dialog |

### `updated_since` / `server_time`

| Step | Expected |
| --- | --- |
| Open Home; wait 60s with app foreground | Auto refresh uses delta if prior today sync stored cursor |
| Kill app; reopen Home; wait 60s | Cursor lost — auto may full-replace today (verify in log: no `updated_since`) |
| Manual pull-refresh | Always full today replace — never delta |
| Check request log | `updated_since` query param only on auto today refresh |

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

### Boss should test (manager role — switch before build)

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
- [ ] List tab shows upcoming reservations; search in All scope
- [ ] Review tab shows pending queue
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
- [ ] `updated_since` appears in auto-refresh log after initial sync
- [ ] Manager role build: Failed Imports **hidden** (current UI); confirm boss won't need it
- [ ] Staff role build: confirm/cancel/create hidden; seat still works

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

## 12. Notification center preview

Diagnostics shows live `controller.notices`. Examples:

- refresh failed / auto-refresh failed
- offline warning
- mutation did not sync
- confirmation email failed / sent / skipped
- hide / restore / create success
- admin test pass/fail
- manage link ready / failed

Dismiss individually or clear all from diagnostics.

---

## 13. Known limitations

- Request logs in-memory only — lost on force quit
- Safe tests are GET-focused
- Schedule test uses fixed 30-day window from today
- No backend test mode flag
- No fake-reservation generator
- No automatic Mail send test
- Cursors not persisted across app restart
- Manager cannot open Failed Imports in current UI (developer gate)

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
- [ ] Cache counts match expectation after today sync
- [ ] Hide → restore → hard delete on test ID only
- [ ] Guest manage link POST appears in log; pasteboard works
- [ ] Confirm + Email POST `/confirm` appears only when explicitly tested
- [ ] Airplane mode → offline notice → recovery refresh
