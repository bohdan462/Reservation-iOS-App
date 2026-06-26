# Open work — V1 stabilization backlog

**Branch:** `audit-current-state`  
**Root HEAD:** `ad5d274` (docs `75dce15` pushed to `origin/audit-current-state`)  
**Last reviewed:** 2026-06-25  
**Scope:** V1 stabilization + guest memory foundation — no V2 automation unless noted

**Priority order:** [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) owns what to do next. This file tracks backlog items and implementation status. Production/device verification remains open even when code is implemented.

**Not V1:** offline manual reservation queue; offline create/edit sync queue; full AI clustering / “knows each other”; VIP editor without backend contract.

Every item includes risk, files, approach, acceptance test, and classification.

---

## P0 — Trust and cache correctness

### P0-1: Expand `isContentEquivalent` field coverage

| Field | Value |
|-------|-------|
| **Risk if not fixed** | Staff sees stale confirmation/reminder sent state; superseded rows look active |
| **Files** | `Persistence/ReservationRecord.swift`, `Services/ReservationRepository.swift` |
| **Approach** | Include `confirmationEmailSentAt`, `reminderEmailSentAt`, `supersededById`, `sourceType` in equivalence OR always merge those fields on upsert |
| **Acceptance** | PATCH response updating only `confirmationEmailSentAt` writes to SwiftData; `[NOOP_REFRESH_TRACE]` not emitted for that case |
| **Class** | V1 stabilization — iOS only |

Implemented 2026-06-15: `isContentEquivalent` now compares all server-backed fields written by `update(from:)`, including confirmation/reminder timestamps, supersession, source, creator, and hidden metadata.

### P0-2: Scheduled full active-window replace

| Field | Value |
|-------|-------|
| **Risk** | Delta leaves ghost rows (cancelled/moved/hidden on server still in cache) |
| **Files** | `Import/ReservationsController.swift`, `Import/ReservationImportService.swift` |
| **Approach** | After N delta cycles or on tab activation if last full > X hours, force `syncActiveWindowFull`; document policy in IOS_LIFECYCLE_AND_SYNC |
| **Acceptance** | Cancel reservation on server → disappears from Host within one full sync cycle without manual app reinstall |
| **Class** | V1 stabilization — iOS only |

Implemented 2026-06-15: automatic active-window refresh now forces full replace when no successful full has been recorded in the controller session, after 5 successful deltas since the last full, or when the last successful full is older than 2 hours. Manual Host/Bookings refresh remains forced full; delta remains upsert-only.

Also implemented: active-window `server_time` cursors and scope success metadata persist in UserDefaults so delta/full policy resumes after relaunch (not an offline mutation queue). **Device/production verification still open** — see IMPLEMENTATION_QUEUE #4.

### P0-3: Confirm pending UI state

| Field | Value |
|-------|-------|
| **Risk** | Staff thinks reservation unconfirmed while Mail composer open; or confirmed before mail sent |
| **Files** | `ReservationDetailView.swift`, `ReservationActionButtons.swift`, `DetailActionBar` |
| **Approach** | Show “Confirmation email pending” while mail draft open; only show confirmed after `manual_sent` + PATCH |
| **Acceptance** | Detail status badge matches server until mail `.sent`; traces show `ConfirmFlowTrace` phases in order |
| **Class** | V1 stabilization — iOS only |

---

## P1 — Systems fighting each other

### P1-1: Unify auto-refresh gating (Host vs Bookings)

| Field | Value |
|-------|-------|
| **Risk** | Bookings delta-syncs for past dates while Host does not; staff confused by different freshness |
| **Files** | `HostBoardView.swift`, `ReservationsListView.swift`, `ReservationsController.swift` |
| **Approach** | Single policy: auto delta only when selected date is today OR explicit “live service” flag; otherwise manual refresh only |
| **Acceptance** | Viewing past date on Bookings does not trigger 60s network loop |
| **Class** | V1 stabilization — iOS only |

**Related implemented (2026-06-19, `b910bd1`):** foreground return and privacy-cover dismiss call `autoRefreshDashboardIfAllowed`. Device verification still open.

### P1-2: Block legacy `tableName` PATCH when backend layout exists

