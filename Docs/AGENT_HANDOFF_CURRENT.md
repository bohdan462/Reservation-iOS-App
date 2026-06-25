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
| **Root HEAD** | `1dfa14a` — Add Guests tab guest-record search and shared guest history shell |
| **Root vs remote** | Pushed to `origin/audit-current-state` at `1dfa14a` (pending this doc commit) |
| **Backend submodule pointer** | `1431a06` — Add staff guest profile lookup with safe strong-only best match |
| **Backend branch** | `AI` |
| **Backend HEAD** | `1431a06` |
| **Backend vs remote** | Pushed to `origin/AI` at `1431a06` |

**Recent root commits (newest first):**

- `1dfa14a` — Guests tab guest-record search + shared Guest history shell (Slice 3B)
- `823f42c` — iOS guest profile lookup API/client/store foundation (Slice 3A)
- `e1e911a` — docs after backend guest profile lookup
- `b1a09e7` — backend submodule pointer → staff guest profile lookup (`1431a06`)
- `5e90170` — docs after guest person-map Slice 1
- `d541488` — guest profile full-list sync completion + all cached profiles indexed
- `dc3d8c5` — docs after guest cache wiring and Host polish
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

- `1431a06` — `GET /guest-profiles/lookup` staff targeted search with safe strong-only best match
- `078a44a` — document guest self-service cache contract (README)
- `d46713a` — guest self-service no-store headers, JS cache bust, POST cancel returns refreshed `data`
- `854b82d` / `6a30203` — guest-facing confirmation/cancellation/page copy
- `239b297` — guest cancellation email, cancelled dead-state UI, pipeline `developer_summary` flattening

**Deploy zip:** not tracked in git (`Backend/*.zip` ignored). Build locally from backend `HEAD` when deploying.

---

## Current slice goal

**Stabilization still open** (device verification + final smoke test). **Guest memory foundation**, **guest person-map Slice 1** (`d541488`), **backend Slice 2 lookup** (`1431a06`), **iOS Slice 3A lookup foundation** (`823f42c`), **iOS Slice 3B Guests tab lookup UI** (`1dfa14a`), and **Tryzub V1 Host production polish** are shipped.

**Guest Person Map target:** one shared **Guest history** destination by `guestKey`, reused across Guests tab (done in 3B), More → Guest Memory / Regulars (open — Slice 3R), Reservation Detail guest insights (open — Slice 3D integration), Manual Intake candidates (open — Slice 3M), and booking-history rows later. Backend `GET /guest-profiles/{guest_key}` detail DTO is the primary source for full history (`bookingHistory`, `notesHistory`, counts, labels, summary, preferences, source mix, next reservation). SwiftData is operational cache only — avoid recomputing heavy reservation-scoped guest analysis when a backend/cached guest profile exists.

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

### Completed (guest person-map Slice 1 — `d541488`)

1. **`GuestProfileSyncService`** persists sync metadata: `fullListSyncCompleted`, `lastFullListSyncAt`, `backendProfileTotal`, `cachedProfileCount`, `lastSyncFailureReason`.
2. If full-list sync is **incomplete**, iOS forces full paginated `GET /guest-profiles` sync (`updatedSince == nil`).
3. **15-minute guest-profile sync TTL is bypassed** while full-list sync is incomplete; normal TTL applies once complete.
4. Local cached count is reconciled against backend `total` before marking complete.
5. **`GuestLookupStore`** indexes **all** locally cached `GuestProfileCacheRecord` rows — removed old default 500 cap.
6. Guests tab and manual intake remain **local-only while typing** for on-device matches; Guests tab can also run **explicit** backend lookup (Slice 3B).
7. **No** full history prefetch, **no** indexed/predicate search yet.

### Completed (guest person-map Slice 3A — iOS `823f42c`)

1. **DTO/API/client** support for `GET /guest-profiles/lookup` (`GuestProfileLookupResponseDTO`, `ReservationsAPIClient.fetchGuestProfileLookup`).
2. **`GuestProfileStore.lookupProfiles(...)`** — dedupes identical lookup tasks; network task does not capture `ModelContext`; SwiftData upsert runs on `@MainActor` after await.
3. Lookup candidates preserve `guestKey`, `match_basis`, `match_confidence`, and backend `best_match_*` fields (UI must not auto-trust `best_match_guest_key` alone).
4. Compact lookup summaries upsert into SwiftData with `hasDetailPayload: false` — detail blobs preserved on list upsert.
5. **No UI triggers** in this slice.

