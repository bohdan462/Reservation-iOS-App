# Second Engineer Context — Tryzub Reservations

**Purpose:** Keep ChatGPT aligned as the second engineer on Tryzub Reservations. Read this before answering Bohdan about implementation, priorities, docs, Composer prompts, or V1 release planning.

**Release target:** V1 release/testable restaurant build this weekend.

**Owner / product lead:** Bohdan  
**Implementation workflow:** Bohdan + Composer 2.5 (audit/docs) + GPT-5.5 Agent (code)  
**Current project:** Private internal iOS reservation-management app + WordPress backend for Tryzub Ukrainian Kitchen.

---

## 1. How to use this file

This file is **not** the API contract and not the full architecture.

Use it as the current engineering alignment layer:

1. Read this first for priorities and workflow.
2. Then check:
   - [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)
   - [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)
   - [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md)
   - [IOS_ARCHITECTURE.md](./IOS_ARCHITECTURE.md)
   - [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md)
   - [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md)
   - [Backend README](../Backend/tryzub-reservations-api/README.md)
   - [Backend INTELLIGENCE](../Backend/tryzub-reservations-api/INTELLIGENCE.md)
3. Treat stale/reference docs as historical only:
   - [PROJECT_MAP.md](./PROJECT_MAP.md)
   - [PROJECT_METHOD_MAP.md](./PROJECT_METHOD_MAP.md)
   - [ARCHITECTURE_DIAGRAMS.md](./ARCHITECTURE_DIAGRAMS.md)
   - redirect stubs (`IOS_ADMIN_TESTING.md`, `TABLE_CONFIGURATION.md`)

When this file conflicts with `CURRENT_SOURCE_OF_TRUTH.md` or backend plugin docs, **the source-of-truth docs win**.

---

## 2. Current repo state

Latest known **pushed** state:

| Area | State |
|------|-------|
| Backend branch | `AI` |
| Backend HEAD | `1431a06` — Add staff guest profile lookup with safe strong-only best match |
| Root branch | `audit-current-state` |
| Root HEAD | `50df843` — Make Regulars cache-first with shared Guest history destination |
| Backend guest person-map Slice 2 lookup | `1431a06` (backend), `b1a09e7` (root pointer); **deployed** to WordPress |
| iOS guest person-map Slice 3A lookup foundation | `823f42c` |
| iOS guest person-map Slice 3B Guests tab lookup UI | `1dfa14a` |
| iOS guest person-map Slice 3R Regulars cache-first | `50df843` |
| Guest person-map Slice 1 (sync completeness + full cache lookup) | `d541488` |
| Host freshness / idle snapshot polish | `71601fc` |
| Host Intelligence card presentation stability | `39f7fcb` |
| Guest cache foundation | `0f06852` — SwiftData cache + background `updated_since` sync |
| Manual intake + walk-in | `0a89caa` |
| Confirmation safety | `cf6e641` — V1 confirmation flow hardening |
| iOS foreground/privacy refresh | `b910bd1` on root |
| Root submodule pointer | Backend `1431a06` |
| Zip files | **Do not track.** `Backend/*.zip` is gitignored. |

Before any implementation work, verify live git:

```bash
# Backend
cd Backend/tryzub-reservations-api
git status --short
git branch --show-current
git rev-parse --short HEAD
git log --oneline -5

# Root
cd ../..
git status --short
git branch --show-current
git rev-parse --short HEAD
git submodule status
```

**Production:** Guest self-service cancel + dead-state verified live. App login works. Guest profile aggregates exist server-side; iOS syncs list to `GuestProfileCacheRecord` after `0f06852`. Guests tab reads disk cache first after `67e02d2`; explicit all-record lookup + View history shell after `1dfa14a`. Regulars / Guest Memory cache-first after `50df843`. Guest person-map Slice 1 reliability shipped at `d541488`. Backend guest profile lookup route **deployed** to WordPress at `1431a06`; iOS calls it from **Guests tab explicit search only** (`1dfa14a`) — **device lookup smoke tests still open**. Tryzub V1 Host production polish shipped at `71601fc` + `39f7fcb` — final device verification still open.

---

## 3. V1 focus (this weekend)

**Stabilize device verification; guest memory, guest person-map Slices 1/2/3A/3B/3R, and Tryzub V1 Host production polish are shipped.**

