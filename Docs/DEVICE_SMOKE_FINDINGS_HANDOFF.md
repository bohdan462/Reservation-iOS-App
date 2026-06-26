# Device Smoke Findings Handoff — GPT-5.5 Agent High

**Purpose:** Release-blocking and important UX issues found during physical device smoke testing. **Code fixes Phases 1–4 are implemented and pushed**; physical device verification remains open. Slice 3D / 3E stay parked until release smoke verification is accepted or Bohdan explicitly resumes them.

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md) · [DIAGNOSTICS_AND_TESTING.md](./DIAGNOSTICS_AND_TESTING.md)

**Audience:** Bohdan (device verification), Composer 2.5 (audit/docs). GPT-5.5 Agent High only if follow-up code is requested.

---

## 1. Current git / backend state

| Area | State |
|------|--------|
| Root branch | `audit-current-state` |
| Root HEAD | `3da3a68` — Fix Phase 4 device smoke email settings cleanup |
| Remote | `origin/audit-current-state` @ `3da3a68` |
| Device smoke code phases | **Phases 1–4 committed and pushed** (see §1a) |
| Prior iOS slices | `ad5d274` (Manual Intake input polish), `e775f52` (Manual Intake walk-in + guest lookup) |
| Backend HEAD | `63d0cfc` — Allow unknown manual walk-ins without guest identity |
| Backend pointer | `c7f5a69` |
| Backend status | **Implemented, root-pointed, pushed, and deployed to WordPress** |
| Backend lookup | `1431a06` deployed |
| Device smoke tests | **Code landed — physical verification still open; do not claim passed** |
| Next guest person-map code | **3D / 3E parked** until release smoke verification is accepted or Bohdan explicitly resumes |

Working tree should be clean before further Agent work. Agent must not edit backend or create zip files.

---

## 1a. Device smoke code phases landed

| Phase | Commit | Summary |
|-------|--------|---------|
| **Phase 1** | `804c130` | Live button hit area, bottom tab clearance, keyboard-safe guest candidates |
| **Phase 2** | `8eab6c4` | Fast seated-now walk-ins, seated duration, attach known guest to walk-in, walk-in validation, Floor Plan table assignment |
| **Phase 3** | `5762ecb` | Row indicators for auto-confirmed, confirmation email sent, reminder sent |
| **Phase 4** | `3da3a68` | Removed duplicate Email Controls path; local-only email settings under Restaurant Settings as **This Device Email** |

**Status:** implemented and pushed; **physical device verification still open**.

---

## 2. Device language rule

Tryzub Reservations runs on **iPhone and iPad**.

Use:

- device / physical device / device smoke test
- iPhone — only when the finding is iPhone-specific
- iPad — only when the finding is iPad-specific

Avoid default phrases like “restaurant iPad” or “this iPad” in new copy and handoffs.

---

## 3. Screenshot evidence summary

Findings below come from Bohdan’s **physical device smoke session** (2026-06-25) on Tryzub V1 builds including `ad5d274`, against backend `63d0cfc` deployed.

| Area | Evidence type | Notes |
|------|---------------|-------|
| Host Live button | iPad tap failure | Hard/impossible to tap on newer iPad without Home button |
| Bookings / Host lists | Scroll under tab bar | Last reservation row partially hidden on iPhone and iPad |
| Manual Intake walk-in | Full form UX | Date/time pickers shown for live walk-in |
| Host seated rows | Missing duration | Some seated walk-ins show no “Seated Xm” |
| Walk-in table field | Free-text table | Staff can type table string instead of floor-plan pick |
| Walk-in → known guest | Post-create attach | No easy attach after anonymous walk-in create |
| Walk-in edit validation | Wrong mode rules | Name without phone blocked as call-in |
| List row adornments | Stale indicators | Auto-confirm / confirmation email / reminder icons lag until detail open |
| Manual Intake candidates | Keyboard overlap | iPhone keyboard covers guest candidate cards |
| More → Email Controls | Settings duplication | Overlaps Restaurant Settings reminder/auto-confirm |

No new screenshot files are tracked in git; reproduce on physical device using checklist at end of this doc.

---

## 4. Priority table

