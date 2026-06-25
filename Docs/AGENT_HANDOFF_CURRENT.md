# Agent Handoff — Current Slice

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)

---

## Title

V1 stabilization: device verification + final smoke test (guest memory + Tryzub V1 Host production polish shipped)

---

## Git state (2026-06-25)

| Location | State |
|----------|--------|
| **Root branch** | `audit-current-state` |
| **Root HEAD** | `39f7fcb` — Keep Host Intelligence card stable during presentation rebuild |
| **Root vs remote** | Pushed to `origin/audit-current-state` at `39f7fcb` (pending this doc commit) |
| **Backend submodule pointer** | `078a44a` — Document guest self-service cache contract |
| **Backend branch** | `AI` |
| **Backend HEAD** | `078a44a` |
| **Backend vs remote** | Pushed to `origin/AI` at `078a44a` |

**Recent root commits (newest first):**

- `39f7fcb` — Host Intelligence card stable during presentation rebuild (no empty interstitial during key mismatch)
- `71601fc` — Host sync status copy (`Last sync`), stale skip reasons, conditional snapshot minute rebuild, Live no-cursor bypass
- `67e02d2` — Guests tab + Reservation Detail read local guest cache first
- `0a89caa` — manual intake: local guest cache merge, call-in/walk-in, known-guest prefill, phone UX
- `0f06852` — persisted guest profile cache + background incremental sync (`updated_since`)
- `cf6e641` — harden V1 confirmation flow for service safety
- `48c6f87` — add second engineer context for V1 release
- `2b2bc8f` — align docs with sync/confirmation behavior
- `b910bd1` — iOS foreground/privacy-cover refresh

**Backend commits on pointer (newest first):**

- `078a44a` — document guest self-service cache contract (README)
- `d46713a` — guest self-service no-store headers, JS cache bust, POST cancel returns refreshed `data`
- `854b82d` / `6a30203` — guest-facing confirmation/cancellation/page copy
- `239b297` — guest cancellation email, cancelled dead-state UI, pipeline `developer_summary` flattening

**Deploy zip:** not tracked in git (`Backend/*.zip` ignored). Build locally from backend `HEAD` when deploying.

---

## Current slice goal

**Stabilization still open** (device verification + final smoke test). **Guest memory foundation** and **Tryzub V1 Host production polish** (freshness header + idle snapshot + intelligence-card stability) are shipped on iOS.

### Completed (iOS guest memory — `0f06852` + `0a89caa` + `67e02d2`)

1. Backend guest profiles are **persisted server-side** in `{prefix}tryzub_guest_profiles`; iOS fetches list incrementally via `GET /guest-profiles?updated_since=…`.
2. **`GuestProfileCacheRecord`** in SwiftData — local disk cache of backend guest aggregates.
3. **Background list sync** after startup/noncritical deferral (`GuestProfileSyncService` + `AppReservationSession`).
4. **Manual intake** merges persisted guest cache with local `ReservationRecord` history in `GuestLookupStore` — **no network on phone keystroke**.
5. **Manual intake modes:**
   - Call-in → `manual_call_in` + `confirmed`
   - Walk-in → `manual_walk_in` + `seated` (optional table)
   - Known guest call-in → `known_guest_manual` + `confirmed`
   - Known guest walk-in → `manual_walk_in` + `seated` (walk-in analytics; identity from contact fields)
6. Known-guest card **below contact fields**; phone field uses `.textContentType(.none)` + `.phonePad`.
7. **Use** prefill fills name/phone/email/notes safely — does not overwrite typed guest/staff notes.
8. **No `guest_key` on create** — backend create contract does not support it yet; backend resolves identity from name/phone/email after insert.
9. **Guests tab + detail local-first cache wiring** (`67e02d2`):
   - `GuestLookupView` reads `GuestProfileCacheRecord` via `@Query`; result cards show compact guest memory metadata.
   - `ReservationDetailView` reads disk cache preview before memory/network preview.
   - Full guest history / profile pack remains network/detail-only.
   - `RegularGuestsView` disk-first remains a later slice.

### Completed (Tryzub V1 Host production polish — `71601fc` + `39f7fcb`)