| Field | Value |
|-------|-------|
| **Risk** | Silent fallback assigns free-text table conflicting with floor plan |
| **Files** | `TableAssignmentCoordinator.swift`, `FloorPlanStore.swift`, assignment sheets |
| **Approach** | If `hasBackendLayout` and key unresolved → staff error, no legacy PATCH |
| **Acceptance** | Assignment with backend tables always uses `PATCH /tables` or shows blocking message |
| **Class** | V1 stabilization — iOS only |

### P1-3: Guest intelligence loading uncertainty copy

| Field | Value |
|-------|-------|
| **Risk** | “Seen before” from local cache before server contradicts |
| **Files** | `GuestHistorySemantics.swift`, `GuestProfileViewState.swift`, `GuestInsightsView.swift` |
| **Approach** | Until profile/date summary loads, show “Checking guest history…” not visit counts |
| **Acceptance** | Slow network: no “prior visits” line until server or explicit local_bounded mode |
| **Class** | V1 stabilization — iOS only |

### P1-4: Wire `GuestIntelligenceStore` to `FreshnessCoordinator`

| Field | Value |
|-------|-------|
| **Risk** | Duplicate fetches; stale 180s data after mutations |
| **Files** | `GuestIntelligenceStore.swift`, `FreshnessCoordinator.swift`, `ReservationActivityInvalidation` |
| **Approach** | Invalidate guest intel on reservation mutation for affected date |
| **Acceptance** | After seat/cancel, guest intel refetches within one visibility cycle |
| **Class** | V1 stabilization — iOS only |

---

## P2 — Noise reduction and maintainability

### P2-1: Remove dead sync methods

| Field | Value |
|-------|-------|
| **Risk** | Future agent re-wires legacy `performTodayRefresh` / `syncAllReservations` |
| **Files** | `ReservationsController.swift`, `ReservationImportService.swift` |
| **Approach** | Delete unused methods; grep confirms zero callers |
| **Acceptance** | Build passes; no references to removed symbols |
| **Class** | V1 stabilization — iOS only |

### P2-2: Host Intelligence staff-facing AI label

| Field | Value |
|-------|-------|
| **Risk** | Local model prose presented with same weight as deterministic facts |
| **Files** | `HostIntelligenceCard.swift`, `HostIntelligenceController.swift` |
| **Approach** | When `briefingSource == .localModel`, show staff-only “AI wording (beta)” — not hidden by `staffFacingPresentation` |
| **Acceptance** | Host card shows label when enhanced briefing on; guest emails still never mention AI |
| **Class** | V1 stabilization — iOS only |

### P2-3: Hard delete multi-device documentation + UI note

| Field | Value |
|-------|-------|
| **Risk** | Staff assumes delete propagates instantly to all iPads |
| **Files** | `DIAGNOSTICS_AND_TESTING.md`, hard delete UI in More |
| **Approach** | Confirm dialog explains other devices until sync |
| **Acceptance** | Dialog copy present; documented in testing checklist |
| **Class** | V1 stabilization — docs + iOS |

### P2-4: Update legacy iOS reference docs

| Field | Value |
|-------|-------|
| **Risk** | QA follows wrong confirm flow |
| **Files** | `PROJECT_MAP.md`, `PROJECT_METHOD_MAP.md`, `ARCHITECTURE_DIAGRAMS.md` |
| **Approach** | Align confirm, shift reminders, no-show sections with RESERVATION_WORKFLOWS.md |
| **Acceptance** | No doc says “Confirm Only = PATCH only” without Mail-first qualifier |
| **Class** | V1 stabilization — docs only |

---

## P1 — Guest memory (post-foundation)

### P1-6: Indexed / predicate-based local guest search

