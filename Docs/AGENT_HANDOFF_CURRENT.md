# Agent Handoff — Current Slice

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)

---

## Email delivery truth (iOS — landed, device verify pending)

**Slices:** EMAIL-DELIVERY-iOS-1 (model/decode/persistence) + EMAIL-DELIVERY-iOS-2 (UI/correction) — code on working tree; **not committed** at last audit.

**Docs:** [EMAIL_DELIVERY_TRUTH.md](./EMAIL_DELIVERY_TRUTH.md) (iOS), [Backend README](../Backend/tryzub-reservations-api/README.md) (webhook/DB 1.13–1.15).

**Rules:** `_sentAt` ≠ delivered; auto-confirm badge = `confirmationSource`; Host board email-issue only; correction routes wired on detail.

**Next:** device checklist §9 in EMAIL_DELIVERY_TRUTH; backend deploy + webhook before claiming delivered in production.

---

## Title

Service Intelligence snapshot lifecycle (4C done) + human host/admin briefing direction (4D/4E next)

---

## Git state (2026-06-30)

| Location | State |
|----------|--------|
| **Root branch** | `audit-current-state` |
| **Root HEAD** | `50b207a` — Guard service intelligence snapshot across Host hide and source changes |
| **Root vs remote** | Code at `50b207a`; docs synced on `audit-current-state` after lifecycle pass |
| **Build** | **13** — tracked in `2227d8d` |
| **Backend submodule pointer** | `a2422d3` — Add private reservation attachment backend |
| **Backend branch** | `AI` |
| **Backend HEAD** | `a2422d3` |
| **Backend vs remote** | Pushed to `origin/AI` at `a2422d3` |

**Recent root commits (newest first):**

- `50b207a` — Guard service intelligence snapshot across Host hide and source changes (4C-2 + 4C-3)
- `2227d8d` — Intelligance rebuild (4C-1 More → snapshot reader; build 13)
- `bec4a6d` — Restore Host More reminder stats sheet
- `a7cde0c` — Fix Host reminder relocation build
- `e7a2088` — Stabilize service intelligence metadata and enrichment
- `05f70b0` — Add attachment facts to service intelligence snapshot
- `325c7f3` — LOCAL-FIRST-OPS-4B-2 — Wire future planning Host card from unified snapshot
- `4f088f6` — LOCAL-FIRST-OPS-4B-1 — Harden Service Intelligence snapshot before UI consumption
- `f0554a3` — LOCAL-FIRST-OPS-4A: Build unified deterministic per-date Service Intelligence snapshot
- `f2e9be0` — Track build 12 project settings
- `cd842c3` — Document reservation attachment management polish
- `eed6530` — Track build 11 project settings
- `9d2784d` — Polish reservation attachment management UI
- `d947721` — Wire reservation detail shared attachments
- `641e218` — Document reservation attachment iOS sync foundation
- `17a0bee` — Add reservation attachment iOS sync foundation
- `b986732` — Record reservation attachment backend smoke status
- `fa15d22` — Point backend to private reservation attachment backend
- `864db8e` — Add reservation attachments backend-sync handoff docs
- `401390e` — Update docs after device smoke Phases 1–4
- `3da3a68` — Fix Phase 4 device smoke email settings cleanup
- `5762ecb` — Fix Phase 3 device smoke row indicators
- `8eab6c4` — Fix Phase 2 device smoke walk-in workflow
- `804c130` — Fix Phase 1 device smoke layout issues
- `eca9db6` — Add device smoke findings handoff and align current-state docs
- `fceebb3` — docs after Manual Intake input polish + backend deploy
- `75dce15` — docs after Manual Intake input polish + backend deploy
- `ad5d274` — Manual Intake input polish + removed pre-create confirmation/message actions
- `2b59c73` — docs after Manual Intake guest lookup and walk-in support
- `e775f52` — Manual Intake walk-in validation + guest lookup (Slice 3M)
- `c7f5a69` — backend submodule pointer → unknown walk-in support (`63d0cfc`)
- `86c3236` — docs after Regulars cache-first Guest Memory
- `50df843` — Regulars cache-first + shared Guest history destination (Slice 3R)
- `5f7cb45` — docs after Guests tab guest-record search
- `1dfa14a` — Guests tab guest-record search + shared Guest history shell (Slice 3B)
- `823f42c` — iOS guest profile lookup API/client/store foundation (Slice 3A)
- `e1e911a` — docs after backend guest profile lookup
- `b1a09e7` — backend submodule pointer → staff guest profile lookup (`1431a06`)
- `5e90170` — docs after guest person-map Slice 1
- `d541488` — guest profile full-list sync completion + all cached profiles indexed
- `dc3d8c5` — docs after guest cache wiring and Host polish
- `39f7fcb` — Host Intelligence card stable during presentation rebuild
- `71601fc` — Host sync status copy (`Last sync`), stale skip reasons, conditional snapshot minute rebuild
- `67e02d2` — Guests tab + Reservation Detail read local guest cache first
- `0a89caa` — manual intake: local guest cache merge, call-in/walk-in, known-guest prefill, phone UX
- `0f06852` — persisted guest profile cache + background incremental sync (`updated_since`)

