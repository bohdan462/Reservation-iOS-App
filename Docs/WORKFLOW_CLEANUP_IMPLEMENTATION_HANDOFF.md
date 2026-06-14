# Workflow Cleanup Implementation Handoff

**Project:** Tryzub Reservations iOS + WordPress backend  
**Absolute path:** `/Users/bohdantkachenko/Development/Tryzub Reservations`  
**Branch context:** `intelligence` (or current feature branch)  
**Audience:** Coding agent — read this file first; do not rescan the whole app.

**Explicitly out of scope for this pass:** Host AI / local LLM / 3B model routing, prompts, validators, grouping layers, or Host Intelligence engine changes — except minimal note-source wording fixes if duplicate labels mislead staff.

---

## 1. Purpose

This is a **focused production cleanup pass** for Tryzub Ukrainian Kitchen’s **internal staff operations app**. It is not a redesign, not a backend rewrite, and not an AI project.

Goals:

- Make confirmation, reminders, no-show recovery, search/detail routing, notes semantics, Bookings tabs, New Reservation UX, and service-pressure copy **staff-trustworthy during live service**.
- Preserve backend contract: managed reservations are truth; SwiftData is cache; normal workflow never calls import or backend blast endpoints.
- Keep diffs narrow; use existing controller/mutation patterns.

**Read first (in order):**

| Doc | Path | Why |
|-----|------|-----|
| Backend contract | `Docs/README.md` | Routes, status transitions, manual email, staff_notes PATCH |
| Project map | `Docs/PROJECT_MAP.md` | File locations, tab shell, mutation semantics |
| Architecture | `Docs/ARCHITECTURE_DIAGRAMS.md` | Confirm/manual-email sequence, sync scopes |
| Method map | `Docs/PROJECT_METHOD_MAP.md` | Confirm Only vs Confirm + Email, controller methods |
| iOS testing | `Docs/IOS_ADMIN_TESTING.md` | Acceptance scenarios, endpoint checklist |
| Activity history | `Docs/ACTIVITY_HISTORY.md` | manual-email-log activity rows |
| Intelligence (read-only) | `Docs/INTELLIGENCE.md` | Guest intel boundaries — do not change in this pass |
| Host AI handoff (do not implement) | `Docs/HOST_AI_IMPLEMENTATION_HANDOFF.md` | Separate pass |

There is **no repo-root `README.md`** for the iOS app; `Docs/README.md` is the backend + integration contract.

---

## 2. Product truth / staff workflow truth

| Rule | Meaning |
|------|---------|
| Internal staff app | Not a public guest booking UI. Manager/Developer roles gate destructive ops. |
| Confirm (online reservations) | Staff confirms by **opening Mail/Gmail draft** with guest-manage link, sending manually, then logging `manual_sent` and **PATCH `status=confirmed`** only after send (or explicit no-email path for call-ins). |
| Not normal confirm | `POST /managed-reservations/{id}/confirm` is **backend/provider email** — legacy/debug only. |
| Guest notes | Text submitted by guest (CF7/import). **Read-only** on detail; editable only via backend truth paths if product allows PATCH `guest_notes` (rare). |
| Staff notes | Operational notes from staff/backend. **PATCH `staff_notes`** supported. Distinct from guest notes. |
| Local structured notes | `ReservationStructuredNoteRecord` is **device-only today** — must not be presented as backend truth. |
| No-show | Recoverable: backend allows `no_show → confirmed, seated` (see `Docs/README.md` status map). Late guests can still be seated. |
| Search/detail | Always key by **`remoteID` (managed reservation ID)**. If not in cache, **GET by ID** then upsert. |
| New Reservation | Actions that require an existing reservation (**Text Table Ready**, manage link, confirm) must **not** appear on create form. |
| Service pressure | Human phrasing for hosts (“One party around 9:00”), not “Pressure builds … 1 reservation.” |
| Shift reminders | **Manual** beginning-of-shift review list; staff composes email/SMS; log activity. **No automatic blast.** |

---

## 3. Backend contract that must not be violated

**Base:** `https://tryzubchicago.com/wp-json/tryzub/v1`

### Used by normal app

