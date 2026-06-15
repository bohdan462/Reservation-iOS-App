# Tryzub Reservations — current-state audit

**Branch:** `audit-current-state`  
**Audit date:** 2026-06-14  
**Auditor basis:** Swift source code (truth); docs used as clues only  
**Scope:** iOS staff app stabilization — no code changes in this pass

---

## 1. Executive summary

### What is healthy

- **Clear backend truth model** in code: managed reservations API is authoritative; SwiftData is cache; `POST /import` is not in the API client normal path.
- **Unified active-window sync** converges on `ReservationsController.performActiveWindowRefresh` → `ReservationSyncService` → `ReservationRepository`.
- **Cache-first startup** releases UI from local SwiftData before network (`releaseStartupUIFromLocalCacheIfAvailable`).
- **Mail-first confirmation MVP** (`beginPrimaryConfirmFlow`) with `isBackendConfirmEmailEnabled = false` — staff sends styled HTML via Mail, logs `manual_sent`, then PATCHes confirmed.
- **Activity history** is read-only on iOS; backend writes on mutation; `ReservationActivityStore` + invalidation wired.
- **Host intelligence engine** is deterministic for facts/actions; local model is wording-only with template fallback.
- **Floor plan backend path** exists (`PATCH /tables`) with `FloorPlanStore` as canonical when layout resolves.
- **Guest communication cleanup** shipped: shared `GuestEmailTemplateRenderer`, shift reminders sheet, staff review before send.

### What is risky

| Risk | Severity |
|------|----------|
| **Delta sync never deletes** stale/moved/hidden rows until full active-window replace | High |
| **`isContentEquivalent` skips writes** for `confirmationEmailSentAt`, `reminderEmailSentAt`, `supersededById`, `sourceType`, etc. | High |
| **Dual 60s auto-refresh loops** (Host + Bookings) with asymmetric gating (Host today-only vs Bookings any date) | Medium |
| **Legacy dead sync paths** still in controller (`performTodayRefresh`, `syncAllReservations`, etc.) — audit noise | Low |
| **Dual table assignment** (canonical `/tables` vs legacy `tableName` PATCH) without strong staff UI distinction | Medium |
| **Guest intel 180s TTL** without `FreshnessCoordinator`; local_bounded mode can disagree with server | Medium |
| **Host AI prose** hidden from staff (`staffFacingPresentation` suppresses “local model” caption) | Medium |
| **Optimistic status PATCH** writes SwiftData before server confirms | Medium |
| **Documentation drift** — handoffs described gaps now fixed; testing doc still says PATCH-only confirm | High (trust) |

### What is fighting each other

1. **Full vs delta sync** — delta is fast but leaves ghost rows; mutations mark scope “fresh” and can delay full replace.
2. **Multiple refresh owners** — startup pass, tab activation, manual refresh, Host 60s loop, Bookings 60s loop, history prefetch, floor 60s loop — coalesced via `activeWindowRefreshTask` but still duplicate evaluation.
3. **Guest intelligence sources** — backend profile pack vs date summary vs SwiftData local pool vs note heuristics — merge rules exist (`GuestHistorySemantics`) but loading races confuse staff.
4. **Table truth** — `FloorPlanStore` backend layout vs `HostTableConfigStore` UserDefaults advisory vs legacy `tableName` string.
5. **Confirm semantics** — UI “Confirm” opens Mail; status may still read `new` until mail `.sent`; staff without email gets immediate PATCH (`markConfirmedWithoutEmail`).
6. **Old docs vs code** — `IOS_ADMIN_TESTING.md`, `PROJECT_METHOD_MAP.md` still describe pre-cleanup flows.

### What must not be changed (product truths)

1. Backend managed-reservations = reservation truth.
2. SwiftData = cache only.
3. No Flamingo reads in normal workflow.
4. No `POST /import` in normal workflow.
5. Activity history backend-written, iOS read-only.
6. Backend floor plan canonical when available.
7. Local model / Host AI = wording only — no mutations.
8. Guest intelligence must not overclaim; identity strength matters.
9. Staff trust > cleverness; no confident UI over uncertain data.
10. No auto-send email/SMS in V1 without backend safeguards.

### What should be fixed first (stabilization order)

See §9 and [OPEN_WORK.md](./OPEN_WORK.md). Top 5:

