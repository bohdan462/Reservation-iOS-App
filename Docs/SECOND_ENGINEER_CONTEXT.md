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
| Backend HEAD | `a2422d3` — Add private reservation attachment backend |
| Root branch | `audit-current-state` |
| Root HEAD | `fa15d22` — backend attachment pointer |
| Remote | `origin/audit-current-state` @ `fa15d22` |
| Backend guest person-map Slice 2 lookup | `1431a06` (backend), `b1a09e7` (root pointer); **deployed** to WordPress |
| Backend guest person-map Slice 3M-B unknown walk-in | `63d0cfc` (backend), `c7f5a69` (root pointer); **deployed** to WordPress |
| iOS guest person-map Slice 3A lookup foundation | `823f42c` |
| iOS guest person-map Slice 3B Guests tab lookup UI | `1dfa14a` |
| iOS guest person-map Slice 3R Regulars cache-first | `50df843` |
| iOS guest person-map Slice 3M Manual Intake lookup + walk-in validation | `e775f52` |
| Manual Intake input polish (post-3M) | `ad5d274` |
| Device smoke Phase 1 — layout / hit-testing | `804c130` |
| Device smoke Phase 2 — walk-in workflow | `8eab6c4` |
| Device smoke Phase 3 — row indicators | `5762ecb` |
| Device smoke Phase 4 — email settings cleanup | `3da3a68` |
| Guest person-map Slice 1 (sync completeness + full cache lookup) | `d541488` |
| Host freshness / idle snapshot polish | `71601fc` |
| Host Intelligence card presentation stability | `39f7fcb` |
| Guest cache foundation | `0f06852` — SwiftData cache + background `updated_since` sync |
| Manual intake + walk-in | `0a89caa` |
| Confirmation safety | `cf6e641` — V1 confirmation flow hardening |
| iOS foreground/privacy refresh | `b910bd1` on root |
| Root submodule pointer | Backend `a2422d3` |
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

**Production:** Guest self-service cancel + dead-state verified live. App login works. Guest profile aggregates exist server-side; iOS syncs list to `GuestProfileCacheRecord` after `0f06852`. Guests tab reads disk cache first after `67e02d2`; explicit all-record lookup + View history after `1dfa14a`. Regulars / Guest Memory cache-first after `50df843`. Manual Intake walk-in validation + guest lookup after `e775f52`; input polish after `ad5d274`. Backend unknown walk-in contract **deployed** at `63d0cfc` / `c7f5a69`. Backend guest profile lookup route **deployed** at `1431a06`. Device smoke code Phases 1–4 **landed** (`804c130` → `3da3a68`) — **physical device verification still open**. Tryzub V1 Host production polish shipped at `71601fc` + `39f7fcb`.

---

## 3. V1 focus (this weekend)

**Stabilize physical device verification; guest memory, guest person-map Slices 1/2/3A/3B/3R/3M-B/3M, Manual Intake input polish, device smoke code Phases 1–4, and Tryzub V1 Host production polish are shipped in code.**

**Guest Person Map target:** one shared **Guest history** destination by `guestKey` (`GuestProfileDetailView`). Guests tab wired (`1dfa14a`). Regulars / Guest Memory wired (`50df843`). Manual Intake candidates wired (`e775f52`). Reservation Detail — open (Slice 3D-a). Full booking/notes timeline UI is Slice 3D; current detail view is summary shell only.

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
14. ~~Backend guest person-map Slice 3M-B — unknown walk-in~~ — `63d0cfc` / `c7f5a69` (blank walk-in identity; placeholder masking; no fake profiles; **deployed**).
15. ~~iOS guest person-map Slice 3M — Manual Intake lookup + walk-in validation~~ — `e775f52` (local search; explicit all-record lookup; Use guest + View history; walk-in blank identity).
16. ~~Manual Intake input polish~~ — `ad5d274` (review sheet before create; no pre-create messages; keyboard Next/Done; debounced lookup; 3M preserved).
17. ~~Device smoke code Phases 1–4~~ — `804c130` (layout/hit-testing), `8eab6c4` (walk-in workflow), `5762ecb` (row indicators), `3da3a68` (email settings cleanup).

### Still open (stabilization)

18. **iOS data/fetch on device** — foreground/privacy refresh (`b910bd1`).
19. **Confirmation mode on physical device** — Mail vs backend `/confirm`.
20. **Release smoke test** — end-to-end staff ops on physical device (include guest full-list sync, Guests + Manual Intake lookup + input polish, unknown walk-in save with backend `63d0cfc` deployed, Host header/flicker + intelligence-card checks, **device smoke verification checklist** in [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md)).
21. **Device smoke P1/P2 verification** — code landed; physical hardware checks still open ([DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) §10).

