# Current Source of Truth — Tryzub Reservations

**Last reviewed:** 2026-06-24  
**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md)

Compact master rules. When this file conflicts with stale index/diagram docs, **this file and backend plugin docs win**.

**Backend contracts live only in** [Backend/tryzub-reservations-api/README.md](../Backend/tryzub-reservations-api/README.md) and [INTELLIGENCE.md](../Backend/tryzub-reservations-api/INTELLIGENCE.md). Do not duplicate them into root `Docs/`.

---

## 1. Authority rules

1. **Backend** ([README.md](../Backend/tryzub-reservations-api/README.md), [INTELLIGENCE.md](../Backend/tryzub-reservations-api/INTELLIGENCE.md)) is source of truth for API routes, DB schema, guest tokens, email types, intelligence payloads, and pipeline diagnostics.
2. **SwiftData** (`ReservationRecord` and related records) is **local iOS operational cache only** — never authoritative over the server.
3. **iOS** reads and writes **managed reservations** via the private REST API. It does **not** use raw Flamingo for normal staff workflow.
4. **Normal iOS refresh must not call** `POST /managed-reservations/import`.
5. **Do not create a second sync manager.** `ReservationsController` + `ReservationSyncService` own refresh and mutation orchestration.
6. **Do not create a second guest truth engine** beside `GuestOperationalTruth` and backend aggregates (`/guest-profiles`, `/guest-intelligence`). In-memory stores are cache layers, not parallel truth.
7. **Checked/fetched status UI already exists** on Host (`HomeServiceStatusPresenter`, `ScreenFreshnessState`). Do not add duplicate stale-warning UI without proving a real gap.

---

## 2. Data fetch / freshness (iOS)

1. **Cache-first startup** — show local SwiftData when available; network pass follows.
2. **Active-window sync** — full replace vs delta upsert per `ReservationsController` policy (bounded-full after 5 deltas or 2 hours).
3. **Sync cursor persistence** — active-window `server_time` cursors live in `ReservationsController.serverCursorByScope` and are **persisted in UserDefaults** (`tryzub.sync.serverCursors.v1`) so delta/full policy can resume after relaunch. Scope last-success timestamps and active-window bounds metadata are also persisted in UserDefaults. This is **not** an offline mutation queue.
4. **SwiftData** stores reservation rows (operational cache only). **`lastSyncedAt`**, **`lastFreshnessCheckedAt`**, and **`cacheTrustSource`** are controller presentation/session fields rehydrated from local DB timestamps and startup state where applicable — not server truth.
5. **Foreground / privacy unlock refresh** — implemented `b910bd1` via `autoRefreshDashboardIfAllowed` in `ReservationsListView`.
6. **Stale local cache risk** — if refresh skipped, fails, or staff device holds old PATCH without `expected_updated_at`, UI can disagree with server.
7. **Offline / degraded** — no offline manual create/edit queue in V1. Mutations are blocked when network is unavailable; cache remains visible for viewing. Offline notices only.
8. **Checked/fetched UI** — Host already shows checked/updated/saved-data state via `HomeServiceStatusPresenter` and `ScreenFreshnessState`. Do not add duplicate Host stale-warning UI without device-proven gap.

---

## 3. Current confirmation truth

1. **Both paths exist:** backend confirmation (`POST /managed-reservations/{id}/confirm`) and **manual Mail** staff confirmation.
2. **Active device behavior depends on Email Automation / This iPad Email Controls** (`EmailAutomationSettings.backendConfirmationEnabled`). Code default is **`true`** — do **not** assume Mail-first unless the device setting is confirmed on the pilot iPad.
3. **Manual Mail path** (when backend confirmation is off or staff uses reviewable send): `beginPrimaryConfirmFlow` → guest manage link → Mail composer → `manual-email-log` → PATCH `confirmed` on `.sent` only.
4. **Backend confirmation path** (when enabled): `POST /confirm` sends through backend/provider; must only confirm after backend send success when a usable guest email exists. **Not production-verified** until live tests pass.
5. **Agents must not switch pilot flows** unless explicitly asked.
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