| Method | Route | iOS usage |
|--------|-------|-----------|
| GET | `/managed-reservations` | Sync, schedule, search (paged) |
| GET | `/managed-reservations/{id}` | Reconcile, detail fallback fetch |
| PATCH | `/managed-reservations/{id}` | Status, fields, `staff_notes`, hide/restore |
| POST | `/managed-reservations` | Manual create |
| POST | `/managed-reservations/{id}/guest-manage-link` | Manual confirmation draft |
| POST | `/managed-reservations/{id}/manual-email-log` | `draft_created`, `manual_sent`, `manual_failed` |
| PATCH | `/managed-reservations/{id}/tables` | Floor assignment (when layout exists) |
| GET | `/managed-reservations/{id}/activity` | Detail history |

### Not used by normal app

| Method | Route | Reason |
|--------|-------|--------|
| POST | `/managed-reservations/import` | Admin/auto-import only; not in API client |
| POST | `/managed-reservations/{id}/confirm` | Backend sends email; MVP UI disabled |
| POST | `/managed-reservations/send-due-reminders` | Admin/cron blast; not staff workflow |

### Confirm semantics (backend README)

- **PATCH `status=confirmed`:** confirms reservation; **does not send email**.
- **POST `/confirm`:** confirms + attempts backend email (Postmark/wp_mail).
- **POST `/manual-email-log` `manual_sent`:** records staff manual send; may set `confirmation_email_sent_at`; **does not change status by itself**.
- **Target staff flow:** generate manage link → Mail compose → on `.sent` → `manual-email-log` + PATCH confirmed (implementation gap today — see §5).

`/confirm` **must remain in code** (`ReservationMutationService.confirmReservation`, `ReservationsController.confirmReservation`) for legacy/debug when `ReservationEmailWorkflow.isBackendConfirmEmailEnabled == true`. **Normal Confirm button must not call it** (currently gated off — keep gate).

---

## 4. Existing implementation map

Use **symbol search** on these paths only.

### Tab shell & Bookings

| Path | Types / functions | Why | Change? | Do not change |
|------|-------------------|-----|---------|---------------|
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/ReservationsListView.swift` | `ReservationsTabShell`, `ReservationScheduleView`, `reservationDestination(remoteID:)`, `displayedReservations`, `loadScheduleAllPage` | Bookings tabs, search, navigation to detail by `Int` remoteID | Add No Show tab/filter; fix detail fallback; tab counts | Host board section; floor tab wiring |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/ReservationPresentation.swift` | `ReservationScheduleScope` (`.upcoming`, `.needsReview`, `.all`, `.cancelled`) | Segment definitions & titles | Extend/replace with Active/Seated/Completed/No Show per product | Unrelated formatters |

**Current Bookings segments:** `Upcoming | Review (New) | All | Cancelled` — **not** the target `All | Active | Seated | Completed | Cancelled | No Show`.

**Search/detail bug location:**

```swift
// ReservationsListView.reservationDestination — cache-only lookup
if let reservation = reservationLookupRows.first(where: { $0.remoteID == remoteID }) {
    ReservationDetailView(...)
} else {
    ContentUnavailableView("Reservation Not Found", ...)
}
```

Same pattern in Host shell `reservationDestination` (~line 498). `ReservationDetailDestinationView` (cancelled path) uses `@Query` by remoteID but **no server fetch**.

### Reservation detail

