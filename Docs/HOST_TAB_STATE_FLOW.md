# Host tab state flow

**Status:** Current source of truth  
**Audit date:** 2026-06-14  
**Related fixes:** HT-1, HT-2, HT-3

## 1. Selected date — single source of truth

```
HomeDashboardView.@State selectedDate: Date
  → Binding $selectedDate → HostBoardView.selectedDate
  → selectedDateKey = selectedDate.reservationDateString()
```

- **Owner:** `HomeDashboardView` only (`ReservationsListView.swift`).
- **Date chips:** `ReservationServiceDateSelector` binds to the same `$selectedDate`.
- **Calendar button:** `ReservationOpenCalendarButton` binds to the same `$selectedDate` when `showsCalendarButton == true`.
- **Host board today:** `showsCalendarButton: false` in `HomeServiceHeader` — staff use chips only on Host; calendar contract still applies wherever the button is shown.
- **Reset to today:** `resetHostToToday()` on tab activate / navigation reset token — does not auto-run after close.
- **Navigation note:** `controller.noteHostBoardSelectedDate(dateKey)` sets `hostBoardDateNavigationAt` for intelligence stability cooldown.

**Rule:** Never add `@State selectedDate` inside `HostBoardView`.

## 2. Reservation feed

`HomeDashboardView.selectedDateReservations`:

1. Filter `@Query` reservations where `reservationDate == selectedDateKey`.
2. Exclude `hiddenReservations.isHidden(record)`.
3. Include only `record.isHostBoardOperational`.

**`isHostBoardOperational`** (`ReservationRecord.swift`):

| Status | On Host board |
|--------|---------------|
| `new`, `needsReview`, `confirmed`, `seated` | Included |
| `completed`, `cancelled`, `noShow` | Excluded (terminal) |

Passed to `HostBoardView` as `reservations: [ReservationRecord]`.

**Important:** Feed is **not** gated on `isActive`. Tab visibility uses `isVisible` for network/animation only.

## 3. HostBoardSnapshot lifecycle

### What the snapshot contains

`HostBoardSnapshot` (private struct in `HostBoardView.swift`):

| Field | Use |
|-------|-----|
| `selectedDate` | Date this snapshot was built for |
| `now` | `clockTick` at build time |
| `upcoming` | new / needsReview / confirmed, sorted for host |
| `seated` | seated, chronological |
| `needsReview`, `newReservations` | attention subsets |
| `noTableCount`, `expectedGuestCount` | KPIs |
| `arrivalPressure` | `ArrivalPressureSummary` for chart |
| `peakTimeText`, `nextReservationText` | header KPI copy |

Built in `.task(id: boardSnapshotBuildKey)` from current `reservations`, `selectedDate`, `clockTick`, service density bounds, effective table assignments.

### `boardSnapshotBuildKey`

```
selectedDateKey
+ hostIntelligenceReservationStamp (reservation ids/status/tables)
+ hostIntelligenceOperationalMinuteStamp ("op-minute-*" on today, "future-day" otherwise)
+ hostTableConfigStore.tableConfigFingerprint
+ floorPlanStore.layoutFingerprint(for: selectedDateKey)
```

Task re-runs when date or reservation data changes.

### Snapshot preservation (why it exists)

When `incomingCount == 0` but `stableCountByDate[selectedDateKey] > 0`, the board **may** skip overwriting to avoid a transient empty flash (tab return, `@Query` timing).

### HT-1 contract (mandatory)

**Cached snapshot must match `selectedDateKey`.**

1. **Preserve only when same date:**
   ```swift
   if incomingCount == 0, lastStableCount > 0, cachedMatchesSelectedDate { return }
   ```
   `cachedMatchesSelectedDate` = `boardSnapshot?.selectedDate.reservationDateString() == selectedDateKey`

2. **Clear on date change:**
   ```swift
   .onChange(of: selectedDateKey) {
     if boardSnapshot?.selectedDate != newKey { boardSnapshot = nil }
   }
   ```

3. **Render guard:**
   ```swift
   currentDateBoardSnapshot  // nil if cached date ≠ selectedDateKey
   let snapshot = currentDateBoardSnapshot ?? HostBoardSnapshot(...)  // ephemeral fallback
   ```

**Never** show Saturday lists/pressure while header chips say Today.

## 4. Date-stale bug contract

| Surface | Must match |
|---------|------------|
| Date chips / header | `selectedDate` binding |
| Seated + upcoming lists | `snapshot` built for `selectedDateKey` |
| Pressure summary + chart | `snapshot.arrivalPressure` for same date |
| Host Intelligence input | `makeHostEngineInput` uses same `reservations` + `selectedDateKey` |

**Failure mode (pre–HT-1):** preserve kept old `boardSnapshot` after date change → lists and graph showed previous day.

**Manual check:** Saturday → Today after close → all three align to Today (or empty if no operational rows).