| ID | Priority | Title | Code | Device verify |
|----|----------|-------|------|---------------|
| 1 | **P1** | iPad Live button hit area | `804c130` Phase 1 | **Open** |
| 2 | **P1** | List bottom row under floating tab bar | `804c130` Phase 1 | **Open** |
| 3 | **P1** | Walk-in uses full reservation form | `8eab6c4` Phase 2 | **Open** |
| 4 | **P1** | Some walk-ins missing seated duration | `8eab6c4` Phase 2 | **Open** |
| 5 | **P1** | Walk-in table must use Floor Plan | `8eab6c4` Phase 2 | **Open** |
| 6 | **P1** | Attach known guest to existing walk-in | `8eab6c4` Phase 2 | **Open** |
| 7 | **P1** | Walk-in edit blocked by call-in phone rule | `8eab6c4` Phase 2 | **Open** |
| 8 | **P1** | Row indicators stale until detail open | `5762ecb` Phase 3 | **Open** |
| 9 | **P2** | Manual Intake candidates under keyboard | `804c130` Phase 1 | **Open** |
| 10 | **P2** | Email Controls vs Restaurant Settings | `3da3a68` Phase 4 | **Open** |

---

## 5. Issues (observed / expected / files / reuse / acceptance)

### P1-1 — iPad Live button hit area

**Observed:** On newer iPads without a physical Home button, the Host **Live** button can be hard or impossible to tap.

**Expected:** Live toggle has a reliable minimum tap target (44pt+) and is not covered by header blur, safe-area inset, collapse overlay, or sibling controls.

**Likely files:**

- `Tryzub Reservations/Features/Reservations/HostBoardView.swift` — `actionBar`, `liveHostModeEnabled`, Live `Button` (~2130+)
- Host header chrome helpers in `TryzubGlassChrome.swift` / `ReservationSharedUI.swift` if overlay z-order involved

**Reuse:** Existing `@AppStorage("host.liveModeEnabled")` and Live refresh behavior — **do not** rewrite sync.

**Acceptance:**

- [ ] Live button tappable on iPad (no Home button) in portrait and landscape
- [ ] Toggle state persists; Live refresh behavior unchanged
- [ ] No regression on iPhone Host header

---

### P1-2 — Reservation list bottom row covered by floating tab bar

**Observed:** On iPhone and iPad, long reservation lists scroll under the floating tab bar; the last card is partly hidden.

**Expected:** Last reservation row scrolls fully above the tab bar on all tab list surfaces.

**Likely files:**

- `Tryzub Reservations/Features/Reservations/ReservationsListView.swift` — `.contentMargins(.bottom, ReservationLayout.scrollBottomInset, …)` (multiple list sections)
- `Tryzub Reservations/Features/Reservations/ReservationSharedUI.swift` — `ReservationLayout.scrollBottomInset` (16), `floatingTabBarClearance` (16), `BottomSafeActionBar`
- `Tryzub Reservations/Features/Reservations/HostBoardView.swift` — scroll content margins

**Reuse:** `ReservationLayout` as single spacing source; `BottomSafeActionBar` pattern for pushed destinations already documents tab clearance intent.

**Acceptance:**

- [ ] Bookings list: last row fully visible above tab bar (iPhone + iPad)
- [ ] Host board lists: same
- [ ] Pushed detail screens still use appropriate bottom action clearance
- [ ] No double-padding that wastes vertical space on short lists

---

### P1-3 — Walk-in creation uses too much of the full reservation form

**Observed:** Live walk-ins use the same full Manual Intake / manual reservation flow with date and time pickers.

**Expected:** A **live walk-in** path defaults to **now**, creates as **seated**, and records **seated time immediately**. Full manual reservation creation (future date/time, call-in, etc.) remains available separately.

**Likely files:**

- `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift` — intake mode `.walkIn`, `applyIntakeModeDefaults`, form fields
- `Tryzub Reservations/Import/ReservationsController.swift` — `applyOptimisticStatusUpdate`, `localSeatedAtByReservationID` on seated create
- Entry points that present Manual Intake from Host / Bookings

**Reuse:** Existing walk-in validation (`manual_walk_in`, blank identity), review sheet (`prepareCreateConfirmation` → `createReservation()` only from sheet confirm), backend `63d0cfc` contract.

**Acceptance:**

- [ ] Walk-in default: today + now (or nearest allowed staff slot), status seated
- [ ] Seated timestamp recorded at create (local + survives sync where backend allows)
- [ ] Review sheet still shown before create
- [ ] Call-in and full manual create unchanged
- [ ] Unknown walk-in blank identity still works (3M)

---

### P1-4 — Some walk-ins do not show seated duration

**Observed:** Some seated walk-ins do not show time since seated on Host / list rows.

**Expected:** Every **seated** reservation, including walk-ins created seated, shows seated duration from **actual seated time**.

**Likely files:**