| Field | Value |
|-------|-------|
| **Risk** | Full-table in-memory filter degrades as guest list grows |
| **Files** | `GuestProfileRepository.swift`, `GuestLookupStore.swift` |
| **Approach** | SwiftData predicates / phone-prefix index; avoid scanning all rows on each keystroke |
| **Acceptance** | Lookup remains local-only; search latency stable with 500+ cached profiles |
| **Class** | **Required before broader product release** — acceptable for current Tryzub V1 data size as-is |
| **Queue** | [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #6 |

### P1-7: Backend targeted guest lookup by phone/email/name

| Field | Value |
|-------|-------|
| **Risk** | Known guest invisible when not yet in local cache or name-only weak match |
| **Files** | Backend `guest-profiles.php`, `routes.php`; iOS `ReservationsAPIClient`, `GuestProfileStore`, `GuestLookupView`, `ManualReservationFormView` |
| **Approach** | `GET /guest-profiles/lookup` with exact email/phone and possible name candidates |
| **Acceptance** | Strong phone/email input returns canonical `guest_key` profile when backend has it; name-only never auto-canonical |
| **Class** | **Done** — backend `1431a06` **deployed** to WordPress; iOS foundation `823f42c` + Guests tab UI `1dfa14a` + Manual Intake UI `e775f52`; **device lookup smoke tests still open** |
| **Queue** | [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #16, #20, #21, #17 |

### P1-8: Manual Intake backend lookup + walk-in/call-in validation (Slice 3M)

| Field | Value |
|-------|-------|
| **Risk** | Staff cannot find guest by name during intake; walk-in blocked without phone/name |
| **Files** | `ManualReservationFormView.swift`, `GuestLookupStore.swift`, `GuestLookupModels.swift`, `GuestProfileStore.swift`; backend `managed-reservations.php` (`63d0cfc`) |
| **Approach** | Local name/phone/email search while typing; explicit all-record lookup; Use guest / View history; walk-in blank identity; call-in name+phone |
| **Acceptance** | No network on every digit; multiple name matches shown; staff must tap; walk-in save without phone/name with backend `63d0cfc` deployed |
| **Class** | **Done** — iOS `e775f52`; backend `63d0cfc` / `c7f5a69` **deployed**; **device smoke tests still open** |
| **Queue** | [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #17, #18 |

### P1-8d: Manual Intake input polish (post-3M)

| Field | Value |
|-------|-------|
| **Risk** | Accidental create during live service; pre-create message actions confuse staff before reservation exists |
| **Files** | `ManualReservationFormView.swift`, `GuestLookupStore.swift` |
| **Approach** | Keep final review sheet; remove `GuestTextMessageActionButtons` from Manual Intake; keyboard Next/Done; debounced local lookup; phone threshold 7 digits |
| **Acceptance** | Add opens review sheet before create; no pre-create send-confirmation UI; Reservation Detail confirm/message still works post-create |
| **Class** | **Done** — `ad5d274`; **device smoke tests still open** |
| **Queue** | [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #17b |

### P1-8b: Regulars cache-first + shared Guest history (Slice 3R)

| Field | Value |
|-------|-------|
| **Risk** | Guest Memory shows “25 of 101” while full cache exists; tap runs heavy `GuestInsightsView` |
| **Files** | `RegularGuestsView.swift`, `ReservationsListView.swift`, `GlobalServiceIntelligenceView.swift` |
| **Approach** | Primary list from `GuestProfileCacheRecord` via `@Query`; tap → `GuestProfileDetailView(guestKey:)` |
| **Acceptance** | All cached profiles browsable locally; no network page cap as primary UI |
| **Class** | **Done** — `50df843` |
| **Queue** | [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #11 |

### P1-8c: iOS backend fallback when local cache incomplete / no match (Guests/Manual — partial)

| Field | Value |
|-------|-------|
| **Risk** | Staff cannot find guest when local full-list sync incomplete |
| **Files** | `GuestLookupView.swift` (done for explicit search), `ManualReservationFormView.swift` (open) |
| **Approach** | Guests tab + Manual Intake: explicit Search all guest records (`1dfa14a`, `e775f52`) |
| **Acceptance** | No network on every digit |
| **Class** | **Done** in 3B + 3M |

### P1-9: Detail blob persistence for opened guest profiles

| Field | Value |
|-------|-------|
| **Risk** | Re-opened detail re-fetches full history; offline detail preview thin |
| **Files** | `GuestProfileRepository.swift`, `GuestProfileStore.swift` |
| **Approach** | Encode `booking_history` / `notes_history` into SwiftData on detail fetch for disk-first full profile reopen |
| **Acceptance** | Second open of same guest uses disk detail blobs when fresh enough |
| **Class** | Later slice — not V1 stabilization blocker |
| **Queue** | [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #19 (Slice 3E) |

### P1-10: Guest profile re-sync on foreground / mutations

| Field | Value |
|-------|-------|
| **Risk** | New backend profiles not visible until next app session |
| **Files** | `AppReservationSession.swift`, `GuestProfileSyncService.swift` |
| **Approach** | Trigger incremental sync on foreground return or reservation mutation (optional) |
| **Acceptance** | Profile list updates within one visibility cycle after server change |
| **Class** | Optional follow-up — not V1 stabilization blocker |
| **Queue** | [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #23 |

---

## P3 — Structural (post-stabilization)

### P3-1: Split `ReservationsListView.swift`

| Field | Value |
|-------|-------|
| **Risk** | Merge conflicts; hard onboarding |
| **Files** | `ReservationsListView.swift` → Host/Bookings/More files |
| **Approach** | Extract `HomeDashboardView`, `ReservationScheduleView`, `ReservationMoreView` to separate files |
| **Acceptance** | Behavior unchanged; build passes |
| **Class** | V1.1 — iOS only |

---

## Open from archived handoffs (verified still open)

### OW-1: Bookings service-state tabs (Active / Seated / Completed)

| Field | Value |
|-------|-------|
| **Risk** | Staff mental model mismatch during service |
| **Files** | `ReservationsListView.swift` (`ReservationScheduleScope`) |
| **Approach** | Add scopes filtering `confirmed`/`seated`/`completed` for selected date |
| **Acceptance** | Bookings can filter today’s seated without Host tab |
| **Class** | **V2 feature** (was in workflow handoff; defer until P0–P1 done) |

### OW-2: Backend confirmation email (`POST /confirm`)

| Field | Value |
|-------|-------|
| **Risk** | Re-enabling bypasses staff review |
| **Files** | `ReservationEmailWorkflow.swift`, controller, action buttons |
| **Approach** | Only with explicit product decision + Resend integration |
| **Acceptance** | N/A — **out of V1** |
| **Class** | V2 — backend + iOS |

### OW-3: Automated due reminders (`send-due-reminders`)

| Field | Value |
|-------|-------|
| **Risk** | Auto-send without staff review |
| **Files** | Not in API client today |
| **Approach** | Shift reminders sheet remains normal flow |
| **Acceptance** | No client route added in V1 |
| **Class** | V2 — backend + iOS |

---

## Implemented — remove from active backlog

- Guest profile SwiftData cache + background incremental list sync (`0f06852`)
- Guest list `updated_since` on iOS API client + UserDefaults sync cursor (`0f06852`)
- Manual intake: local guest cache merge, call-in/walk-in modes, known-guest prefill, phone UX (`0a89caa`)
- Guests tab + detail local-first guest cache wiring (`67e02d2`)
- Host freshness + idle snapshot flicker polish (`71601fc`)
- Host Intelligence card presentation stability (`39f7fcb`)
- Guest person-map Slice 1 — full-list sync completion + full cache lookup (`d541488`)
- Backend guest person-map Slice 2 — staff profile lookup (`1431a06` backend, `b1a09e7` root pointer)
- iOS guest person-map Slice 3A — lookup API/client/store foundation (`823f42c`)
- iOS guest person-map Slice 3B — Guests tab explicit all-record lookup + shared Guest history shell (`1dfa14a`)
- iOS guest person-map Slice 3R — Regulars cache-first + shared Guest history (`50df843`)
- Backend guest person-map Slice 3M-B — unknown walk-in without guest identity (`63d0cfc` backend, `c7f5a69` root pointer; **deployed**)
- iOS guest person-map Slice 3M — Manual Intake walk-in validation + guest lookup (`e775f52`)
- Manual Intake input polish — review sheet, no pre-create messages, keyboard/debounce (`ad5d274`)
- V1 confirmation flow hardening (`cf6e641`)
- Mail-first confirm + manual-email-log + PATCH (when backend confirmation is **off** on device)
- Both backend `/confirm` and manual Mail paths exist; active path is setting-dependent (`EmailAutomationSettings`, default `backendConfirmationEnabled = true`)
- Foreground / privacy-cover refresh (`b910bd1`) — code done; device verify open
- Active-window bounded-full policy + UserDefaults cursor persistence (P0-2)
- Shift reminders (`ShiftReminderReviewSheet`) — Host ⋯ + Bookings bell
- Shared guest email templates (`GuestEmailTemplateRenderer`)
- No-show Bookings tab
- Bookings New/Review split: New now means `.new`, Review means `.needsReview`; manual add removed from Bookings.
- Detail server fetch on cache miss
- `HostAttentionGrouper`
- Manual/custom email log skip + trace (`unsupported_email_type`)
- `POST /import` not in normal client workflow
- Offline mutations blocked when degraded; no offline create/edit queue (not V1)

---

*Owner: stabilization pass on `audit-current-state`. Update this file when items close.*