## 5. Pressure graph flow

```
reservations (selected day)
  → HostBoardSnapshot.init
       → ArrivalPressureEngine.build(
            from: upcoming + seated,
            selectedDate:,
            serviceOpen/Close: from availability for selectedDateKey,
            now: clockTick,
            effectiveTableAssignments:)
  → snapshot.arrivalPressure
  → hostOperationalServicePressureSection
       → collapsed: summary line only
       → expanded: ArrivalPressureWaveChart(summary:)
```

- **`isPressureExpanded`:** UI only — does not change data.
- **Service window:** `serviceDensityBounds` uses availability for **selected** date (properties named `todayAvailability` are keyed by `selectedDateKey`).
- **Stale data:** prevented by HT-1 `currentDateBoardSnapshot`.

## 6. Calendar picker flow

**Components:** `ReservationServiceDateSelector` + `ReservationOpenCalendarButton` (`ReservationSharedUI.swift`).

**Layout (HT-2):** `HStack` — date strip and calendar button side by side. Strip uses `layoutPriority(0)`; calendar `44×44` with `contentShape(Rectangle())`. Strip must not overlap calendar hit target.

**Presentation (HT-2):**

| Size class | Picker |
|------------|--------|
| `.compact` (iPhone) | `.sheet` with graphical `DatePicker`, `.presentationDetents([.medium, .large])` |
| regular (iPad) | `.popover` with graphical `DatePicker` |

**Binding:** Always `$selectedDate` — no secondary date state.

**Host board:** `showsCalendarButton: false` — chips only. Re-enabling calendar requires setting `showsCalendarButton: true` in `HomeServiceHeader` and verifying HT-2 hit tests.

**Beyond 7-day strip:** `displayDates` extends when selected date falls outside default week.

## 7. Seated duration flow

**Source:** `ReservationsController.localSeatedAtByReservationID` (local, persisted). Fallback: `apiUpdatedAt` when local missing.

**Text:** `controller.seatedDurationText(for: reservation, now: referenceNow)`  
Examples: `Seated just now`, `Seated 12m`, `Seated 1h 05m`

**Host row wiring (`HostBoardReservationRow`):**

- `context: .todaySeated` when `status == .seated`
- `contextNote: seatedDurationText`
- `seatedDurationDotStyle: controller.seatedDurationDotStyle(...)`
- `referenceNow: snapshot.now` (from `clockTick`)

**Display (HT-3):** `ReservationRowView.hostBoardMetaItems` — seated duration in **metadata row** with status dot. **Not** the insight line (`insight: nil` for `.hostBoard`).

**Clock:** `runClockLoop()` updates `clockTick` each minute → rebuilds snapshot `now` → row metadata refreshes. **No new timers.**

## 8. Host Intelligence refresh flow

```
HostBoardView.makeHostEngineInput(now: clockTick)
  → HostIntelligenceEngine.evaluate
  → HostAttentionGrouper.build(selectedDateKey, floorTableSource, bookingLoadReport)
  → HostIntelligenceController.refreshBriefing(hostBoardContext:, bookingLoadReport:)
  → HostIntelligenceCard (compact strip on board)
```

**Refresh keys include:**

- `selectedDateKey`
- reservation + seated stamps
- floor layout fingerprint + effective table assignments
- guest intelligence cache stamp
- operational minute stamp (today only)

**Local model:** opt-in via `HostIntelligenceSettingsStore` — does not own date state.

**Actions:** `handleHostIntelligenceAction` → `HostSuggestedActionRouter` → open reservation + intent banner. See [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md).

## 9. Required manual tests

| # | Scenario | Pass criteria |
|---|----------|---------------|
| 1 | Select Saturday → return Today after close | Header, lists, pressure all Today; no Saturday bleed |
| 2 | Calendar pick date outside chip strip (where button shown) | `selectedDate` updates; strip scrolls to selection |
| 3 | Seat guest on today | Seated column shows `Seated Nm`; updates ~1 minute |
| 4 | Pressure vs list date | Peak legend and row IDs match `selectedDateKey` |
| 5 | Host Intelligence strip | Briefing reflects selected day’s reservations |
| 6 | Tab away and back to Host | No wrong-date snapshot; no permanent empty flash |
| 7 | iPhone calendar (if enabled) | Sheet opens; iPad popover opens |
| 8 | Closed day, zero operational rows | Empty/closed UI — not previous day’s data |

**DEBUG traces:** `MultiDeviceSyncTrace.hostSnapshotPreserve`, `[HOST_BOARD] cleared stale snapshot`, `DateBoundaryTrace`.

## Related docs

- [HOST_TAB_ARCHITECTURE.md](./HOST_TAB_ARCHITECTURE.md)
- [HOST_TAB_UI_DESIGN_SYSTEM.md](./HOST_TAB_UI_DESIGN_SYSTEM.md)
- [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md)
