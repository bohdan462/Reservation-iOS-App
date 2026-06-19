# Host tab architecture

**Status:** Current source of truth  
**Audit date:** 2026-06-14  
**Related fixes:** HT-1 (snapshot date), HT-2 (calendar), HT-3 (seated duration)

## Purpose

The Host tab is the staff **live-service command center** for Tryzub Ukrainian Kitchen.

- Shows today’s (or selected day’s) operational reservations, seated guests, pressure, reminders, and Host Intelligence.
- Internal operations tool — **not** a customer booking surface.
- Staff confirm every mutation; the board suggests and routes only.

**Design intent:** premium, glass/liquid, calm but alive, readable during service — not cluttered, not generic, not fragile.

## Entry points

```
ReservationsListView (tab shell)
  └─ ReservationsTabShell
       └─ HomeDashboardView          ← Host tab root (private struct in ReservationsListView.swift)
            ├─ @State selectedDate   ← selected-date owner (SSOT)
            ├─ selectedDateReservations
            └─ HostBoardView         ← main board UI
```

| Layer | File | Role |
|-------|------|------|
| Tab shell | `Features/Reservations/ReservationsListView.swift` | `TabView`, stores, navigation to detail |
| Host wrapper | `HomeDashboardView` (same file) | Owns `selectedDate`, filters reservations, passes binding |
| Board | `Features/Reservations/HostBoardView.swift` | Canvas, snapshot, lists, pressure, AI strip, actions |

## Main file map

| File | Type / functions | Renders / owns | Consumes | Risk |
|------|------------------|----------------|----------|------|
| `ReservationsListView.swift` | `ReservationsTabShell`, `HomeDashboardView` | Tab shell, Host tab wrapper | `@Query`, `ReservationsController` | **Med** — owns `selectedDate` SSOT |
| `HostBoardView.swift` | `HostBoardView`, `HostBoardSnapshot`, `HomeServiceHeader`, columns, rows | Full Host board (~3k lines) | `$selectedDate`, `reservations`, env objects | **Critical** — snapshot, date, actions |
| `ReservationSharedUI.swift` | `ReservationServiceDateSelector`, `ReservationOpenCalendarButton` | Date chips, calendar picker | `$selectedDate` | **High** — date UX, hit testing |
| `ReservationRowView.swift` | `ReservationRowView`, `ReservationRowPresenter` | Shared reservation cell | `contextNote`, `displayStyle`, capabilities | **High** — row contract, seated metadata |
| `ReservationsController.swift` | `seatedDurationText`, `localSeatedAtByReservationID`, mutations | Logic only | SwiftData, API | **Med** — seated timestamps, PATCH |
| `ArrivalPressureWaveChart.swift` | `ArrivalPressureWaveChart` | Pressure wave chart + bucket sheet | `ArrivalPressureSummary` | **Low** — display |
| `ArrivalPressureEngine.swift` | `ArrivalPressureEngine.build` | Pressure calculation | reservations, selectedDate, service window | **Low** — pure logic |
| `TryzubGlassChrome.swift` | `TryzubHostBoardCanvas`, `hostBoardGlass*` modifiers | Atmosphere + glass surfaces | — | **Low** — design tokens |
| `HostIntelligenceCard.swift` | `HostIntelligenceCard` | AI compact strip + full card | snapshot, presentation | **Med** — staff-facing copy |
| `HostIntelligenceEngine.swift` | `evaluate`, fact/action builders | Deterministic intelligence | reservations, settings, floor source | **Med** — facts only, no mutations |
| `HostSuggestedActionRouter.swift` | `route(for:)` | Maps actions → navigation | `HostSuggestedAction` | **Med** — routing only |

### Supporting files (touch with care)

| File | Role |
|------|------|
| `HostIntelligenceController.swift` | Briefing refresh, display snapshot |
| `HostBoardViewStateStore.swift` / `HostBoardLifecycleCoordinator` | Startup deferral, availability/guest-intel scheduling |
| `HostBoardActionRouter.swift` | Guest note sheet helpers (cluster actions) |
| `ShiftReminderReviewSheet.swift` | Manual reminder draft review |
| `FloorPlanStore.swift` | Effective table assignments for selected date |

## Host Board sections

Rendered inside `HostBoardView` (open-service branch unless closed-day):

