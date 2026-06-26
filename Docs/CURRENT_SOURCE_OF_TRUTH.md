# Current Source of Truth — Tryzub Reservations

**Last reviewed:** 2026-06-26  
**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md)

Compact master rules. When this file conflicts with stale index/diagram docs, **this file and backend plugin docs win**.

**Backend contracts live only in** [Backend/tryzub-reservations-api/README.md](../Backend/tryzub-reservations-api/README.md) and [INTELLIGENCE.md](../Backend/tryzub-reservations-api/INTELLIGENCE.md). Do not duplicate them into root `Docs/`.

---

## 1. Authority rules

1. **Backend** ([README.md](../Backend/tryzub-reservations-api/README.md), [INTELLIGENCE.md](../Backend/tryzub-reservations-api/INTELLIGENCE.md)) is source of truth for API routes, DB schema, guest tokens, email types, intelligence payloads, and pipeline diagnostics.
2. **SwiftData** (`ReservationRecord`, `GuestProfileCacheRecord`, and related records) is **local iOS operational cache only** — never authoritative over the server.
3. **iOS** reads and writes **managed reservations** via the private REST API. It does **not** use raw Flamingo for normal staff workflow.
4. **Normal iOS refresh must not call** `POST /managed-reservations/import`.
5. **Do not create a second sync manager.** `ReservationsController` + `ReservationSyncService` own refresh and mutation orchestration.
6. **Do not create a second guest truth engine** beside `GuestOperationalTruth` and backend aggregates (`/guest-profiles`, `/guest-intelligence`). In-memory stores are cache layers, not parallel truth.
7. **Host sync status UI** — `HomeServiceStatusPresenter` shows `Last sync HH:mm` (server sync), `Checked HH:mm` (cache-only), stale dot at 120s, and staff-facing skip reasons (`71601fc`). `ScreenFreshnessState` covers availability/slots sub-screens. Do not add duplicate stale-warning UI without proving a real gap.

---

## 2. Data fetch / freshness (iOS)