**Backend commits on pointer (newest first):**

- `a2422d3` — private reservation attachments (plugin 0.5.5, DB 1.12.0): staff-auth CRUD + private storage + content route
- `63d0cfc` — unknown `manual_walk_in` without guest identity; placeholder masking; call-in still requires name + phone
- `1431a06` — `GET /guest-profiles/lookup` staff targeted search with safe strong-only best match
- `078a44a` — document guest self-service cache contract (README)
- `d46713a` — guest self-service no-store headers, JS cache bust, POST cancel returns refreshed `data`
- `854b82d` / `6a30203` — guest-facing confirmation/cancellation/page copy
- `239b297` — guest cancellation email, cancelled dead-state UI, pipeline `developer_summary` flattening

**Deploy zip:** not tracked in git (`Backend/*.zip` ignored). Build locally from backend `HEAD` when deploying.

---

## Current slice goal

**Snapshot lifecycle implementation (4C-1/2/3) is code-complete at `50b207a`.** **Current focus:**

1. **Finish 4C runtime smoke** — stale reservation-source fallback while Host hidden still open ([OPEN_WORK.md](./OPEN_WORK.md)).
2. **Human service briefing direction (4D/4E)** — not generic AI copy or “staff needs review” wording. The app substitutes parts of the admin/host job: brief the team **before, during, and after service** in the voice of a strong human host/admin/manager. See [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md).

**Next phase is not generic AI copy.** It is **human service briefing from the parent intelligence layer**:

| Layer | Role |
|-------|------|
| **Canonical snapshot** | What is true — `HostServiceIntelligenceSnapshot` |
| **Parent briefing packet** | All facts the system can safely talk about (reservations, floor, seated timing, guest memory, notes, attachments, reminders, business analytics, walk-ins, activity, snapshot facts) |
| **Narrative layer** | How a good host/admin says it — template first, optional local model |
| **LLM** | Wording only, never truth |

**Host Board** — live work surface during service; compact intelligence where staff actually work; not a static dashboard. **More → Service Intelligence** — deeper briefing view for the day, guests, timing, business context, unresolved items; same truth as Host Board.

**Stabilization** (physical device verification, attachments live verification) remains open separately. **Slice 3D/3E parked** until smoke verification is accepted or Bohdan resumes.

**Bookings CPU (P0-CPU-1A):** implemented; device verification open. **P0-CPU-1B:** Review intelligence card removed (`65a7f1f`) — card file may remain orphaned. **P0-CPU-1C:** HostBoardSnapshot body fallback — separate follow-up ([OPEN_WORK.md](./OPEN_WORK.md)).

