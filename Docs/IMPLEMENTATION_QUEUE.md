# Implementation Queue

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)

Ordered slices for **V1**. Stabilization items (#4, #4b, #4c, #4d) remain open. Guest memory foundation (#7–#9), Guests tab cache wiring (#5), guest person-map Slice 1 (#5d), backend guest person-map Slice 2 lookup (#16), backend 3M-B (#18), iOS Slices 3A/3B/3R/3M, Manual Intake input polish (#17b), Tryzub V1 Host production polish (#5b, #5c), and **device smoke Phases 1–4 (#24–#27)** are **done in code**.

**Current focus:** (1) **4C-SMOKE** — stale reservation-source fallback open; (2) **4D-1** parent briefing packet / richer named facts from all intelligence layers; (3) **4E** human host/admin narrative — local model wording only, reused on Host Board + More; (4) physical device verification + release smoke; (5) reservation attachments live verification (build **13**). See [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md), [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md).

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
| **Status** | **done** — backend `a2422d3`, root pointer `fa15d22` |
| **Scope** | Backend `AI`: `tryzub_reservation_attachments` table, private disk storage, staff-auth list/upload/patch/delete/content routes, activity log |
| **Handoff** | [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md) §8 Slice A |

---

## 29. Reservation Attachments Slice B — deploy + backend manual tests

| Field | Value |
|-------|-------|
| **Status** | **done** — deployed + production-smoked 2026-06-26 |
| **Scope** | WordPress deploy, private path hardening, curl checklist on production |
| **Handoff** | [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md) §9 |
| **Notes** | Core staff API passed; direct **image** URL 404; unauthenticated REST content 401; directory marker cached 200 text/html — host hardening recommended, not blocking. HEIC/oversize/PDF optional; iOS V1 JPEG upload only. |

---

## 30. Reservation Attachments Slice C — iOS DTO/API/cache

| Field | Value |
|-------|-------|
| **Status** | **done** — `17a0bee` |
| **Scope** | `ReservationsAPIClient`, attachment DTOs, `ReservationAttachmentRecord` remote fields, `AttachmentFileStore` download cache, backend label mapping |
| **Notes** | `AttachmentFeatureFlag.remoteUploadEnabled` remains **false**; `ReservationDetailView` unchanged; no automatic remote fetch on reservation refresh |

---

## 31. Reservation Attachments Slice D — Reservation Detail sync UI

| Field | Value |
|-------|-------|
| **Status** | **done** — `d947721` |
| **Scope** | `ReservationDetailView` orchestration: remote list/upsert/download/upload/delete, local-only preservation, progress/errors; `remoteUploadEnabled` **true** |
| **Notes** | API calls detail-scoped only; no normal refresh attachment downloads; old pre-sync local-only attachments not auto-shared — staff may need to reattach; live/cross-device verification still open |

---

## 32. Reservation Attachments Slice E — management UI polish

| Field | Value |
|-------|-------|
| **Status** | **done** — `9d2784d` |
| **Scope** | Staff-friendly attachment rows; manage/details sheet; tag + note edit; fit-to-screen preview; manage delete; shared PATCH via `updateReservationAttachment`; local-only SwiftData edit; `deletedRemote` skipped by note signals |
| **Notes** | Build **12** tracked (`f2e9be0`); TestFlight build 12 upload pending (build 11 already submitted) |

---

## 33. Reservation Attachments — live cross-device verification

| Field | Value |
|-------|-------|
| **Status** | **current** — Slice E polish done; live verification not run |
| **Scope** | Multi-device + fresh-install recovery tests; fix-only follow-ups (incl. upload/list race if observed) |
| **Handoff** | [RESERVATION_ATTACHMENTS.md](./RESERVATION_ATTACHMENTS.md) §9 |

---

## 34. P0-CPU-1A — Bookings Needs Review row insight cache

| Field | Value |
|-------|-------|
| **Status** | **done in code** — `ReservationsListView.swift` (`ReservationScheduleView`) |
| **Scope** | Move `NewBookingRowInsightBuilder.build` off `ForEach`/body into keyed MainActor `.task` cache; use `GuestInsightLocalPool.boundedPool`; generation guard; row render = dict lookup |
| **Notes** | **P0-CPU-1A implemented; build passed; device verification open.** Do not claim Bookings performance fully fixed. |

---

## 35. P0-CPU-1B — NewBookingsIntelligenceCard aggregate summary (follow-up)

| Field | Value |
|-------|-------|
| **Status** | **open** — fix only if Bookings remains heavy after 1A device smoke |
| **Scope** | `NewBookingsIntelligenceSummary.build` in `body` when `scope == .needsReview` still runs aggregate `GuestInsightsController().analyze` |
| **Notes** | **P0-CPU-1B:** NewBookingsIntelligenceCard aggregate summary still runs body-time analysis; fix only if Bookings remains heavy after 1A smoke. |

---

## 36. P0-CPU-1C — HostBoardSnapshot body fallback (follow-up)

| Field | Value |
|-------|-------|
| **Status** | **open** — separate PR from Bookings |
| **Scope** | `HostBoardView` synchronous snapshot build in `body` fallback |
| **Notes** | Host-only; do not bundle with P0-CPU-1A/B |

---

## 37. P0-DETAIL-1 — Cache Detail guest truth per reservation fingerprint

| Field | Value |
|-------|-------|
| **Status** | **done in code** — `84f210c` |
| **Scope** | `ReservationDetailView.swift`, `GuestHistorySemantics.swift` — keyed `detailGuestTruthFingerprint` + `DetailGuestTruthBundle`; body reads cache only |
| **Notes** | **Smoke-supported.** `DETAIL_TRUTH_CACHE_TRACE` rebuild/publish/skip by semantic fingerprint. Activity, attachments, profile fetches, status mutations unchanged. **Do not claim** final physical smoke passed. |

---

## 38. P0-LOCALMODEL-1 — Defer Detail note analysis until model is warm and idle

| Field | Value |
|-------|-------|
| **Status** | **done in code** — `4e4c274` |
| **Scope** | `ReservationDetailView.swift` — deterministic `recomputeNoteSignals()` immediate; model enrichment via keyed `.task` + `LOCAL_MODEL_GATE_TRACE` |
| **Notes** | **Smoke-supported.** Detail open no longer cold-loads 3B model. **Do not claim** final physical smoke passed. |

---

## 39. P0-HOST-2B — Remove Host inline full-history returning scan

| Field | Value |
|-------|-------|
| **Status** | **done** — `ec63d26` |
| **Scope** | `HostIntelligenceInlineItem.swift` — map returning inline chips from `snapshot.guestSignals` instead of `ReturningGuestHistoryIndex(records: knownReservations)` |
| **Notes** | Trace: `using_snapshot_guest_signals`. Device verification open. |

---

## 40. LOCAL-FIRST-OPS-4C-1 — More reads canonical Service Intelligence snapshot

| Field | Value |
|-------|-------|
| **Status** | **done** — `2227d8d` |
| **Scope** | `GlobalServiceIntelligenceView.swift` — reads `serviceIntelligenceSnapshot`; Service facts section; legacy fallback |
| **Notes** | `[SERVICE_INTEL_UI_TRACE] surface=more_service_intelligence` |

---

## 41. LOCAL-FIRST-OPS-4C-2 — Preserve snapshot across Host hide

| Field | Value |
|-------|-------|
| **Status** | **done** — `50b207a` |
| **Scope** | `HostIntelligenceController.resetVolatilePresentation`, `HostBoardView` hide path |
| **Notes** | `[SERVICE_INTEL_LIFECYCLE_TRACE] event=preserve_snapshot_on_hide` |

---

## 42. LOCAL-FIRST-OPS-4C-3 — Reservation-source fingerprint stale guard

| Field | Value |
|-------|-------|
| **Status** | **done** — `50b207a` |
| **Scope** | `serviceIntelligenceSourceFingerprint`, `isServiceIntelligenceSnapshotCurrent` |
| **Notes** | More `stale_source_fingerprint` fallback; attachment/guest-intel/floor not in fingerprint — follow-up optional |

---

## 43. LOCAL-FIRST-OPS-4C-SMOKE — Runtime verification (open)

| Field | Value |
|-------|-------|
| **Status** | **open** — partial pass |
| **Scope** | Device traces for snapshot build, More use_snapshot, date transition, stale reservation-source fallback |
| **Passed** | Host snapshot build; More use_snapshot after Host hide; date transition clear; snapshot_source_current |
| **Open** | Stale reservation-source fallback after reservation change while Host hidden |

---

## 44. LOCAL-FIRST-OPS-4D-1 — Parent briefing packet / richer named facts

| Field | Value |
|-------|-------|
| **Status** | **open** — next deterministic slice |
| **Scope** | Expand `HostServiceIntelligenceSnapshotBuilder` + parent briefing packet from all intelligence layers: reservations, floor/seated timing, guest memory, notes, attachments, reminders, business analytics, walk-ins/completed/no-shows, activity |
| **Notes** | Deterministic only; canonical snapshot = what is true; parent packet = all facts the system can safely talk about; no LLM in 4D-1 |

---

## 45. LOCAL-FIRST-OPS-4E-1 — Local model narrative (human host/admin tone)

| Field | Value |
|-------|-------|
| **Status** | **open** |
| **Scope** | Validator-protected local model prose from parent briefing packet; human host/admin/manager voice — not “staff needs review” or technical signal labels |
| **Notes** | LLM = wording only, never truth; template fallback on failure |

---

## 46. LOCAL-FIRST-OPS-4E-2 — Reuse narrative on Host Board and More

| Field | Value |
|-------|-------|
| **Status** | **open** |
| **Scope** | Same validated narrative on Host Board compact intelligence and More → Service Intelligence full briefing when cache valid |
| **Notes** | Cache by date + snapshot/packet fingerprint + model/prompt version; More must not trigger model load independently |

---

## 47. LOCAL-FIRST-OPS-4E-3 — Live / manual briefing refresh

| Field | Value |
|-------|-------|
| **Status** | **open** |
| **Scope** | Truth-safe refresh when service state changes during shift; manual refresh path; validator-protected; no stale narrative after reservation/floor/seated changes |
| **Notes** | Must respect snapshot lifecycle + source fingerprint; invalidates narrative cache when packet fingerprint changes |

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
| Reservation attachments backend Slice A+B | `a2422d3` (backend), production-smoked |
| Reservation attachments iOS Slice C — DTO/API/cache | `17a0bee` |
| Reservation attachments iOS Slice D — Detail sync UI | `d947721` — `remoteUploadEnabled` true |
| Reservation attachments iOS Slice E — management UI polish | `9d2784d` |
| Build 13 project settings | `2227d8d` — tracked |
| LOCAL-FIRST-OPS-4C-1 — More reads canonical snapshot | `2227d8d` |
| LOCAL-FIRST-OPS-4C-2 — Preserve snapshot across Host hide | `50b207a` |
| LOCAL-FIRST-OPS-4C-3 — Reservation-source fingerprint stale guard | `50b207a` |
| P0-HOST-2B — Remove Host inline full-history returning scan | `ec63d26` |
| LOCAL-FIRST-OPS-4A — Build unified deterministic per-date Service Intelligence snapshot | `f0554a3` |

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