**`71601fc` — Host freshness + reduced idle snapshot flicker**

1. Header says **`Last sync HH:mm`** for successful server sync; **`Checked HH:mm`** remains for cache-only freshness checks.
2. When trust is stale (>120s), header can show a short staff-facing secondary reason:
   - `Paused` · `Paused while editing` · `Waiting — busy` · `Retry soon`
   - Fallback: `May be out of date · tap refresh`
3. **Live mode + today** can bypass only `full_fresh_no_cursor` idle skip — does not bypass app inactive, interaction active, controller busy, interval throttle, or failure cooldown.
4. **Conditional snapshot minute rebuild** — Host snapshot no longer rebuilds every minute for:
   - non-today selected date
   - quiet today boards with no time-sensitive rows
   - Minute updates still occur when seated, due soon/due now/overdue, or upcoming within ~90 minutes.
5. Stale threshold remains **120 seconds**. Reduced idle snapshot flicker — not all flicker eliminated. No backend, `FreshnessCoordinator`, or global sync rewrite.

**`39f7fcb` — Host Intelligence card presentation stability (`HostBoardView.swift` only)**

1. Host Intelligence card no longer renders `HostIntelligenceCardPresentation.empty` during presentation-key mismatch.
2. Keeps prior stable card/chips visible while async card presentation rebuild catches up.
3. Removes old-card → empty-card → rebuilt-card flicker path.
4. Does **not** change Host Intelligence cadence, local model pipeline, sync, backend, guest cache, or `FreshnessCoordinator`.
5. Brief text/attention can update slightly before inline chips during the short rebuild window — acceptable vs chips vanishing.

### Still open (V1 stabilization)