---

## Current Intelligence state

### 4C snapshot lifecycle (done in code — `2227d8d`, `50b207a`)

| Slice | Commit | Behavior |
|-------|--------|----------|
| **4C-1** | `2227d8d` | More → Service Intelligence reads `HostIntelligenceController.serviceIntelligenceSnapshot` when ready; top card + Service facts from `rankedFacts`; skips duplicate note/attachment analyzers when snapshot active |
| **4C-2** | `50b207a` | Host hide calls `resetVolatilePresentation(reason: "view_hidden")` — preserves canonical snapshot, evaluated-date state, and `localEvaluationComplete` |
| **4C-3** | `50b207a` | `serviceIntelligenceSourceFingerprint` guards stale preserved snapshot; More falls back to legacy with `reason=stale_source_fingerprint` when reservation-source inputs changed |

**Canonical read model:** `HostServiceIntelligenceSnapshot` — built only on Host path via `HostServiceIntelligenceSnapshotBuilder` → `HostIntelligenceController.updateServiceIntelligenceSnapshot`. **More never builds it.**

**Partial runtime smoke (device, 2026-06-30):**

| Test | Status |
|------|--------|
| Host snapshot build | **Passed** |
| More `use_snapshot reason=ready` | **Passed** |
| Date transition clear | **Passed** |
| Source fingerprint current | **Passed** |
| Stale reservation-change fallback | **Open** |

- `[SERVICE_INTEL_SNAPSHOT_TRACE] decision=build` — passed (today + future date after transition)
- `[SERVICE_INTEL_UI_TRACE] surface=more_service_intelligence decision=use_snapshot reason=ready` — passed after Host hide
- `[SERVICE_INTEL_LIFECYCLE_TRACE] event=clear_snapshot_on_date_transition` — passed
- `[SERVICE_INTEL_LIFECYCLE_TRACE] event=snapshot_source_current` — passed
- **Open:** stale reservation-source fallback after backend/reservation change while Host hidden
- Host local model attempted later; validator blocked wrong reservation count (`HOST_AI_VALIDATOR_TRACE`) — expected safety behavior

**Tone direction (product):** Good — “6:30 · Julie, 5 guests. Birthday note. Seat with care.” / “Tristan has been seated at A1 for 1h 24m.” / “Nothing urgent right now. Keep an eye on A1.” Bad — “Staff needs review.” / “Check guest note.” / “Operational action required.” / “Guest signal detected.” Current UI is technically correct but too quiet/generic; 4D/4E targets human host/admin language on both surfaces.

**Observed product behavior:** Host compact card (“Next: Julie at 18:30 · 5 guests”, occasion chip) and More → Service Intelligence (“Julie Bachman mentioned a birthday”, Service facts section) reuse the same canonical snapshot — one source of truth across surfaces.

**Known staleness gaps (follow-up, not blockers for 4D):** attachment/OCR, backend guest-intel summaries, floor/table layout not in 4C-3 reservation-source fingerprint — see [OPEN_WORK.md](./OPEN_WORK.md).

**P0 smoothness (Detail + local model):** **P0-DETAIL-1** (`84f210c`) and **P0-LOCALMODEL-1** (`4e4c274`) **done in code; smoke-supported.** Detail guest truth moved off body/computed hot paths (`DETAIL_TRUTH_CACHE_TRACE`). Detail no longer cold-loads 3B model on open (`LOCAL_MODEL_GATE_TRACE`). Deterministic note signals still immediate.

**P0 Host smoothness (P0-HOST-2B, P0-DETAIL-2 Slice A, P0-NAV-1):** All implemented. Host inline card no longer scans full history pool during date nav. Detail secondary work deferred after first paint. Host/Bookings reactive work gated during navigation transitions.

**LIVE-SYNC-1A/1B:** Foreground active-window delta polling restored (60s TTL, server cursor, retry). Bookings auto-refresh loop demoted — root foreground loop owns all active-window reservation polling.