1. **Predictable refresh policy** — document and enforce when full replace runs; reduce ghost rows.
2. **Expand `isContentEquivalent` or force field merge** for email timestamps and superseded flags.
3. **Unify auto-refresh gating** between Host and Bookings.
4. **Confirm UI truthfulness** — status/copy until `manual_sent` + PATCH complete.
5. **Retire or gate legacy table assignment** when backend layout exists.

---

## 2. Source-of-truth audit

| Domain | Canonical truth | iOS representation | Stale/mislead risk |
|--------|-----------------|-------------------|-------------------|
| **Reservations** | `GET/PATCH/POST /managed-reservations` | `ReservationRecord` in SwiftData | Delta leaves deleted rows; equivalence skip |
| **SwiftData** | Cache mirror | `@Query` across tabs | Not authoritative; can show hidden/superseded until full sync |
| **Floor plan** | `GET /floor-plan`, `GET/PUT /restaurant-tables`, `PATCH /tables` | `FloorPlanStore.cacheByDate` | 60s TTL; legacy fallback bypasses conflicts |
| **Activity history** | Backend writes on mutation | `ReservationActivityStore` (memory, 90s TTL) | Empty for pre-1.7.0 rows; stale until invalidation |
| **Guest intelligence** | `GET /guest-intelligence` (+ reservation profile) | `GuestIntelligenceStore` | 180s cache; `local_bounded` uses SwiftData heuristics |
| **Business analytics** | `GET /business-intelligence/summary` | `BusinessIntelligenceStore` | 600s cache |
| **System/pipeline health** | `GET /intelligence/system-status` | `IntelligenceSystemStatusStore` | 600s cache |
| **Reservation analytics (ops)** | `GET /reservation-analytics/summary` | `RestaurantSettingsStore` slice | 600s cache |
| **Host intelligence facts** | `HostIntelligenceEngine` (deterministic) | Recomputed; not persisted as truth | Attention card preservation can show old facts |
| **Local model** | Template fallback | `HostLlamaBriefingRuntime`, `GuestMessageDraftService` | Must never mutate; validator blocks leaks |
| **Email/confirm/reminders** | Staff Mail + `manual-email-log` | `GuestEmailTemplateRenderer`, `ShiftReminderReviewSheet` | `POST /confirm` disabled; manual/custom skips backend log |

---

## 3. Lifecycle conflict audit

| Owner | Role today | Verdict |
|-------|------------|---------|
| **ReservationsController** | God-object: sync, mutations, startup, capabilities, notices, availability, email log, scope freshness | **Keep** — consolidate callers; extract only after stabilization |
| **ReservationSyncService** | Active-window full/delta; legacy methods unused | **Keep** — delete dead methods in V1.1 cleanup |
| **ReservationMutationService** | PATCH/POST/DELETE/reconcile | **Keep** |
| **ReservationRepository** | SwiftData upsert/replace/delete | **Keep** — fix equivalence |
| **ReservationsListView** | Tab shell, Bookings, More, startup gate | **Keep** — split files later |
| **HostBoardView** | Host UI + 60s loop + intelligence input | **Keep** |
| **FloorPlanStore** | Floor cache, assign, 60s refresh | **Keep** — wire FreshnessCoordinator consistently |
| **GuestIntelligenceStore** | Server guest intel cache | **Keep** — add FreshnessCoordinator or shared invalidation |
| **BusinessIntelligenceStore** | BI summary cache | **Keep** |
| **IntelligenceSystemStatusStore** | Pipeline health cache | **Keep** |
| **RestaurantSettingsStore** | Setup, hours, slots, analytics | **Keep** |
| **ManualReservationFacade** | Read model for manual form | **Keep** |
| **ReservationAvailabilityFacade** | Availability read model | **Keep** |
| **GuestProfileFacade** | Merges server + local guest profile | **Keep** — strengthen loading/uncertainty copy |
| **HostIntelligenceController** | Engine + optional LLM wording | **Keep** — add staff-facing beta labels |
| **HostBoardLifecycleCoordinator** | Defers optional Host loads | **Keep** |
| **FreshnessCoordinator** | Session-scoped TTL/coalescing | **Keep** — extend to guest intel |
| **ReservationActivityStore** | Activity feed cache | **Keep** |
| **HiddenReservationsStore** | Session soft-hide overlay | **Keep** — not synced to server hide |
| **HostTableConfigStore** | Advisory local table inventory | **Keep** — label clearly non-canonical |

---

## 4. Refresh / task / timer audit