1. **Cache-first startup** — show local SwiftData when available; network pass follows.
2. **Active-window sync** — full replace vs delta upsert per `ReservationsController` policy (bounded-full after 5 deltas or 2 hours).
3. **Sync cursor persistence** — active-window `server_time` cursors live in `ReservationsController.serverCursorByScope` and are **persisted in UserDefaults** (`tryzub.sync.serverCursors.v1`) so delta/full policy can resume after relaunch. Scope last-success timestamps and active-window bounds metadata are also persisted in UserDefaults. This is **not** an offline mutation queue.
4. **SwiftData** stores reservation rows and guest profile list aggregates (operational cache only). **`lastSyncedAt`**, **`lastFreshnessCheckedAt`**, and **`cacheTrustSource`** are controller presentation/session fields rehydrated from local DB timestamps and startup state where applicable — not server truth.
5. **Guest profile list sync** — iOS fetches `GET /guest-profiles` in background after startup deferral; **list only**, no bulk detail/history prefetch. Full-list completion tracked in UserDefaults (`d541488`): while incomplete, forces full paginated sync and bypasses 15-minute TTL; reconciles local count vs backend `total`.
6. **Guest profile lookup (backend Slice 2 — `1431a06`)** — `GET /guest-profiles/lookup` is a staff-only search doorway returning compact candidates with `match_basis` / `match_confidence` and safe strong-only `best_match_*` fields. Exact email and 10+ digit phone are strong; 7–9 digit phone and name-only walk-ins are possible candidates requiring staff confirmation. Lookup does **not** replace paginated `GET /guest-profiles` (complete list) or `GET /guest-profiles/{guest_key}` (full history/notes/stats). No rebuild, no reservation-table scan, no public access. **Deployed** to production WordPress at `1431a06`. iOS calls from Guests tab and Manual Intake explicit search only (`1dfa14a`, `e775f52`). Device lookup smoke tests still open.
7. **Unknown walk-in backend contract (Slice 3M-B — `63d0cfc`, root pointer `c7f5a69`)** — `manual_walk_in` may omit name, phone, and email; `manual_call_in` still requires name + 10+ digit phone. Internal placeholders satisfy `NOT NULL` columns only; API masks placeholder email/phone. Placeholders ignored for `guest_key`, profile aggregation, duplicate match, and email send. **Implemented, root-pointed, and deployed** to WordPress at `63d0cfc`.
8. **iOS guest profile lookup foundation (Slice 3A — `823f42c`)** — DTO/API/client + `GuestProfileStore.lookupProfiles(...)`; deduped network tasks; MainActor SwiftData upsert of compact summaries without clearing detail blobs; no UI in 3A.
9. **Guests tab explicit lookup (Slice 3B — `1dfa14a`)** — typing searches saved on-device matches only; backend lookup runs only on **Search all guest records** button or keyboard search submit; Likely guest / Possible match badges; staff must tap; **View history** opens `GuestProfileDetailView` when `guestKey` exists; **Book reservation** separate.
10. **Guest Person Map / shared Guest history** — target is one shared destination by `guestKey` (`GuestProfileDetailView`, title Guest history). **Guests tab:** done (`1dfa14a`). **Regulars / Guest Memory:** done (`50df843`). **Manual Intake candidates:** done (`e775f52`). **Reservation Detail:** open (Slice 3D-a). Full booking history and notes timeline remain on backend detail DTO + Slice 3D UI; `GuestProfileDetailView` currently shows summary shell only.
11. **Guest lookup indexing** — `GuestLookupStore` indexes all locally cached `GuestProfileCacheRecord` rows (`d541488`); broad in-memory filter acceptable for **current Tryzub V1 data size**; indexed search required before broader product release. **No backend lookup on keystroke.**
12. **Manual intake guest lookup (Slice 3M — `e775f52`)** — local search by name/phone/email while typing; explicit **Search all guest records** for backend candidates; **Use guest** + **View history**; walk-in may save with blank identity (iOS sends blank fields); call-in requires name + plausible phone.
13. **Manual Intake input polish (`ad5d274`)** — final review/confirmation sheet before backend create (`createReservation()` only from sheet confirm); removed pre-create `GuestTextMessageActionButtons` / send-confirmation actions (post-create confirm/email remains on Reservation Detail); keyboard Next/Done; DEBUG-only focus trace; debounced local lookup (250–300 ms); phone local-search from 7 digits; capped candidates; no backend lookup while typing; 3M walk-in/call-in rules preserved.
14. **Manual create** — does **not** send `guest_key` (backend create contract lacks it); identity resolved server-side from contact fields after insert.
15. **Foreground / privacy unlock refresh** — implemented `b910bd1` via `autoRefreshDashboardIfAllowed` in `ReservationsListView`.
16. **Stale local cache risk** — if refresh skipped, fails, or staff device holds old PATCH without `expected_updated_at`, UI can disagree with server.
17. **Offline / degraded** — no offline manual create/edit queue in V1. Mutations are blocked when network is unavailable; cache remains visible for viewing. Offline notices only.
18. **Host sync header** — `Last sync HH:mm` after successful active-window server sync; `Checked HH:mm` for cache-only freshness; stale secondary reasons when trust >120s (`Paused`, `Paused while editing`, `Waiting — busy`, `Retry soon`, or fallback `May be out of date · tap refresh`). Live + today bypasses only `full_fresh_no_cursor` idle skip.
19. **Host snapshot timing** — snapshot minute rebuild is conditional (`71601fc`): stable for non-today and quiet today boards; still minute-refreshes for seated / due / overdue / upcoming within ~90 min. Reduced idle snapshot flicker — not eliminated.
20. **Host Intelligence card presentation** — keeps last stable card/chips during async presentation rebuild (`39f7fcb`); no empty interstitial during key mismatch. Removed intelligence-card empty flicker path — final device verification still open.
21. **Guests tab + detail** — `GuestLookupView` reads `GuestProfileCacheRecord` from disk first (`67e02d2`); explicit all-record lookup (`1dfa14a`); `ReservationDetailView` disk cache preview before memory/network; full guest history remains network/detail-only — detail blobs not yet persisted for every profile (Slice 3E); Reservation Detail still uses `GuestInsightsView`, not shared `GuestProfileDetailView`.
22. **Regulars / Guest Memory** — `RegularGuestsView` is cache-first (`50df843`): `@Query` on `GuestProfileCacheRecord`, local search/filter/sort, tap opens `GuestProfileDetailView(guestKey:)`; no network page-25 primary list; full history UI remains Slice 3D.
23. **Device smoke code Phases 1–4 (`804c130` → `3da3a68`)** — layout/hit-testing, walk-in workflow, row indicators, email settings cleanup **landed in code**. Physical device verification still open. Slice **3D/3E parked** until smoke verification accepted or Bohdan resumes.
24. **Email settings ownership** — Backend reminders and auto-confirm rules live in **Restaurant Settings** (`RestaurantSettingsStore`, `/restaurant-setup`). Local-only switches live under **This Device Email** (`EmailAutomationSettingsStore`, UserDefaults). More → Email Controls removed (`3da3a68`).
25. **Reservation attachments (iOS UI — Slice D)** — Reservation Detail **shared attachments wired in code** at `d947721`: detail-scoped list/upload/download/delete, local-only preservation, staff-facing progress/errors. `AttachmentFeatureFlag.remoteUploadEnabled` is **true** (gated by reservation id + credentials). **Live/cross-device verification still open** — do not treat as production-verified until Slice E passes. Old pre-sync **local-only** attachments may remain on the original device only; staff should **reattach important old images** if they need shared visibility. See [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md).
26. **Reservation attachments (backend — deployed)** — Backend `a2422d3` (plugin **0.5.5**, DB **1.12.0**): private storage + staff-auth routes. **Deployed and production-smoked.** **No public image URLs**; direct image path **404**; guest self-service must never expose attachments.
27. **Reservation attachments (iOS foundation — Slice C)** — Root `17a0bee`: DTOs, `ReservationsAPIClient` list/upload/PATCH/delete/download, `ReservationAttachmentRecord` remote fields + upsert helper, `AttachmentFileStore` download cache, backend label mapping. **Next practical step: Slice E** live verification (not new backend work).