- `Tryzub Reservations/Import/ReservationsController.swift` — `seatedAt`, `seatedDurationText`, `localSeatedAtByReservationID`, `seatedTimestampFallback`
- `Tryzub Reservations/Features/Reservations/ReservationSharedUI.swift` — seated timestamp helpers
- `Tryzub Reservations/Features/Reservations/HostBoard/HostBoardReservationRow.swift`
- `Tryzub Reservations/Features/Reservations/ReservationRowView.swift`
- Create path in `ManualReservationFormView` / mutation handlers after walk-in POST

**Reuse:** `ReservationsController.seatedDurationText` / dot style; do not duplicate duration math in views.

**Acceptance:**

- [ ] Walk-in created seated → “Seated 0m” (or equivalent) within one list refresh cycle
- [ ] Duration increments on clock tick / refresh
- [ ] Seat action from confirmed still sets local seated time
- [ ] No false duration for non-seated statuses

---

### P1-5 — Walk-in table assignment must use Floor Plan tables

**Observed:** Manual Intake / edit flow still allows free-text `tableName` when backend floor layout exists.

**Expected:** When `FloorPlanStore.hasBackendLayout`, staff pick a **real table** via existing Floor Plan / `TableAssignmentSheet` / `TableAssignmentCoordinator` — not type or PATCH a raw table string.

**Likely files:**

- `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift` — `tableName` text fields in walk-in / manual create
- `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift` — `TableAssignmentSheet`
- `Tryzub Reservations/Features/FloorPlan/TableAssignmentCoordinator.swift`
- `Tryzub Reservations/Features/FloorPlan/FloorPlanStore.swift`
- `Docs/FLOOR_PLAN_AND_TABLES.md` — canonical assignment flow

**Reuse:** `TableAssignmentCoordinator.assign`, `PATCH /managed-reservations/{id}/tables`, Host/Detail assignment paths.

**Acceptance:**

- [ ] With backend layout: walk-in create/edit cannot save arbitrary table string
- [ ] Assignment uses floor-plan table keys/labels
- [ ] Without layout: legacy fallback behavior documented and unchanged
- [ ] Host assign-table flow still works

---

### P1-6 — Attach known guest to already-created walk-in

**Observed:** Staff can create anonymous walk-in first, then needs an easy way to add a known guest later without changing source away from walk-in.

**Expected:** Reservation detail / edit allows search/select saved or backend guest and attach identity; `source_type` stays **`manual_walk_in`**.

**Likely files:**

- `Tryzub Reservations/Features/Reservations/ReservationDetailView.swift`
- `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift` — edit mode / `ReservationEditFormView`
- `Tryzub Reservations/Features/Guests/GuestLookupStore.swift`
- `Tryzub Reservations/Features/Guests/GuestProfileStore.swift`
- `GuestLookupStore` + Manual Intake candidate UI patterns (`Use guest`)

**Reuse:** `GuestLookupStore`, `GuestProfileStore.lookupProfiles`, Manual Intake **Use guest** / **Search all guest records** — no new guest store.

**Acceptance:**

- [ ] Open seated walk-in detail → attach known guest via lookup
- [ ] Name/phone/email fill; `manual_walk_in` preserved
- [ ] Review/save uses walk-in validation (phone not required)
- [ ] No auto-pick of possible matches

---

### P1-7 — Walk-in edit with name but no phone blocked as call-in

**Observed:** Editing a walk-in with a known guest name but no phone can show call-in validation error (“Add a valid phone number…”).

**Expected:** Walk-in / manual walk-in **update** allows name without phone. **Call-in create** still requires name + phone.

**Likely files:**

- `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift` — `ReservationFormValidator.validate`, field errors, `ReservationEditFormView` intake mode binding
- `ReservationFormDraft.updateRequest`, `validateRequiredFields`

**Reuse:** Existing 3M split: `intakeMode == .walkIn` omits phone requirement; ensure **edit** path passes walk-in mode from `reservation.sourceTypeValue == .manualWalkIn`.

**Acceptance:**

- [ ] Edit walk-in: name only → save succeeds
- [ ] Edit call-in reservation: phone still required
- [ ] Create call-in: phone still required
- [ ] Create walk-in: blank phone still allowed

---

### P1-8 — Auto-confirm, reminder, and email-sent icons stale until detail opens

**Observed:** Auto-confirm adornment appears after opening detail; list cells do not update promptly. Confirmation email sent and reminder sent should also appear on rows without opening detail.

