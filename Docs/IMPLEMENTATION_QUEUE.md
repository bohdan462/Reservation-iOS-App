# Implementation Queue

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)

Ordered slices for **V1**. Stabilization items (#4, #4b, #4c, #4d) remain open. Guest memory foundation (#7–#9), Guests tab cache wiring (#5), guest person-map Slice 1 (#5d), backend guest person-map Slice 2 lookup (#16), backend 3M-B (#18), iOS Slices 3A/3B/3R/3M, Manual Intake input polish (#17b), Tryzub V1 Host production polish (#5b, #5c), and **device smoke Phases 1–4 (#24–#27)** are **done in code**.

**Current focus:** (1) physical device verification + release smoke test (backend `63d0cfc` **deployed**); (2) **reservation attachments backend-sync** — see [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md). **Next attachment code slice:** **Attachment Slice A** (backend only). **Next guest person-map code slice:** **3D** (parked until smoke verification accepted or Bohdan resumes).

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

## 4b. Confirmation mode on physical device

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
| **Scope** | End-to-end staff ops on physical device (iPhone and iPad) |
| **Include** | Guest profile background sync (`0f06852`); guest full-list sync completion (`d541488`); manual walk-in + known-guest intake (`0a89caa`); Guests tab + detail cache (`67e02d2`); Guests tab explicit all-record lookup + View history shell (`1dfa14a`); Regulars cache-first + View history (`50df843`); Manual Intake walk-in validation + guest lookup (`e775f52`); Manual Intake input polish (`ad5d274`); backend unknown walk-in (`63d0cfc`, deployed); Host freshness (`71601fc`); Host Intelligence card stability (`39f7fcb`); **device smoke Phases 1–4 verification** ([DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) §10) |
| **Guest memory checks** | Full-list sync eventually marks complete; Guests/manual intake finds known guest outside old 500 cap; no backend call on every phone digit; Guests tab explicit search only (not per keystroke); incomplete full-list sync does not wait on TTL before retrying full sync |
| **Host header checks** | Header shows `Last sync HH:mm`; stale secondary reason when refresh skipped/stale; Live-on today does not sit stale without explanation; manual refresh bumps `Last sync` on success |
| **Host flicker checks** | Quiet Host board does not rebuild/flicker every minute from idle snapshot timing; Host Intelligence card chips do not disappear/reappear when intelligence refreshes; during service, seated/due/nearby rows still update timing |

---

## 4d. Device smoke verification (Phases 1–4 code landed)

| Field | Value |
|-------|-------|
| **Status** | **current** — code at `804c130` → `3da3a68`; physical verification not done |
| **Scope** | Layout/hit-testing, walk-in workflow, row indicators, email settings cleanup |
| **Checklist** | [DEVICE_SMOKE_FINDINGS_HANDOFF.md](./DEVICE_SMOKE_FINDINGS_HANDOFF.md) §10 |
| **Do not overstate** | Code landed ≠ device smoke passed |

---

## 24. Device smoke Phase 1 — layout and hit-testing

| Field | Value |
|-------|-------|
| **Status** | **done** — `804c130` |
| **Scope** | Live button hit area; bottom tab clearance; Manual Intake keyboard-safe guest candidates |
| **Do not overstate** | Physical device verification still open (#4d) |

---

## 25. Device smoke Phase 2 — walk-in workflow

| Field | Value |
|-------|-------|
| **Status** | **done** — `8eab6c4` |
| **Scope** | Seated-now walk-ins; seated duration; attach known guest; walk-in validation; Floor Plan table assignment |
| **Do not overstate** | Physical device verification still open (#4d) |

---

## 26. Device smoke Phase 3 — row indicators

| Field | Value |
|-------|-------|
| **Status** | **done** — `5762ecb` |
| **Scope** | Auto-confirmed, confirmation email sent, reminder sent on list rows without detail open |
| **Do not overstate** | Physical device verification still open (#4d) |

---

## 27. Device smoke Phase 4 — email settings cleanup

| Field | Value |
|-------|-------|
| **Status** | **done** — `3da3a68` |
| **Scope** | Removed More → Email Controls; **This Device Email** under Restaurant Settings; backend reminders/auto-confirm unchanged |
| **Do not overstate** | No sending behavior changed; physical device verification still open (#4d) |

---

## 5. Guests tab + detail local-first guest cache wiring

| Field | Value |
|-------|-------|
| **Status** | **done** — `67e02d2` |
| **Scope** | `GuestLookupView`, `ReservationDetailView`, `GuestProfileRepository` |
| **Delivered** | Guests tab reads `GuestProfileCacheRecord`; result cards show compact guest memory metadata; detail disk cache preview before memory/network; explicit all-record lookup + shared Guest history shell (`1dfa14a`); Regulars cache-first (`50df843`) |

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

## 11. RegularGuestsView disk-first (Slice 3R)

| Field | Value |
|-------|-------|
| **Status** | **done** — `50df843` |
| **Scope** | `RegularGuestsView`, `ReservationsListView`, `GlobalServiceIntelligenceView` |
| **Delivered** | Primary list from `@Query` `GuestProfileCacheRecord`; local search/filter/sort; honest sync copy; tap opens `GuestProfileDetailView(guestKey:)`; removed network page-25 primary UI and “Showing 25 of 101” copy; `environment` passed from More and Service Intelligence |
| **Do not overstate** | Background `GuestProfileSyncService` still refreshes cache; full history UI remains Slice 3D; detail JSON persistence remains Slice 3E |

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
| **Status** | **done** — backend `1431a06`, root pointer `b1a09e7`; **deployed** to WordPress |
| **Scope** | `GET /guest-profiles/lookup` in `guest-profiles.php`, `routes.php`, backend `README.md` |
| **Delivered** | Staff-auth lookup doorway; exact email + 10+ digit phone strong; 7–9 digit phone and name-only possible; compact summaries with `match_basis` / `match_confidence`; safe strong-only `best_match_*`; no rebuild/scan/public tokens |
| **Do not overstate** | iOS calls route from Guests tab explicit search only (`1dfa14a`); name-only is never canonical; full list/detail endpoints unchanged; **device lookup smoke tests still open** |

---

## 17. Manual Intake backend lookup + walk-in/call-in validation (Slice 3M)

| Field | Value |
|-------|-------|
| **Status** | **done** — `e775f52` (depends on backend `63d0cfc` for unknown walk-in save) |
| **Scope** | `ManualReservationFormView`, `GuestLookupStore`, `GuestLookupModels`, `GuestProfileStore` |
| **Delivered** | Walk-in optional identity (blank fields sent); call-in name+phone required; local name/phone/email search while typing; explicit Search all guest records; Use guest + View history → `GuestProfileDetailView`; removed phone-only suggestion UI |
| **Do not** | Call backend on every keystroke; auto-select candidates |
| **Do not overstate** | Full booking/notes timeline remains Slice 3D; detail JSON persistence remains Slice 3E; `schedulePhoneLookup` dead code cleanup remains P3; input polish (`ad5d274`) does not replace device smoke |

---

## 17b. Manual Intake input polish (post-3M)

| Field | Value |
|-------|-------|
| **Status** | **done** — `ad5d274` |
| **Scope** | `ManualReservationFormView.swift`, `GuestLookupStore.swift` |
| **Delivered** | Review sheet before create (no direct create); removed pre-create `GuestTextMessageActionButtons`; Reservation Detail confirm/message unchanged; keyboard Next/Done; DEBUG-only focus trace; debounced local lookup (250–300 ms); phone search from 7 digits; capped candidates; 3M walk-in/call-in preserved |
| **Do not overstate** | Device smoke tests still open; full Guest history remains Slice 3D |

---

## 18. Backend walk-in create without required name/phone (Slice 3M-B)

| Field | Value |
|-------|-------|
| **Status** | **done** — backend `63d0cfc`, root pointer `c7f5a69`; **deployed** to WordPress |
| **Scope** | `managed-reservations.php`, `formatting.php`, `validation.php`, `intelligence-helpers.php`, `guest-profiles.php`, `emails.php`, backend `README.md` |
| **Delivered** | `manual_walk_in` without name/phone/email; call-in still requires name+phone; placeholder masking; no fake `guest_key`/profiles; placeholder email not sendable |
| **Note** | iOS `e775f52` sends blank identity fields — backend owns `Walk-in guest` display |

---

## 19. Detail blob persistence for opened full guest profiles (Slice 3E)

| Field | Value |
|-------|-------|
| **Status** | **later** |
| **Scope** | `GuestProfileRepository`, `GuestProfileStore` — persist `booking_history` / `notes_history` JSON on detail fetch for disk-first full profile reopen |
| **Note** | Schema slots exist; list sync does not populate detail blobs; `hasDetailPayload` can be true while JSON fields remain nil today |

---

## 20. Guest person-map Slice 3A — iOS lookup foundation

| Field | Value |
|-------|-------|
| **Status** | **done** — `823f42c` |
| **Scope** | `GuestProfileDTO.swift`, `ReservationsAPIClient.swift`, `GuestProfileStore.swift`, `GuestLookupModels.swift`, `GuestLookupStore.swift` |
| **Delivered** | DTO/API/client for `GET /guest-profiles/lookup`; `GuestProfileStore.lookupProfiles(...)` with task dedupe; MainActor SwiftData upsert; candidate metadata preserved; no UI triggers |

---

## 21. Guest person-map Slice 3B — Guests tab lookup UI + shared history shell

| Field | Value |
|-------|-------|
| **Status** | **done** — `1dfa14a` |
| **Scope** | `GuestLookupView.swift`, `GuestProfileDetailView.swift` |
| **Delivered** | Explicit Search all guest records; local typing unchanged; Likely guest / Possible match; View history + Book reservation; `GuestProfileDetailView` summary shell by `guestKey` |
| **Do not overstate** | Not full booking/notes timeline; not Reservation Detail integration; not disk-first full detail (3E) |

---

## 22. Guest person-map Slice 3D — full shared Guest history UI

| Field | Value |
|-------|-------|
| **Status** | **later** — **parked** until device smoke verification accepted or Bohdan resumes |
| **Scope** | `GuestProfileDetailView` + extract/reuse from `GuestInsightsView` / `GuestServiceProfilePresentation` — booking history timeline, guest/staff notes timeline, source mix, usual party/day/time; wire Reservation Detail to shared destination when `guestKey` known (3D-a); booking-history row → local `ReservationDetailView` when cached, otherwise read-only |
| **Primary data** | Backend `GET /guest-profiles/{guest_key}` detail DTO (`bookingHistory`, `notesHistory`, etc.) |

---

## 23. Guest profile re-sync on foreground / mutations

| Field | Value |
|-------|-------|
| **Status** | **later** — optional follow-up |
| **Scope** | `AppReservationSession`, `GuestProfileSyncService` — currently syncs once per session after startup deferral |

---

## 28. Reservation Attachments Slice A — backend private storage + DB/routes

| Field | Value |
|-------|-------|
| **Status** | **current** — not started |
| **Scope** | Backend `AI` from `63d0cfc`: `tryzub_reservation_attachments` table, private disk storage, staff-auth list/upload/patch/delete/content routes, activity log |
| **Handoff** | [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md) §8 Slice A |
| **Do not touch** | iOS, guest self-service, confirmation/reminder flows |
| **Do not start iOS** until Slice A deployed and Slice B manual tests pass |

---

## 29. Reservation Attachments Slice B — deploy + backend manual tests

| Field | Value |
|-------|-------|
| **Status** | **current** — blocked on Slice A |
| **Scope** | WordPress deploy, private path hardening, curl checklist on staging/production |
| **Handoff** | [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md) §9 |

---

## 30. Reservation Attachments Slice C — iOS DTO/API/cache

| Field | Value |
|-------|-------|
| **Status** | **current** — blocked on Slice B |
| **Scope** | `ReservationsAPIClient`, attachment DTOs, `ReservationAttachmentRecord` remote fields, `AttachmentFileStore` download cache |
| **Do not touch** | Second API client; SwiftData blobs |

---

## 31. Reservation Attachments Slice D — Reservation Detail sync UI

| Field | Value |
|-------|-------|
| **Status** | **current** — blocked on Slice C |
| **Scope** | `ReservationDetailView`, upload progress, server list/delete/patch, enable `remoteUploadEnabled` |
| **Do not touch** | Confirm/Mail, device smoke code |

---

## 32. Reservation Attachments Slice E — two-device verification

| Field | Value |
|-------|-------|
| **Status** | **current** — blocked on Slice D |
| **Scope** | Multi-device + fresh-install recovery tests; fix-only follow-ups |
| **Handoff** | [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md) §9 |

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
| Backend guest person-map Slice 2 — staff profile lookup | `1431a06` (backend), `b1a09e7` (root pointer); **deployed** |
| iOS guest person-map Slice 3A — lookup foundation | `823f42c` |
| iOS guest person-map Slice 3B — Guests tab lookup UI + shared history shell | `1dfa14a` |
| iOS guest person-map Slice 3R — Regulars cache-first + shared Guest history | `50df843` |
| Backend guest person-map Slice 3M-B — unknown walk-in without guest identity | `63d0cfc` (backend), `c7f5a69` (root pointer); **deployed** |
| iOS guest person-map Slice 3M — Manual Intake walk-in validation + guest lookup | `e775f52` |
| Manual Intake input polish — review sheet, no pre-create messages, keyboard/debounce | `ad5d274` |
| Device smoke Phase 1 — layout / hit-testing | `804c130` |
| Device smoke Phase 2 — walk-in workflow | `8eab6c4` |
| Device smoke Phase 3 — row indicators | `5762ecb` |
| Device smoke Phase 4 — email settings cleanup | `3da3a68` |

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
