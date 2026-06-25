# Implementation Queue

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)

Ordered slices for **V1**. Stabilization items (#4, #4b, #4c) remain open. Guest memory foundation (#7–#9), Guests tab cache wiring (#5), guest person-map Slice 1 (#5d), and Tryzub V1 Host production polish (#5b, #5c) are **done**.

**Current focus:** iOS device verification, confirmation mode on restaurant iPad, final V1 smoke test.

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

---

## 4b. Confirmation mode on restaurant iPad

| Field | Value |
|-------|-------|
| **Status** | **current** — not yet verified on test device |
| **Scope** | `EmailAutomationSettings.backendConfirmationEnabled` |
| **Note** | Confirmation hardening shipped at `cf6e641`; device setting still needs explicit check |

---

## 4c. Final V1 smoke test

| Field | Value |
|-------|-------|
| **Status** | **current** — after #4 and #4b |
| **Scope** | End-to-end staff ops on restaurant iPad |
| **Include** | Guest profile background sync (`0f06852`); guest full-list sync completion (`d541488`); manual walk-in + known-guest intake (`0a89caa`); Guests tab + detail cache (`67e02d2`); Host freshness (`71601fc`); Host Intelligence card stability (`39f7fcb`) |
| **Guest memory checks** | Full-list sync eventually marks complete; Guests/manual intake finds known guest outside old 500 cap; no backend call on every phone digit; incomplete full-list sync does not wait on TTL before retrying full sync |
| **Host header checks** | Header shows `Last sync HH:mm`; stale secondary reason when refresh skipped/stale; Live-on today does not sit stale without explanation; manual refresh bumps `Last sync` on success |
| **Host flicker checks** | Quiet Host board does not rebuild/flicker every minute from idle snapshot timing; Host Intelligence card chips do not disappear/reappear when intelligence refreshes; during service, seated/due/nearby rows still update timing |

---

## 5. Guests tab + detail local-first guest cache wiring

| Field | Value |
|-------|-------|
| **Status** | **done** — `67e02d2` |
| **Scope** | `GuestLookupView`, `ReservationDetailView`, `GuestProfileRepository` |
| **Delivered** | Guests tab reads `GuestProfileCacheRecord`; result cards show compact guest memory metadata; detail disk cache preview before memory/network; full history remains network/detail-only |
| **Gap** | `RegularGuestsView` disk-first remains later |

---

## 5b. Host freshness + idle snapshot flicker polish

| Field | Value |
|-------|-------|
| **Status** | **done** — `71601fc` |
| **Scope** | `HostBoardView.swift`, `ReservationSharedUI.swift`, `ReservationsController.swift` |
| **Delivered** | `Last sync` / `Checked` header copy; stale staff-facing skip reasons; conditional snapshot minute rebuild; Live + today bypasses only `full_fresh_no_cursor` |
| **Do not overstate** | Reduced idle snapshot flicker — not all flicker eliminated; did **not** fix intelligence-card presentation flicker (see #5c); 120s stale threshold unchanged |

---

## 5c. Host Intelligence card presentation stability

| Field | Value |
|-------|-------|
| **Status** | **done** — `39f7fcb` |
| **Scope** | `HostBoardView.swift` only |
| **Delivered** | No `HostIntelligenceCardPresentation.empty` during presentation-key mismatch; keeps prior stable card/chips during async presentation rebuild; removes old-card → empty-card → rebuilt-card flicker path |
| **Do not overstate** | Removed empty interstitial flicker path — not all Host flicker eliminated; does not change Host Intelligence cadence, local model pipeline, sync, backend, guest cache, or `FreshnessCoordinator`; final device verification still open |

---

## 5d. Guest person-map Slice 1 — full-list sync completion + full cache lookup

| Field | Value |
|-------|-------|
| **Status** | **done** — `d541488` |
| **Scope** | `GuestProfileSyncService.swift`, `GuestProfileRepository.swift`, `GuestLookupStore.swift` |
| **Delivered** | Sync metadata (`fullListSyncCompleted`, `lastFullListSyncAt`, `backendProfileTotal`, `cachedProfileCount`, `lastSyncFailureReason`); force full paginated sync while incomplete; TTL bypass while incomplete; reconcile cached count vs backend total; index all cached profiles in lookup (removed 500 cap) |
| **Do not overstate** | No backend targeted lookup; no full history prefetch for every profile; no indexed search; improves reliability but does not block final V1 smoke test; final device verification still open |

---

## 6. Indexed / predicate-based local guest search

| Field | Value |
|-------|-------|
| **Status** | **product-scale follow-up** — required before broader product release |
| **Scope** | `GuestProfileRepository`, `GuestLookupStore` — replace full-table in-memory filter |
| **Why** | Broad in-memory filtering is acceptable for **current Tryzub V1 data size** only; will not scale for multi-venue or large guest lists |
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
| **Status** | later — partially improved by `67e02d2` disk preview; full dedupe remains open |
| **Scope** | `ReservationDetailView` — remove redundant `GuestIntelligenceStore.loadProfile` when aggregate suffices |

---

## 11. RegularGuestsView disk-first

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `RegularGuestsView` — read `GuestProfileCacheRecord` before network |

---

## 12. Analytics local persisted cache

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `BusinessIntelligenceStore` disk persistence |

---

## 13. Public guest token route rate limiting

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `reservation-self-service.php` |

---

## 14. Feedback MVP

| Field | Value |
|-------|-------|
| **Status** | later |

---

## 15. Floor-first Host mode

| Field | Value |
|-------|-------|
| **Status** | later |

---

## 16. Backend targeted guest lookup by phone/email/name

| Field | Value |
|-------|-------|
| **Status** | **later** — before broader product release |
| **Scope** | Backend `guest-profiles` route or dedicated lookup endpoint; iOS client when needed |
| **Note** | Closest existing route is `GET /guest-profiles?q=` (fuzzy LIKE); no exact identity resolver yet |

---

## 17. iOS backend fallback lookup when local cache incomplete

| Field | Value |
|-------|-------|
| **Status** | **later** — after #16 or hardened `q=` use |
| **Scope** | `GuestLookupStore`, `GuestProfileSyncService` — fallback only when `fullListSyncCompleted == false` or no local match with strong phone/email input |
| **Do not** | Call backend on every keystroke |

---

## 18. Detail blob persistence for opened full guest profiles

| Field | Value |
|-------|-------|
| **Status** | **later** |
| **Scope** | `GuestProfileRepository`, `GuestProfileStore` — persist `booking_history` / `notes_history` JSON on detail fetch |
| **Note** | Schema slots exist; list sync does not populate detail blobs |

---

## 19. Guest profile re-sync on foreground / mutations

| Field | Value |
|-------|-------|
| **Status** | **later** — optional follow-up |
| **Scope** | `AppReservationSession`, `GuestProfileSyncService` — currently syncs once per session after startup deferral |

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
| Guests tab + detail local-first cache wiring | `67e02d2` |
| Host freshness + idle snapshot flicker polish | `71601fc` |
| Host Intelligence card presentation stability | `39f7fcb` |
| Guest person-map Slice 1 — sync completeness + full cache lookup | `d541488` |

---

## Parked / not v1

| Item | Reason |
|------|--------|
| **Offline manual reservation queue** | Explicitly not v1 |
| **Broad Host redesign** | After stabilization |
| **Full AI clustering / “knows each other” / local semantic tags** | Not started |
| **VIP editor** | No backend guest-level notes contract |
| Multi-tenant rewrite | Post-V1 |
| SMS automation | Owner decision |
| New LLM feature work | Host Intelligence local model is wording-only |

---

## Deploy artifacts

- `Backend/*.zip` is **gitignored** — build locally when deploying.
- Zip must wrap files in `tryzub-reservations-api/` folder for WordPress plugin update.