| File / type | Trigger | Frequency | isActive gated? | Network? | SwiftData write? | Cancellation? | Duplicate? | Risk | Recommendation |
|-------------|---------|-----------|-----------------|----------|------------------|---------------|------------|------|----------------|
| `StartupRootView` `.task` | App launch | Once | N/A | Via controller | Via sync | Task cancel on deinit | With session warmup | Low | Keep |
| `performStartupNetworkPass` | `loadIfNeeded` | Once | N/A | Active window | Full/delta | `startupNetworkPassTask` | — | Med | Keep; trace skip reasons |
| `startBackgroundStartupDelta` | Cache hit + stale | Once | After UI release | Delta | Upsert only | Utility task | — | Med | Schedule periodic full |
| `requestManualTodayRefresh` | Host pull/toolbar | On demand | `isVisible` | Forced full | Replace window | Coalesced | — | Low | Keep |
| `requestScheduleRefresh` | Bookings pull/toolbar | On demand | `isActive` | Forced full | Replace window | Coalesced | — | Low | Keep |
| `scheduleBecameActive` | Bookings tab show | On tab | `isActive` | Full if stale 300s | Replace | — | With auto loop | Med | Debounce with auto |
| `HostBoardView.runAutoRefreshLoop` | Host visible | 60s | `isVisible && isAppActive` (today) | Delta/full policy | Upsert/replace | `.task` cancel | Bookings loop | **High** | Align gating with Bookings |
| `runBookingsAutoRefreshLoop` | Bookings tab | 60s | `isActive` + scene active | Delta/full policy | Upsert/replace | `.task` cancel | Host loop | **High** | Same |
| `scheduleHistoryPrefetchWhenReady` | Post-startup | ≤1/12h | Guards | Paginated GET | Upsert only | `historyPrefetchTask` | — | Med | Keep; never delete |
| `FloorPlanStore` auto | Floor tab today | 60s | `isActive && isToday` | GET floor-plan | In-memory | Cancel on hide | Reservation sync | Low | Keep |
| `HostBoardLifecycleCoordinator` | Host visible/date | On change | `isVisible` | Floor, availability, guest intel | None (res) | Task identity | — | Low | Keep |
| `ReservationDetailDestinationView` | Missing row | On navigate | — | GET by id | Upsert | Once | — | Low | Keep |
| `loadScheduleAllPage` | Bookings All scope | Pagination | `isActive` | GET paged | Upsert only | Generation guard | — | Med | Upsert-only label in UI |
| `performTodayRefresh` | — | **Dead** | — | — | — | — | Active window | Low | Delete |
| `syncAllReservations` | — | **Dead** | — | — | — | — | Active window | Low | Delete |

---

## 5. Mutation audit

| Mutation | Endpoint | UI callers | Server result | Local cache | Activity | Failure | 404/conflict | Stale row risk | Fix needed? |
|----------|----------|------------|---------------|-------------|----------|---------|--------------|----------------|-------------|
| Create manual | `POST /managed-reservations` | Manual form (Host/Bookings/Guests/More) | New row | Upsert response | Backend writes | Error notice | — | Low | No |
| Edit | `PATCH /managed-reservations/{id}` | Detail edit, notes | Updated row | Upsert | Yes | Revert optimistic? | Reconcile on uncertain | Med | Verify optimistic revert |
| Confirm only (no email) | `PATCH` status confirmed | `markConfirmedWithoutEmail` | confirmed | Optimistic + upsert | Yes | Error | — | Low | Copy says “without email” — OK |
| Confirm + email (MVP) | Mail → `manual-email-log` → `PATCH` | `beginPrimaryConfirmFlow` → `finalizeManualConfirmationAfterSend` | confirmed + log | Upsert reconcile | Yes | Partial failure message | — | Med | Status UI until sent |
| Backend confirm | `POST /confirm` | Gated off (`isBackendConfirmEmailEnabled=false`) | — | — | — | — | — | — | Do not enable V1 |
| Manual email log | `POST /manual-email-log` | Detail confirm, shift reminders | Log row | Optional reconcile | Yes | Non-blocking | — | Low | Manual/custom skips log |
| Guest manage link | `POST /guest-manage-link` | Detail, shift reminders | Link DTO | None | — | Error | — | — | No |
| Seat | `PATCH` status seated | Host, Detail | seated | Upsert | Yes | — | — | Low | No |
| Complete | `PATCH` completed | Host, Detail | completed | Upsert | Yes | — | — | Low | No |
| Cancel | `PATCH` cancelled | Host, Detail | cancelled | Upsert | Yes | — | — | Low | No |
| No-show | `PATCH` no_show | Host, Detail | no_show | Upsert | Yes | — | — | Low | No |
| No-show recovery | `PATCH` seated | Detail after no-show | seated | Upsert | Yes | — | — | Low | No |
| Hide wrong entry | `PATCH` is_hidden | Detail (dev/manager) | hidden | Upsert | Yes | — | — | Med | Session hide vs server hide |
| Restore hidden | `PATCH` unhide | Detail/More | visible | Upsert | Yes | — | — | Low | No |
| Hard delete | `DELETE ?force=1` | More/dev cleanup | gone | `deleteReservation` | Yes | Error | 404 | **High** other devices | Document no propagation |
| Table assign canonical | `PATCH /tables` | Floor, coordinator | assignment | Upsert + floor refresh | Yes | 409? | — | Med | Prefer always |
| Table assign legacy | `PATCH` tableName | Coordinator fallback | tableName string | Upsert | Yes | No conflict check | — | **High** | Warn/block when layout exists |
| Blocked slots | `DELETE` blocked slots | Settings | updated | Settings store | — | — | — | Low | No |
| Restaurant setup/hours | `GET/PATCH` setup | Settings, login | settings | In-memory + cache | — | — | — | Low | No |