**Not production-ready** until items 18–21 pass.

### Reservation attachments (backend deployed — iOS Slice C next)

31. **Reservation attachments** — Backend private sync **deployed** (`a2422d3`) and **production-smoked** 2026-06-26. iOS still local-only on Reservation Detail. See [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md). **Next code: iOS Slice C** (DTO/API/cache only).

### Before broader product release (not V1 stabilization blocker)

32. **Slice 3D — full shared Guest history UI** — booking history timeline, guest/staff notes timeline, source mix, usual party/day/time in `GuestProfileDetailView`; Reservation Detail bridge (3D-a); booking-history row routing. **Parked until device smoke verification accepted or Bohdan resumes.**
33. **Slice 3E — detail JSON persistence** — disk-first full profile reopen. **Parked until device smoke verification accepted or Bohdan resumes.**
34. **Indexed / predicate-based local guest search** — replace broad in-memory filtering; acceptable for **current Tryzub V1 data size** only.
35. **`ReservationDetail` guest fetch dedupe** — partially improved; full dedupe later.
36. **Guest profile re-sync on foreground/mutations** — optional follow-up; currently once per session at startup deferral.
37. **Backend lookup device smoke tests** — route deployed at `1431a06`; checklist **not yet passed**.
38. **Backend unknown walk-in device smoke tests** — `63d0cfc` **deployed**; checklist **not yet passed**.
39. **P3 cleanup** — remove unused `GuestLookupStore.schedulePhoneLookup`; backend README wording cleanup if README still says pilot/MVP.
40. **P2 follow-ups** — phone normalization 10 vs 11 digit; dedicated validation error for blank lookup instead of `invalidURL`.

**Parked:** offline queue, SMS, broad Host redesign, full AI clustering / “knows each other” / local semantic tags, VIP editor without backend contract.

---

## 4. Hard product rules

| Rule | Detail |
|------|--------|
| Backend is source of truth | SwiftData (reservations + guest profiles) is operational cache only |
| Guest profiles server-side | Precomputed in `tryzub_guest_profiles`; iOS list sync uses `updated_since` |
| Manual intake lookup | **Local** name/phone/email while typing — **no** `/guest-profiles/lookup` per digit; explicit **Search all guest records** in Manual Intake (`e775f52`) |
| Guest profile lookup (backend) | `GET /guest-profiles/lookup` (`1431a06` deployed) — iOS calls from **Guests tab** and **Manual Intake** explicit search (`1dfa14a`, `e775f52`) |
| Guests tab lookup | Local while typing; explicit **Search all guest records** for backend candidates; **View history** when `guestKey` exists |
| Guest history destination | `GuestProfileDetailView` by `guestKey` — summary shell only until Slice 3D; wired from Guests tab (`1dfa14a`), Regulars (`50df843`), and Manual Intake (`e775f52`); **not** wired from Reservation Detail yet |
| Walk-in create | `manual_walk_in` + `seated`; name/phone/email **optional** on iOS (`e775f52`) — sends blank fields; backend `63d0cfc` owns display; backend **deployed** — device smoke still open |
| Manual Intake create UX | Review sheet before backend create (`ad5d274`); no pre-create confirmation/message buttons; post-create confirm/email on Reservation Detail only |
| Manual create identity | **No `guest_key` on create** — send contact fields; backend resolves after insert |
| Name-only walk-ins | Valid searchable profiles; `match_confidence: possible` only — staff must confirm; never auto-canonical |
| Known guest walk-in | `manual_walk_in` + `seated` (walk-in analytics; identity from contact fields) |
| Known guest call-in | `known_guest_manual` + `confirmed` when staff taps Use / books from Guests |
| No offline queue in V1 | Mutations blocked when degraded |
| Host sync header | `Last sync HH:mm` (server sync), `Checked HH:mm` (cache-only); stale secondary reasons at `71601fc` |
| Guest token after cancel | Token stays valid; cancelled dead state |
| No zip in git | Build locally |
| Normal iOS refresh | Must **not** call `POST /managed-reservations/import` |
| Reservation attachments | **Backend deployed** (`a2422d3`, production-smoked); **iOS local-only today** — Slice C next ([RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md)); **no public image URLs**; guest self-service must never expose attachments |

---

## 5. Code truths docs must match