**Expected:** List rows show small timely indicators from normal reservation sync/mutation data (`confirmationEmailSentAt`, `reminderEmailSentAt`, auto-confirm evidence) without requiring detail open.

**Likely files:**

- `Tryzub Reservations/Features/Reservations/HostBoard/HostBoardReservationRow.swift` — `showsAutoConfirmedAdornment` via `ReservationActivityStore`
- `Tryzub Reservations/Features/Reservations/ActivityHistory/ReservationActivityStore.swift` — `hasBackendAutoConfirmEvidence`
- `Tryzub Reservations/Features/Reservations/ReservationRowView.swift` — `BackendAutoConfirmedIcon`, meta adornments
- `Tryzub Reservations/Features/Reservations/ReservationsListView.swift` — bookings row presentation
- `Tryzub Reservations/Persistence/ReservationRecord.swift` — `confirmationEmailSentAt`, `reminderEmailSentAt`
- `Tryzub Reservations/Import/ReservationsController.swift` — upsert after sync/mutation

**Reuse:** Prefer **`ReservationRecord` DTO fields** for email-sent badges; use activity store for auto-confirm only if needed — prefetch/warm activity cache on list appear or merge auto-confirm signal into reservation payload if backend exposes it.

**Acceptance:**

- [ ] After sync/confirm/reminder mutation, list row shows correct icons without opening detail
- [ ] Auto-confirm icon on Host board when evidence exists
- [ ] Confirmation-email-sent and reminder-sent visible on appropriate rows
- [ ] No extra network call per row on every keystroke

---

### P2-9 — Manual Intake guest candidates covered by keyboard

**Observed:** On iPhone, saved guest candidates appear under the guest section and can be covered by the keyboard.

**Expected:** Candidates visible in keyboard-safe area — above form content or pinned above keyboard.

**Likely files:**

- `Tryzub Reservations/Features/Reservations/ManualReservationFormView.swift` — `ManualGuestCandidateSection`, `ScrollView`, keyboard toolbar
- Consider `.safeAreaInset(edge: .bottom)` or focused-field scroll without reintroducing per-focus animation jank removed in `ad5d274`

**Reuse:** Existing debounced local lookup (`GuestLookupStore` 250–300 ms); capped candidates (6 UI / 8 index).

**Acceptance:**

- [ ] iPhone: typing name/phone shows candidates above keyboard
- [ ] iPad: candidates remain visible with external keyboard and on-screen keyboard
- [ ] Review sheet and 3M lookup rules unchanged

---

### P2-10 — Email Controls may duplicate Restaurant Settings

**Observed:** More screen had **Email Controls** while Restaurant Settings already has Backend Reminders and Backend Auto-Confirm.

**Expected:** One clear settings path for reminders, auto-confirm, and confirmation email controls.

**Code status:** **Implemented** — `3da3a68` Phase 4. More → Email Controls removed. Restaurant Settings owns **Backend Reminders** and **Backend Auto-Confirm**; local-only switches live under **This Device Email** (summary card + edit screen). No sending behavior changed.

**Likely files (landed):**

- `Tryzub Reservations/Features/Reservations/ReservationsListView.swift` — removed More → Email Controls
- `Tryzub Reservations/Features/Reservations/EmailAutomationSettingsView.swift` — renamed to **This Device Email**
- `Tryzub Reservations/Features/Reservations/RestaurantSettingsStore.swift` — **This Device Email** card + backend sections

**Reuse:** `RestaurantSettingsStore` PATCH `/restaurant-setup`; `EmailAutomationSettingsStore` remains local UserDefaults only.

**Acceptance:**

- [ ] More no longer shows Email Controls
- [ ] Restaurant Settings contains **This Device Email** plus backend reminder/auto-confirm settings
- [ ] Staff cannot confuse local device switches with backend automation rules
- [ ] No conflicting persisted values

---

## 6. Architecture constraints (do not violate)

1. Backend is source of truth.
2. SwiftData is operational cache only.
3. Do not create a second API client.
4. Do not create a second guest store.
5. Do not create a second sync manager.
6. Do not call backend import from normal iOS refresh.
7. Do not remove the Manual Intake **final review sheet**.
8. Do not re-add pre-create confirmation or text-message buttons to Manual Intake.
9. Do not require phone for walk-ins or known-guest walk-ins.
10. Do not auto-select possible guest matches.
11. Do not assign tables with raw strings when backend floor layout exists.
12. Reuse existing Floor Plan / table assignment code.
13. Reuse existing `GuestLookupStore` and `GuestProfileStore`.
14. Reuse existing Reservation Detail confirmation/message workflow.
15. **Do not start Slice 3D or 3E** until these findings are fixed or explicitly parked by Bohdan.

