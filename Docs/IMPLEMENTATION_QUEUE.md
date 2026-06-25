# Implementation Queue

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)

Ordered slices for **V1**. Stabilization items (#4, #4b, #4c) remain open. Guest memory foundation (#7–#9) is **done**. Next product slice: **Guests tab + detail local-first wiring** (#5).

**Current focus:** iOS device verification, confirmation mode on restaurant iPad, final V1 smoke test — then Guests tab cache wiring.

---

## 1. Backend self-service cancellation + cache fix — verify and deploy consistency

| Field | Value |
|-------|-------|
| **Status** | **done** — verified in production |
| **Scope** | `reservation-self-service.php` |
| **Commits** | `d46713a`, `078a44a` README |

---

## 2. Production auth verification

| Field | Value |
|-------|-------|
| **Status** | **done** — app login works in production |

---

## 3. Pipeline diagnostics verification

| Field | Value |
|-------|-------|
| **Status** | **done** — reviewed; old `unexplained_missing` test non-blocking |

---

## 4. iOS data/fetch/storage verification on device

| Field | Value |
|-------|-------|
| **Status** | **current** — code at `b910bd1`; device verification not done |
| **Scope** | `ReservationsListView`, `ReservationsController`, `FreshnessCoordinator` |
| **Verification** | Foreground + privacy unlock refresh; bounded-full; no import on normal refresh |
| **Do not mix with** | Guests tab cache wiring until stabilization green |

---

## 4b. Confirmation mode on restaurant iPad

| Field | Value |
|-------|-------|
| **Status** | **current** — not yet verified on pilot device |
| **Scope** | `EmailAutomationSettings.backendConfirmationEnabled` |
| **Note** | Confirmation hardening shipped at `cf6e641`; pilot setting still needs explicit check |

---

## 4c. Final V1 smoke test

| Field | Value |
|-------|-------|
| **Status** | **current** — after #4 and #4b |
| **Scope** | End-to-end staff ops on restaurant iPad |
| **Include** | Guest profile background sync (`0f06852`), manual walk-in + known-guest intake (`0a89caa`) |

---

## 5. Guests tab + detail local-first guest cache wiring

| Field | Value |
|-------|-------|
| **Status** | **next** — after #4, #4b, #4c (or parallel if Bohdan approves) |
| **Scope** | `GuestLookupView`, `GuestProfileFacade` / `ReservationDetailView`, `RegularGuestsView` — read `GuestProfileCacheRecord` before network |
| **Why** | Manual intake uses cache; Guests tab search still reservation-history only; detail still network-first |
| **Verification** | Guests tab finds backend-known guests after sync without typing phone in manual form; detail shows cached aggregate when fresh |
| **Do not mix with** | AI clustering, VIP editor, offline queue |

---

## 6. Indexed / predicate-based local guest search

| Field | Value |
|-------|-------|
| **Status** | **product-scale follow-up** — required before broader product release |
| **Scope** | `GuestProfileRepository`, `GuestLookupStore` — replace full-table in-memory filter |
| **Why** | Broad in-memory filtering is acceptable for **Tryzub V1 pilot only**; will not scale for multi-venue or large guest lists |
| **Do not mix with** | Backend schema changes |

---

## 7. Guest profile local cache foundation

| Field | Value |
|-------|-------|
| **Status** | **done** — `0f06852` |
| **Scope** | `GuestProfileCacheRecord`, `GuestProfileRepository`, `GuestProfileSyncService`, `GuestProfileStore` disk write-through, `updated_since` on API client |
| **Verification** | Background paginated list sync after startup deferral; no detail prefetch |

---

## 8. Manual intake local guest cache + walk-in

| Field | Value |
|-------|-------|
| **Status** | **done** — `0a89caa` |
| **Scope** | `ManualReservationFormView`, `GuestLookupStore`, `GuestLookupModels` |
| **Delivered** | Call-in / walk-in modes; known-guest card + prefill; local cache merge; `manual_walk_in`+`seated`, `known_guest_manual`+`confirmed`; phone `.textContentType(.none)` |
| **Gap** | Guests tab not wired (see #5) |

---

## 9. Guest `updated_since` incremental sync

| Field | Value |
|-------|-------|
| **Status** | **done** — shipped in `0f06852` |
| **Scope** | `ReservationsAPIClient.fetchGuestProfiles(updatedSince:)`, `GuestProfileSyncService` cursor |

---

## 10. ReservationDetail guest fetch dedupe

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `ReservationDetailView` — remove redundant `GuestIntelligenceStore.loadProfile` when aggregate suffices |

---

## 11. Analytics local persisted cache

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `BusinessIntelligenceStore` disk persistence |

---

## 12. Public guest token route rate limiting

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `reservation-self-service.php` |

---

## 13. Feedback MVP

| Field | Value |
|-------|-------|
| **Status** | later |

---

## 14. Floor-first Host mode

| Field | Value |
|-------|-------|
| **Status** | later |

---

## Completed (reference)

| Slice | Commit / note |
|-------|----------------|
| Backend guest cancel + cache | `d46713a`, `078a44a` — verified in production |
| Production auth | Verified in production |
| Pipeline diagnostics | Reviewed — old unexplained test |
| iOS foreground / privacy refresh (code) | `b910bd1` — device verify open (#4) |
| V1 confirmation hardening | `cf6e641` |
| Guest profile SwiftData cache + background sync | `0f06852` |
| Manual intake cache merge + walk-in + known guest | `0a89caa` |
| Guest list `updated_since` on iOS | `0f06852` |

---

## Parked / not v1

| Item | Reason |
|------|--------|
| **Offline manual reservation queue** | Explicitly not v1 |
| **Host stale warning UI** | Already covered by `HomeServiceStatusPresenter` / `ScreenFreshnessState` |
| **Broad Host redesign** | After stabilization |
| **Full AI clustering / “knows each other” / local semantic tags** | Not started |
| **VIP editor** | No backend guest-level notes contract |
| Multi-tenant rewrite | Post-pilot |
| SMS automation | Owner decision |
| New LLM feature work | Host Intelligence local model is wording-only |

---

## Deploy artifacts

- `Backend/*.zip` is **gitignored** — build locally when deploying.
- Zip must wrap files in `tryzub-reservations-api/` folder for WordPress plugin update.