---

## 3. Current confirmation truth

1. **Both paths exist:** backend confirmation (`POST /managed-reservations/{id}/confirm`) and **manual Mail** staff confirmation.
2. **Active device behavior depends on This Device Email** (`EmailAutomationSettings.backendConfirmationEnabled`, local UserDefaults). Code default is **`true`** — do **not** assume Mail-first unless the device setting is confirmed on the physical device.
3. **Manual Mail path** (when backend confirmation is off or staff uses reviewable send): `beginPrimaryConfirmFlow` → guest manage link → Mail composer → `manual-email-log` → PATCH `confirmed` on `.sent` only.
4. **Backend confirmation path** (when enabled): `POST /confirm` sends through backend/provider; must only confirm after backend send success when a usable guest email exists. **Not production-verified** until live tests pass.
5. **Agents must not switch confirmation flows** on the test device unless explicitly asked.
6. See [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md) for step-by-step detail.

---

## 4. Guest cancellation truth

1. Guest self-cancel: `POST /reservation-self/cancel` with manage token.
2. **Backend `239b297`:** sends `cancellation` email after successful status update and row re-fetch.
3. **Backend `d46713a`:** no-store/no-cache on guest self-service REST; JS `cache: 'no-store'` + `_ts` bust; POST cancel may return refreshed guest-safe `data`.
4. **Token remains valid after cancellation.** Page must show **cancelled dead state** (heading, subtitle, status pill, no cancel button) — not invalidate the token.
5. **Deploy verification still required** on live WordPress after cache fix upload.
6. Staff cancel remains PATCH `cancelled` from Host/Detail — separate from guest self-service.
7. **Risk:** stale iOS/staff PATCH without `expected_updated_at` can revert `cancelled` → `confirmed` (backend allows that transition).

---

## 5. Pipeline truth

1. Coarse counts (e.g. ~300 managed vs ~338 Flamingo non-spam) must be **explainable** in developer diagnostics.
2. Classifications include: `managed_active`, `managed_hidden`, `managed_terminal`, `failed_import`, `duplicate_import`, `hard_deleted_test_row`, `spam_or_rejected`, `non_reservation_form`, `form_source_unknown`, `unexplained_missing`.
3. Use `GET /intelligence/reservation-pipeline-diagnostics`; summary under `/intelligence/system-status` → `pipeline_diagnostics.summary`. See [INTELLIGENCE.md](../Backend/tryzub-reservations-api/INTELLIGENCE.md).
4. **Unknown / unexplained** intake must remain visible in developer-facing diagnostics.

---

## 6. Host tab truth

1. **`selectedDate` is owned by `HomeDashboardView` only** (`ReservationsListView.swift`).
2. **`HostBoardView` must use `@Binding` only** — must not introduce a second `selectedDate` source.
3. Host Board must **not** render snapshot or operational data for the wrong selected date (see [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md)).
4. **Snapshot rebuild cadence** — `boardSnapshotBuildKey` uses conditional minute stamp (`hostBoardSnapshotTimingRefreshStamp`, `71601fc`); do not revert to unconditional per-minute rebuild without device reason.
5. **Intelligence card presentation** — render uses last stable `@State` presentation during async rebuild (`39f7fcb`); do not reintroduce key-mismatch `.empty` gate in `liveHostIntelligenceSection`.
6. **Auto-refresh skip reasons** — surfaced in header secondary when stale; cleared on successful server sync.

---

## 7. Host Intelligence truth

1. **Deterministic engine** owns facts and operational signals.
2. **Local model** may rewrite wording only (see [LOCAL_MODEL_INTELLIGENCE.md](./LOCAL_MODEL_INTELLIGENCE.md)).
3. Local model must **not** invent facts, mutate reservations, send messages, or decide actions.

---

## 8. Deploy / repo truth

1. **Backend submodule pointer** (root) should match deployed plugin code SHA when possible.
2. **Deploy zips are not tracked** in root git (`Backend/*.zip` gitignored). Production zip SHA is not repo truth unless recorded elsewhere.
3. WordPress plugin zip must use folder `tryzub-reservations-api/` at archive root.

---

## 9. Process rules

1. **One commit per concern.**
2. **Audit first, implement second.**
3. **Composer** audits and maps; produces handoff packets.
4. **GPT-5.5 Agent** writes code only after an exact handoff ([AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)).
5. **Do not mix unrelated dirty files.**
6. **Do not let stale docs** (`PROJECT_MAP`, `PROJECT_METHOD_MAP`, `ARCHITECTURE_DIAGRAMS`) override this file, backend plugin docs, or current workflow docs.