---

## 7. Implementation order (code landed)

### Phase 1 — Layout and hit-testing — **`804c130`**

1. P1-1 iPad Live button tap target / overlay z-order
2. P1-2 List bottom inset above floating tab bar
3. P2-9 Manual Intake keyboard-safe candidate area

### Phase 2 — Walk-in workflow — **`8eab6c4`**

4. P1-3 Quick seated-now walk-in defaults
5. P1-4 Seated duration for every seated walk-in (tie to create/seated timestamp)
6. P1-6 Attach known guest to existing walk-in
7. P1-7 Walk-in edit validation (not call-in rules)
8. P1-5 Floor Plan table assignment when layout exists

### Phase 3 — Timely row indicators — **`5762ecb`**

9. P1-8 Auto-confirm, confirmation email sent, reminder sent on list rows without detail open

### Phase 4 — Settings cleanup — **`3da3a68`**

10. P2-10 Email Controls vs Restaurant Settings consolidation

**Next:** physical device verification (§10), then release smoke. Do **not** start Slice 3D/3E until smoke verification is accepted or Bohdan explicitly resumes.

---

## 8. What not to touch

- Backend plugin (`Backend/tryzub-reservations-api`) unless Bohdan opens a backend task
- Slice **3D** full Guest history UI / Reservation Detail bridge
- Slice **3E** detail JSON persistence / disk-first full profile reopen
- Manual Intake removal of review sheet or re-addition of pre-create message buttons
- `GuestTextMessageActionButtons` on Reservation Detail (post-create only)
- Build number / TestFlight metadata unless explicitly requested
- Zip deploy artifacts

---

## 9. Audit checklist after Agent fix

Composer or Bohdan should verify:

- [ ] Only expected Swift files changed; no backend/docs drift unless docs task follows
- [ ] `xcodebuild` succeeds (generic iOS Simulator)
- [ ] Manual Intake review sheet still gates create
- [ ] No pre-create send-confirmation UI in Manual Intake
- [ ] Walk-in blank identity + call-in name/phone rules preserved (3M)
- [ ] No `/guest-profiles/lookup` while typing
- [ ] No second API client / guest store / sync manager
- [ ] Floor layout path uses `TableAssignmentCoordinator` when layout exists
- [ ] 3D/3E scope not started

---

## 10. Device smoke verification checklist (still open)

Run on **physical device** (iPhone and/or iPad as noted). Code for all items is landed; checkboxes remain until Bohdan verifies on hardware.

- [ ] Live button tappable on **iPad** without Home button (portrait and landscape)
- [ ] Last row clears floating tab bar on **iPhone and iPad** (Bookings + Host)
- [ ] Manual Intake candidates stay visible above **iPhone** keyboard
- [ ] Live walk-in create → review sheet → save as seated now
- [ ] Seated duration appears on new walk-ins and increments
- [ ] Attach known guest on walk-in edit; source remains walk-in
- [ ] Walk-in edit name-only/no-phone saves
- [ ] Floor Plan assignment path used when backend layout exists; no raw table string
- [ ] Auto-confirm / confirmation / reminder indicators show on list rows without opening detail
- [ ] More no longer shows Email Controls; Restaurant Settings contains **This Device Email** plus backend reminder/auto-confirm settings
- [ ] Regression: unknown walk-in party/time only still saves (backend `63d0cfc`)
- [ ] Regression: Reservation Detail confirm/email workflow still works post-create

**Do not claim** device smoke passed until Bohdan confirms on physical hardware.

---

## 11. Final state summary for next conversation

**Shipped:** Tryzub V1 guest person-map through 3M-B/3M, Manual Intake input polish (`ad5d274`), backend unknown walk-in deployed (`63d0cfc`), device smoke code Phases 1–4 (`804c130` → `3da3a68`).

**Open:** Physical **device smoke verification** (this handoff P1/P2). Confirmation mode on device. Release smoke test.

**Parked until smoke verification accepted or Bohdan resumes:** Slice **3D** (full Guest history UI + Reservation Detail bridge), Slice **3E** (detail JSON persistence / disk-first full profile reopen).

**Next step:** Physical device verification + release smoke — not further device-smoke Agent code unless verification finds regressions.

---

*Created: 2026-06-25. Updated: 2026-06-26. Align with root `3da3a68`, backend `63d0cfc` deployed, backend lookup `1431a06` deployed.*
