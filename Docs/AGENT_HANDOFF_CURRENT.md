# Agent Handoff — Current Slice

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)

---

## Title

iOS foreground / privacy stale refresh

---

## Git state (2026-06-19)

| Location | State |
|----------|--------|
| **Root branch** | `audit-current-state` — clean working tree |
| **Root HEAD** | `3c44856` — Update backend plugin for auth and guest cancellation fixes |
| **Backend submodule pointer** | `239b297` — Add guest cancellation email and pipeline visibility fixes |
| **Backend branch** | `AI` — clean working tree |
| **iOS** | Clean (no uncommitted Swift for this slice) |

**Recent root commits:**

- `3c44856` — submodule pointer → `239b297`
- `ac6c622` — remove duplicate Docs backend contract copies
- `b0f9419` — documentation source of truth and agent handoff

**Backend commits included in pointer:**

- `239b297` — guest cancellation email, cancelled self-service dead state, confirmation copy cleanup, pipeline `developer_summary` flattening
- `5a04af4` — auth role repair and diagnostics

---

## Backend verification reminder

Backend slice is **committed** but **not verified live** until deployed and checked on WordPress.

After deploy, verify before treating guest cancel / auth as production-ready:

1. Manager `/ping` → `user.can_manage_tryzub_reservations: true`
2. Guest cancel → `email_type=cancellation` in email log
3. Cancelled guest page → dead-state copy; no cancel button
4. Confirmation email → no “Request Different Time”
5. `GET /intelligence/system-status` → flattened pipeline fields in `developer_summary`

See prior handoff tests in git history (`b0f9419` era `AGENT_HANDOFF_CURRENT.md`) or post-deploy checklist in conversation notes.

---

## Goal

Refresh reservations when the app returns to **foreground** or when the **restaurant privacy cover** is dismissed, using existing refresh methods (`requestManualTodayRefresh`, `autoRefreshDashboardIfAllowed`), without refresh loops or fighting startup/background policy.

**Current gap:** `scenePhase == .active` in `ReservationsListView` only resets stale navigation — no network refresh. Privacy cover `recordInteraction()` / `dismissCover()` only dismisses UI. Host/Bookings auto-refresh loops skip while inactive and may wait up to 60s after return.

---

## Allowed files

| File | Why |
|------|-----|
| `Tryzub Reservations/Features/Reservations/ReservationsListView.swift` | `scenePhase` handler; privacy cover modifier attachment |
| `Tryzub Reservations/Import/ReservationsController.swift` | `requestManualTodayRefresh`, `autoRefreshDashboardIfAllowed`, busy/cooldown guards |
| `Tryzub Reservations/Features/Reservations/RestaurantPrivacyCover.swift` | Privacy cover dismiss hook; `RestaurantPrivacyCoverController` |
| `Tryzub Reservations/Services/FreshnessCoordinator.swift` | TTL / skip decisions (only if hook must respect coordinator) |
| Related privacy cover/controller files | Only if needed for dismiss callback wiring |

## Read-only reference

| File | Why |
|------|-----|
| `Tryzub Reservations/Features/Reservations/HostBoardView.swift` | 60s auto-refresh loop (`autoRefreshDashboardIfAllowed`) |
| `Tryzub Reservations/Services/AppReservationSession.swift` | Startup wiring; `FreshnessCoordinator` injection |

---

## Forbidden

- All backend PHP (`Backend/tryzub-reservations-api/*`)
- Guest profile SwiftData cache
- Walk-in creation mode
- Host stale warning UI (queue #3)
- Full Host Board refactor
- Rate limits, analytics persistence, zip/build number churn

---

## Implementation guidance (audit → code)

1. **Foreground:** Hook `scenePhase` transition to `.active` (or equivalent) to trigger refresh when appropriate tab is visible.
2. **Privacy unlock:** Hook `RestaurantPrivacyCoverController.recordInteraction()` / `dismissCover()` (or modifier callback) — not on every touch, only when cover was presented and is dismissed.
3. **Prefer existing methods:**
   - `requestManualTodayRefresh(context:source:)` for explicit staff-context refresh after unlock/foreground
   - `autoRefreshDashboardIfAllowed` only if semantics match (quiet delta; respects interaction guards)
4. **Guardrails:** Respect `hasActiveMutation`, `hasActiveReservationRefresh`, manual cooldown, auto interval throttle, `isScopeFresh` / 300s TTL. Do not duplicate startup pass (`performActiveWindowRefresh(mode: .startup)`).
5. **Tab scope:** Decide whether refresh fires at root shell level or only when Host/Bookings is active — document choice in commit message.

---

## Tests

1. **Background return** — background app 2+ min, foreground → board reflects remote changes without manual pull-to-refresh.
2. **Privacy unlock** — idle until cover shows, dismiss → refresh within reasonable time; no loop on normal touches.
3. **Mutation in flight** — active create/edit → foreground/unlock does not stomp in-flight mutation.
4. **Host tab** — visible Host + today → refresh on foreground/unlock.
5. **Bookings tab** — visible Bookings → refresh on foreground/unlock (or explicitly skipped with documented reason).
6. **No duplicate refresh loop** — no back-to-back full syncs; cooldown guards hold; logs show skip vs fetch decisions.

---

## Command-line budget

```bash
git status --short
git diff --stat
# Xcode build after implementation
```

- Read only allowed + reference files.
- Audit first (Composer); implement second (GPT-5.5 Agent).
- One commit series per concern.

---

## Out of scope

Backend, walk-ins, guest profile cache, Host stale warning UI, full Host Board refactor, analytics persistence.