### Completed (guest person-map Slice 3B — iOS `1dfa14a`)

1. **Guests tab** explicit **Search all guest records** (button + keyboard search submit only — **no per-keystroke backend lookup**).
2. Typing still searches **saved on this iPad** matches only (`GuestLookupStore`).
3. Staff-facing sections: **Saved on this iPad** / **All guest records**; strong email/phone → **Likely guest**; name/partial/possible/weak/unknown → **Possible match**.
4. Staff must tap a candidate — **no automatic selection** or auto-open.
5. Results with `guestKey` can open **`GuestProfileDetailView`** (title: **Guest history**) via **View history**; **Book reservation** remains separate.
6. **`GuestProfileDetailView`** is the shared destination **shell** by `guestKey` through existing `GuestProfileStore.loadProfile(guestKey:)` — shows identity/contact, labels, first/last seen, metrics, next reservation, summary/pattern lines.
7. **Not in 3B:** full booking-history list, chronological notes timeline, source-mix UI, disk-first full detail persistence, Regulars integration, Manual Intake backend lookup, Reservation Detail shared-destination routing.

### Completed (guest person-map Slice 2 — backend `1431a06`, root pointer `b1a09e7`)

Staff targeted guest lookup doorway — part of the guest person-map / “know your guest” system:

1. **`GET /tryzub/v1/guest-profiles/lookup`** — staff/admin auth via `tryzub_can_read_reservations`; registered **before** `/guest-profiles/{guest_key}`.
2. Params: `phone`, `email`, `q`, bounded `limit` (default 5, max 10). At least one required.
3. **Exact normalized email** → `match_confidence: strong`, `match_basis: email`.
4. **Exact 10+ digit phone** → `match_confidence: strong`, `match_basis: phone`.
5. **7–9 digit phone** exact/suffix → `match_confidence: possible`, `match_basis: phone`.
6. **Name-only `q`** → possible candidates for walk-ins and guests without contact details; `match_basis: name`; never strong.
7. Returns **compact profile summaries** only (`guest_key`, identity fields, visit stats, labels, summary, `match_basis`, `match_confidence`). **No** `booking_history`, `notes_history`, self-service tokens, manage links, or cancellation tokens.
8. **Safe best match:** `best_match_guest_key` / `best_match_basis` / `best_match_confidence` populated only when exactly one unique strong guest key exists; null when zero or conflicting strong matches. Name-only and partial-phone candidates never become canonical automatically.
9. **No** inline rebuild, **no** reservation-table scan, **no** public access.
10. **Complete guest access preserved:** paginated `GET /guest-profiles` remains the full profile list; `GET /guest-profiles/{guest_key}` and `GET /guest-profiles/by-reservation/{id}` remain full detail/history/notes/stats.
11. **Not deployed** to production WordPress yet; **iOS calls this route from Guests tab explicit search only** (`1dfa14a`) — not from Manual Intake or per-keystroke typing.

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
3. Final V1 smoke test on restaurant iPad — must now include guest full-list sync, Guests/intake lookup, Host header/flicker + intelligence-card checks (see [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #4c).

**Not production-ready** until stabilization items 1–3 pass.

### Product-scale follow-up (before broader product release)

Replace broad in-memory guest filtering with **indexed / predicate-based local search**. Acceptable for **current Tryzub V1 data size** only.

**Later slices (not blocking V1 smoke test):** **3R** Regulars / Guest Memory cache-first + shared Guest history tap; **3D** full shared Guest history UI (booking history + notes timeline); **3M** Manual Intake name search, all-record lookup, candidate list, walk-in/call-in validation; **3M-B** backend support for true unknown walk-ins without name/phone; **3E** detail JSON persistence; phone normalization 10 vs 11 digit follow-up; dedicated validation error for blank lookup if needed; indexed local guest search; foreground/mutation-triggered guest-profile re-sync; `ReservationDetail` guest fetch dedupe (partially improved; full dedupe later).

**Regulars / Guest Memory (still open — Slice 3R):** `RegularGuestsView` remains **network-page-first** (`page: 1`, `perPage: 25`) and can show **“Showing 25 of 101 profiles”** even when all profiles are cached locally. Backend rows are not tappable to `GuestProfileDetailView`; local fallback still opens heavy reservation-scoped `GuestInsightsView`.

**Manual Intake (still open — Slice 3M):** phone/local-first only; **no backend lookup**; walk-in still requires name + 10-digit phone on both iOS validator and backend create; true optional walk-in name/phone needs **3M-B** backend + iOS changes.

**Backend lookup P2 follow-ups (non-blocking):** 10-digit local vs stored `1`-prefixed country-code mismatch; short numeric `q` may enter text/name search; name-query SQL may also match email substring while reporting `name` basis; unrelated `phone`+`email` params may return separate candidates; suffix phone `LIKE` may not use phone index efficiently.

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
- Final V1 smoke test (staff ops on restaurant iPad) — include guest full-list sync completion, Guests/intake lookup beyond old 500 cap, walk-in/known-guest, Host `Last sync` + stale reasons + reduced idle flicker + intelligence-card chip stability
- Guest profile background sync on test iPad (post-`0f06852` install)
- Manual walk-in + known-guest intake on test iPad (post-`0a89caa` install)
- Guests tab + detail cache wiring on test iPad (post-`67e02d2` install)
- Host freshness/flicker polish on test iPad (post-`71601fc` install)
- Host Intelligence card presentation stability on test iPad (post-`39f7fcb` install)
- Guest profile full-list sync + full-cache lookup on test iPad (post-`d541488` install)
- Backend guest profile lookup route deployed + smoke-tested on WordPress (post-`1431a06` deploy — **not done**)
- Guests tab explicit all-record lookup + View history shell on test iPad (post-`1dfa14a` install)

---

## iOS guest memory (`0f06852` + `0a89caa` + `67e02d2` + `d541488` + `823f42c` + `1dfa14a`)

| Component | Role |
|-----------|------|
| `GuestProfileCacheRecord` | SwiftData disk cache of list aggregates |
| `GuestProfileRepository` | Upsert, search, phone match; `allCachedProfiles` for full local index |
| `GuestProfileSyncService` | Paginated `/guest-profiles`; full-list completion metadata + TTL bypass while incomplete (`d541488`) |
| `GuestProfileStore` | Memory TTL + disk write-through; `lookupProfiles` for explicit lookup (`823f42c`) |
| `GuestLookupStore` | Merges all cached profiles + reservation history for manual intake and Guests tab local search (`d541488`) |
| `GuestLookupView` | Local search while typing; explicit **Search all guest records**; **View history** + **Book reservation** (`1dfa14a`) |
| `GuestProfileDetailView` | Shared **Guest history** shell by `guestKey` — summary/metrics only until Slice 3D (`1dfa14a`) |
| `ReservationDetailView` | Disk cache preview before memory/network; still opens reservation-scoped `GuestInsightsView` for full history |
| `RegularGuestsView` | **Still network-page-first** — Slice 3R open |
| `ManualReservationFormView` | Call-in/walk-in segmented mode, phone-only known-guest card, prefill — **no backend lookup** |

**Rules:**

- List sync only in background — **no detail/history prefetch**, no `/guest-profiles/rebuild`, no `/guest-intelligence` on keystroke.
- Backend `/guest-profiles/lookup` is called from **Guests tab explicit search only** (`1dfa14a`) — not Manual Intake, not per keystroke.
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
3. **Run** final V1 smoke test — include guest full-list sync, Guests/intake lookup (no per-digit backend calls), walk-in/known-guest, Host header (`Last sync`), stale secondary reasons, Live-on-today refresh, quiet-board idle flicker, intelligence-card chips stable during refresh, seated/due timing updates, manual refresh bumps `Last sync`.
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
| Guest cache + lookup | `GuestProfileCacheRecord.swift`, `GuestProfileRepository.swift`, `GuestProfileSyncService.swift`, `GuestProfileStore.swift`, `GuestLookupView.swift`, `GuestProfileDetailView.swift` |
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