| Path | Types / functions | Why | Change? | Do not change |
|------|-------------------|-----|---------|---------------|
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/ReservationDetailView.swift` | `ReservationDetailView`, `sendGuestConfirmationEmail()`, `handleGuestConfirmationMailFinished`, `finalizeManualConfirmationAfterSend`, `notesCard`, `structuredNotesSection`, `noteSignalsCard`, `depositSection`, `preorderSection` | Detail UI, manual Mail path, notes duplication | Notes semantics; wire Confirm to Mail flow; staff_notes PATCH | Guest Insights engine; local model draft generation internals |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/ReservationStructuredNoteUI.swift` | `StructuredNoteEditorSheet` | Local-only structured notes (manager/kitchen/bar/deposit) | Demote or relabel; stop duplicating backend staff notes | — |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Persistence/ReservationStructuredNoteRecord.swift` | SwiftData model | Device-only note storage | Do not treat as truth | — |

### Staff actions & confirm

| Path | Types / functions | Why | Change? | Do not change |
|------|-------------------|-----|---------|---------------|
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift` | `ReservationHostAction`, `availableActions`, `ReservationHostActionPolicy`, `dialogMessage` | Which actions show; confirm copy | Confirm → Mail-first flow; block confirm on completed; no-show recovery | Table assign routing |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/ReservationEmailWorkflow.swift` | `isBackendConfirmEmailEnabled = false` | MVP manual-mail flag | Keep false for normal UI | — |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/GuestConfirmationMail.swift` | `GuestConfirmationMailComposer`, `GuestConfirmationMailPresenter` | MFMailCompose wrapper | Reuse for primary Confirm | — |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/ReservationDetailView.swift` | `ManualEmailDraftService` (nested) | Draft subject/body/HTML | Microcopy / consequence text | — |

**Current confirm paths (gap):**

- `confirmOnly` → `updateStatus(.confirmed)` **immediately** (Detail, Host, Bookings) — no Mail gate.
- Detail **More → Open email draft** → `sendGuestConfirmationEmail()` → Mail → `recordManualConfirmationSent` — **does not PATCH confirmed** (controller comment: manual log does not change status).
- `confirmAndSendEmail` → `confirmReservation` → POST `/confirm` — disabled when `isBackendConfirmEmailEnabled == false`.

### Controller & API

| Path | Types / functions | Why | Change? | Do not change |
|------|-------------------|-----|---------|---------------|
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Import/ReservationsController.swift` | `updateStatus`, `updateReservation`, `confirmReservation`, `recordManualConfirmationSent`, `recordManualConfirmationDraftCreated`, `generateGuestManageLink`, `reconcileReservation`, `loadScheduleAllPage` | All mutations & reconcile | Confirm-after-mail orchestration; detail fetch helper | Sync scope/cursor logic |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Services/ReservationMutationService.swift` | `updateReservation`, `confirmReservation`, `reconcileReservation` | PATCH/POST/GET | Use existing PATCH for staff_notes + status | — |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Network/ReservationsAPIClient.swift` | `fetchReservation`, `updateReservation`, `logManualEmail`, `confirmReservation`, `generateGuestManageLink` | HTTP | No new routes | Do not add `import` or `send-due-reminders` |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Network/ReservationDTO.swift` | `guestNotes`, `staffNotes`, `ReservationUpdateRequest` | PATCH fields | staff_notes updates | — |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Persistence/ReservationRecord.swift` | `remoteID`, `statusValue`, `matchesSearch` | Cache model | — | Schema |

### New Reservation / manual create

| Path | Types / functions | Why | Change? | Do not change |
|------|-------------------|-----|---------|---------------|
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift` | `ManualReservationFormView`, `partyCard`, `GuestTextMessageActionButtons` in guest section, `safeAreaInset` primary button, `slotContextBanner` | Create form layout | Remove Text Table Ready; fix bottom inset; party 30 layout | Create POST payload semantics |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Reservations/GuestTextMessage.swift` | `GuestTextMessageActionButtons`, `tableDueBody` | Text Table Ready button | Hide on create mode | Detail/table-ready usage |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/Guests/GuestLookupStore.swift` | Phone suggestion (recent fix) | Call-in prefill | Only if regression | — |

### No-show & seat

| Path | Types / functions | Why | Change? | Do not change |
|------|-------------------|-----|---------|---------------|
| `ReservationActionButtons.availableActions` | `.noShow` when confirmed/seated; **no seat when no_show** | Recovery missing | Add **Seat late arrival** / reopen from no_show | Auto no-show |
| `ReservationsController.updateStatus` | PATCH status | Seat recovery | Allow `no_show → seated` or `→ confirmed` | — |
| `HostBoardView.perform` | Host quick actions | Same policy | Align with action policy | Host AI card |

Backend allows: `no_show → new, needs_review, confirmed, seated`.

### Note signals & labels (deterministic only — no model changes)

| Path | Types / functions | Why | Change? | Do not change |
|------|-------------------|-----|---------|---------------|
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/ServiceIntelligence/Analyzers/NoteSignalAnalyzer.swift` | `analyze(_:)` | Keyword signals from guest+staff notes | Source attribution (guest vs staff) | LocalModelNoteAnalyzer |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/ServiceIntelligence/Diagnostics/NoteSignalTrace.swift` | `[SERVICE_NOTE_ANALYZER_TRACE]` | Existing trace | Extend or alias `[NOTE_SIGNAL_TRACE]` | — |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/HostIntelligence/HostGuestIntelligenceSupport.swift` | Guest signal labels | Host card wording | **Do not change** unless note chip duplicates mislabel source | Engine/grouping |