**Guest Person Map target:** one shared **Guest history** destination by `guestKey` (`GuestProfileDetailView`). Guests tab wired (`1dfa14a`). Regulars / Guest Memory wired (`50df843`). Reservation Detail, Manual Intake — open (Slices 3D-a, 3M). Full booking/notes timeline UI is Slice 3D; current detail view is summary shell only.

### Done (backend + iOS product)

1. ~~Guest self-service cancel + cache~~ — verified in production.
2. ~~Production auth~~ — app login works.
3. ~~Pipeline diagnostics~~ — reviewed; old `unexplained_missing` test non-blocking.
4. ~~Guest profile local cache foundation~~ — `0f06852` (SwiftData + incremental list sync).
5. ~~Manual intake local guest cache + walk-in~~ — `0a89caa` (call-in, walk-in, known guest, phone UX, local lookup).
6. ~~Guests tab + detail local-first cache wiring~~ — `67e02d2` (Guests tab `@Query` cache; detail disk preview before network).
7. ~~Host freshness + idle snapshot flicker polish~~ — `71601fc` (`Last sync` copy, stale skip reasons, conditional snapshot minute rebuild, Live no-cursor bypass).
8. ~~Host Intelligence card presentation stability~~ — `39f7fcb` (no empty interstitial during presentation-key mismatch; keeps prior chips during async rebuild).
9. ~~Guest person-map Slice 1 — full-list sync completion + full cache lookup~~ — `d541488` (sync metadata, TTL bypass while incomplete, all cached profiles indexed; no iOS backend lookup yet).
10. ~~Backend guest person-map Slice 2 — staff profile lookup~~ — `1431a06` / `b1a09e7` (`GET /guest-profiles/lookup`; safe strong-only best match; **deployed** to WordPress).
11. ~~iOS guest person-map Slice 3A — lookup foundation~~ — `823f42c` (DTO/API/store; no UI).
12. ~~iOS guest person-map Slice 3B — Guests tab lookup UI~~ — `1dfa14a` (explicit all-record search; View history shell).
13. ~~iOS guest person-map Slice 3R — Regulars cache-first~~ — `50df843` (cache-first `@Query` list; tap → `GuestProfileDetailView`; no network page-25 primary UI).

### Still open (stabilization)

14. **iOS data/fetch on device** — foreground/privacy refresh (`b910bd1`).
15. **Confirmation mode on restaurant iPad** — Mail vs backend `/confirm`.
16. **Final V1 smoke test** — end-to-end staff ops on restaurant iPad (include guest full-list sync, Guests explicit lookup + View history, Regulars cache-first, Host header/flicker + intelligence-card checks).

**Not production-ready** until items 14–16 pass.

### Before broader product release (not V1 stabilization blocker)

17. **Slice 3D — full shared Guest history UI** — booking history + notes timeline in `GuestProfileDetailView`; Reservation Detail bridge (3D-a).
18. **Slice 3M — Manual Intake lookup + validation** — name search, all-record lookup, candidates; walk-in still requires name+phone today.
19. **Slice 3M-B — backend walk-in without phone/name** — backend + iOS contract change.
20. **Slice 3E — detail blob persistence** — disk-first full profile reopen.
21. **Indexed / predicate-based local guest search** — replace broad in-memory filtering; acceptable for **current Tryzub V1 data size** only.
22. **`ReservationDetail` guest fetch dedupe** — partially improved; full dedupe later.
23. **Guest profile re-sync on foreground/mutations** — optional follow-up; currently once per session at startup deferral.
24. **Backend lookup device smoke tests** — route deployed at `1431a06`; staff-auth lookup checklist **not yet passed**.
25. **P2 follow-ups** — phone normalization 10 vs 11 digit; dedicated validation error for blank lookup instead of `invalidURL`.

**Parked:** offline queue, SMS, broad Host redesign, full AI clustering / “knows each other” / local semantic tags, VIP editor without backend contract.

---

## 4. Hard product rules

