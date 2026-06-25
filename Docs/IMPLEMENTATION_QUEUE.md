# Implementation Queue

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)

Ordered slices for **V1 production stabilization**. Finish open items (#4, #4b, #4c) before new product features. One slice per commit series unless explicitly combined.

**Current focus:** iOS device verification, confirmation mode on restaurant iPad, and final V1 smoke test — backend guest self-service, auth, and pipeline items verified in production.

---

## 1. Backend self-service cancellation + cache fix — verify and deploy consistency

| Field | Value |
|-------|-------|
| **Status** | **done** — verified in production (cancel email + cancelled dead-state on reload) |
| **Scope** | `reservation-self-service.php` (no-store headers, POST `data`, JS cache bust) |
| **Prior work** | `239b297` cancellation email + dead-state UI; `854b82d`/`6a30203` copy |
| **Why** | Production showed Confirmed + cancel button after successful guest cancel email (stale GET cache) |
| **Verification** | POST cancel → `data.status=cancelled`; GET headers `no-store`; reload shows dead state; token still valid; push `d46713a`; deploy zip matches submodule SHA |
| **Do not mix with** | iOS features, walk-ins, guest profile cache |

---

## 2. Production auth verification

| Field | Value |
|-------|-------|
| **Status** | **done** — app login works in production; optional curl spot-check remains |
| **Scope** | Live WordPress — manager Application Password, `/ping`, protected routes |
| **Why** | Anonymous checks passed; app login now confirmed live |
| **Verification** | App login works; optional `/ping` curl and `/restaurant-setup` 200 spot-check |
| **Do not mix with** | Guest self-service UI changes |

---

## 3. Pipeline diagnostics verification

| Field | Value |
|-------|-------|
| **Status** | **done** — reviewed; `unexplained_missing` is known old pre-hardening test, non-blocking for V1 |
| **Scope** | `GET /intelligence/reservation-pipeline-diagnostics`, `/intelligence/system-status` |
| **Why** | `239b297` flattened `developer_summary`; live check complete |
| **Verification** | Developer role can load diagnostics; historical unexplained row understood — not a current production mystery |
| **Do not mix with** | iOS import paths |

---

## 4. iOS data/fetch/storage verification on device

| Field | Value |
|-------|-------|
| **Status** | **current** — code at `b910bd1`; device verification not done |
| **Scope** | `ReservationsListView`, `ReservationsController`, `ReservationImportService`, `FreshnessCoordinator` |
| **Why** | Foreground/privacy refresh implemented; cache-first + delta/full policy must be trusted in ops |
| **Verification** | Background return + privacy unlock refresh board; no import on normal refresh; ghost rows cleared by bounded-full; checked/updated/saved-data UI reflects state (no duplicate stale-warning UI) |
| **Do not mix with** | Walk-ins, guest SwiftData cache |

---

## 4b. Confirmation mode on restaurant iPad

| Field | Value |
|-------|-------|
| **Status** | **current** — not yet verified on pilot device |
| **Scope** | Email Automation / This iPad Email Controls (`EmailAutomationSettings.backendConfirmationEnabled`) |
| **Why** | Code default is backend `/confirm` enabled; pilot may intend Mail-first — must match restaurant intent |
| **Verification** | Confirm active setting on restaurant iPad; send test confirmation; verify expected path (Mail vs server) |
| **Do not mix with** | Backend schema changes |

---

## 4c. Final V1 smoke test

| Field | Value |
|-------|-------|
| **Status** | **current** — after #4 and #4b |
| **Scope** | End-to-end staff ops on restaurant iPad (refresh, reservations, confirm flow, guest self-service spot-check) |
| **Why** | Individual backend checks passed; full ops pass still required before calling V1 ready |
| **Do not mix with** | New product features |

---

| Field | Value |
|-------|-------|
| **Status** | pending — **after #4, #4b, #4c** |
| **Scope** | `ManualReservationFormView` — pass `manual_walk_in` + seated default |
| **Why** | Backend accepts walk-in; iOS never sends source type |
| **Do not mix with** | Backend schema changes (not required for basic path) |

---

## 6. Guest profile local cache / indexing

| Field | Value |
|-------|-------|
| **Status** | later — **after stabilization** |
| **Scope** | SwiftData cache record + `GuestProfileStore` |
| **Why** | Profiles lost on restart; repeated network on detail |
| **Do not mix with** | Guest Insights Phase 2 UI polish |

---

## 7. Guest `updated_since` incremental sync

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | iOS API client + `GuestProfileStore` list fetch |
| **Why** | Backend supports `updated_since` on `/guest-profiles`; iOS does not pass it |

---

## 8. ReservationDetail guest fetch dedupe

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `ReservationDetailView` — remove redundant `GuestIntelligenceStore.loadProfile` when aggregate suffices |

---

## 9. Analytics local persisted cache

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `BusinessIntelligenceStore` disk persistence |

---

## 10. Public guest token route rate limiting

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `reservation-self-service.php` — per-token / per-IP limits |

---

## 11. Feedback MVP

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | TBD — not in current codebase |

---

## 12. Floor-first Host mode

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | Host Board presentation mode |

---

## Completed (reference)

| Slice | Commit / note |
|-------|----------------|
| Backend guest cancel email + page copy + pipeline flattening | `239b297`, `5a04af4` |
| iOS foreground / privacy stale refresh (code) | `b910bd1` — verify on device (queue #4) |
| Guest self-service cache fix | `d46713a` + `078a44a` README — **verified in production** |
| Production auth (app login) | **Verified in production** |
| Pipeline diagnostics review | **Done** — unexplained item is known old test |

---

## Parked / not v1

Do **not** schedule these as active next work:

| Item | Reason |
|------|--------|
| **Host stale warning UI** | `HomeServiceStatusPresenter` / `ScreenFreshnessState` already show Updated / Checked / Saved data / offline — **do not duplicate** unless device testing proves a gap |
| **Offline manual reservation queue** | Explicitly not v1 — no queued offline creates/edits |
| **Offline create/edit / sync-when-online queue** | Not v1 — mutations blocked offline; cache view-only |
| Multi-tenant rewrite | Post-pilot |
| SMS automation | Cost / owner decision |
| Broad Host redesign | After stabilization |
| New LLM / AI feature work | Host Intelligence local model is wording-only per [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md) |

---

## Deploy artifacts

- `Backend/*.zip` is **gitignored** — build locally when deploying.
- Zip must wrap files in `tryzub-reservations-api/` folder for WordPress plugin update (not flat archive root).