**AI touch point (wording only if needed):** `ReservationDetailView.enrichNoteSignalsWithModel()` — avoid if cleanup can use `NoteSignalAnalyzer` only.

### Service pressure chart (copy + animation — not Host AI card)

| Path | Types / functions | Why | Change? | Do not change |
|------|-------------------|-----|---------|---------------|
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/HostIntelligence/ArrivalPressure/ArrivalPressureEngine.swift` | `buildChartCopy`, `buildManagerFacts` | Chart headline/subtitle | Human wording for low activity | Bucket math |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/HostIntelligence/ArrivalPressure/ArrivalPressureWaveChart.swift` | `playEntrance`, `bucketHeadline` | Animation + bucket labels | Slow animation; simpler copy | Tap targets |
| `/Users/bohdantkachenko/Development/Tryzub Reservations/Tryzub Reservations/Features/HostIntelligence/ManagerNarrativeModels.swift` | `pressureHeadline` — “Pressure builds toward …” | Host card text | **Out of scope** unless accidentally shown on chart | Manager narrative writer |

Problem copy examples today:

- `ArrivalPressureEngine`: `"Peak around \(time) · 1 reservation / 1 guest"`, `"Quiet until X, then pressure builds"`.
- `ManagerNarrativeModels.pressureHeadline`: `"Pressure builds toward \(peak), 1 reservation"`.

Chart fix should live in **`ArrivalPressureEngine.buildChartCopy`** (and wave chart subtitles), not in LLM prompts.

### Existing trace helpers (extend, don’t remove)

| Path | Trace prefix |
|------|----------------|
| `Import/FormTrace.swift` | `[FORM_TRACE]` |
| `Import/MultiDeviceSyncTrace.swift` | sync/host/guest lookup |
| `Features/HostIntelligence/ArrivalPressure/ArrivalPressureWaveChart.swift` | `[ARRIVAL_PRESSURE_TRACE]` |
| `Features/ServiceIntelligence/Diagnostics/NoteSignalTrace.swift` | `[SERVICE_NOTE_ANALYZER_TRACE]` |
| `Import/ManualPhoneSuggestTrace.swift` | `[MANUAL_PHONE_SUGGEST_TRACE]` |

---

## 5. Current known problems to fix

### A. Confirm workflow

- **Confirm Only** PATCHes `confirmed` immediately without Mail — contradicts pilot manual-mail truth.
- Detail **Open email draft** logs `manual_sent` but **does not PATCH confirmed** (`ReservationsController` comment line ~2801).
- Staff can get confusing split: “confirmed” in list vs “draft not sent” in Mail.
- **Completed** reservations: `availableActions` excludes confirm for completed, but email draft paths may still be reachable from More menu — audit and block.
- `confirmAndSendEmail` still exists in dialogs when backend flag enabled — must stay hidden/disabled in normal UI.
- **Target:** Primary **Confirm** opens Mail (or call-in: mark confirmed without email when no usable email). Mail `.sent` → `manual-email-log` + PATCH `confirmed`. Mail `.cancelled` → no status change.

### B. Shift reminders

- **No dedicated UI** found for beginning-of-shift reminder review.
- Backend `POST /send-due-reminders` is admin blast — **must not** wire to staff UI.
- **Target:** New or extended screen: list today’s confirmed reservations needing reminder, staff reviews, opens Mail/SMS compose, logs `manual-email-log` with `email_type: reminder` (per README).

### C. No-show

- Bookings has **no No Show tab**; `upcoming` filter **excludes** `no_show` (line ~611).
- `availableActions` offers no-show for confirmed/seated but **no recovery** (seat) from `no_show`.
- **Target:** No Show tab by date; **Seat party** / **Mark arrived** from no_show; counts match rows.

### D. Search/detail

- Search in All mode loads pages via `loadScheduleAllPage` into `allModeRecords`, but `reservationDestination` may not find row if navigation races cache or row only in search results not merged into lookup set.
- No `reconcileReservation` / `fetchReservation` on miss.
- **Target:** `ReservationDetailLoaderView(remoteID:)` → try cache → GET by ID → upsert → show detail or real error.

### E. Notes semantics