**LOCAL-FIRST-OPS-2A/2B:** Host no-op CPU work gated on reservation fingerprint. Host date-switch stale publish guards implemented — `beginSelectedDateTransition`, `isEvaluatedForSelectedDate`, full synchronous state reset on `selectedDateKey` change; stale data cannot render or be published for the old date.

**LOCAL-FIRST-OPS-3A (`2a5b81f`):** Bookings All tab scoped to active-window @Query for non-historical date scopes. All tab no longer iterates 4,162 SwiftData records for today/upcoming views. `filterTraceKey` now uses count+first-10 prefix (O(1) instead of O(n) string in SwiftUI key path). `BOOKINGS_FILTER_TRACE` capped to count+firstIDs+omitted. `traceBookingsDateBoundary` per-record loop capped at 50 rows. `BOOKINGS_SCOPE_TRACE` added. **Do not claim** physical smoke passed — device verification open.

**LOCAL-FIRST-OPS-3B:** Removed `NewBookingsIntelligenceCard`, all Needs Review insight tasks, `needsReviewInsightRebuildKey`, `guestInsightHistoryPool` fingerprint from SwiftUI key path, and all 8 related functions from `ReservationsListView`. Eliminated the hidden O(N) body-time compute that fingerpinted the full `guestInsightHistoryPool` on every SwiftUI render.

**LOCAL-FIRST-OPS-4C (`2227d8d`, `50b207a`):** Unified More → Service Intelligence with canonical snapshot; snapshot survives Host hide; reservation-source fingerprint stale guard. See **Current Intelligence state** above.

**LOCAL-FIRST-OPS-4A (`f0554a3`):** Created unified deterministic per-date staff intelligence snapshot.
- **New:** `ServiceIntelligence/Models/HostServiceIntelligenceSnapshot.swift` — `ServiceIntelligenceFactCategory` (14 categories with ranked `basePriority`), `ServiceIntelligenceFact` (id, reservationID, guestName, category, priority, headline, detail), `HostServiceIntelligenceSnapshot` (dateKey, serviceMode, headline, subline, rankedFacts, inputFingerprint).
- **New:** `ServiceIntelligence/Engine/HostServiceIntelligenceSnapshotBuilder.swift` — pure, deterministic builder. Sources: (A) `HostGuestSignal` from existing snapshot (no re-scan), (B) `NoteSignalAnalyzer` per day reservation for deposit/preorder/banquet signals absent from Host pipeline, (C) `HostBriefingFact.largeParty`, (D) busiest `HostSlotPressure` → mainWave, (E) noTable count for `futurePlanning` mode. Dedup by `(reservationID, category)`. Cap 12 facts. Headline rules for today/future-large-party/future-counts/empty-day. FNV-1a `inputFingerprint` via `HostAttentionStableDigest`.
- **Modified:** `HostIntelligenceController` — `@Published serviceIntelligenceSnapshot`, private fingerprint cache, `updateServiceIntelligenceSnapshot(_:)` with skip gate, reset on `beginSelectedDateTransition`.
- **Modified:** `HostBoardView.rebuildServiceBriefing()` — calls `updateServiceIntelligenceSnapshot` after `serviceBriefingState` is built (serviceMode accurate). No UI card changes in this slice — snapshot is proof-wired only.
- Build: **SUCCEEDED** (exit 0, zero warnings, zero lints). Builder never called from SwiftUI body.
- Device log: `[SERVICE_INTEL_SNAPSHOT_TRACE] decision=build` emits once per meaningful fingerprint change; `decision=skip reason=fingerprint_unchanged` on re-selection with unchanged data. No LLM traces added. No full-history scan. No Bookings Review query reintroduced.

