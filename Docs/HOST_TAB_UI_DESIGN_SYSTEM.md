# Host tab UI design system

**Status:** Current source of truth  
**Audit date:** 2026-06-14  
**Related fixes:** HT-2 (calendar), HT-3 (seated duration)

## 1. Design goal

The Host tab is the restaurant’s **live operations command center** — internal staff only.

It should feel:

- **Premium** — deliberate spacing, glass surfaces, restrained color
- **Glass / liquid** — layered atmosphere, soft strokes, not flat gray boxes
- **Alive but calm** — subtle motion during service; nothing frantic
- **Futuristic operations** — intelligence strip, pressure wave, crisp rows
- **Readable in service** — glanceable time, table, seated duration, status
- **Not cluttered** — one-line AI summary, compact metadata, collapsed pressure by default
- **Not fragile** — visual changes must not break date/snapshot state (see state-flow doc)

## 2. Glass surfaces

**Canvas:** `TryzubHostBoardCanvas` (`TryzubGlassChrome.swift`)

- `Color(.systemBackground)` base + soft accent/blue blurred circles
- All board content sits above atmosphere

**Modifiers:**

| Modifier | Typical use | Notes |
|----------|-------------|-------|
| `hostBoardGlassSurface(cornerRadius:)` | Header, large panels | Base grouped + stroke |
| `hostBoardGlassPanel(cornerRadius:strokeOpacity:)` | AI strip, pressure, reminders | Default stroke ~0.10–0.14 |
| `hostBoardGlassCapsule(strokeOpacity:)` | State chips, Review button | Compact controls |
| `hostBoardGlassChip(isSelected:)` | Date chips (`.hostBoardGlass` style) | Selected = filled accent |

**Tokens (`TryzubGlassChrome`):**

- `surfaceCorner: 18` (intro); Host header lerps 14 → 11 on collapse
- `surfaceStrokeOpacity: 0.08` baseline; panels often 0.10–0.12
- `hostBoardAccentBlue` for selected chip emphasis

**Rules:**

- Prefer glass modifiers over raw `Color(.secondarySystemGroupedBackground)` on Host board.
- Keep stroke opacity low in dark mode — test both appearances.
- Row backgrounds on Host use tinted fill + optional iOS 26 glass branch — do not mix arbitrary opacities per row.

## 3. Typography rules

| Element | Font | Rule |
|---------|------|------|
| AI strip summary | `.caption.weight(.medium)` | One sentence; max 2 lines |
| AI state chip | `.caption2.weight(.medium)` | Quiet label (Calm / Busy / etc.) |
| Section headers (Seated, Reservations) | `.headline.weight(.medium)` | Not `.largeTitle` |
| Hour section labels | `.caption.weight(.semibold)` | Secondary hierarchy |
| Row guest name | `.headline.weight(.medium)` (wide) / `.subheadline` (compact) | Line limit 1 |
| Row time | prominent in time column | Eyebrow = status on Host (`SEATED`) |
| Row metadata | `.caption` / `.caption2` | Table, notes, **seated duration** |
| Pressure summary | `.caption.weight(.medium)` | Single line when collapsed |
| KPI / stats | `.caption` – `.subheadline` | Muted secondary for counts |

**Avoid:** giant bold operational warnings in the strip; engineering terms (“slot pressure”, “candidate”); HostStaffLanguage rewrites exist — use staff-facing copy.

## 4. Animation rules

| Animation | Allowed | Notes |
|-----------|---------|-------|
| Date chip select | `.snappy(duration: 0.32–0.38)` | Scale 0.96 → 1 |
| Pressure expand/collapse | `.snappy(duration: 0.32)` | Chevron rotation |
| Header collapse on scroll | `.smooth(duration: 0.32)` | Scale/lerp via `HostBoardHeaderCollapse` |
| AI mark pulse | breathe/glow on `HostIntelligenceMark` | **Fixed size** — do not resize strip |
| Row press | opacity via button style | No bounce |

**Forbidden without explicit approval:**

- Per-second UI timers
- Continuous layout-affecting animations on lists
- Animations that fight scroll or header collapse

**Clock:** `clockTick` updates **once per minute** for seated duration and today operational stamps. Respect `@Environment(\.accessibilityReduceMotion)` on header collapse and AI mark.

## 5. Host row contract

`ReservationRowView` with `displayStyle: .hostBoard` (`HostBoardReservationRow`).

**Must show:**

- Time + party count (time column)
- Guest name
- Eyebrow: status uppercase (`SEATED`, `CONFIRMED`, …)
- Table (or “No table”) — tappable when `onTableTap` set
- Guest/staff note icons when present
- Needs-review icon when applicable

**Seated duration (HT-3):**

- Only when `status == .seated`
- Shown in **metadata row** via `hostBoardMetaItems` — e.g. `Seated 12m`
- `TryzubStaffStatusDot` beside duration text
- Sourced from `contextNote` = `seatedDurationText` — **not** insight line

**Must not show on Host board:**

- Full `presentation.insight` line (noisy operational timing as second row)
- Submitted-time insight (schedule/review only)
- New-booking insight lines (Host strips these)

**Attention insights:** only `dueSoon` / `attention` prominence may appear in metadata — sparingly.

## 6. Date control contract

**Strip:** horizontal chips — Today + next days; extends when selection outside window.

**Calendar button (HT-2):**

- `44×44` minimum hit target
- `HStack` with strip — **no ZStack overlap**
- iPhone → sheet; iPad → popover
- Same `$selectedDate` binding

**Host board current product setting:** `showsCalendarButton: false` — chips only. If re-enabled, run calendar manual tests from [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md).

**Header collapse:** date strip scales; calendar (if shown) must remain tappable at minimum collapse height.

## 7. AI strip contract

`HostIntelligenceCard` — `presentationStyle: .compactStrip` on Host board.

| Element | Rule |
|---------|------|
| Summary | One operational sentence; template or validated narrative |
| State chip | Small glass capsule — service state (not pressure score in staff mode) |
| Primary action chip | One chip when single high-confidence action (future AI-2) |
| Review | When multiple actions or prompts; opens `HostIntelligenceReviewView` |
| Quiet service | Summary only; no action chip; no Review if nothing to check |

**Do not:** invent actions not in app; show generic “Take action”; own `selectedDate` state.

## 8. Pressure graph contract

- **Data:** always `currentDateBoardSnapshot.arrivalPressure` (HT-1)
- **Default:** collapsed summary line; expand for `ArrivalPressureWaveChart`
- **Summary:** peak legend + subtitle from engine — staff language
- **Interaction:** bucket tap → `ArrivalPressureBucketSheet` (chart only)
- **Not** a separate date source — if graph disagrees with lists, snapshot date is wrong

## 9. Dark / light testing

Before shipping Host UI changes, verify:

| Device | Mode | Check |
|--------|------|-------|
| iPad | Dark | Glass strokes visible; row metadata readable |
| iPad | Light | No washed-out chips; pressure chart legible |
| iPhone | Both | Stacked lists; header in scroll; tap targets |
| Reduce Motion | Either | Header collapse + AI mark respect setting |

**High contrast:** status dots and attention tints must remain distinguishable.

## Related docs

- [HOST_TAB_ARCHITECTURE.md](./HOST_TAB_ARCHITECTURE.md)
- [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md)
- [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md)
