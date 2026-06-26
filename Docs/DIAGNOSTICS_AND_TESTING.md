# Diagnostics and testing

**Status:** Current source of truth (supersedes `IOS_ADMIN_TESTING.md`)  
**Branch:** `audit-current-state`  
**Audit date:** 2026-06-26

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
5. Reservation attachments — `AttachmentFeatureFlag.remoteUploadEnabled` is **true** (Slice D `d947721`; Slice E polish `9d2784d`); normal reservation refresh must not auto-download attachment bytes; live cross-device verification still open

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

## Guest memory / person-map test (`d541488`)

1. On fresh install or first session, guest profile **full-list sync** eventually marks `fullListSyncCompleted` (local count reconciled with backend total).
2. **Guests tab** and **manual intake** can find a known guest that would have been outside the old 500-profile lookup cap.
3. **No backend call** occurs on every phone digit while typing in Guests or manual intake.
4. If full-list sync is incomplete, guest profile sync **does not wait on 15-minute TTL** before retrying full paginated sync.
5. Full guest history is **not** prefetched for every profile — detail/history remains on open.

## Backend guest profile lookup smoke test (`1431a06`)

**Status:** checklist only — route **deployed** at `1431a06`; **device smoke tests not yet passed**.

Requires staff auth (`tryzub_can_read_reservations`). Backend `1431a06` is live on WordPress.

1. Unauthenticated `GET /guest-profiles/lookup` → **401/403**
2. Known exact `email=` → one `strong` candidate; `best_match_guest_key`, `best_match_basis`, `best_match_confidence: strong` all populated
3. Known exact 10-digit `phone=` → one `strong` candidate; best-match fields populated
4. `email` + `phone` resolving to **same** profile → one candidate; unambiguous strong best match
5. `email` + `phone` resolving to **different** profiles → multiple candidates; **all best-match fields null**
6. Name-only walk-in `q=` → `possible` candidates with `match_basis: name`; **all best-match fields null**
7. 7–9 digit `phone=` → `possible` candidates; best-match fields null
8. Four-digit `phone=` only → `profiles: []`; best-match fields null
9. No params → **400**
10. Lookup result `guest_key` opens `GET /guest-profiles/{guest_key}` with `booking_history` and `notes_history` intact
11. Paginated `GET /guest-profiles` list behavior unchanged

**Do not claim:** device smoke tests passed, name-only result is confirmed identity, lookup returns full history.

## Manual Intake walk-in + guest lookup (`63d0cfc` + `e775f52` + `ad5d274`)

**Status:** checklist only — backend `63d0cfc` **deployed** to WordPress (root pointer `c7f5a69`); iOS `e775f52` + input polish `ad5d274` shipped; **device smoke tests not yet passed** — **ready to test on physical device**. P1/P2 findings: [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md).

Requires staff auth for backend lookup routes.

1. Unknown walk-in party/time only → **Add** → review sheet → **confirm** → save
2. Response shows Walk-in guest / blank phone/email / seated
3. Unknown walk-in does not create fake Guest Memory profile
4. Walk-in partial phone → save; phone omitted from payload
5. Call-in blank phone → blocked **before** review sheet
6. Call-in valid name+phone → save
7. Manual Intake has **no** pre-create confirmation/message buttons (`GuestTextMessageActionButtons` removed)
8. Reservation Detail still has confirmation/message workflow after reservation exists
9. Type known guest name/phone/email → local candidates after debounce (~250–300 ms)
10. **Search all guest records** → backend candidates; staff must tap **Use guest**; no auto-pick
11. **View history** from candidate with `guestKey` → shared Guest history shell
12. No `/guest-profiles/lookup` while typing in Manual Intake

**Do not claim:** full booking/notes timeline in Guest history; device smoke tests passed; TestFlight uploaded.

## Host header + flicker test (`71601fc` + `39f7fcb`)

1. Host header shows **`Last sync HH:mm`** after successful sync (not `Updated`)
2. When sync is stale (>2 min) and auto-refresh skipped, secondary shows staff reason (`Paused`, `Paused while editing`, `Waiting — busy`, `Retry soon`, or `May be out of date · tap refresh`)
3. **Live on + today:** header should not sit stale without explanation when foreground and no modal open
4. **Quiet off-hours** (no seated, no reservations within ~90 min): board should not visibly flicker every minute from idle snapshot timing (`71601fc`)
5. **Host Intelligence card:** inline chips should not disappear/reappear when intelligence refreshes (`39f7fcb`)
6. **During service** (seated or due soon): seated duration / due labels still update over time
7. Manual **Refresh** from Host ⋯ menu bumps `Last sync` on success

## Device smoke verification (`804c130` → `3da3a68`)

**Status:** code Phases 1–4 **landed**; **physical device verification not yet passed**. Full checklist: [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) §10.

Requires physical device (iPhone and/or iPad as noted per item):

- [ ] Live button tappable on **iPad** without Home button
- [ ] Last row clears floating tab bar on **iPhone and iPad** (Bookings + Host)
- [ ] Manual Intake candidates stay visible above **iPhone** keyboard
- [ ] Live walk-in create → review sheet → save as seated now
- [ ] Seated duration appears on new walk-ins
- [ ] Attach known guest on walk-in edit; source remains walk-in
- [ ] Walk-in edit name-only/no-phone saves
- [ ] Floor Plan assignment when backend layout exists; no raw table string
- [ ] Auto-confirm / confirmation / reminder indicators on list rows without opening detail
- [ ] More no longer shows Email Controls; Restaurant Settings has **This Device Email** + backend reminder/auto-confirm

**Do not claim:** device smoke passed; code landed ≠ verification complete.

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
- [ ] Guests tab finds backend-known guest after sync (`67e02d2`); known guest outside old 500 cap findable (`d541488`)
- [ ] Guest profile full-list sync completes; no per-digit backend calls during Guests/intake typing (`d541488`)
- [ ] Confirm with email (Mail flow)
- [ ] Confirm without email
- [ ] Shift reminder email + text review
- [ ] Seat / complete / cancel / no-show
- [ ] Floor assign (if layout configured)
- [ ] Bookings search + detail
- [ ] Activity history on detail + More
- [ ] Backend guest profile lookup smoke tests after WordPress deploy (`1431a06`) — staff auth only
- [ ] Manual Intake walk-in + guest lookup + input polish on physical device (`e775f52`, `ad5d274`; backend `63d0cfc` **deployed**)
- [ ] Backend unknown walk-in contract smoke tests on WordPress (`63d0cfc` **deployed**)
- [ ] Device smoke Phases 1–4 verification on physical device (`804c130` → `3da3a68` — code landed)
- [ ] Reservation attachment live verification — cross-device list/upload/edit/download/delete against deployed backend (`a2422d3`); iOS wired through Slice E (`9d2784d`); old local-only attachments may need reattach; upload/list race follow-up if observed; **not fully passed/recorded — do not claim passed**
- [ ] More → Restaurant Settings: **This Device Email** + backend reminders/auto-confirm (no Email Controls)
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