---

## 6. SwiftData / cache audit

### Replace vs upsert

| Path | Method | Deletes local rows in window? |
|------|--------|------------------------------|
| Full active window | `replaceDateWindowYielding` | Yes — IDs in window not in response |
| Delta | `upsert` / `upsertYielding` | **No** |
| History prefetch | `upsertYielding` | No |
| Schedule All pagination | `upsert` | No |
| Mutations | `upsert` or `deleteReservation` | Hard delete only on force delete |

### `isContentEquivalent` gap

Compared: identity, guest fields, status, table, notes, `apiUpdatedAt`, hidden.  
**Not compared:** `confirmationEmailSentAt`, `reminderEmailSentAt`, `supersededById`, `sourceType`, `createdByDevice`, `hiddenAt`, etc.

**Risk:** Server updates email-sent timestamps or superseded linkage without changing compared fields → local row skipped → staff sees stale confirmation state.

### Hard delete propagation

Backend hard delete removes row on that device only after successful DELETE. Other cached devices retain row until full sync or reconcile — **expected**; staff must not assume multi-device instant removal.

### Guest Insights misleading cache

`GuestLookupStore` and `GuestInsightsController` read SwiftData pool. `GuestHistorySemantics` prioritizes server evidence, but loading races can show “prior visits” from local cache before server returns “first time.”

### Developer cache reset

Should: clear SwiftData reservations, reset sync cursors/scopes in controller, reset intelligence stores, reset floor cache. Verify in diagnostics (see DIAGNOSTICS_AND_TESTING.md).

---

## 7. UI trust audit

| Scenario | Current behavior | Trust risk | Recommendation |
|----------|------------------|------------|----------------|
| Confirmed before email sent | Status may be `new` until mail `.sent` + PATCH | Staff thinks unconfirmed while composing | Show “Confirming…” / pending email state |
| No guest email | Immediate PATCH without mail | OK if copy clear | Keep `markConfirmedWithoutEmail` message |
| Stale local reservation | Delta doesn't remove | Shows cancelled/moved rows | Force full on manual refresh; periodic full |
| Hidden/deleted still cached | Hidden filter + server hide | Row visible on other devices | Copy explains sync delay |
| Guest “regular” from local | Local pool match before server | Overclaim | Keep “not confirmed” captions |
| Host Intelligence urgency | Deterministic severity + preserved card | Old facts linger | Shorten preservation window |
| Local model briefing | Caption hidden in production card | AI sounds authoritative | Show “AI wording (beta)” staff-only |
| Bookings counts | Scope filters + hidden overlay | Count mismatch | Trace already present; verify |
| Service pressure copy | Deterministic booking load | Can feel alarmist | Keep operational tone |
| Floor/table conflict | Legacy path silent | Wrong table assigned | Block legacy when backend layout exists |
| Analytics pipeline health | 600s cached BI/status | Stale “healthy” | Show loaded-at timestamp |
| Activity empty | Pre-1.7.0 or no events | Looks like bug | Explain in UI |

---

## 8. Documentation rewrite plan

### Proposed migration table