| Rule | Detail |
|------|--------|
| Backend is source of truth | SwiftData (reservations + guest profiles) is operational cache only |
| Guest profiles server-side | Precomputed in `tryzub_guest_profiles`; iOS list sync uses `updated_since` |
| Manual intake lookup | **Local only** on phone keystroke for suggestions — **no** `/guest-profiles/lookup` per digit; **no backend lookup in Manual Intake yet** (Slice 3M) |
| Guest profile lookup (backend) | `GET /guest-profiles/lookup` (`1431a06`) — iOS calls from **Guests tab explicit search only** (`1dfa14a`) |
| Guests tab lookup | Local while typing; explicit **Search all guest records** for backend candidates; **View history** when `guestKey` exists |
| Guest history destination | `GuestProfileDetailView` by `guestKey` — summary shell only until Slice 3D; wired from Guests tab (`1dfa14a`) and Regulars (`50df843`); **not** wired from Reservation Detail yet |
| Walk-in create | `manual_walk_in` + `seated`; **still requires name + 10-digit phone** (iOS + backend) — true optional contact needs 3M-B |
| Manual create identity | **No `guest_key` on create** — send contact fields; backend resolves after insert |
| Name-only walk-ins | Valid searchable profiles; `match_confidence: possible` only — staff must confirm; never auto-canonical |
| Known guest walk-in | `manual_walk_in` + `seated` (walk-in analytics; identity from contact fields) |
| Known guest call-in | `known_guest_manual` + `confirmed` when staff taps Use / books from Guests |
| No offline queue in V1 | Mutations blocked when degraded |
| Host sync header | `Last sync HH:mm` (server sync), `Checked HH:mm` (cache-only); stale secondary reasons at `71601fc` |
| Guest token after cancel | Token stays valid; cancelled dead state |
| No zip in git | Build locally |
| Normal iOS refresh | Must **not** call `POST /managed-reservations/import` |

---

## 5. Code truths docs must match

### Guest memory + person-map (iOS — through `50df843`)

- `GuestProfileCacheRecord` in SwiftData; registered in `Tryzub_ReservationsApp` `ModelContainer`.
- `GuestProfileSyncService` paginates `GET /guest-profiles` after `canStartNoncriticalStartupLoads`; tracks full-list completion metadata in UserDefaults (`d541488`).
- While `fullListSyncCompleted == false`: forces full paginated sync (`updatedSince == nil`) and **bypasses 15-minute TTL**.
- Once complete: incremental `updated_since` cursor + normal 15-minute TTL.
- Reconciles local `cachedProfileCount` against `backendProfileTotal` before marking complete.
- **List sync only** — no bulk detail/history prefetch, no `/guest-profiles/rebuild`, no `/guest-intelligence` on typing.
- `GuestProfileStore.lookupProfiles` (`823f42c`) — explicit lookup API; deduped tasks; MainActor SwiftData upsert of compact summaries.
- `GuestLookupStore` merges **all** cached profiles + `ReservationRecord` history for local search (`d541488`).
- `GuestLookupView` (`1dfa14a`): local search while typing; explicit **Search all guest records**; **View history** + **Book reservation** when `guestKey` exists.
- `GuestProfileDetailView` (`1dfa14a`): shared **Guest history** shell by `guestKey` — summary/metrics only until Slice 3D.
- `RegularGuestsView` (`50df843`): cache-first `@Query` on `GuestProfileCacheRecord`; local search/filter/sort; tap → `GuestProfileDetailView(guestKey:)`.
- `ReservationDetailView`: disk cache preview; opens reservation-scoped `GuestInsightsView` — not shared `GuestProfileDetailView` yet.
- Manual intake: phone-only local suggestion; **no backend lookup**; walk-in still requires name + phone.
- Phone: `GuestLookupPhoneNormalizer.digits`; intake phone `.textContentType(.none)`.
- In-memory filter over full cache rows: acceptable for **current Tryzub V1 data size**; indexed search required before broader product release.

### Host production polish (iOS — `71601fc` + `39f7fcb`)

**`71601fc` — freshness header + reduced idle snapshot flicker**

- `HomeServiceStatusPresenter`: `Last sync` primary for server sync; stale secondary with staff-facing skip labels.
- `VisibleAutoRefreshSkipReason`: Paused / Paused while editing / Waiting — busy / Retry soon; fallback `May be out of date · tap refresh`.
- `preferVisibleLiveRefresh`: Live + today bypasses only `full_fresh_no_cursor`; other skip guards unchanged.
- Snapshot minute rebuild conditional: stable for non-today and quiet today; still minute-refreshes for seated / due / overdue / within ~90 min.
- Stale threshold: 120s. Reduced idle snapshot flicker — not all flicker eliminated.

**`39f7fcb` — intelligence card presentation stability (`HostBoardView.swift` only)**

- Removed render-time key gate that showed `HostIntelligenceCardPresentation.empty` during async presentation rebuild.
- Keeps prior stable card/chips visible until `rebuildHostIntelligenceCardPresentation` updates `@State`.
- Does not change Host Intelligence cadence, local model pipeline, sync, backend, guest cache, or `FreshnessCoordinator`.