**Reservation attachments (boss request):** Backend **deployed and production-smoked** (`a2422d3`, plugin **0.5.5**, DB **1.12.0**). iOS **Slice C** at `17a0bee` (DTO/API/cache). iOS **Slice D** at `d947721` (Detail shared list/upload/download/delete). iOS **Slice E** at `9d2784d` (management UI polish). `AttachmentFeatureFlag.remoteUploadEnabled` **true**; API calls detail-scoped only. Build **13** tracked (`2227d8d`). Live/cross-device verification still open. **Live/cross-device verification not run** — do not claim passed. Old pre-sync local-only attachments may remain device-local; staff should reattach important old images for shared visibility. Full plan: [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md). **Next:** live verification checklist — do not change backend unless a real API bug is found. Physical device smoke remains a separate open track.

**Guest Person Map target:** one shared **Guest history** destination by `guestKey` (`GuestProfileDetailView`). Wiring status:

| Entry point | Shared Guest history | Status |
|-------------|---------------------|--------|
| Guests tab | `GuestProfileDetailView(guestKey:)` | **Done** — `1dfa14a` |
| Regulars / Guest Memory | `GuestProfileDetailView(guestKey:)` | **Done** — `50df843` |
| Manual Intake candidates | `GuestProfileDetailView(guestKey:)` | **Done** — `e775f52` |
| Reservation Detail | `GuestProfileDetailView(guestKey:)` | **Open** — Slice 3D-a |
| Booking-history rows | local `ReservationDetailView` if cached; else read-only | **Open** — Slice 3D |

Backend `GET /guest-profiles/{guest_key}` detail DTO is the primary source for full history (`bookingHistory`, `notesHistory`, counts, labels, summary, preferences, source mix, next reservation). SwiftData is operational cache only — avoid recomputing heavy reservation-scoped guest analysis when a backend/cached guest profile exists. `GuestProfileDetailView` currently shows a **summary shell only** — full booking/notes timeline is Slice 3D.

### Completed (iOS guest memory — `0f06852` + `0a89caa` + `67e02d2`)

1. Backend guest profiles are **persisted server-side** in `{prefix}tryzub_guest_profiles`; iOS fetches list incrementally via `GET /guest-profiles?updated_since=…`.
2. **`GuestProfileCacheRecord`** in SwiftData — local disk cache of backend guest aggregates.
3. **Background list sync** after startup/noncritical deferral (`GuestProfileSyncService` + `AppReservationSession`).
4. **Manual intake** merges persisted guest cache with local `ReservationRecord` history in `GuestLookupStore` — **no network on phone keystroke**.
5. **Manual intake modes:**
   - Call-in → `manual_call_in` + `confirmed` (name + plausible phone required)
   - Walk-in → `manual_walk_in` + `seated` (optional table; name/phone/email optional — Slice 3M + backend 3M-B)
   - Known guest call-in → `known_guest_manual` + `confirmed`
   - Known guest walk-in → `manual_walk_in` + `seated` (walk-in analytics; identity from contact fields when staff taps Use guest)
6. Known-guest candidate cards in Manual Intake; phone field uses `.textContentType(.none)` + `.phonePad`.
7. **Use guest** prefill fills name/phone/email safely — does not overwrite typed guest/staff notes; staff must tap; no auto-pick.
8. **No `guest_key` on create** — backend create contract does not support it yet; backend resolves identity from name/phone/email after insert.
9. **Guests tab + detail local-first cache wiring** (`67e02d2`):
   - `GuestLookupView` reads `GuestProfileCacheRecord` via `@Query`; result cards show compact guest memory metadata.
   - `ReservationDetailView` reads disk cache preview before memory/network preview.
   - Full guest history / profile pack remains network/detail-only.
   - `RegularGuestsView` cache-first wiring completed in Slice 3R (`50df843`).

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

### Completed (guest person-map Slice 3R — iOS `50df843`)