| Current file | Action | New home |
|--------------|--------|----------|
| `DOCS_INDEX.md` | **CREATE** | Navigation hub |
| `AUDIT_CURRENT_STATE.md` | **CREATE** | This file |
| `OPEN_WORK.md` | **CREATE** | Stabilization backlog |
| `IOS_ARCHITECTURE.md` | **CREATE** | App structure |
| `IOS_LIFECYCLE_AND_SYNC.md` | **CREATE** | Sync/refresh |
| `RESERVATION_WORKFLOWS.md` | **CREATE** | Staff workflows |
| `FLOOR_PLAN_AND_TABLES.md` | **CREATE** | Merges TABLE_CONFIGURATION |
| `HOST_INTELLIGENCE.md` | **CREATE** | Host AI + engine |
| `DIAGNOSTICS_AND_TESTING.md` | **CREATE** | Replaces IOS_ADMIN_TESTING |
| `README.md` | **UPDATE** banner | Backend contract (keep body) |
| `INTELLIGENCE.md` | **KEEP** | Add audit header |
| `LOCAL_MODEL_INTELLIGENCE.md` | **KEEP** | Wording boundaries |
| `ACTIVITY_HISTORY.md` | **KEEP** | Activity read model |
| `PROJECT_MAP.md` | **UPDATE_REQUIRED** | Trim; link to new docs |
| `PROJECT_METHOD_MAP.md` | **UPDATE_REQUIRED** or shrink to index |
| `ARCHITECTURE_DIAGRAMS.md` | **UPDATE_REQUIRED** | Refresh audit section |
| `IOS_ADMIN_TESTING.md` | **SUPERSEDED** | Point to DIAGNOSTICS_AND_TESTING |
| `TABLE_CONFIGURATION.md` | **SUPERSEDED** | Point to FLOOR_PLAN_AND_TABLES |
| `BACKEND_INTELLIGENCE.md` | **ARCHIVE** | Duplicate of INTELLIGENCE |
| `refactor.md` | **ARCHIVED** | ARCHIVE/ |
| `HOST_AI_IMPLEMENTATION_HANDOFF.md` | **ARCHIVED** | ARCHIVE/ |
| `WORKFLOW_CLEANUP_IMPLEMENTATION_HANDOFF.md` | **ARCHIVED** | ARCHIVE/ |
| `HOST_INTELLIGENCE_LOCAL_MODEL_RUNTIME_PROPOSAL.md` | **ARCHIVED** | ARCHIVE/ |

### New doc summaries

- **IOS_ARCHITECTURE.md** — Entry, login, `AppReservationSession`, tab shell, environment objects, capabilities, file index.
- **IOS_LIFECYCLE_AND_SYNC.md** — Startup states, active-window full/delta, cursors, auto loops, coalescing, SwiftData writes.
- **RESERVATION_WORKFLOWS.md** — Confirm/Mail, reminders, manual create, seat/complete/cancel/no-show, hide/delete, guest messaging.
- **FLOOR_PLAN_AND_TABLES.md** — Canonical vs legacy assignment, HostTableConfig advisory, migration risks.
- **HOST_INTELLIGENCE.md** — Engine vs LLM, settings toggles, grouping, template fallback, traces.
- **DIAGNOSTICS_AND_TESTING.md** — Safe tests, confirm flow checklist, shift reminders, cache reset.

---

## 9. Stabilization backlog

Full itemized list with acceptance tests: **[OPEN_WORK.md](./OPEN_WORK.md)**

### Implementation order (Phase 6 — do not implement without approval)

| Priority | Item | Why first |
|----------|------|-----------|
| P0 | Fix `isContentEquivalent` / merge email timestamps | Staff sees wrong confirmation/reminder state |
| P0 | Full-sync policy after delta (schedule or manual) | Ghost rows undermine trust |
| P1 | Unify Host/Bookings auto-refresh gating | Asymmetric sync behavior |
| P1 | Confirm pending UI state | “Confirmed” truthfulness |
| P1 | Block legacy table PATCH when backend layout exists | Wrong assignments |
| P2 | Guest intel FreshnessCoordinator + uncertainty copy | Overclaim reduction |
| P2 | Host card staff-facing AI label | Wording vs facts |
| P2 | Delete dead sync methods | Reduce accidental reuse |
| P2 | Update PROJECT_MAP / testing docs | QA trust |
| P3 | Split ReservationsListView.swift | Maintainability |
| V2 | Backend confirm email, auto reminders, Resend | Explicitly out of V1 |

---

## 10. Risky code areas (file paths)