### Sync / freshness (iOS)

- Cache-first startup; active-window full vs delta upsert.
- `server_time` cursors persist in UserDefaults — not an offline mutation queue.
- Bounded-full after 5 deltas or 2 hours.

### Confirmation (staff)

- Both Mail and `POST /confirm` paths exist; device setting matters (`EmailAutomationSettings.backendConfirmationEnabled`, default `true`).
- Hardening at `cf6e641` — pre-reconcile before backend confirm.

### Guest self-service (backend `d46713a`+)

- Public routes with no-store headers; cancel returns refreshed guest-safe `data`.

---

## 6. Production verification

| Check | Status |
|-------|--------|
| Guest cancel + dead-state | Done |
| App login | Done |
| Pipeline unexplained item | Known old test — non-blocking |
| iOS foreground/privacy refresh on device | **Open** |
| Confirmation mode on restaurant iPad | **Open** |
| Final V1 smoke test | **Open** |
| Guest profile sync on test iPad | **Open** (post-`0f06852`) |
| Manual walk-in / known-guest intake on test iPad | **Open** (post-`0a89caa`) |
| Guests tab + detail cache wiring on test iPad | **Open** (post-`67e02d2`) |
| Host freshness / idle snapshot polish on test iPad | **Open** (post-`71601fc`) |
| Host Intelligence card presentation stability on test iPad | **Open** (post-`39f7fcb`) |
| Guest profile full-list sync + full-cache lookup on test iPad | **Open** (post-`d541488`) |
| Guests tab explicit all-record lookup + View history on test iPad | **Open** (post-`1dfa14a`) |
| Regulars cache-first + View history on test iPad | **Open** (post-`50df843`) |
| Backend guest profile lookup deployed on WordPress | **Done** — `1431a06`; **device smoke tests still open** |

---

## 7. Deploy workflow (zip local-only)

```bash
cd Backend
zip -r tryzub-reservations-api.zip tryzub-reservations-api \
  -x "tryzub-reservations-api/.git/*" "tryzub-reservations-api/.git/**"
```

---

## 8. Agent workflow

| Role | Tool | Does |
|------|------|------|
| Audit / docs / prompts | **Composer 2.5** | Read-only audits, doc reconciliation, handoff packets |
| Code | **GPT-5.5 Agent** | Implements from exact handoff; allowed files only |
| Product / deploy | **Bohdan** | Priorities, credentials, WordPress upload, device testing |

---

## 9. What to tell Bohdan when he asks “what’s next?”

1. Device-test iOS refresh (`b910bd1`).
2. Confirm confirmation mode on restaurant iPad.
3. Final V1 smoke test — include guest full-list sync, Guests explicit all-record lookup + View history (no per-digit backend), walk-in/known-guest, Host `Last sync`, stale reasons, reduced idle flicker, intelligence-card chips stable during refresh, seated/due timing, manual refresh.
4. Before broader product release → **3D** full Guest history UI + Reservation Detail bridge, **3M/3M-B** Manual Intake lookup + walk-in validation, **3E** detail blob persistence, **indexed local guest search**; run backend lookup device smoke tests (`1431a06`).
5. Later → guest profile re-sync on foreground/mutations; `ReservationDetail` guest fetch dedupe.
6. Do **not** start offline queue, AI clustering, or VIP editor without backend contract.

---

## 10. Known risks

- Deployed plugin SHA not tracked in git; submodule pointer is repo truth.
- Stale staff PATCH can revert guest `cancelled`.
- Broad in-memory guest search will not scale beyond current Tryzub V1 data size — plan indexed search before broader release.
- Backend lookup route **deployed** to WordPress at `1431a06`; iOS calls it from Guests tab explicit search only (`1dfa14a`); device smoke tests still open.
- `GuestProfileDetailView` is summary shell only — full booking/notes timeline is Slice 3D; not disk-first full detail (Slice 3E).
- Host `clockTick` still runs every 60s — idle flicker reduced (`71601fc`), not eliminated. Intelligence-card empty interstitial removed (`39f7fcb`); final device verification still open.
- Final V1 smoke test not yet run — do not claim App Store / production-ready.

---

*Last aligned: 2026-06-25 (iOS Slice 3R `50df843` + backend lookup `1431a06` deployed). Update when repo HEAD or verification status changes materially.*
