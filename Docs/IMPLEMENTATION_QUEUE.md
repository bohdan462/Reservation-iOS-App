# Implementation Queue

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)

Ordered slices for **V1 production stabilization**. Finish #1–#4 before new product features. One slice per commit series unless explicitly combined.

**Current focus:** data storage/fetch/freshness correctness and backend production verification — not new guest or Host product work.

---

## 1. Backend self-service cancellation + cache fix — verify and deploy consistency

| Field | Value |
|-------|-------|
| **Status** | **current** — code committed `d46713a`; live verification pending |
| **Scope** | `reservation-self-service.php` (no-store headers, POST `data`, JS cache bust) |
| **Prior work** | `239b297` cancellation email + dead-state UI; `854b82d`/`6a30203` copy |
| **Why** | Production showed Confirmed + cancel button after successful guest cancel email (stale GET cache) |
| **Verification** | POST cancel → `data.status=cancelled`; GET headers `no-store`; reload shows dead state; token still valid; push `d46713a`; deploy zip matches submodule SHA |
| **Do not mix with** | iOS features, walk-ins, guest profile cache |

---

## 2. Production auth verification

| Field | Value |
|-------|-------|
| **Status** | pending |
| **Scope** | Live WordPress — manager Application Password, `/ping`, protected routes |
| **Why** | Anonymous checks pass; manager `can_manage_tryzub_reservations` not verified live |
| **Verification** | `/ping` with manager creds; `/restaurant-setup` 200; role repair from `5a04af4` confirmed on production |
| **Do not mix with** | Guest self-service UI changes |

---

## 3. Pipeline diagnostics verification

| Field | Value |
|-------|-------|
| **Status** | pending |
| **Scope** | `GET /intelligence/reservation-pipeline-diagnostics`, `/intelligence/system-status` |
| **Why** | `239b297` flattened `developer_summary`; needs authenticated live check |
| **Verification** | Developer role can load diagnostics; unexplained intake visible; no stale doc assumptions |
| **Do not mix with** | iOS import paths |

---

## 4. iOS data/fetch/storage verification on device

| Field | Value |
|-------|-------|
| **Status** | pending — code at `b910bd1`; device verification not done |
| **Scope** | `ReservationsListView`, `ReservationsController`, `ReservationImportService`, `FreshnessCoordinator` |
| **Why** | Foreground/privacy refresh implemented; cache-first + delta/full policy must be trusted in ops |
| **Verification** | Background return + privacy unlock refresh board; no import on normal refresh; ghost rows cleared by bounded-full; checked/updated/saved-data UI reflects state (no duplicate stale-warning UI) |
| **Do not mix with** | Walk-ins, guest SwiftData cache |

---

## 5. Walk-in / wait room creation

| Field | Value |
|-------|-------|
| **Status** | pending — **after #1–#4** |
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
| Backend guest cancel email + page copy + pipeline flattening | `239b297`, `5a04af4`; root pointer was `3c44856` era |
| iOS foreground / privacy stale refresh | `b910bd1` — verify on device (queue #4) |
| Guest self-service cache fix (code) | `d46713a` — verify live (queue #1) |

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