| Area | Files |
|------|-------|
| Sync god-object | `Import/ReservationsController.swift` |
| Delta no-delete | `Import/ReservationImportService.swift` (ReservationSyncService), `Services/ReservationRepository.swift` |
| Equivalence skip | `Persistence/ReservationRecord.swift` (`isContentEquivalent`) |
| Dual auto-refresh | `Features/Reservations/HostBoardView.swift`, `Features/Reservations/ReservationsListView.swift` |
| Confirm flow | `Features/Reservations/ReservationDetailView.swift`, `Features/Reservations/ReservationEmailWorkflow.swift` |
| Legacy confirm POST | `Import/ReservationsController.swift` (`confirmReservation`), gated by flag |
| Table dual path | `Features/FloorPlan/TableAssignmentCoordinator.swift`, `Features/FloorPlan/FloorPlanStore.swift` |
| Guest intel merge | `Features/GuestInsights/GuestHistorySemantics.swift`, `Features/ReadModels/GuestProfileFacade.swift` |
| Host AI presentation | `Features/HostIntelligence/HostIntelligenceCard.swift`, `HostIntelligenceController.swift` |
| Hidden overlay | `Features/Reservations/HiddenReservationsStore.swift` |
| Optimistic status | `Import/ReservationsController.swift` (`updateStatus`) |
| Large shell file | `Features/Reservations/ReservationsListView.swift` (~3000 lines) |
| Dead sync API | `Import/ReservationImportService.swift` (`syncAllReservations`, `syncToday*`) |

---

## Appendix A — Repository inventory (Phase 1 summary)

### App entry and session

- `Tryzub_ReservationsApp.swift` → `AppRootView` → login / product intro / `ReservationsListView`
- `AppCredentialStore`, `AppRoleStore` (manager/developer), `AppReservationSession` owns `ReservationsController`
- Capabilities: `Core/Roles/AppUserRole.swift` → `AppCapabilities`

### Tab shell

- `ReservationsListView` → `StartupRootView` → `ReservationsTabShell` (5 tabs)
- Shared stores created in shell: settings, floor, host intelligence, guest intel, BI, activity, etc.

### Per-tab lifecycle

| Tab | View | isActive | @Query | Auto network |
|-----|------|----------|--------|--------------|
| Host | `HomeDashboardView` → `HostBoardView` | `selectedTab == .host` | Active window (always live) | 60s if today |
| Floor | `FloorPlanView` | floor tab | None (store) | 60s if today |
| Bookings | `ReservationScheduleView` | bookings tab | Active window + all cache | 60s |
| Guests | `GuestLookupView` | guests tab | All non-hidden | Search only |
| More | `ReservationMoreView` | none | Per destination | Passive |

### Network endpoints used in normal staff flow

`GET/PATCH/POST/DELETE /managed-reservations`, `/tables`, `/guest-manage-link`, `/manual-email-log`, `/activity`, `/guest-intelligence`, `/business-intelligence/summary`, `/intelligence/system-status`, `/reservation-analytics/summary`, `/floor-plan`, `/restaurant-tables`, restaurant setup/hours/slots/blocked-slots.

**Not used in normal flow:** `POST /import`, `POST /confirm` (flag off), `POST /send-due-reminders` (not in client).

### Traces present (DEBUG unless noted)

`StartupPolicyTrace`, `ActiveWindowFreshnessTrace`, `MultiDeviceSyncTrace`, `ConfirmFlowTrace`, `WorkflowCleanupTrace`, `GuestCommunicationTrace`, `SHIFT_REMINDER_TRACE`, `SwiftDataTrace`, `HostAILifecycleTrace`, `GuestIntelTrace`, `ServiceIntelligenceTrace`, `MutationVersionTrace`, `AttachmentOCRTrace`.

---

## Appendix B — Handoff implementation status

| Handoff item | Status |
|--------------|--------|
| Mail-first confirm | **Implemented** |
| Shift reminders sheet | **Implemented** (Host ⋯ menu + Bookings bell) |
| No-show Bookings tab | **Implemented** |
| Detail fetch on miss | **Implemented** |
| Notes semantics | **Partial** — verify acceptance |
| Bookings Active/Seated/Completed tabs | **Not implemented** (still Upcoming/Review/No Show/All/Cancelled) |
| HostAttentionGrouper | **Implemented** |
| Backend confirm email | **Disabled** (`isBackendConfirmEmailEnabled = false`) |
| Guest email template centralization | **Implemented** |

---

*This document is the current source of truth for stabilization planning on branch `audit-current-state`.*
