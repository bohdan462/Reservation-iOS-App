# Diagnostics and testing

**Status:** Current source of truth (supersedes `IOS_ADMIN_TESTING.md`)  
**Branch:** `audit-current-state`  
**Audit date:** 2026-06-14

## Roles

| Role | Diagnostics | Dangerous actions |
|------|-------------|-------------------|
| Manager | Limited | No hard delete, no import trigger |
| Developer | Full `DeveloperDiagnosticsView` | Hard delete, endpoint probes |

## Safe invariants (must stay true)

1. Normal refresh never calls `POST /import`
2. `isBackendConfirmEmailEnabled == false` in production restaurant test build (unless explicitly changed)
3. Local model never PATCHes reservations
4. Activity history — iOS never POSTs activity events

## Confirmation test (current MVP)

**Do not** test “Confirm Only = PATCH only”. Current flow:

1. Open reservation with email in **new** or **needs_review**
2. Tap Confirm
3. **Expect:** Mail composer with styled HTML (not immediate status change)
4. Send mail (or cancel)
5. On send: reservation becomes **confirmed**; `manual-email-log` recorded
6. Without email: immediate PATCH confirmed + message “without email”

**Traces:** `ConfirmFlowTrace` in DEBUG console

## Shift reminders test

1. Host → ⋯ → **Shift reminders** OR Bookings → bell icon
2. Sheet shows eligible counts
3. Tap **Email** on a row → review sheet → approve → Mail composer
4. On send: `manual-email-log` `reminder`; status **not** forced to confirmed

## Sync / cache test

1. Manual pull refresh on Host → forced full active window
2. Cancel reservation on another device → within full sync cycle, row should leave Host list (known gap if only delta — see OPEN_WORK P0-2)
3. Developer: verify `ActiveWindowFreshnessTrace` shows full vs delta

## Host header + flicker test (`71601fc` + `39f7fcb`)

1. Host header shows **`Last sync HH:mm`** after successful sync (not `Updated`)
2. When sync is stale (>2 min) and auto-refresh skipped, secondary shows staff reason (`Paused`, `Paused while editing`, `Waiting — busy`, `Retry soon`, or `May be out of date · tap refresh`)
3. **Live on + today:** header should not sit stale without explanation when foreground and no modal open
4. **Quiet off-hours** (no seated, no reservations within ~90 min): board should not visibly flicker every minute from idle snapshot timing (`71601fc`)
5. **Host Intelligence card:** inline chips should not disappear/reappear when intelligence refreshes (`39f7fcb`)
6. **During service** (seated or due soon): seated duration / due labels still update over time
7. Manual **Refresh** from Host ⋯ menu bumps `Last sync` on success

## Floor / table test

1. Floor tab with backend layout → assign via sheet
2. Verify `PATCH /tables` in request log (developer)
3. Do not rely on free-text `tableName` when layout exists

## Guest intelligence test

1. Open guest with email on detail
2. Before network completes, caption should not claim confirmed visit count
3. After load, server-backed line preferred over local pool

## Guest messaging test

1. Draft guest message → review sheet shows beta warning if AI source
2. Manual/clarification email sent → no `manual-email-log` as confirmation; trace `unsupported_email_type`

## TestFlight checklist (abbreviated)

- [ ] Login manager + developer
- [ ] Host tab loads cache-first
- [ ] Host header shows `Last sync`; stale secondary when appropriate (`71601fc`)
- [ ] Host board quiet off-hours — no minute idle flicker; intelligence-card chips stable during refresh (`39f7fcb`); seated/due timing still updates in service
- [ ] Guests tab finds backend-known guest after sync (`67e02d2`)
- [ ] Confirm with email (Mail flow)
- [ ] Confirm without email
- [ ] Shift reminder email + text review
- [ ] Seat / complete / cancel / no-show
- [ ] Floor assign (if layout configured)
- [ ] Bookings search + detail
- [ ] Activity history on detail + More
- [ ] Logout clears session

## Cache reset (developer)

Use diagnostics cache reset when testing stale-row behavior. Expect: SwiftData cleared, sync cursors reset, intelligence stores cleared.

## Failure scenarios

| Scenario | Expected staff experience |
|----------|---------------------------|
| Offline mutation | Error notice; optimistic status reverted where implemented |
| Mail cancelled | No `manual_sent`; status unchanged |
| 404 reconcile | Detail fetch attempted; error if not on server |
| Hard delete other device | Row may persist until full sync |

## Related docs

- [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md)
- [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md)
- [OPEN_WORK.md](./OPEN_WORK.md)

## Historical

`IOS_ADMIN_TESTING.md` — outdated confirm section; use this doc instead.
