# iOS UI/UX Status

## 1. Design Goal

The current UI pass focuses on making the app feel like a calm host operations tool instead of a developer dashboard. The host should quickly see who is next, when they arrive, how many guests, whether the reservation is confirmed, whether a table is assigned, and what action comes next.

The reservation cell standard is now intentionally monochrome: black text, grey metadata, light grey row fills, and subtle grey separation. Status is shown with compact text instead of colored badges. Actions use neutral outlined buttons.

This pass does not change backend behavior, fetch timing, auto-refresh, API contracts, or SwiftData sync rules.

## 2. iPad Landscape Layout

The Today screen now uses a compact summary strip at the top and puts the reservation board immediately below it.

The wide host board keeps the two-column model:

- left: Seated / In House
- right: Upcoming Today

When no one is seated, the seated column is narrower and uses a compact empty state so Upcoming Today gets more visual priority.

## 3. iPad Portrait Layout

The board keeps the compact segmented layout:

- Upcoming
- Seated
- Review

Rows are more compact and use the same action rules as the wide board.

## 4. iPhone Layout

iPhone keeps the stacked/segmented host board. The compact rows avoid putting too much metadata in one line and preserve time/name/status priority.

Manual visual review is still required on smaller iPhone widths.

## 5. Today Dashboard / Summary Behavior

The large metric card was replaced with a compact summary strip.

It shows:

- date
- last synced / refreshing state
- count
- guests
- new
- review
- form problems
- no table

The strip uses small chips rather than large stat cards so reservations dominate the screen.

## 6. Warning / Chip Behavior

Warnings are now compact chips or thin inline messages:

- form problems
- needs review
- without table
- refresh/action notices

The warning treatment is also neutral/grey so the screen does not become a stack of competing colors. Form problem chips remain tappable through the existing failed-import flow.

## 7. Reservation Row Structure

One shared `ReservationRowView` is now the visual standard for Today, Schedule, and Review. Screens pass context and accessories into that row instead of maintaining separate-looking cell designs.

Host board wide rows are treated like a grid:

- time
- party size
- guest + phone/notes
- table
- status
- details / primary action accessory

The row follows the pasted reference more closely:

- light grey rounded rectangle
- bold time on the left
- compact party/table block
- bold uppercase guest name
- small phone/notes metadata
- tiny uppercase status text
- ellipsis/details and optional primary action on the right

The row was tightened with smaller padding and fixed-width scan points. Time, status, and action labels use one-line constraints.

Schedule and Review now route through the same row component as Today. They differ by context and available actions, not by separate visual styling.

## 8. Host Board Behavior

Upcoming reservations are visually dominant when Seated is empty.

Empty states are compact and no longer consume half the screen with large illustration space.

The next reservation still receives a subtle highlight.

## 9. Detail Screen Behavior

The detail hero is more compact:

- smaller time treatment
- one-line guest name
- compact status and pills
- compact action bar
- smaller Edit Details button

Developer/sync fields are now collapsed under “Developer / Sync Info” so the operational detail screen does not start as a long technical page.

## 10. Action Button Rules

Row actions now show a compact readable primary action on the right:

- new: Confirm
- needs_review: Confirm if capability allows
- confirmed: Seat
- confirmed/no table: Table action is available through existing table assignment flow
- seated: Complete
- completed/cancelled/no_show: no primary operational action

Secondary actions are moved behind a menu when space is tight. Action labels are constrained to one line and use neutral grey/black styling.

## 11. Known UI Limitations

- No full table map yet.
- No waitlist UI yet.
- Detail view still needs real-device tuning after staff tries it during service.
- Schedule screen still uses list navigation rather than a full iPad split view.
- Smaller iPhone widths need manual visual review.
- No screenshot-based UI tests yet.

## 12. Screens To Review Manually

Check these before calling the UI final:

- iPad landscape Today / Host Board
- iPad portrait Today / Host Board
- iPhone Pro Max Today / Host Board
- smaller iPhone width Today / Host Board
- Schedule list with long names and long phone numbers
- Review list with needs-review staff notes
- Reservation detail for new, confirmed, seated, cancelled, and needs-review records
- Detail action bar with Confirm, Seat, Assign Table, Cancel, and No Show options

Acceptance checks:

- time does not wrap
- action labels do not wrap vertically
- rows stay compact
- summary strip stays compact
- warnings stay compact
- Upcoming Today dominates when no one is seated
- detail primary action is visible without hunting

## 13. Files Changed

- `Tryzub Reservations/Features/Reservations/HostBoardView.swift`
- `Tryzub Reservations/Features/Reservations/ReservationActionButtons.swift`
- `Tryzub Reservations/Features/Reservations/ReservationRowView.swift`
- `Tryzub Reservations/Features/Reservations/ReservationDetailView.swift`
- `Tryzub Reservations/Features/Reservations/ReservationsListView.swift`
- `IOS_UI_STATUS.md`

Build status after this UI pass:

- `xcodebuild -project "Tryzub Reservations.xcodeproj" -scheme "Tryzub Reservations" -destination 'generic/platform=iOS Simulator' build` succeeded.