- Detail shows **Notes** card (guest + staff from DTO) **and** separate **Staff notes** (`ReservationStructuredNoteRecord` local) **and** deposit/preorder sections **and** note signals — duplication.
- `StructuredNoteEditorSheet` footer: “stored on this device only” — conflicts with backend `staff_notes` PATCH support.
- **Target:** One **Guest notes** (read-only), one **Staff notes** (PATCH backend), signal **chips** for deposit/preorder/banquet (from `NoteSignalAnalyzer`, not editable truth).

### F. New Reservation

- `GuestTextMessageActionButtons` includes **Text Table Ready** on create form (`ManualReservationFormView` ~675).
- `safeAreaInset` bottom button may be covered by keyboard/custom time warning (`slotContextBanner` / `HostReservationSlotContextBanner`).
- Party grid 1–8 + stepper to 60 — party **30** layout/clarity issues reported.
- **Target:** Text Confirmation only (or none) on create; primary button always visible; clean large-party UX.

### G. Bookings

- Segments don't match ops language (Active/Seated/Completed/No Show).
- `upcoming` hides completed/cancelled/no_show — OK for Upcoming, but **All** must retain them.
- Tab counts may not match filtered rows — audit `TryzubSegmentedControl` badges.
- **Target:** Consistent filters + accurate counts.

### H. Service pressure chart

- Robotic copy (“1 reservation”, “pressure builds”).
- Animation: `easeOut(0.7)` + `repeatForever` pulse may feel fast/harsh.
- **Target examples:**
  - “One party around 9:00.”
  - “A little busier around 9:00.”
  - “Main rush around 7:00.”
  - “No real rush on this date.”

### I. Confirmation microcopy

- `dialogMessage` for `confirmOnly` still describes “Choose Confirm only to update status” vs manual Mail path.
- **Target:** Before Mail opens, explain: sends confirmation email from **your** Mail app, marks reservation confirmed **after** send, does not use backend email.

---

## 6. Implementation plan for next agent

### Phase 1 — Read docs & map symbols (no code)

**Files:** This handoff + `Docs/README.md` §Confirm + §manual-email-log + status map.  
**Acceptance:** Written checklist of symbols to touch per phase.

### Phase 2 — Confirm workflow correction

**Files:**

- `ReservationActionButtons.swift` — action availability, dialog copy
- `ReservationDetailView.swift` — unify Confirm with Mail flow
- `ReservationsListView.swift` / `HostBoardView.swift` — row/board confirm handlers
- `ReservationsController.swift` — optional `confirmReservationViaManualMail` orchestrator: manage link → draft log → (after sent) PATCH confirmed + manual_sent

**Routes:** `POST /guest-manage-link`, `POST /manual-email-log`, `PATCH /managed-reservations/{id}` (status).  
**Not used:** `POST /confirm`.

**Traces:** `[CONFIRM_FLOW_TRACE] step=dialog_open|mail_compose|mail_sent|mail_cancelled|patch_confirmed|skipped_no_email`

**Tests:**

- Online `new` reservation → Confirm → Mail → sent → status confirmed + manual_sent logged.
- Mail cancelled → status unchanged.
- Call-in no email → direct PATCH confirmed allowed.
- Completed → Confirm not offered.

### Phase 3 — Notes semantics cleanup

**Files:**

- `ReservationDetailView.swift` — collapse sections
- `ReservationStructuredNoteUI.swift` — deprecate or clearly label local-only
- `ReservationsController.updateReservation` — staff_notes PATCH
- `NoteSignalAnalyzer.swift` — chip source labels

**Routes:** `PATCH /managed-reservations/{id}` with `staff_notes`.

**Traces:** `[NOTES_SEMANTICS_TRACE]`, `[NOTE_SIGNAL_TRACE]`, `[STAFF_NOTES_PATCH_TRACE]`

**Tests:**

- Guest notes read-only; staff notes save to backend; no duplicate “Staff notes” blocks; deposit/preorder as chips only.

### Phase 4 — Search/detail bug

**Files:**

- `ReservationsListView.swift` — replace bare `ContentUnavailableView` destination
- New small loader view (suggested): `ReservationDetailRouteView` using `controller.reconcileReservation`
- Optionally `ReservationDetailDestinationView` for cancelled path

**Routes:** `GET /managed-reservations/{id}` on cache miss.

**Traces:** `[SEARCH_RESULT_TRACE]`, `[DETAIL_ROUTE_TRACE]`, `[DETAIL_FETCH_TRACE]`

**Tests:**