| Section | Component | Data source |
|---------|-----------|-------------|
| Header / date | `HomeServiceHeader` → `ReservationServiceDateSelector` | `$selectedDate` binding |
| KPIs / status | `HostOperationalStatusPanel`, `HostBoardSummaryCard` | `snapshot`, availability |
| Pressure graph | `hostOperationalServicePressureSection` → `ArrivalPressureWaveChart` | `snapshot.arrivalPressure` |
| AI strip | `HostIntelligenceCard` (compact) + Review sheet | `HostIntelligenceController` |
| Reminders | `HostReminderBatchCard` | `hostReminderPanelContext` (today only) |
| Seated list | `HostBoardColumn` ("Seated") | `snapshot.seated` |
| Upcoming list | `HomeReservationsPanel` | `snapshot.upcoming` (hour sections) |
| Booking load strip | `HostBookingLoadCompactStrip` | cached booking-load report |
| Floor setup prompt | `HostFloorSetupPromptCard` | floor source not configured |

**Sheets / dialogs:** shift reminders, backend reminder confirmation, Host Intelligence review, table assignment (per row), confirm/cancel/no-show alerts.

**Layout:** iPhone stacked lists; iPad wide split (`wideBoard`) when width ≥ 1100 or tablet idiom. Header collapses on scroll via `HostBoardHeaderCollapse`.

## Ownership rules

| Concern | Owner | Consumers must |
|---------|-------|----------------|
| Selected service date | `HomeDashboardView.selectedDate` | Bind only — never duplicate `@State` in `HostBoardView` |
| Reservation feed | `HomeDashboardView.selectedDateReservations` | Pass as `HostBoardView.reservations` |
| Board snapshot | `HostBoardView.boardSnapshot` + `HostBoardSnapshot` init | Use `currentDateBoardSnapshot` for render; never show wrong-date cache |
| Mutations (seat, confirm, etc.) | `ReservationsController` | Views send intent via `handleAction` / `perform` |
| Row presentation | `ReservationRowView` + `ReservationRowPresenter` | No network, no status PATCH |
| Pressure buckets | `ArrivalPressureEngine` | Built inside snapshot; chart reads `snapshot.arrivalPressure` |
| Host Intelligence facts | `HostIntelligenceEngine` | Controller refreshes; card displays only |
| Action routing | `HostSuggestedActionRouter` + `handleHostIntelligenceAction` | Opens detail + intent banner; no auto-mutation |
| Glass styling | `TryzubGlassChrome` modifiers | Visual only |

## UI-only vs logic-only

**Safe for UI-only agents:**

- `TryzubGlassChrome.swift` (visual tokens)
- `HostIntelligenceCard.swift` (layout, labels — not engine)
- `ReservationRowView.swift` (presentation contract — coordinate with HT-3 rules)
- `ReservationSharedUI.swift` (date chips, calendar presentation)
- Private subviews inside `HostBoardView.swift` **only if** snapshot/date/action wiring unchanged

**Logic / data — do not change without reading state-flow doc:**

- `HostBoardView` `.task(id: boardSnapshotBuildKey)`, `onChange(selectedDateKey)`
- `HomeDashboardView.selectedDateReservations` filter
- `HostIntelligenceEngine`, `HostIntelligenceController.refreshBriefing`
- `ReservationsController` seated timestamps and mutations
- `ArrivalPressureEngine.build`

## Do-not-touch rules

1. **Do not create a second `selectedDate`** in `HostBoardView` or child views.
2. **Do not render lists or pressure from a snapshot whose `selectedDate` ≠ current `selectedDateKey`.** Use `currentDateBoardSnapshot` (HT-1).
3. **Do not preserve `boardSnapshot` across date changes.** Preserve is same-date only when `incomingCount == 0` and `lastStableCount > 0`.
4. **Do not add per-row or per-second timers.** Seated duration uses existing `clockTick` minute loop.
5. **Do not let glass/style refactors change business logic** (filters, snapshot keys, action handlers).
6. **Do not move action routing** without tracing `onOpenReservation` → `navigationPath` and `HostReservationOpenIntentStore`.
7. **Do not gate `selectedDateReservations` on `isActive`** — causes empty snapshot flicker on tab return.
8. **Do not auto-advance selected date after close** — staff picks the day explicitly.

## Related docs

- [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md) — date, snapshot, clock, pressure, seated, calendar
- [HOST_TAB_UI_DESIGN_SYSTEM.md](./HOST_TAB_UI_DESIGN_SYSTEM.md) — glass, typography, row/AI contracts
- [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md) — intelligence pipeline (not tab shell)
- [IOS_ARCHITECTURE.md](./IOS_ARCHITECTURE.md) — app entry, tab shell, controller