1. Verify iOS data/fetch/storage on device (foreground/privacy refresh at `b910bd1`).
2. Confirm confirmation mode on restaurant iPad (Mail vs backend `/confirm`).
3. Final V1 smoke test on restaurant iPad — must now include Host header/flicker + intelligence-card checks (see [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #4c).

**Not production-ready** until stabilization items 1–3 pass.

### Product-scale follow-up (before broader product release)

Replace broad in-memory guest filtering with **indexed / predicate-based local search**. Acceptable for **current Tryzub V1 data size** only.

**Later slices (not blocking V1 smoke test):** `RegularGuestsView` disk-first; `ReservationDetail` guest fetch dedupe (partially improved; full dedupe later).

**Parked / not started:** offline queue, broad Host redesign, full AI clustering / “knows each other” / local semantic tags, VIP editor (no backend guest-notes contract).

---

## Backend self-service cache fix (`d46713a`)

**Status:** committed, pushed, **verified in production** — guest cancel email + cancelled dead-state on reload.

---

## Production deploy state

| Item | Status |
|------|--------|
| Guest self-service cache fix | **Live and verified** |
| App login | **Works** in production |
| Guest profile aggregates (backend table) | **Live** — iOS syncs incrementally |
| Deployed zip SHA in git | **Not tracked** |

---

## Verified in production (known)

- Anonymous `GET /ping` → 200
- Protected routes without auth → 401
- Guest cancellation email + cancelled dead-state on reload
- App login (manager/developer protected routes)
- Pipeline diagnostics reviewed; `unexplained_missing` old test — **non-blocking**

## Not yet verified in production / device

- iOS foreground/privacy-cover refresh on physical device
- Confirmation mode on restaurant iPad
- Final V1 smoke test (staff ops on restaurant iPad) — include guest cache, walk-in/known-guest, Host `Last sync` + stale reasons + reduced idle flicker + intelligence-card chip stability
- Guest profile background sync on test iPad (post-`0f06852` install)
- Manual walk-in + known-guest intake on test iPad (post-`0a89caa` install)
- Guests tab + detail cache wiring on test iPad (post-`67e02d2` install)
- Host freshness/flicker polish on test iPad (post-`71601fc` install)
- Host Intelligence card presentation stability on test iPad (post-`39f7fcb` install)

---

## iOS guest memory (`0f06852` + `0a89caa` + `67e02d2`)

| Component | Role |
|-----------|------|
| `GuestProfileCacheRecord` | SwiftData disk cache of list aggregates |
| `GuestProfileRepository` | Upsert, search, phone match |
| `GuestProfileSyncService` | Paginated `/guest-profiles` + `updated_since` cursor in UserDefaults |
| `GuestProfileStore` | Memory TTL + optional disk write-through when `ModelContext` passed |
| `GuestLookupStore` | Merges cache + reservation history for manual intake and Guests tab |
| `GuestLookupView` | `@Query` cache + compact guest memory metadata on result cards |
| `ReservationDetailView` | Disk cache preview before memory/network preview |
| `ManualReservationFormView` | Call-in/walk-in segmented mode, known-guest card, prefill |

**Rules:**

- List sync only in background — **no detail/history prefetch**, no `/guest-profiles/rebuild`, no `/guest-intelligence` on keystroke.
- Phone normalization: `GuestLookupPhoneNormalizer.digits` everywhere (typed phone, cache, reservation history).
- Broad in-memory guest filter: acceptable for **current Tryzub V1 data size**; indexed search required before broader product release.

**Data model reminders:**

- Backend is source of truth; SwiftData (reservations + guest profiles) is operational cache only.
- No offline mutation queue in V1.

---

## Host production polish (`71601fc` + `39f7fcb`)

| Component | Role |
|-----------|------|
| `HomeServiceStatusPresenter` | `Last sync` / `Checked` primary; stale secondary skip reasons (`71601fc`) |
| `VisibleAutoRefreshSkipReason` | Staff labels for auto-refresh skip paths (`71601fc`) |
| `ReservationsController.autoRefreshDashboardIfAllowed` | `preferVisibleLiveRefresh` bypasses only `full_fresh_no_cursor` when Live + today (`71601fc`) |
| `HostBoardView.hostBoardSnapshotTimingRefreshStamp` | Conditional minute key for snapshot rebuild (`71601fc`) |
| `HostBoardView.stableHostIntelligenceCardPresentation` | Keeps last card/chips during async presentation rebuild (`39f7fcb`) |

**Do not overstate:** reduced idle snapshot flicker (`71601fc`) — not all flicker eliminated; `clockTick` still runs every 60s. Removed Host Intelligence card empty interstitial flicker path (`39f7fcb`) — final device verification still open.

---

## Next exact actions

1. **Device-test** iOS foreground/privacy refresh (`b910bd1`).
2. **Confirm** confirmation mode on restaurant iPad.
3. **Run** final V1 smoke test — include guest cache, walk-in/known-guest, Host header (`Last sync`), stale secondary reasons, Live-on-today refresh, quiet-board idle flicker, intelligence-card chips stable during refresh, seated/due timing updates, manual refresh bumps `Last sync`.
4. Before broader product release → **indexed local guest search** ([IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #6).

---

## Forbidden until stabilization verified

- Offline manual reservation queue / offline edits (not v1)
- Broad Host Board refactor
- Full AI clustering / graph mapping / local semantic tags
- VIP editor without backend contract
- Backend contract duplication into root `Docs/`

---

## Read-only reference

| Area | Files |
|------|--------|
| Guest cache | `GuestProfileCacheRecord.swift`, `GuestProfileRepository.swift`, `GuestProfileSyncService.swift`, `GuestProfileStore.swift`, `GuestLookupView.swift` |
| Manual intake | `ManualReservationFormView.swift`, `GuestLookupStore.swift` |
| Host freshness | `HostBoardView.swift`, `ReservationSharedUI.swift`, `ReservationsController.swift` |
| Guest self-service | `Backend/.../reservation-self-service.php` |
| Backend contracts | `Backend/.../README.md`, `INTELLIGENCE.md` |
| iOS refresh | `ReservationsListView.swift`, `ReservationsController.swift`, `FreshnessCoordinator.swift` |

---

## Command-line budget

```bash
# Backend
cd Backend/tryzub-reservations-api && git status --short && git log -3 --oneline

# Root
cd .. && git status --short && git submodule status && git log -3 --oneline
```

Audit first (Composer); implement only from approved handoff; one commit per concern.