- All-mode search → tap row → detail loads even if row not in active-window cache.
- Invalid ID → clear error, no crash.

### Phase 5 — Bookings No Show tab & recovery

**Files:**

- `ReservationPresentation.swift` — extend `ReservationScheduleScope` or add filter enum
- `ReservationsListView.swift` — `displayedReservations` filters + segment UI
- `ReservationActionButtons.swift` — recovery actions for `no_show`

**Routes:** `PATCH` status only.

**Traces:** `[BOOKINGS_TAB_TRACE]`, `[BOOKINGS_FILTER_TRACE]`, `[NO_SHOW_FLOW_TRACE]`

**Tests:**

- No Show tab lists by date; seat from no_show works; All still shows all statuses.

### Phase 6 — New Reservation UX

**Files:**

- `ManualReservationFormView.swift` — remove table-ready buttons in create mode; inset/scroll fixes
- `GuestTextMessage.swift` — optional `showsTableReady: Bool` parameter

**Traces:** `[NEW_RESERVATION_UX_TRACE]`

**Tests:**

- No Text Table Ready on create; Add Reservation visible with keyboard open; party 30 usable.

### Phase 7 — Shift reminders review flow

**Files (new or extend):**

- Suggested: `ShiftReminderReviewView.swift` under `Features/Reservations/`
- Reuse `ManualEmailDraftService` / reminder body builder (may need new template)
- `ReservationsController` — filter confirmed today + `reminder_email_sent_at == nil` from cache

**Routes:** `POST /manual-email-log` (`email_type: reminder`); **not** `send-due-reminders`.

**Traces:** `[SHIFT_REMINDER_TRACE]`

**Tests:**

- Review list opens; compose opens; log on send; no auto blast.

### Phase 8 — Service pressure copy/animation

**Files:**

- `ArrivalPressureEngine.swift` — `buildChartCopy`
- `ArrivalPressureWaveChart.swift` — `playEntrance`, bucket labels

**Traces:** `[SERVICE_PRESSURE_COPY_TRACE]`, `[SERVICE_PRESSURE_ANIMATION_TRACE]`

**Tests:**

- Single-party day shows “One party around …” not “1 reservation”.
- Calm day: “No real rush on this date.”

### Phase 9 — Traces & acceptance testing

- Add trace enums (DEBUG-only pattern like `FormTrace`).
- Run `Docs/IOS_ADMIN_TESTING.md` scenarios + §8 checklist below.
- `xcodebuild -scheme "Tryzub Reservations" -destination "generic/platform=iOS" build`

---

## 7. Traces to add/verify

| Trace | When |
|-------|------|
| `[CONFIRM_FLOW_TRACE]` | Confirm tap, dialog, mail compose result, PATCH decision |
| `[SHIFT_REMINDER_TRACE]` | Shift review open, row select, compose, log |
| `[NO_SHOW_FLOW_TRACE]` | Mark no-show, recovery seat |
| `[DETAIL_ROUTE_TRACE]` | Navigation with remoteID, cache hit/miss |
| `[DETAIL_FETCH_TRACE]` | GET by ID start/success/fail |
| `[SEARCH_RESULT_TRACE]` | Search query, result IDs, tap ID |
| `[NOTES_SEMANTICS_TRACE]` | Which sections rendered; guest vs staff source |
| `[NOTE_SIGNAL_TRACE]` | Analyzer signals count/types/sources |
| `[STAFF_NOTES_PATCH_TRACE]` | PATCH staff_notes payload hash, success/fail |
| `[NEW_RESERVATION_UX_TRACE]` | Create surface actions visible, inset layout |
| `[BOOKINGS_TAB_TRACE]` | Tab select, scope raw value |
| `[BOOKINGS_FILTER_TRACE]` | Filter predicate, row count |
| `[SERVICE_PRESSURE_COPY_TRACE]` | headline/subtitle chosen, bucket counts |
| `[SERVICE_PRESSURE_ANIMATION_TRACE]` | reduceMotion, duration |

Keep existing `[FORM_TRACE]`, `[ARRIVAL_PRESSURE_TRACE]`, `[MANUAL_PHONE_SUGGEST_TRACE]` unless replacing with deduped versions.

---

## 8. Acceptance checklist

Run on simulator + physical iPad (Manager role).