1. **More → Guest Memory / Regulars** is **cache-first** — primary list reads `GuestProfileCacheRecord` via `@Query`.
2. **No backend page-25 list** as primary UI; **“Showing 25 of 101 profiles”** copy removed.
3. Search, filter, and sort are **local** over cached profiles (250ms debounce on search text).
4. Honest sync copy: “X guest profiles saved on this iPad” / “Still syncing…” using `GuestProfileSyncService` metadata keys.
5. Row tap opens **`GuestProfileDetailView(guestKey:environment:)`** — shared Guest history shell; **no** heavy `GuestInsightsView` on normal row tap.
6. **Service Intelligence → Guest Memory** and **More → Guest Memory** both pass `environment` into `RegularGuestsView`.
7. Background `GuestProfileSyncService` remains the freshness mechanism — no per-keystroke backend lookup.
8. **Not in 3R:** full booking-history list, notes timeline, source-mix UI, detail JSON persistence (3E), Manual Intake (done in 3M), Reservation Detail bridge.

### Completed (guest person-map Slice 3M-B — backend `63d0cfc`, root pointer `c7f5a69`)

Unknown walk-in backend contract for Tryzub V1 staff operations:

1. **`manual_walk_in`** may omit `guest_name`, `phone`, and `email` — operational fields (date, time, party size, status) still required.
2. **`manual_call_in`** still requires `guest_name` and 10+ digit `phone`; `email` optional.
3. Unknown walk-ins store internal placeholders only where DB `NOT NULL` requires them; API responses **mask** placeholder email/phone.
4. Placeholder name (`Walk-in guest`), placeholder email, and repeated-digit fake phones are **ignored** for `guest_key` resolution, profile rebuilds/lookups, duplicate matching, and email eligibility.
5. Walk-ins with real email, phone, or meaningful full name still enter normal guest profile flow.
6. Confirmation/reminder/manual email paths reject placeholder email — not sendable.
7. **Implemented, root-pointed, and deployed** to WordPress at `63d0cfc` / `c7f5a69`. Production unknown walk-in save is **ready for device verification** — smoke tests not yet passed.

### Completed (guest person-map Slice 3M — iOS `e775f52`)

1. **Walk-in** can save with blank name, phone, and email — iOS sends **blank identity fields**, not fake placeholders; backend owns `Walk-in guest` display.
2. Walk-in `source_type` remains **`manual_walk_in`**; status remains **seated**; known-guest walk-in stays `manual_walk_in` even after **Use guest**.
3. Partial/invalid walk-in phone or email is **non-blocking** and **omitted** from create payload.
4. **Call-in** still requires guest name + plausible phone; email optional.
5. **Local search while typing** by name, phone, or email (`GuestLookupStore`); placeholder walk-in names excluded from index.
6. **Explicit Search all guest records** calls `GET /guest-profiles/lookup` via `GuestProfileStore.lookupProfiles` — **no backend lookup while typing**.
7. Candidate cards: **Saved on this iPad** / **All guest records**; Likely guest / Possible match; **Use guest** (staff tap required); **View history** → `GuestProfileDetailView(guestKey:environment:)`.
8. Removed old phone-only `GuestPhoneLookupSuggestionRow` from Manual Intake UI.
9. **Not in 3M:** full booking-history list, notes timeline, source-mix UI, Reservation Detail bridge, detail JSON persistence (3E).
10. **P3 cleanup open:** unused `GuestLookupStore.schedulePhoneLookup` dead code remains.

### Completed (Manual Intake input polish — iOS `ad5d274`)

Post-3M staff-operations polish for live-service Manual Intake:

