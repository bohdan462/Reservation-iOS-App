# Current Source of Truth — Tryzub Reservations

**Last reviewed:** 2026-06-19  
**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md)

Compact master rules. When this file conflicts with stale index/diagram docs, **this file and backend plugin docs win**.

---

## 1. Authority rules

1. **Backend** ([README.md](../Backend/tryzub-reservations-api/README.md), [INTELLIGENCE.md](../Backend/tryzub-reservations-api/INTELLIGENCE.md)) is source of truth for API routes, DB schema, guest tokens, email types, intelligence payloads, and pipeline diagnostics.
2. **SwiftData** (`ReservationRecord` and related records) is **local iOS operational cache only** — never authoritative over the server.
3. **iOS** reads and writes **managed reservations** via the private REST API. It does **not** use raw Flamingo for normal staff workflow.
4. **Normal iOS refresh must not call** `POST /managed-reservations/import`.
5. **Do not create a second sync manager.** `ReservationsController` + `ReservationSyncService` own refresh and mutation orchestration.
6. **Do not create a second guest truth engine** beside `GuestOperationalTruth` and backend aggregates (`/guest-profiles`, `/guest-intelligence`). In-memory stores are cache layers, not parallel truth.

---

## 2. Current confirmation truth

1. **Both** backend confirmation (`POST /managed-reservations/{id}/confirm`) and **Mail-first** staff confirmation exist in code.
2. **Current pilot staff workflow** is **Mail-first** when **backend confirmation is off** in Email Controls (`EmailAutomationSettings.backendConfirmationEnabled`).
3. Code defaults may enable backend confirmation; **agents must not switch pilot flows** unless explicitly asked.
4. `POST /managed-reservations/{id}/confirm` is a **backend / gated / migration path**. Do not force it into current MVP UI or docs without product approval.
5. Primary staff path with email: `beginPrimaryConfirmFlow` → guest manage link → Mail composer → `manual-email-log` → PATCH `confirmed` on `.sent`. See [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md).

---

## 3. Guest cancellation truth

1. Guest self-cancel exists: `POST /reservation-self/cancel` with manage token.
2. **Implemented** in backend commit `239b297`: sends `cancellation` email after successful self-cancel (re-fetch row post-update); guest page **dead-state** copy for cancelled bookings; confirmation email no longer includes misleading “Request Different Time” CTA.
3. **Deploy verification still required:** confirm on live WordPress — email log row `email_type=cancellation`, cancelled page dead-state, double-cancel / too-late guards, confirmation copy.
4. Staff cancel remains PATCH `cancelled` from Host/Detail — separate from guest self-service.

---

## 4. Pipeline truth

1. Coarse counts (e.g. ~300 managed vs ~338 Flamingo non-spam) must be **explainable** in developer diagnostics.
2. The gap is **not automatically** “lost reservations.” Classifications include: `managed_active`, `managed_hidden`, `managed_terminal`, `failed_import`, `duplicate_import`, `hard_deleted_test_row`, `spam_or_rejected`, `non_reservation_form`, `form_source_unknown`, `unexplained_missing`.
3. Use `GET /intelligence/reservation-pipeline-diagnostics` for per-submission explanations; summary also appears under `/intelligence/system-status` → `pipeline_diagnostics.summary`. See [INTELLIGENCE.md](../Backend/tryzub-reservations-api/INTELLIGENCE.md).
4. **Unknown / unexplained** intake must remain visible in developer-facing diagnostics — do not hide behind a single aggregate number.

---

## 5. Host tab truth

1. **`selectedDate` is owned by `HomeDashboardView` only** (`ReservationsListView.swift`).
2. **`HostBoardView` must use `@Binding` only** — must not introduce a second `selectedDate` source.
3. Host Board must **not** render snapshot or operational data for the wrong selected date (see [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md)).

---

## 6. Host Intelligence truth

1. **Deterministic engine** owns facts and operational signals.
2. **Local model** may rewrite wording only (see [LOCAL_MODEL_INTELLIGENCE.md](./LOCAL_MODEL_INTELLIGENCE.md)).
3. Local model must **not** invent facts, mutate reservations, send messages, or decide actions.

---

## 7. Process rules

1. **One commit per concern.**
2. **Audit first, implement second.**
3. **Composer** audits and maps; produces handoff packets.
4. **GPT-5.5 Agent** writes code only after an exact handoff ([AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)).
5. **Do not mix unrelated dirty files** (e.g. backend auth/activation dirt with feature slices).
6. **Do not let stale docs** (`PROJECT_MAP`, `PROJECT_METHOD_MAP`, `ARCHITECTURE_DIAGRAMS`) override this file, backend plugin docs, or current workflow docs.