- [ ] Confirm on online reservation opens Mail with manage link draft.
- [ ] Mail **sent** → `manual_sent` logged + status **confirmed**.
- [ ] Mail **cancelled** → status **not** confirmed.
- [ ] Manual call-in without email can be confirmed without Mail.
- [ ] **Completed** reservation cannot be confirmed or sent confirmation.
- [ ] Normal UI never calls `POST /confirm` (`APIRequestLogStore` / diagnostics).
- [ ] Shift reminders review list opens; manual compose only; activity logged.
- [ ] **No Show** tab shows correct rows for selected date.
- [ ] No-show party can be **seated** after late arrival.
- [ ] Search result opens detail (server GET fallback if needed).
- [ ] Staff notes PATCH persists after refresh.
- [ ] Guest notes and staff notes shown once each; no duplicate sections.
- [ ] New Reservation: **no Text Table Ready**; Add button not covered.
- [ ] Party 30 layout acceptable.
- [ ] Pressure chart uses human low-activity copy.
- [ ] Build succeeds.
- [ ] **No Host AI / model files changed.**

---

## 9. Token-saving guidance for next agent

1. **Start here** — do not open `refactor.md` or full `PROJECT_METHOD_MAP.md` unless stuck.
2. **Search exact symbols first:** `reservationDestination`, `confirmOnly`, `recordManualConfirmationSent`, `ReservationScheduleScope`, `StructuredNoteEditorSheet`, `buildChartCopy`, `GuestTextMessageActionButtons`.
3. **Open only named files** in §4 and the active phase in §6.
4. **Large files:** `ReservationsListView.swift`, `ReservationDetailView.swift`, `ReservationsController.swift` — use symbol search; read only relevant `MARK` sections.
5. **Do not open:** `HostIntelligenceEngine.swift`, `HostBriefingWriter.swift`, `ManagerNarrativeWriter.swift`, `HostLlamaBriefingRuntime.swift`, `GuestMessageDraftWriter.swift` unless fixing a note **label** string visible on detail.
6. **Keep changes narrow** — prefer one orchestration method in controller over new architecture.
7. **No backend route changes** — iOS only.

---

## 10. Return report template

Next agent must fill this after implementation:

```markdown
## Workflow cleanup report

### Docs read
- [ ] Docs/WORKFLOW_CLEANUP_IMPLEMENTATION_HANDOFF.md
- [ ] Docs/README.md (confirm, manual-email-log, status map)
- [ ] (others)

### Files changed
- 

### Backend routes used
- 

### Backend routes explicitly not used
- POST /managed-reservations/import
- POST /managed-reservations/{id}/confirm
- POST /managed-reservations/send-due-reminders

### Confirmation flow before/after
- Before:
- After:

### Notes semantics before/after
- Before:
- After:

### No-show behavior
- 

### Search/detail fix
- 

### New Reservation UX fix
- 

### Bookings tabs fix
- 

### Service pressure copy examples (device)
- 

### Traces observed (sample lines)
- 

### Limitations / deferred
- 
```

---

## Appendix A — Suggested confirm orchestration (reference only)

Do not treat as mandatory design — implement minimal diff.

```
Staff taps Confirm (has email)
  → [CONFIRM_FLOW_TRACE] step=dialog_open
  → POST /guest-manage-link (if needed)
  → POST /manual-email-log draft_created
  → Present MFMailCompose
  → on .sent:
       POST /manual-email-log manual_sent
       PATCH status=confirmed
       [CONFIRM_FLOW_TRACE] step=patch_confirmed
  → on .cancelled:
       [CONFIRM_FLOW_TRACE] step=mail_cancelled (no PATCH)

Staff taps Confirm (no email, manual call-in)
  → PATCH status=confirmed only
  → [CONFIRM_FLOW_TRACE] step=patch_confirmed reason=no_email
```

---

## Appendix B — Docs read for this audit

- `Docs/README.md` (contract sections)
- `Docs/PROJECT_MAP.md`
- `Docs/ARCHITECTURE_DIAGRAMS.md` (mutation + manual email sequences)
- `Docs/PROJECT_METHOD_MAP.md` (confirm semantics header + controller index)
- `Docs/IOS_ADMIN_TESTING.md`
- `Docs/INTELLIGENCE.md` (skim — boundaries only)
- `Docs/HOST_AI_IMPLEMENTATION_HANDOFF.md` (excluded from implementation)
- Targeted symbol search in files listed in §4

**No app code changed in this audit pass.**