1. **Final review/confirmation sheet remains** before backend create — primary Add validates, dismisses keyboard, opens review sheet; `createReservation()` runs **only** from final sheet confirm.
2. **Removed pre-create confirmation/message actions** — no `GuestTextMessageActionButtons` on Manual Intake; no send-confirmation / send-text / create-and-send before reservation exists.
3. **Reservation Detail** confirmation/message workflow **unchanged** — post-create confirm/email remains on detail (`ReservationDetailView`, `ReservationActionButtons`, `ManualTextMessageService`).
4. **Keyboard Next/Done** flow on name/phone/email; focus trace **DEBUG-only**; removed `draft_changed` per-keystroke trace flood.
5. **Local guest lookup** debounced (250–300 ms); phone local-search threshold starts at **7 digits**; local candidate results capped (index 8 / UI 6); no backend lookup while typing.
6. Removed animated focus scroll; candidate section layout more stable while keyboard is open.
7. Review sheet summary improved — intake mode, Walk-in guest / No phone / No email, table and notes when set.
8. **Walk-in/call-in 3M behavior preserved** — blank walk-in identity, call-in name+phone required, Use guest, View history, explicit Search all guest records.

### Completed (device smoke Phase 1 — iOS `804c130`)

1. **Live button hit area** — reliable tap target on Host header.
2. **Bottom tab clearance** — last list row scrolls above floating tab bar (`topLevelTabScrollBottomInset`).
3. **Manual Intake keyboard-safe candidates** — guest candidate tray stays visible above iPhone keyboard.

### Completed (device smoke Phase 2 — iOS `8eab6c4`)

1. **Fast seated-now walk-ins** — live walk-in defaults to now + seated; review sheet preserved.
2. **Seated duration** — seated walk-ins show duration from seated timestamp.
3. **Attach known guest to walk-in** — detail/edit lookup; source stays `manual_walk_in`.
4. **Walk-in edit validation** — name-only/no-phone saves; call-in rules unchanged.
5. **Floor Plan table assignment** — when backend layout exists, table pick via floor plan (no raw table string).

### Completed (device smoke Phase 3 — iOS `5762ecb` + email-delivery refresh)

1. **Row indicators** — auto-confirm from **`confirmationSource`**; confirmation/reminder labels from **delivery truth** (not `_sentAt` as delivered); Host **Email issue** for failures only.
2. **No activity prefetch for badges** — DTO/sync fields only; activity remains history-only.

See [EMAIL_DELIVERY_TRUTH.md](./EMAIL_DELIVERY_TRUTH.md).

### Completed (device smoke Phase 4 — iOS `3da3a68`)