### Guest memory + person-map (iOS — through `ad5d274`)

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
- `ManualReservationFormView` (`e775f52`, `ad5d274`): walk-in optional identity; call-in name+phone required; local search while typing; explicit all-record lookup; Use guest + View history → `GuestProfileDetailView`; review sheet before create; no pre-create messages; keyboard Next/Done; debounced lookup.
- `ReservationDetailView`: disk cache preview; opens reservation-scoped `GuestInsightsView` — not shared `GuestProfileDetailView` yet.
- Phone: `GuestLookupPhoneNormalizer.digits`; intake phone `.textContentType(.none)`.
- In-memory filter over full cache rows: acceptable for **current Tryzub V1 data size**; indexed search required before broader product release.
- **P3:** `GuestLookupStore.schedulePhoneLookup` unused after 3M.

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
| Confirmation mode on physical device | **Open** |
| Device smoke P1/P2 code | **Landed** — Phases 1–4 (`804c130` → `3da3a68`); **physical verification open** — [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) |
| Final V1 smoke test | **Open** |
| Guest profile sync on physical device | **Open** (post-`0f06852`) |
| Manual walk-in / known-guest intake on physical device | **Open** (post-`0a89caa`) |
| Guests tab + detail cache wiring on physical device | **Open** (post-`67e02d2`) |
| Host freshness / idle snapshot polish on physical device | **Open** (post-`71601fc`) |
| Host Intelligence card presentation stability on physical device | **Open** (post-`39f7fcb`) |
| Guest profile full-list sync + full-cache lookup on physical device | **Open** (post-`d541488`) |
| Guests tab explicit all-record lookup + View history on physical device | **Open** (post-`1dfa14a`) |
| Regulars cache-first + View history on physical device | **Open** (post-`50df843`) |
| Manual Intake walk-in + guest lookup + input polish on physical device | **Open** (post-`e775f52` / `ad5d274`; backend `63d0cfc` **deployed**) |
| Backend guest profile lookup deployed on WordPress | **Done** — `1431a06`; **device smoke tests still open** |
| Backend unknown walk-in (`63d0cfc`) on WordPress | **Deployed** — **device smoke tests still open** |

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
2. **Run device smoke verification** — [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) §10 (code Phases 1–4 landed).
3. Confirm confirmation mode on physical device.
4. Release smoke test — include guest full-list sync, Guests + Manual Intake explicit lookup + View history (no per-digit backend), unknown walk-in save (`63d0cfc` deployed), Manual Intake review sheet + no pre-create messages (`ad5d274`), Host `Last sync`, stale reasons, reduced idle flicker, intelligence-card chips stable during refresh, seated/due timing, manual refresh, device smoke checklist items.
5. **Reservation attachments** — backend **deployed + production-smoked** (`a2422d3`); **next: iOS Slice C** (DTO/API/cache). See [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md).
6. Before broader product release → **3D** full Guest history UI + Reservation Detail bridge, **3E** detail JSON persistence / disk-first full profile reopen, **indexed local guest search**; run backend lookup + unknown walk-in device smoke tests.
7. Later → guest profile re-sync on foreground/mutations; `ReservationDetail` guest fetch dedupe; remove `schedulePhoneLookup` (P3); backend README pilot/MVP wording cleanup if needed.
8. Do **not** start offline queue, SMS, AI clustering, or VIP editor without backend contract.

---

## 10. Known risks

- Deployed plugin SHA not tracked in git; submodule pointer is repo truth.
- Stale staff PATCH can revert guest `cancelled`.
- Broad in-memory guest search will not scale beyond current Tryzub V1 data size — plan indexed search before broader release.
- Backend lookup route **deployed** to WordPress at `1431a06`; iOS calls from Guests tab + Manual Intake explicit search (`1dfa14a`, `e775f52`); device smoke tests still open.
- Backend unknown walk-in `63d0cfc` **deployed** to WordPress — device smoke tests still open.
- `GuestProfileDetailView` is summary shell only — full booking/notes timeline is Slice 3D; detail JSON persistence / disk-first reopen is Slice 3E.
- Host `clockTick` still runs every 60s — idle flicker reduced (`71601fc`), not eliminated. Intelligence-card empty interstitial removed (`39f7fcb`); final device verification still open.
- Final V1 smoke test not yet run — do not claim App Store / production-ready.

---

*Last aligned: 2026-06-26 (backend attachment Slice B production-smoked; iOS Slice C next; device smoke verification still open). Update when repo HEAD or verification status changes materially.*