1. **Removed More → Email Controls** — no duplicate settings path.
2. **Restaurant Settings ownership** — Backend Reminders and Backend Auto-Confirm remain in Restaurant Settings.
3. **This Device Email** — local-only `EmailAutomationSettingsStore` switches under Restaurant Settings; screen renamed from Email Controls; no sending behavior changed.

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
11. **Deployed** to production WordPress at `1431a06`. iOS calls this route from **Guests tab** and **Manual Intake** explicit **Search all guest records** only (`1dfa14a`, `e775f52`) — not per-keystroke typing. **Device smoke tests for lookup still open** (see verification table).

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
2. Confirm confirmation mode on physical device (Mail vs backend `/confirm`).
3. **Run device smoke verification** — [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) §10 (Phases 1–4 code landed).
4. Final V1 device smoke test — must include guest full-list sync, Guests/intake lookup, Host header/flicker + intelligence-card checks, and device smoke checklist ([IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #4c).

**Not production-ready** until stabilization items 1–3 pass.

### Product-scale follow-up (before broader product release)

Replace broad in-memory guest filtering with **indexed / predicate-based local search**. Acceptable for **current Tryzub V1 data size** only.

**Later slices (not blocking release smoke test):** **3D** full shared Guest history UI (booking history timeline, guest/staff notes timeline, source mix, usual party/day/time) + Reservation Detail bridge (3D-a) + booking-history row → local `ReservationDetailView` when cached else read-only; **3E** detail JSON persistence / disk-first full profile reopen; phone normalization 10 vs 11 digit follow-up; dedicated validation error for blank lookup if needed; indexed local guest search; foreground/mutation-triggered guest-profile re-sync; `ReservationDetail` guest fetch dedupe (partially improved; full dedupe later); remove unused `schedulePhoneLookup` (P3); backend README wording cleanup if README still says pilot/MVP.

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
| Backend guest profile lookup (`1431a06`) | **Deployed** to WordPress |
| Backend unknown walk-in support (`63d0cfc`) | **Deployed** to WordPress — root pointer `c7f5a69` |
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
- Confirmation mode on physical device
- Final V1 device smoke test — include guest full-list sync completion, Guests/intake lookup beyond old 500 cap, walk-in/known-guest, Host `Last sync` + stale reasons + reduced idle flicker + intelligence-card chip stability; **device smoke verification** in [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) §10 (code Phases 1–4 landed)
- Guest profile background sync on physical device (post-`0f06852` install)
- Manual walk-in + known-guest intake on physical device (post-`0a89caa` install)
- Guests tab + detail cache wiring on physical device (post-`67e02d2` install)
- Host freshness/flicker polish on physical device (post-`71601fc` install)
- Host Intelligence card presentation stability on physical device (post-`39f7fcb` install)
- Guest profile full-list sync + full-cache lookup on physical device (post-`d541488` install)
- Backend guest profile lookup route **deployed** on WordPress (`1431a06`) — **device smoke tests still open** (exact email/phone lookup; name-only possible match; conflicting phone/email does not auto-pick; guest key opens full detail; unauthenticated lookup blocked)
- Guests tab explicit all-record lookup + View history shell on physical device (post-`1dfa14a` install)
- Regulars cache-first + View history on physical device (post-`50df843` install)
- Manual Intake walk-in blank identity save on physical device (post-`e775f52` / `ad5d274`; backend `63d0cfc` **deployed** — ready to test)
- Manual Intake local + all-record guest lookup + View history on physical device (post-`e775f52` / `ad5d274`)
- Manual Intake input polish on physical device (post-`ad5d274`) — review sheet before create; no pre-create message buttons; Next/Done keyboard; debounced local lookup
- Backend unknown walk-in contract on WordPress (`63d0cfc` **deployed**) — blank walk-in create; no fake guest profile; placeholder email not sendable; **device smoke tests still open**

---

## iOS guest memory (`0f06852` + `0a89caa` + `67e02d2` + `d541488` + `823f42c` + `1dfa14a` + `50df843` + `e775f52` + `ad5d274`)

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
| `RegularGuestsView` | Cache-first `@Query` list; local search/filter/sort; tap → `GuestProfileDetailView` (`50df843`) |
| `ManualReservationFormView` | Walk-in optional identity (`e775f52`); call-in name+phone required; local search while typing; explicit all-record lookup; Use guest + View history (`e775f52`); input polish — review sheet before create, no pre-create messages, keyboard Next/Done, debounced lookup (`ad5d274`) |

**Rules:**

- List sync only in background — **no detail/history prefetch**, no `/guest-profiles/rebuild`, no `/guest-intelligence` on keystroke.
- Backend `/guest-profiles/lookup` is called from **Guests tab** and **Manual Intake** explicit **Search all guest records** only (`1dfa14a`, `e775f52`) — not per keystroke.
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
2. **Confirm** confirmation mode on physical device.
3. **Run device smoke verification** — [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) §10.
4. **Run** release smoke test — include guest full-list sync, Guests + Manual Intake lookup (no per-digit backend), unknown walk-in save (backend `63d0cfc` deployed), Manual Intake review sheet + no pre-create messages (`ad5d274`), walk-in/known-guest, Host header (`Last sync`), stale secondary reasons, Live-on-today refresh, quiet-board idle flicker, intelligence-card chips stable during refresh, seated/due timing updates, manual refresh bumps `Last sync`, device smoke checklist items.
5. Before broader product release → **indexed local guest search** ([IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #6).

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
