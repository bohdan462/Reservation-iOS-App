# Tryzub Reservations Refactor Blueprint

## 1. Why this audit exists

The iOS app has grown from a cache-backed reservation list into a multi-surface operations console: startup cache policy, active-window sync, SwiftData persistence, Host Board intelligence, Guest Intelligence, Business Analytics, local model wording, manual guest drafts, restaurant availability, and backend Floor Plan now all run inside the same mounted SwiftUI tab shell.

The underlying principle is still correct: WordPress managed reservations and the new floor-plan tables are server truth; SwiftData and in-memory stores are caches. The current implementation, however, has too many independent lifecycle owners. Views, controllers, stores, facades, and diagnostics can all start work. That makes the app feel laggy and creates service risks when another staff device changes a reservation before this device knows.

This file is an audit and staged refactor blueprint only. It does not authorize deleting code or changing backend contracts in one pass.

## 2. Executive summary

### 2.1 What changed too much

- `ReservationsController` grew from workflow coordinator into startup coordinator, sync freshness owner, mutation owner, restaurant setup cache, availability cache, diagnostics owner, notice center, local seated timestamp store, and history prefetch scheduler.
- `ReservationsListView` now mounts many long-lived stores: `RestaurantSettingsStore`, `HostTableConfigStore`, `HostIntelligenceController`, `GuestIntelligenceStore`, `BusinessIntelligenceStore`, `IntelligenceSystemStatusStore`, and `FloorPlanStore`.
- More surfaces became data-aware: Host, Bookings, Floor, Detail, Manual Add, Business Analytics, Guest Insights, Regular Guests, Guest Lookup, Hidden, Failed Imports, and Diagnostics.
- Table assignment split into two architectures: old `table_name` string PATCH plus local table inventory, and new backend table layout plus per-date assignment endpoint.
- Intelligence moved from local/cache-only into backend evidence packs plus local model wording, but some screens still compute local fallback from broad SwiftData snapshots.

### 2.2 Current biggest lag/refetch suspects

1. Mounted tabs with broad or active-window `@Query` recompute after repository upserts.
2. `HostBoardView` starts many `.task(id:)` pipelines: auto-refresh, clock, snapshot build, availability, guest intelligence, host engine, history enrichment, narrative refresh.
3. Host Board appears to receive a broader history pool from the shell, but `makeHostEngineInput` passes day-only reservations as `allKnownReservations`, forcing weaker local guest-history signals and extra recompute.
4. `GuestProfileFacade.loadIfNeeded` triggers date summary, reservation profile fetch, and local cache analysis on detail open.
5. `RegularGuestsView` observes broad reservation history and clusters in memory.
6. `GuestInsightsView` and `GuestInsightsAnalysisCoordinator` can analyze large cache snapshots.
7. `ReservationScheduleView` All mode can page broad history and upsert many rows.
8. `ManualReservationFacade` polls every 200ms while waiting for availability completion.
9. `BusinessAnalyticsCoordinator` may load legacy analytics, business intelligence, and system status for one screen.
10. `FloorPlanStore` has its own date cache and 60s auto-refresh independent of reservation active-window refresh.
11. `RestaurantSettingsStore.ensureDateOperations` and controller availability caches overlap in responsibility.

### 2.3 Current biggest architecture conflicts

- `Docs/TABLE_CONFIGURATION.md` says `HostTableConfigStore` is canonical local table inventory. Backend README now says `{prefix}tryzub_restaurant_tables` and `{prefix}tryzub_reservation_table_assignments` are canonical.
- Reservation detail and Host assignment sheets still mutate `ReservationUpdateRequest(tableName:)`; Floor Plan mutates `PATCH /managed-reservations/{id}/tables`.
- Guest Intelligence backend says iOS should trust backend profile packs when available; local cache guest memory still appears as fallback on detail and guest insight surfaces.
- Docs describe tab switches as mostly non-fetching; Floor Plan tab activation currently calls `FloorPlanStore.load(date:)`, and Host tab performs several non-reservation loads when visible.
- Mutation code reconciles uncertain network failures but does not consistently treat `404/not_found` as server truth after another device deletes/hides a row.
- `ReservationRecord.isContentEquivalent(to:)` may skip cache writes for server-side changes to email timestamps, supersession, and some hidden metadata if no compared field changes.

### 2.4 Current biggest product risks

- A staff device can show stale local rows after another device hides/deletes/changes a reservation, then present the wrong failure copy.
- Old table assignment can write a table name that does not correspond to an active backend floor table.
- Backend floor assignment conflicts are only handled in the new Floor Plan path, not the old detail/host table-name path.
- LLM wording is bounded, but stale or fallback facts can still make the UI sound more certain than the data supports.
- Broad SwiftData observation during service can make the UI feel unstable right when staff need fast actions.

## 3. Current source-of-truth rules

| Domain | Current real source of truth | Current iOS cache/owner | Drift or risk |
| --- | --- | --- | --- |
| Reservations | Backend `tryzub_reservations` via `GET/PATCH/POST/DELETE /managed-reservations` | SwiftData `ReservationRecord` through `ReservationRepository` | Correct principle; multi-device conflict copy incomplete. |
| Reservation list freshness | Backend active window plus `server_time` cursor | `ReservationsController` in-memory/persisted metadata plus SwiftData | Mostly centralized, but views still start screen-specific work. |
| SwiftData | Cache only | `ReservationRepository`, view `@Query` consumers | Writes are server-first, but upserts wake mounted tabs. |
| Availability/slots | Backend restaurant setup/hours/day availability/blocked slots/public slots | `ReservationsController`, `RestaurantSettingsStore`, `ReservationAvailabilityFacade`, `ManualReservationFacade` | Split ownership and direct-load fallback can duplicate work. |
| Floor Plan | Backend restaurant tables and reservation table assignments | `FloorPlanStore` selected-date cache | New canonical path; old local table inventory still active. |
| Old table assignment | Backend `ReservationDTO.tableName` compatibility/display field | `HostTableConfigStore`, `ReservationTableOptionsStore`, `TableAssignmentSheet` | Conflicts with backend floor layout and assignment conflict checks. |
| Guest Intelligence | Backend date summaries and reservation profile packs | `GuestIntelligenceStore`; local SwiftData fallback | Correct direction, but local fallback still heavy and can over-sound certainty. |
| Host Intelligence | Deterministic `HostIntelligenceEngine` facts/actions | `HostIntelligenceController`; LLM wording only | Good boundary; table facts still depend on old table store. |
| Business Analytics | Backend BI DTOs and legacy analytics DTO | `BusinessAnalyticsCoordinator`, `BusinessIntelligenceStore`, `IntelligenceSystemStatusStore`, `RestaurantSettingsStore` | Multiple GETs per screen; acceptable with gating, but not central freshness. |
| Messaging | Staff-reviewed drafts; backend manual email log only records activity | `GuestCommunicationCoordinator`, `GuestMessageDraftService`, detail UI | Good boundary; no auto-send. |
| Roles/capabilities | Backend coarse capability plus iOS manager/developer UI gating | `AppRoleStore`, `AppCapabilities` | Backend does not distinguish all iOS roles except hard delete. |

## 4. Current app architecture map

| Area/file | Current responsibility | State owned | Endpoints/SwiftData | Triggers | Status |
| --- | --- | --- | --- | --- | --- |
| `Tryzub_ReservationsApp.swift` | App entry, credential/login gate, SwiftData container | App session and environment wiring | SwiftData container for `ReservationRecord` | Scene startup | Active. |
| `App/*`, `Core/Roles/*` | Credentials, role selection, capability model, notices | Keychain/session role/capabilities | `GET /restaurant-setup` for login validation | Login/logout | Active; backend role model is coarser. |
| `ReservationsListView.swift` | Root shell, native `TabView`, environment stores, many nested screens | Selected tab, startup overlay state, root `@Query`s, shared stores | SwiftData active-window queries; delegates network to stores/controllers | `.task`, `.onAppear`, `.onChange`, `.refreshable` in nested screens | Active but too much lifecycle ownership. |
| `ReservationsController.swift` | Reservation workflow coordinator and broad app operations owner | Sync scopes, cursors, operation state, notices, setup, availability, local seated timestamps | Reservation GET/PATCH/POST/DELETE; settings; availability; analytics; import failures; SwiftData through repository | Startup, tab activation, auto-refresh, mutations, diagnostics | Active but overloaded. |
| `ReservationImportService.swift` | GET sync service | No published state | `GET /managed-reservations`; repository upsert/replace | Called by controller | Active; old today/schedule/review paths are legacy. |
| `ReservationMutationService.swift` | Server-first mutations | No published state | PATCH/POST/DELETE/reconcile + repository writes | Called by controller | Active; thin and useful. |
| `ReservationRepository.swift` | SwiftData cache writes/deletes | `ModelContext` only | Upsert, replace date/window, delete local rows | Called after server responses | Active; MainActor and view invalidation risk. |
| `ReservationsAPIClient.swift` | All HTTP and API request logging | Request serializer/logging | All REST endpoints | Called by services/stores/controller | Active; reason enum is valuable. |
| `HostBoardView.swift` | Host/service dashboard and Host AI surface | Selected date, board snapshot, host presentation state | SwiftData queries; controller availability; Guest Intelligence; Host AI | Many `.task(id:)` and `.onChange` triggers | Active; top lifecycle/recompute hotspot. |
| `ReservationDetailView.swift` | Reservation detail, actions, guest profile, drafts, old table sheet | Sheet state, draft state, `GuestProfileFacade` | SwiftData window query; Guest Intelligence profile; PATCH/tableName; guest link/manual email | `.onAppear`, `.task(id:)`, action `Task`s | Active; table path and profile work need stabilization. |
| `ManualReservationFormView.swift` | Create/edit form, validation, slot loading, table field | Draft state and facade state | POST/PATCH, availability/slots via controller/facade | Date changes, form open/save | Active; should delegate more to facade/store. |
| `ReservationActionButtons.swift` | Shared row/detail action buttons and old table assignment sheet | Inline action state; `TableAssignmentSheet` local state | PATCH `table_name`; local table inventory | Buttons, `.task(id:)`, `.onAppear` | Active, but table assignment sheet conflicts with new Floor Plan. |
| `RestaurantSettingsStore.swift` | Settings store plus embedded settings views | Setup, hours, date ops, analytics caches | restaurant setup/hours/day availability/blocked slots/slots/legacy analytics | Settings screen `.task`, date change, save | Active but too large. |
| `BusinessAnalyticsView.swift` / coordinator | Business analytics screen orchestration | Selected range, loading/error state | `GET /reservation-analytics/summary`, BI summary, system status | `onAppear`, range change, refresh | Active; multi-endpoint screen. |
| `Features/FloorPlan/*` | New backend floor layout and assignment MVP | Selected-date floor state, layout tables, save/assign state | `GET/PUT /restaurant-tables`, `GET /floor-plan`, `PATCH /tables` | Floor tab appear/date change/auto-refresh/setup sheet | Active; canonical future table path. |
| `Features/Guests/*` | Operational guest lookup for call-ins | Search cache/profile list | SwiftData read only; no network while typing | Cache key task, search debounce | Active; should stay lightweight. |
| `Features/GuestInsights/*` | Local guest memory and regulars | Analysis state/stores | Broad SwiftData read; optional Guest Intelligence store | Detail/More open, cache key/search tasks | Active but performance risk. |
| `Features/HostIntelligence/*` | Deterministic host engine, local model wording, table advisory | Host settings, table config, narrative state | Local UserDefaults, optional local model; no mutation endpoints | Host board evaluation tasks, diagnostics | Active; old table source drift. |
| `Features/GuestMessaging/*` | Staff-reviewed drafts | Drafting/error state | No reservation mutation except separate manual email log from detail | Detail button actions | Active and safe boundary. |
| `Features/ReadModels/*` | Facades/builders for host board, profile, manual form, availability | View-state caches and tasks | Read from controller/stores; some direct Task work | View calls | Active; should become core screen state boundary. |

## 5. Current controller/store/service responsibility map

| Component | Owns today | Target ownership | Fetches | Mutates | Publishes too much? | Overlap | Keep/merge/deprecate/rewrite |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `ReservationsController` | Sync scopes, cursors, mutations, notices, setup, availability, diagnostics, seated timestamps | Reservation workflow coordinator plus delegate to freshness/mutation/reconcile stores | Active window, cancelled, hidden, settings, slots, analytics, import failures | Reservation create/edit/status/hide/restore/delete/email-log/link | Yes | Restaurant settings, availability, diagnostics | Keep, split responsibilities in phases. |
| `ReservationSyncService` | GET list sync and repository writes | Data access service for reservation list/cache | Managed reservations full/delta/legacy scopes | SwiftData cache only | No | Legacy today/schedule/review paths | Keep, rename file later. |
| `ReservationMutationService` | Server-first mutation calls and cache writes | Canonical reservation mutation service | Reconcile by ID | PATCH/POST/DELETE/confirm/log/link | No | Controller wraps too much copy | Keep; add conflict result types later. |
| `ReservationRepository` | SwiftData cache writes/deletes | Sole reservation cache writer | SwiftData fetches | SwiftData upsert/replace/delete | No published state | View `@Query` reads are separate | Keep; add batch/snapshot helpers. |
| `ReservationsAPIClient` | HTTP transport, DTO decoding, request logs | Sole HTTP adapter | All endpoints | All HTTP methods | No | Some controller direct calls bypass services | Keep. |
| `GuestIntelligenceStore` | Date guest summaries and reservation profile packs | Backend guest intelligence cache with explicit TTL and owner | `GET /guest-intelligence`, `GET /guest-intelligence/reservation/{id}` | None | Moderate | Detail, Host, Guest Insights | Keep; centralize profile loading policy. |
| `BusinessIntelligenceStore` | Range-keyed BI cache | Range-keyed backend BI cache | `GET /business-intelligence/summary` | None | Low | BusinessAnalyticsCoordinator | Keep. |
| `IntelligenceSystemStatusStore` | Range-keyed system status cache | Range-keyed health cache | `GET /intelligence/system-status` | None | Low | BusinessAnalyticsCoordinator | Keep. |
| `FloorPlanStore` | Selected-date floor plan, layout load/save, table assignment | Canonical floor-plan state and assignment service | `GET /floor-plan`, `GET /restaurant-tables` | `PUT /restaurant-tables`, `PATCH /tables` | Moderate | Old `TableAssignmentSheet` / `tableName` | Keep; route old assignment UI through it later. |
| `RestaurantSettingsStore` | Settings screens, date ops, legacy analytics cache | Settings/ops store only; no Host/Add duplicate availability owner | Setup/hours/day availability/slots/blocked/analytics | Setup/hours/day availability/blocked slots | Yes, file is huge | Controller availability and analytics | Keep, split UI/store later. |
| `HostIntelligenceController` | Host engine output and local model briefing presentation | Deterministic Host AI presentation owner | No backend directly | None | Moderate | Host view tasks and Guest Intelligence store | Keep; move heavy prep outside body triggers. |
| `HostIntelligenceEngine` | Deterministic facts/actions | Authoritative deterministic host decision engine | None | None | No | LLM wording | Keep; do not weaken. |
| `GuestProfileFacade` | Detail/Guest Insights profile state | Detail profile screen state coordinator | Triggers Guest Intelligence profile via store | None | Moderate | GuestInsights local analysis | Keep; add cancellation/generation discipline. |
| `ReservationAvailabilityFacade` | Freshness decision helper for availability bundle | Shared availability freshness coordinator frontend | Controller day availability/slots/blocked | None | No | Controller and Manual facade | Keep; promote into central coordinator. |
| `ManualReservationFacade` | Manual Add view state and load polling | Manual form screen model | Availability bundle through controller/facade | None | Moderate | Form view logic | Keep; remove polling later. |
| `HostBoardViewStateBuilder` | Host board read model | Pure builder only | None | None | No | HostBoardView computed keys | Keep. |
| `GuestCommunicationCoordinator` | Guest draft orchestration and compose/copy prep | Staff-reviewed draft coordinator | No backend directly | No reservation mutation | Low | Detail manual email log path | Keep. |
| `HostTableConfigStore` | Local UserDefaults table inventory | Deprecated compatibility/advisory fallback | UserDefaults | UserDefaults | Moderate | Backend floor layout | Deprecate after migration. |
| `ReservationTableOptionsStore` | Legacy fallback table names | Compatibility only | UserDefaults | UserDefaults | No | HostTableConfigStore, Floor Plan | Deprecate. |
| `HiddenReservationsStore` | Hidden filter helper | Thin cache/display helper | None | None | No | `ReservationRecord.isHidden` | Keep or inline later. |

## 6. Current startup lifecycle

1. `Tryzub_ReservationsApp` loads credentials from env/Keychain, role from `AppRoleStore`, and gates into login or `ReservationsListView`.
2. Scene-level SwiftData container is installed for `ReservationRecord`.
3. `ReservationsListView` root `.task` starts startup presentation and `controller.beginStartupPresentation(context:)`.
4. `ReservationsController.loadIfNeeded(context:)` checks local cache and performs startup active-window policy: skip if fresh, full if cold/missing cursor, delta if stale with cursor.
5. Active-window sync calls `ReservationSyncService.syncActiveWindowFull` or `syncActiveWindowChanges`, which writes SwiftData via `ReservationRepository`.
6. Startup presentation releases UI from cache before noncritical followups.
7. Deferred work starts restaurant setup and history prefetch; Host visible tasks can also start availability and guest intelligence after startup deferral.

Risk: startup is better than earlier phases, but there are still multiple noncritical owners. Views must not become startup coordinators again.

## 7. Current tab lifecycle

### Host

- Root `HomeDashboardView` and `HostBoardView` remain mounted under native `TabView`.
- Uses active-window SwiftData `@Query` plus selected-date filtering.
- `.task(id: isVisible && isAppActive)` starts a 60s auto-refresh loop through `autoRefreshDashboardIfAllowed`.
- `.task(id: isVisible)` starts a clock loop.
- `.task(id: boardSnapshotBuildKey)` rebuilds `HostBoardSnapshot`.
- `.task(id: availability key)` prepares availability summary.
- `.task(id: guest-intelligence key)` schedules backend guest intelligence date summary.
- `.task(id: hostIntelligenceEvaluationKey)` runs deterministic engine.
- `.task(id: hostIntelligenceEnrichmentKey)` refreshes briefing/local model presentation.

### Floor

- `FloorPlanView.onAppear` calls `store.load(date:)`.
- Date changes call `loadForSelectedDate`.
- Toolbar refresh calls `store.refresh(force: true)`.
- `store.setAutoRefreshActive` runs its own 60s floor-plan refresh when active and selected date is today.
- Layout setup loads restaurant tables, saves via PUT, then refreshes selected-date floor plan.

### Bookings

- Active-window SwiftData query serves Upcoming/Needs Review/Cancelled filters.
- `.task(id: isActive)` sleeps briefly then calls `scheduleBecameActive`.
- Manual refresh calls `requestScheduleRefresh`.
- All mode search/date/filter calls `loadScheduleAllPage` or `refreshScheduleDate`.
- Needs Review is no longer a top-level tab, but legacy review methods remain.

### Guests

- `GuestLookupView` uses cached non-hidden reservations only.
- It rebuilds profiles when cache key changes and debounces search.
- It should not call Guest Intelligence or network while typing.

### More

- Navigation-only root. Child screens fetch lazily: Hidden, Failed Imports, settings, analytics, diagnostics, guest memory.
- `BusinessAnalyticsView` uses `onAppear/onDisappear` to start/cancel `BusinessAnalyticsCoordinator`.
- Hidden and Import Failures fetch on `.task` and `.refreshable`.

## 8. Fetch/refetch trigger audit

| Screen/File | Trigger | Method called | Endpoint or SwiftData query | Startup? | Tab open? | Date change? | Body recompute? | Auto-refresh? | IsActive gated? | TTL/cache guarded? | Cancels stale work? | Can overlap? | Risk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ReservationsListView` root | `.task` | startup presentation/load | Active-window GET + SwiftData replace/upsert | Yes | No | No | No | No | N/A | Yes | Partial | With deferred work | High |
| `ReservationsTabShell` | `@Query` | pending badge/privacy snapshot | SwiftData active window | Yes | Mounted | No | Yes after writes | No | No | N/A | N/A | Recomputes with sync | Medium |
| `HostBoardView` | `.task(id: visible/appActive)` | `autoRefreshDashboardIfAllowed` | `GET /managed-reservations?from&to&updated_since` or full | No | Host active | No | No | Yes | Yes | Interval/cooldown | Loop cancels | With floor/store loads | High |
| `HostBoardView` | `.task(id: selectedDate availability)` | `prepareAvailability` | day availability, slots, blocked slots | Deferred | Host active | Yes | No | No | Yes | TTL/in-flight | Some | With form/settings availability | Medium |
| `HostBoardView` | `.task(id: guest intelligence)` | `GuestIntelligenceStore.scheduleLoad` | `GET /guest-intelligence?date=` | Deferred | Host active | Yes | No | No | Yes | 180s/debounce | Yes | Detail profile loads | Medium |
| `HostBoardView` | `.task(id: host engine key)` | `HostIntelligenceController.evaluate` | Local engine over snapshots | No | Host active | Yes | Yes via key | No | Yes | Semantic key | N/A | With SwiftData writes | High |
| `Bookings` | `.task(id: isActive)` | `scheduleBecameActive` | Active-window GET if stale | No | Yes | No | No | No | Yes | 300s | Controller scope | With startup/host refresh | Medium |
| `Bookings` | `.refreshable`/toolbar | `requestScheduleRefresh` | Active-window full GET | No | Manual | No | No | No | Yes | Manual cooldown limited | Scope guard | With other manual refresh | Medium |
| `Bookings All` | search/date/load more | `loadScheduleAllPage` / `refreshScheduleDate` | `GET /managed-reservations` pages/date | No | Explicit | Yes | No | No | Yes | Generation guards | Partial | Upserts wake tabs | High |
| `FloorPlanView` | `onAppear` | `store.load(date:)` | `GET /floor-plan?date=` | No | Yes | No | No | Store loop | Yes | date cache for force false | Cancels load task | Independent of reservation refresh | Medium |
| `FloorPlanView` | date change | `store.load(date:)` | `GET /floor-plan?date=` | No | If active/mounted | Yes | No | No | Partial | Cache guarded | Yes | With auto refresh | Medium |
| `FloorPlanStore` | auto loop | `refresh(force: true)` | `GET /floor-plan?date=` | No | Active today | No | No | Yes | Yes | No TTL on loop | Cancels loop | With tab/date refresh | Medium |
| `FloorPlanLayoutSetupView` | `.task` | `loadLayout` | `GET /restaurant-tables` | No | Sheet open | No | No | No | Sheet | No visible TTL | No explicit generation | With floor refresh | Low/medium |
| `ReservationDetailView` | `.task(id: guestInsightCacheKey)` | local analysis | SwiftData window/history pool | No | Detail open | Cache changes | Yes via key | No | View mounted | Semantic-ish | Generation | With profile fetch | High |
| `ReservationDetailView` | `.task(id: guestIntelligenceFetchKey)` | `GuestProfileFacade.loadIfNeeded` | `GET /guest-intelligence/reservation/{id}` + date summary | No | Detail open | Reservation date | No | No | View mounted | Store TTL | Generation | With Host date summary | Medium |
| `ManualReservationFormView` | open/date change | facade/controller slot load | day availability, slots, blocked slots | No | Form open | Yes | No | No | Form mounted | TTL/in-flight | Poll/cancel | With Host/settings availability | Medium |
| `BusinessAnalyticsView` | `onAppear` | coordinator visible/load | legacy analytics + BI + system status | No | More child open | Range change | No | No | Screen visible | 600s/debounce | Yes | Triple endpoint | Medium |
| `RegularGuestsView` | `@Query` + `.task(id: cacheKey)` | Regular guest clustering | SwiftData broad read | No | More child open | No | Yes after writes | No | View mounted | Cache key | Some | Expensive cache growth | High |
| `GuestLookupView` | cache/search tasks | local lookup store | SwiftData cache only | No | Guests active | No | Cache key | No | Yes | Cache key | Search debounce | Low |
| `HiddenReservationsView` | `.task`/refresh | `loadHiddenReservationsPage` | `GET include_hidden=1` + upsert | No | More child open | No | No | No | Screen | 300s unless force | Scope guard | With mutation/hide | Low/medium |
| `ImportFailuresView` | `.task`/refresh | `fetchImportFailures` | `GET /import-failures` | No | More child open | No | No | No | Screen | None/explicit | No | Low |
| `DeveloperDiagnosticsView` | buttons | `runAdminFetchTest` | GET probes only | No | Explicit | No | No | No | Developer | None | Button-driven | Low |

## 9. Endpoint usage and ownership map

| Endpoint | Owner in iOS | Reason enum | Screen trigger | Startup? | Tab open? | Date change? | Auto refresh? | Mutation? | Writes SwiftData? | TTL/cache guard? | Conflict behavior |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `GET /managed-reservations?from&to` | `ReservationsController` / `ReservationSyncService` | `active_window`, `schedule_window` | Startup, manual refresh, Bookings stale | Yes | Bookings if stale | Window only | fallback full | No | replace window | Scope freshness | Generic errors. |
| `GET /managed-reservations?updated_since` | `ReservationSyncService` | `active_window_delta` | Host auto/startup delta | Possible | No | No | Yes | No | upsert only | Cursor/interval | Empty delta safe. |
| `GET /managed-reservations/{id}` | `ReservationMutationService` | `reconcile_by_id` | uncertain mutation reconcile | No | No | No | No | No | upsert | none | 404 not yet treated as already gone. |
| `POST /managed-reservations` | `ReservationMutationService` | `mutation_create` | Manual Add/import repair | No | User action | Selected date | No | Yes | upsert | in-flight guard | Generic create failure. |
| `PATCH /managed-reservations/{id}` | `ReservationMutationService` | `mutation_patch` | edit/status/hide/restore/old table | No | User action | No | No | Yes | upsert | row guard | Uncertain reconcile; 404 generic. |
| `DELETE /managed-reservations/{id}` | `ReservationMutationService` | `hard_delete` | Hidden dev cleanup | No | User action | No | No | Yes | delete local after success | row guard | 404 generic failure. |
| `POST /managed-reservations/{id}/confirm` | `ReservationMutationService` | `mutation_confirm` | Confirm + Email fallback | No | User action | No | No | Yes | upsert | disabled in MVP | Uncertain reconcile; 404 generic. |
| `POST /managed-reservations/{id}/manual-email-log` | Controller/API | `manual_email_log` | Detail draft/sent/fail | No | User action | No | No | Yes | only reconcile after manual sent | row guard | 404 generic. |
| `POST /managed-reservations/{id}/guest-manage-link` | Controller/API | `guest_manage_link` | Detail More | No | User action | No | No | Yes | No | row guard | 404 generic. |
| `GET /restaurant-setup` | Controller/settings/login | `restaurant_setup` | Login/startup/settings/form | Yes | Settings/form | No | No | No | No | in-memory freshness | Generic. |
| `GET /restaurant-hours` | Controller/settings | `restaurant_hours` | Settings | Deferred | More child | Range/date | No | No | No | store cache | Generic. |
| `GET /restaurant-day-availability` | Controller/settings/facade | `restaurant_day_availability` | Host/form/settings | Deferred | Host/form | Yes | No | No | No | date TTL/in-flight | Generic. |
| `GET /reservation-slots` | Controller/settings/facade | `reservation_slots` | Host/form/settings | Deferred | Host/form | Yes | No | No | No | date TTL/in-flight | Generic. |
| `GET /restaurant-blocked-slots` | Controller/settings/facade | `restaurant_blocked_slots` | Host/form/settings | Deferred | Host/form | Yes | No | No | No | date TTL/in-flight | Generic. |
| `GET /guest-intelligence` | `GuestIntelligenceStore` | `guest_intelligence` | Host selected date/detail ensure | No | Host/detail | Yes | No | No | No | 180s/debounce | Generic fallback. |
| `GET /guest-intelligence/reservation/{id}` | `GuestIntelligenceStore` | `guest_intelligence` | Detail/Guest Insights | No | Detail open | Reservation date | No | No | No | profile TTL | Generic fallback. |
| `GET /business-intelligence/summary` | `BusinessIntelligenceStore` | `business_intelligence_summary` | Business Analytics | No | More child | Range | No | No | No | 600s | Generic warning. |
| `GET /intelligence/system-status` | `IntelligenceSystemStatusStore` | `intelligence_system_status` | Business Analytics | No | More child | Range | No | No | No | 600s | Generic warning. |
| `GET /restaurant-tables` | `FloorPlanStore` | `restaurant_tables` | Layout setup | No | Sheet open | No | No | No | No | none | Staff-safe error partly. |
| `PUT /restaurant-tables` | `FloorPlanStore` | `restaurant_tables_put` | Layout save | No | User action | No | No | Yes | No | saving guard | Overlap mapped to staff copy. |
| `GET /floor-plan` | `FloorPlanStore` | `floor_plan` | Floor tab/date/refresh/auto | No | Floor active | Yes | Yes | No | No | date cache for force false | Generic. |
| `PATCH /managed-reservations/{id}/tables` | `FloorPlanStore` | `reservation_tables_patch` | Floor assignment sheet | No | User action | Selected date | No | Yes | upsert through controller.save | 409 handled; 404 generic. |
| `GET /managed-reservations/import-failures` | Controller/import service | `failure_count`, `import_failures_full` | More/diagnostics/badge | Deferred | More child | No | No | No | No | capability/freshness for count | Generic. |
| `POST /managed-reservations/import` | None in iOS client | N/A | Should not be called | No | No | No | No | Forbidden normal workflow | No | N/A | Must remain unused. |

## 10. Mutation and multi-device conflict audit

| Mutation | Endpoint | Current success behavior | Current 404/already-gone behavior | Current uncertain behavior | Current local cache behavior | Target behavior |
| --- | --- | --- | --- | --- | --- | --- |
| Confirm Only | PATCH status confirmed | Upsert DTO; notice updated | Generic “could not update” then optimistic revert | Reconcile by ID if may-have-reached | Optimistic status then revert on catch | If not found, refresh active date/window and show “changed on another device.” |
| Seat | PATCH status seated | Upsert DTO; local seated timestamp | Generic failure/revert | Reconcile if uncertain | Optimistic status | Same; also reconcile floor assignment if table state relevant. |
| Complete | PATCH status completed | Upsert DTO | Generic failure/revert | Reconcile if uncertain | Optimistic status | Treat already terminal as server truth after refresh. |
| Cancel | PATCH status cancelled | Upsert DTO | Generic failure/revert | Reconcile if uncertain | Optimistic status | If guest/self-service already cancelled, refresh and show changed-on-another-device. |
| No-show | PATCH status no_show | Upsert DTO | Generic failure/revert | Reconcile if uncertain | Optimistic status | Same terminal-state conflict copy. |
| Edit reservation | PATCH fields | Upsert DTO | Generic failure | Reconcile if uncertain | No local write before server except status helper | On 404/409/stale validation, fetch active date and keep form open with server-truth copy. |
| Hide | PATCH `is_hidden=true` | Upsert hidden DTO; row disappears from filters | Generic “Hide did not sync” | No explicit uncertain reconcile branch | Upsert hidden after success | If not found/already hidden, refresh and show “Reservation is already gone or hidden on the server.” |
| Restore | PATCH `is_hidden=false` | Upsert restored DTO | Generic “Restore did not sync” | No explicit uncertain reconcile branch | Upsert after success | If deleted elsewhere, remove local row and show server-truth refresh. |
| Hard delete | DELETE force=1 | Delete local row after success | Generic “not deleted” | No reconcile | Delete only after success | If 404, delete local cache row and show “already gone on server.” |
| Manual create | POST | Upsert new DTO | Not applicable | Generic create failure, no local insert | Server-first | Add idempotency/client-request awareness later; uncertain timeout should search/reconcile if backend supports key. |
| Old table assignment | PATCH `table_name` | Upsert DTO | Generic update failure | Reconcile if uncertain through update path | Server-first but no conflict model | Deprecate; route through backend table assignment service. |
| Floor table assignment | PATCH `/tables` | Save response reservation into cache; refresh floor plan | Generic floor error | No reconcile by ID on uncertain failure | Upsert if response includes reservation | Add 404/already changed copy and active floor refresh. |
| Floor layout save | PUT `/restaurant-tables` | Save returned layout; refresh floor plan | Generic staff-safe save error | No reconcile | No SwiftData | If PUT 200 but floor returns 0, log request/response summary, restaurant_key, is_active. |
| Manual email log | POST `/manual-email-log` | Log result; `manual_sent` reconciles by ID | Generic log failure | No special uncertain handling | Only reconcile for sent | 404 means reservation gone; refresh and do not imply email state changed. |
| Guest manage link | POST `/guest-manage-link` | Returns URL; no cache write | Generic link failed | No special uncertain handling | None | 404/hidden means row changed; refresh and clear draft flow. |

Target staff-safe copy:

```text
Reservation is already gone on the server. Saved data was refreshed.
This reservation was already changed on another device. The list was refreshed.
```

## 11. SwiftData and concurrency risk audit

| File | Method/surface | Risk | Likely user symptom | Recommended later fix |
| --- | --- | --- | --- | --- |
| `ReservationRepository.swift` | `replaceDateWindowYielding`, `upsertYielding` | MainActor SwiftData writes in chunks still invalidate mounted `@Query`s | jank after sync/upsert | Batch writes, publish derived snapshots, measure changed/skipped. |
| `ReservationRecord.swift` | `isContentEquivalent(to:)` | Equivalence check omits several server fields such as confirmation/reminder timestamps, supersession, and hidden metadata | server changes do not appear until another compared field changes | Expand equivalence or use field-version/updated-at driven cache writes. |
| `ReservationsListView.swift` | root `@Query` pending/window | Mounted root queries update on every cache write | tab badge/privacy snapshot recompute | Move badge counts to controller/cache snapshot if needed. |
| `HostBoardView.swift` | multiple `.task(id:)` keys | SwiftData write can cascade into snapshot, engine, briefing tasks | Host card flicker/lag | Single Host lifecycle coordinator and semantic throttling. |
| `HostBoardView.swift` | `makeHostEngineInput` | Day-only reservations appear to be passed as `allKnownReservations` despite a broader history pool being available from the shell | Host guest memory/LLM facts are weaker and may recompute local fallback more often | Pass value snapshots from the intended history pool and keep local analysis off MainActor. |
| `ReservationDetailView.swift` | `@Query` + profile facade | Detail open can run local analysis and backend profile together | slow detail open | Snapshot selected/history records before async work. |
| `GuestProfileFacade.swift` | `Task` with MainActor provider | Async profile completion pulls current SwiftData models from provider | possible stale/unsafe model access if view disappeared | Use value snapshots and explicit cancellation. |
| `GuestInsightsAnalysisCoordinator.swift` | `Task.detached` | Detached work is good, but input must be value snapshots | unsafe model capture if records passed directly | Ensure only `GuestInsightRecordSnapshot` crosses detached boundary. |
| `RegularGuestsView.swift` | broad `@Query` and clustering | Cache growth causes O(n)/pairwise work | More tab hitch | Pre-index snapshots off-main; paginate regulars. |
| `ReservationAvailabilityFacade.swift` | unmanaged direct `Task` | Outside Host selected date path, direct load is fire-and-forget | duplicate availability fetches | Central freshness coordinator with task registry. |
| `ManualReservationFacade.swift` | polling every 200ms | Polling controller loading state | form spinners/jank | Await explicit load result or async stream. |
| `FloorPlanStore.swift` | assignment takes `ModelContext?` | Floor assignment backend work and SwiftData cache write share MainActor path | `unsafeForcedSync` suspicion near assignment | Decouple floor assignment response into DTO event; controller writes cache after await. |
| `BusinessAnalyticsCoordinator.swift` | active task awaits multiple stores | Screen load can serialize/overlap legacy and BI work | analytics tab lag | Let coordinator own one range load plan with clear cancellation. |
| `HostIntelligenceController.swift` | engine evaluation on MainActor | Deterministic engine can be heavy over history and table configs | Host Board stutter | Move pure evaluation to snapshot/off-main if trace exceeds threshold. |

## 12. Table architecture transition audit

The current table source of truth is split:

- Old path: `ReservationRecord.tableName`/`ReservationDTO.tableName` compatibility string; assigned by `TableAssignmentSheet` using `ReservationUpdateRequest(tableName:)`.
- Old inventory: `HostTableConfigStore` stores structured tables in UserDefaults and powers assignment chips and Host AI advisory table-fit.
- Legacy fallback: `ReservationTableOptionsStore` stores raw chip names in `AppStorage`.
- New path: backend owns persistent grid table definitions in `/restaurant-tables`; backend owns per-date assignments in `/floor-plan` and `PATCH /managed-reservations/{id}/tables`.

Screens using old local inventory:

- `ReservationActionButtons.TableAssignmentSheet`
- `ReservationDetailView` table assignment sheet
- `HostBoardView` table assignment sheet
- `ManualReservationFormView` table field/advisory context
- Host Intelligence table pressure/fit support
- Restaurant Settings table import text

Screens using new backend Floor Plan:

- `FloorPlanView`
- `FloorPlanStore`
- `FloorPlanViewStateBuilder`
- `FloorPlanLayoutSetupView`
- `FloorPlanGridView`
- `FloorPlanTableAssignmentSheet`

Duplicated assignment UI:

- Old `TableAssignmentSheet`: edits a freeform table string through generic reservation PATCH.
- New `FloorPlanTableAssignmentSheet`: selects backend table keys and uses conflict-aware assignment endpoint.

Canonical target:

1. Backend floor layout is canonical table layout.
2. Backend `/tables` assignment endpoint is canonical assignment mutation.
3. `ReservationDTO.tableName` remains display/compatibility only, populated by backend assignment endpoint.
4. `HostTableConfigStore` becomes deprecated compatibility/advisory fallback only until all screens read backend table layout.
5. Detail and Host table actions route through the same assignment service as Floor Plan.
6. LLM/Host AI can mention table pressure and “check table fit,” but cannot assign or invent availability.

Migration plan:

1. Add a `TableAssignmentCoordinator` facade that wraps `FloorPlanStore`/`FloorPlanService` without changing UI.
2. Teach old assignment sheet to optionally render backend table options when layout exists.
3. Change Detail/Host assignment save from `PATCH table_name` to `PATCH /tables`.
4. Keep freeform table text as an emergency compatibility field only behind developer/manager fallback copy.
5. Feed Host table-fit advisory from backend table capacities.
6. Mark `Docs/TABLE_CONFIGURATION.md` stale and rewrite it around backend floor layout.
7. Later remove `ReservationTableOptionsStore` default chips and table capacity text import from normal service UI.

## 13. Intelligence and LLM boundary audit

Deterministic facts:

- `HostIntelligenceEngine` produces host facts, action candidates, table pressure, duplicate/no-table/late/seated signals.
- `GuestMessageDraftTemplateWriter` produces deterministic draft fallback.
- Backend intelligence DTOs provide deterministic guest/business/system evidence.
- `GuestMessageDraftValidator`, `HostBriefingWriterValidator`, `ManagerNarrativePacketSanitizer`, and packet builders constrain output.

Backend facts:

- `GET /guest-intelligence?date=` supplies selected-date summaries for Host.
- `GET /guest-intelligence/reservation/{id}` supplies profile packs for Detail/Guest Insights.
- `GET /business-intelligence/summary` supplies management metrics.
- `GET /intelligence/system-status` supplies system/pipeline health.

Local fallback:

- `GuestInsightsController`, `RegularGuestsController`, and local snapshots infer guest memory from cached `ReservationRecord`s.
- This is useful when backend intelligence is absent but must not override exact/strong backend evidence.

LLM boundary:

- Host local model is wording only. It sees sanitized `ManagerNarrativePacket`, not raw reservations, phone, email, raw notes, or backend JSON.
- Guest draft local model is opt-in and defaults off. It sees allowlisted packet fields only.
- LLM output can produce wording, not operational truth or mutations.
- Template fallback must remain always available.

Target canonical pipeline:

```text
Deterministic facts/actions first.
AI-worthy gate second.
LLM rewrite third.
Semantic validator fourth.
Template fallback always.
```

Extra pressure sources:

- Host engine reevaluates from SwiftData-driven keys.
- Host Board has a concrete wiring risk: a broad history pool is passed down from the tab shell, but the engine input currently appears to use day-only reservations for `allKnownReservations`.
- Guest profile loads combine backend profile fetch and local detached analysis.
- Guest Intelligence date summary can be scheduled by Host and detail surfaces.
- Business Analytics loads legacy analytics plus BI plus system status.
- There are two Host LLM wording paths (`ManagerNarrativeWriter` and `LocalModelHostBriefingWriter`) with overlapping prompt/validation responsibilities; target architecture should collapse this to one story per surface.

Do not weaken validators. Refactor should reduce when intelligence runs, not broaden what it can claim.

## 14. Dead/stale/duplicated code candidates

| Candidate | Classification | Why | Do not remove yet? |
| --- | --- | --- | --- |
| `ReservationFloatingTabBar` old shell logic | Legacy but referenced | Native `TabView` is shell; enum/stability may remain | Yes. |
| `ReservationReviewQueueView` paths | Legacy but referenced/possible | Review is Bookings filter; controller methods remain | Yes. |
| `refreshDashboard` | Legacy wrapper | Calls active-window refresh despite old name | Yes; rename later. |
| `refreshScheduleWindowCache` | Legacy wrapper | Active-window path now shared | Yes. |
| `refreshReviewQueues` | Legacy wrapper | Review no longer top-level | Yes. |
| `createReservation` controller method | Dead candidate | UI uses `createAcceptedManualReservation` | Yes. |
| `save(_:context:)` | Dead/misleading candidate | Cache upsert wrapper, no current external callers in docs | Yes. |
| `TableAssignmentSheet` | Conflicts with new architecture | Freeform `tableName` PATCH bypasses backend conflicts | Yes until migrated. |
| `FloorPlanTableAssignmentSheet` | Active canonical candidate | New backend assignment path | Keep. |
| `HostTableConfigStore` | Conflicts with new architecture | UserDefaults table inventory now stale vs backend | Deprecate after migration. |
| `ReservationTableOptionsStore` | Legacy fallback | Default local chip names can conflict with backend layout | Deprecate. |
| Restaurant Settings table import text | Conflicts with new architecture | Imports into local store only | Hide/convert later. |
| Legacy diagnostics GET tests | Active support | Useful but not normal workflow | Keep, label clearly. |
| `POST /managed-reservations/import` docs/test path | Documentation/API only | Must never be normal iOS workflow | Keep forbidden monitor. |
| Local model proposal docs/code | Documentation stale only / active opt-in mix | Proposal historical, current runtime exists | Do not remove; mark status. |
| `ManagerNarrativePacketBuilder.buildBusinessAnalyticsPrototype` | Dead candidate | Prototype/future LLM BI surface with no current production call site | Yes. |
| `BusinessIntelligenceCompactRow` | Dead candidate | Private presentation row not currently instantiated | Yes. |
| `HostBoardView` history-enrichment trace-only task | Stale placeholder | Logs `HostReevalTrace` but does not perform real enrichment work | Yes; merge or remove later. |
| Host LLM dual writer paths | Duplicated architecture | `ManagerNarrativeWriter` and `LocalModelHostBriefingWriter` overlap | Yes; unify later. |
| Old `ReservationAnalyticsSummaryDTO` screen section | Legacy but active | Preserved below BI | Keep until BI fully trusted. |

## 15. Documentation drift

- `Docs/TABLE_CONFIGURATION.md` is materially stale: it says backend stores table name only and `HostTableConfigStore` is canonical. Backend README now documents canonical floor layout and assignment tables.
- `Docs/PROJECT_MAP.md` source tree count is stale after Floor Plan, read models, BI coordinator, startup polish, and local model additions.
- `Docs/ARCHITECTURE_DIAGRAMS.md` tab diagram omits Floor tab and the new floor-plan stores/endpoints.
- `Docs/PROJECT_METHOD_MAP.md` documents table configuration as local advisory; it needs a new floor-plan canonical section.
- Backend README says iOS should not invent floor layout locally; setup seed tables in iOS are acceptable only as first-run draft until PUT succeeds.
- Backend INTELLIGENCE says iOS should use reservation profile endpoint for detail/profile truth; docs still describe some local Guest Insights surfaces as no-network/cache-only.
- `IOS_ADMIN_TESTING.md` endpoint checklist does not yet include all floor-plan endpoints in the iOS diagnostics checklist.
- Role docs differ slightly: Manager has failed-import capability, but some doc rows still imply developer-only navigation.
- Startup docs say tab switch alone fetches nothing; Floor tab activation now loads floor plan when opened.
- Local model docs still mention `HostTableConfigStore` table context and must be updated after table migration.

## 16. Target architecture

### 16.1 Startup coordinator

One startup coordinator should own:

1. Load credentials/session.
2. Load SwiftData cache immediately.
3. Release UI if cache exists.
4. Run one startup freshness decision for active reservation window.
5. Fetch active window only if stale.
6. Start noncritical setup, availability, guest intelligence, and diagnostics only after UI release.
7. Prevent views from starting duplicate startup work.

Acceptance trace examples:

```text
[STARTUP] cache hit; UI released=true
[API] SKIP reason=scope_skip_fresh
[API] START reason=active_window_delta
```

### 16.2 Freshness coordinator

Create a central freshness coordinator for date/range/scope work:

- Active reservation window.
- Floor plan by date.
- Availability bundle by date.
- Guest Intelligence date summary and reservation profile.
- Business analytics range.

It should answer: fresh, stale, in-flight, failed cooldown, or must fetch. Views ask; they do not decide independently.

### 16.3 Screen activation rules

- Tab open must not blindly refetch.
- Active tab can request freshness for its visible scope.
- If fresh, apply cache and log skip.
- If stale, fetch once per scope/date/range.
- Inactive tabs can observe cache but must not start loops.
- `.task(id:)` should be limited to one screen coordinator per screen, not many independent tasks.

### 16.4 Mutation/reconcile rules

- Mutations are server-first unless the optimistic UI is trivially reversible.
- Server response remains truth.
- Uncertain network errors reconcile by ID or active date/window.
- 404/not-found after mutation means server truth may be “already gone,” not simply failure.
- Conflict responses should be typed and staff-safe.
- Notices should describe final truth, not request intent.

### 16.5 Multi-device sync rules

- All mutations handle 404, 409, stale state, and terminal-state conflicts.
- After conflict, refresh affected reservation, active date, or active window.
- If deleted/hidden elsewhere, remove or hide local cache after confirmatory reconcile.
- Staff copy: “changed on another device” or “already gone on the server.”

### 16.6 Table/floor-plan canonical path

- Backend floor layout is canonical.
- `PUT /restaurant-tables` creates/updates layout.
- `GET /floor-plan?date=` is selected-date floor truth.
- `PATCH /managed-reservations/{id}/tables` is canonical assignment/clear.
- `ReservationDTO.tableName` is compatibility display only.
- Old local table inventory becomes advisory fallback until removed.

### 16.7 Intelligence/LLM canonical path

- Backend intelligence evidence first.
- Local cache fallback only when scoped and clearly less certain.
- Host engine facts/actions first.
- LLM may rewrite only approved packets.
- Validators/sanitizers stay strict.
- Template fallback remains the default safety net.

## 17. Step-by-step implementation plan

### Phase 1 — Freeze and measurement

Goal: measure current lag/refetch behavior without changing behavior.

Files likely changed: trace helpers, `ReservationsController`, `HostBoardView`, `FloorPlanStore`, `GuestIntelligenceStore`, `BusinessAnalyticsCoordinator`, diagnostics docs.

What not to touch: backend routes, DTO shapes, mutation semantics, SwiftData schema, LLM validators.

Acceptance logs:

```text
[STARTUP] cache hit; UI released=true
[API] SKIP reason=scope_skip_fresh
[UI_PRESSURE_TRACE] phase=host_engine_evaluate duration=<50ms
[FLOOR_PLAN_TRACE] event=load_completed
[HOST_REEVAL_TRACE]
```

Device test checklist: launch with cache, switch all tabs, open detail, open Manual Add, open Floor, run one mutation, watch logs for duplicate fetches.

Rollback plan: remove added trace calls only.

### Phase 2 — Centralize freshness decisions

Goal: introduce a freshness coordinator that records and dedupes scope/date/range decisions.

Files likely changed: new freshness coordinator, `ReservationsController`, `ReservationAvailabilityFacade`, `FloorPlanStore`, `GuestIntelligenceStore`, `BusinessAnalyticsCoordinator`.

What not to touch: repository write semantics, backend endpoints, UI layout.

Acceptance logs:

```text
[API] SKIP reason=scope_skip_fresh
[FRESHNESS] key=floor_plan date=... action=use_cached
[FRESHNESS] key=guest_intelligence date=... action=in_flight
```

Device test checklist: open Floor twice, switch Host/Bookings repeatedly, date switch quickly, verify one fetch per stale scope.

Rollback plan: keep coordinator as passive logger, route calls back to existing store checks.

### Phase 3 — Stabilize tab lifecycle

Goal: reduce per-view task fanout and ensure one lifecycle owner per visible screen.

Files likely changed: `HostBoardView`, `ReservationsListView`, `FloorPlanView`, `ReservationScheduleView` nested code, `BusinessAnalyticsView`.

What not to touch: action buttons, mutation services, table migration.

Acceptance logs:

```text
[TAB_LIFECYCLE] host active=true coordinator=start
[TAB_LIFECYCLE] host active=false coordinator=stop
[API] SKIP reason=auto_skip_inactive
```

Device test checklist: rapid tab switching, background/foreground, host auto-refresh, floor auto-refresh, Bookings stale activation.

Rollback plan: re-enable existing `.task(id:)` blocks behind flags.

### Phase 4 — Stabilize mutation/reconcile/multi-device behavior

Goal: make server-truth conflict and not-found behavior explicit.

Files likely changed: `ReservationAPIError`, `ReservationMutationService`, `ReservationsController`, action/detail sheets, `FloorPlanStore`.

What not to touch: backend routes, optimistic status UX except copy/reconcile, hard delete authorization.

Acceptance logs:

```text
[MUTATION] result=not_found action=hide reservation=...
[API] START reason=reconcile_by_id
[MUTATION] server_truth_refreshed scope=active_window
```

Device test checklist: delete/hide/change same reservation from another device, then attempt action locally; confirm staff-safe copy and refreshed list.

Rollback plan: fallback to current generic failure copy while preserving typed error decoding.

### Phase 5 — Resolve table architecture conflict

Goal: route all table assignment through backend floor-plan assignment without breaking staff flow.

Files likely changed: `ReservationActionButtons.swift`, `ReservationDetailView.swift`, `HostBoardView.swift`, `FloorPlanStore`, `FloorPlanService`, `HostTableConfigStore`, table docs.

What not to touch: floor layout backend, assignment conflict rules, LLM auto-assignment boundary.

Acceptance logs:

```text
[API] START reason=reservation_tables_patch
[FLOOR_PLAN_TRACE] event=assign_completed
[FLOOR_PLAN_TRACE] event=load_completed tables=...
```

Device test checklist: assign from Floor, assign from Detail, conflict same table/time, seated table conflict, clear assignment, verify `table_name` display compatibility.

Rollback plan: keep old `tableName` sheet behind compatibility fallback if no backend layout exists.

### Phase 6 — Reduce SwiftData/main-actor pressure

Goal: move heavy analysis to value snapshots and reduce mounted-tab recomputation.

Files likely changed: `GuestInsightsAnalysisCoordinator`, `RegularGuestsView`, `GuestProfileFacade`, `HostBoardViewStateStore`, repository batch helpers.

What not to touch: SwiftData schema, backend intelligence contracts, Host engine facts.

Acceptance logs:

```text
[UI_PRESSURE_TRACE] phase=context_save duration=<50ms
[UI_PRESSURE_TRACE] phase=guest_analysis duration=<100ms
[UI_PRESSURE_TRACE] phase=host_snapshot_build duration=<30ms
```

Device test checklist: sync large active window, open More/Regular Guests, open detail with history, verify no gesture timeout warnings.

Rollback plan: keep old analysis path behind a debug setting.

### Phase 7 — Reconnect intelligence safely

Goal: make backend evidence the default and local/LLM layers explicitly subordinate.

Files likely changed: `GuestIntelligenceStore`, `GuestProfileFacade`, `HostIntelligenceController`, `HostIntelligenceEngine`, guest messaging docs.

What not to touch: validators, sanitizers, no-auto-send/no-auto-mutate rules.

Acceptance logs:

```text
[GUEST_INTEL] source=reservation_endpoint
[HOST_AI] model_output_used source=template|localModel
[HOST_AI] model_output_rejected reason=...
```

Device test checklist: Host guest card with backend summary, detail profile pack, backend unavailable fallback, unsafe local model output fallback.

Rollback plan: force template/local-cache fallback while preserving backend fetch cache.

### Phase 8 — Product polish after architecture stability

Goal: polish UI after fetch/mutation/table truth is stable.

Files likely changed: Host/Bookings/Floor/detail forms, settings navigation, diagnostics copy.

What not to touch: freshness coordinator, mutation result semantics, backend contracts.

Acceptance logs:

```text
[API] SKIP reason=scope_skip_fresh
[MUTATION] server_truth_refreshed
[FLOOR_PLAN_TRACE] event=layout_save_completed
```

Device test checklist: full service rehearsal, two-device conflict rehearsal, manager role, developer diagnostics, airplane mode recovery.

Rollback plan: UI-only changes revert independently from architecture layers.

## 18. P0/P1/P2 priorities

P0:

- Fix multi-device mutation semantics for 404/not-found/already-hidden/already-deleted.
- Resolve table assignment canonical path drift.
- Add measurement for duplicate fetches and Host UI pressure.
- Ensure Floor Plan setup/save/floor refresh proof is stable.

P1:

- Central freshness coordinator.
- Reduce Host Board task fanout.
- Move detail/guest analysis to snapshots.
- Unify availability slot loading for Host/Manual Add/settings.

P2:

- Rename misleading methods.
- Retire legacy review/today/schedule wrappers.
- Split `RestaurantSettingsStore` UI from store.
- Update stale docs and diagnostics checklists.
- Persist active-window cursor by window key if not already sufficient.

## 19. Do-not-touch stable areas

- Backend route paths and field names.
- `POST /managed-reservations/import` forbidden rule.
- SwiftData `ReservationRecord` schema without a migration plan.
- `replaceDateWindow` and delta upsert-only semantics unless explicitly tested.
- Manual Gmail/Mail draft boundary: nothing auto-sends.
- LLM validators and sanitizer strictness.
- Hard delete backend authorization.
- Public reservation-slot response privacy.

## 20. Open questions

- Should `.staff` become selectable in the current pilot, or stay dormant?
- Should active-window cursor persistence be expanded to include floor-plan/availability freshness keys?
- Should the old table-name freeform field remain as manager fallback after backend layout migration?
- What exact copy should distinguish “already hidden” from “hard deleted on another device”?
- Should Guest Intelligence profile packs become the default for all detail/guest profile surfaces before local analysis runs?
- Should Floor Plan auto-refresh be coordinated with reservation active-window refresh or remain independent?
- What device dataset size should define acceptable Host Board/Guest Insights performance thresholds?
- Should diagnostics expose a dedicated “multi-device conflict rehearsal” checklist?
- Should Restaurant Settings table import be hidden once backend layout setup is verified?
- Should the backend expose a lightweight reservation mutation version/ETag for stale update detection later?

---

# iOS Final Stabilization Pass (branch: intelligence)

This section is appended live during the stabilization pass. Each phase records what
was implemented, files changed, risk reduced, new traces, and proof status.

## Current Implementation Reality Check (Phase 0)

Confirmed from code, not prior agent claims:

| Component | Exists | Wired into real flow? | Notes |
| --- | --- | --- | --- |
| `FreshnessCoordinator` | Yes | Partial | Used by `FloorPlanStore` + `AppReservationSession`. NOT used by `ReservationsController` active-window/startup (still uses `syncStateByScope` + `isScopeFresh`). |
| `ReservationMutationReconcilePolicy` | Yes | **No → now Yes (Phase 3)** | Before: only its own file referenced it. Now wired into edit/status/hide/restore/delete/confirm catch sites + table-conflict trace. |
| `MutationVersionTrace` | Yes | **No → now Yes (Phase 4)** | Before: defined, never called. Now emitted on every PATCH mutation + table assignment. |
| `SwiftDataTrace` | Yes | Partial | Integrated in `ReservationRepository`. No structural cleanup yet (Phase 11). |
| `HostBoardLifecycleCoordinator` | Yes | Yes | Drives Host lifecycle in `HostBoardView`. |
| `FloorPlanStore` | Yes | Yes | Uses `FreshnessCoordinator`; canonical table assignment path. |
| `ReservationDetailView` table path | Yes | Yes | Canonical when backend layout exists, legacy `table_name` fallback otherwise. |
| `ReservationsController` active-window | Yes | Legacy | Own startup policy + scope freshness. `FreshnessCoordinator` not yet wired here (Phase 5 target). |
| `HostBoardView` header/status copy | Yes | **Fixed (Phase 1)** | `loadingTodayOperations` previously read "Loading today's operations…" over visible cache. |
| Arrival Flow chart | Yes | **Fixed (Phase 2)** | Was a line/wave + single dot → regressed to a lonely floating dot. Now rounded bars. |
| Navigation/onChange handlers | Yes | Symptom present | Repeated "tried to update multiple times per frame" warnings (Phase 8 target). |

## Phase 1 — False Home loading state (DONE)

- **Implemented:** `StartupBackgroundWorkState.loadingTodayOperations.staffProgressLabel`
  changed from "Loading today's operations…" to "Checking available times…". This state
  is only ever set while `ReservationsController.isLoadingHostTodayAvailabilityBundle()`
  is true (today's availability bundle loading), with cached reservations already visible.
- **Files:** `Features/Reservations/ReservationSharedUI.swift`,
  `Import/StartupPolicyTrace.swift`, `Import/ReservationsController.swift`.
- **Risk reduced:** Misleading "still loading" copy over a populated board during service.
- **New trace:** `[HOME_STATUS_TRACE] state=<primary> copy=<secondary> dot=<style>` emitted
  from `refreshHomeServicePresentation` whenever the presentation changes.
- **Status mapping (header secondary line):** freshness check → "Checking service…";
  availability loading → "Checking available times…"; setup → "Checking Tryzub service…";
  manual refresh in-flight with cache → "Checking service…"; idle → none / "Checked HH:mm".
- **Proof:** Builds clean. Device proof pending (look for absence of
  "Loading today's operations…" in `[STARTUP_POLICY] header` / `[HOME_STATUS_TRACE]`).

## Phase 2 — Arrival Flow chart (DONE)

- **Implemented:** Rewrote `ReservationDensityWaveChart` from a line/area + floating dot
  renderer into compact rounded bars (one bar per 15-min window, value = guest count).
  Empty buckets render as a faint baseline nub so empty hours never dominate; arrival
  windows get a prominent rounded bar with a value label; peak bar is emphasized; tap a
  bar to see the window summary; existing footer/peak/next labels retained.
- **Data source:** existing `arrivalBuckets` from Host Board view-state (no refetch).
- **Files:** `Features/Reservations/ReservationDensityWaveChart.swift`.
- **Risk reduced:** Unusable "tiny floating dot" for single-window days (e.g. 4 guests @ 19:30).
- **New trace:** `[ARRIVAL_CHART_TRACE] buckets=N arrivals=M peak=HH:mm renderer=rounded_bars`.
- **Proof:** Builds clean. Device proof pending (expect a clear bar at 19:30 for the
  2-reservation/4-guest sample day).

## Phase 3 — Mutation reconcile policy wired (DONE)

- **Implemented:** `applyMutationReconcilePolicy(error:action:id:reservationDate:context:)`
  helper on `ReservationsController` classifies failures via
  `ReservationMutationReconcilePolicy.classify` and:
  - `.alreadyGone` (404): deletes the local row, marks scopes stale, posts
    `MutationOutcome.copyAlreadyGone` ("…already gone on the server. Saved data was refreshed.").
  - `.alreadyChanged` / `.invalidTransition` (409): reconciles server truth, posts
    `MutationOutcome.copyAlreadyChanged`.
  - `.uncertainNeedsReconcile`: returns false → caller keeps its existing uncertain-network flow.
- **Call sites wired:** `updateReservation` (edit), `updateStatus` (status),
  `hideWrongEntry` (hide), `restoreHiddenReservation` (restore), `hardDeleteReservation`
  (delete), `confirmReservation` (confirm). Floor Plan table conflict emits
  `ReservationMutationReconcilePolicy.traceTableConflict`.
- **Files:** `Import/ReservationsController.swift`,
  `Services/ReservationMutationReconcilePolicy.swift`, `Features/FloorPlan/FloorPlanStore.swift`.
- **Risk reduced:** Stale delete/hide/status no longer shows misleading raw "could not"
  errors; local cache converges to server truth; rows don't stay stuck.
- **New traces:** `[MUTATION_RECONCILE] action=… id=… outcome=already_gone|already_changed|invalid_transition|table_conflict`.
- **Remaining unhandled:** manual email-log path keeps its own copy (low risk, no
  server-truth conflict). Table conflict UI still owned by Floor Plan (intentional).
- **Proof:** Builds clean. Device proof requires a two-device stale mutation.

## Phase 4 — expected_updated_at sent (DONE, with documented gaps)

- **Implemented:** Added `ReservationRecord.rowVersion` (= `apiUpdatedAt ?? createdAt`) and
  `ReservationRepository.rowVersion(forRemoteID:)`. `updateReservation` now attaches the
  cached row version as `expected_updated_at` when the caller didn't supply one.
  Hide/restore (which call the service directly) attach `reservation.rowVersion`. Table
  assignment PATCH carries `expected_updated_at` via `PatchReservationTablesRequest`.
- **Endpoints now sending `expected_updated_at`:**
  - `PATCH /managed-reservations/{id}` (edit / status / hide / restore) ✓
  - `PATCH /managed-reservations/{id}/tables` ✓
- **Documented gaps (intentionally not changed this pass):**
  - `DELETE /managed-reservations/{id}`: client sends `?force=1` only (admin cleanup).
    404 is already handled by the reconcile policy; adding an optimistic guard would
    change force-cleanup semantics. Gap left intentionally.
  - `POST /managed-reservations/{id}/confirm`: client sends no body; not wired to avoid
    expanding the client contract. Gap left intentionally.
- **Encoding:** `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase` → `expectedUpdatedAt`
  becomes `expected_updated_at`; nil is omitted (synthesized `encodeIfPresent`), so no
  request fails on an unknown/empty field.
- **Files:** `Persistence/ReservationRecord.swift`, `Services/ReservationRepository.swift`,
  `Import/ReservationsController.swift`, `Network/FloorPlanDTO.swift`,
  `Services/FloorPlanService.swift`, `Features/FloorPlan/FloorPlanStore.swift`.
- **New trace:** `[MUTATION_VERSION_TRACE] action=… id=… expected_updated_at=present|missing`.
- **Proof:** Builds clean. Device proof: confirm `present` on edit/status/table when the
  row is cached.

## Phase 5 — FreshnessCoordinator wired into active-window lifecycle (DONE, measured)

- **Approach (honest):** `ReservationsController` already has a proven scope-state machine
  (`syncStateByScope` + `isScopeFresh` + `beginScope` + cooldowns) that device logs show
  works — `[API] SKIP reason=scope_skip_fresh` fires and empty deltas never delete rows.
  Ripping that out mid-service is unsafe, so the shared `FreshnessCoordinator` is injected
  as the **shared decision authority/recorder** while the scope-state machine remains the
  **executor**. The coordinator's state (`markInFlight`/`markCompleted`/`markFailed`) now
  tracks active-window fetches so Phase 6 surfaces can consult one authority.
- **Implemented:**
  - `AppReservationSession` injects its single `FreshnessCoordinator` into the controller.
  - `recordActiveWindowFreshness(_:)` mirrors each active-window decision into the shared
    `[FRESHNESS_COORDINATOR]` log: startup skip → `use_cache`, scope-fresh skip →
    `use_cache`, scope-in-flight → `join_in_flight`, network start → `fetch`.
  - `markInFlight` on network start; `markCompleted` on success; `markFailed` on
    failure/cancel; `markCacheHit` on startup cache-fresh skip.
- **Files:** `Services/AppReservationSession.swift`, `Services/FreshnessCoordinator.swift`
  (added `record`), `Import/ReservationsController.swift`.
- **Risk reduced:** Decisions are now observable in one vocabulary; coordinator state is
  authoritative for the active window (foundation for Phase 6).
- **New traces:** `[FRESHNESS_COORDINATOR] scope=activeWindow(from–to) decision=use_cache|fetch|join_in_flight reason=…`.
- **Remaining:** Full executor migration (coordinator as the sole gate) is intentionally
  deferred. The acceptance behavior ("Host open after cache hit does not duplicate
  active-window fetch") is already enforced by the existing machine and now visible via
  the coordinator log. Device proof pending.

## Phase 7 — No-op refresh trace (INSTRUMENTED)

- **Implemented:** `[NOOP_REFRESH_TRACE]` emitted alongside `[CACHE] upsert finished`,
  computing `publishSemanticChange = written>0 || removed>0`. A no-op refresh
  (written=0, removed=0) reports `publishSemanticChange=false`.
- **Files:** `Services/ReservationRepository.swift`.
- **Finding (from device log):** The transient `host_snapshot_build … reservations=0`
  occurred immediately before `[HOST_LIFECYCLE] event=hidden` (tab transition to Floor),
  i.e. it correlates with navigation/visibility, not with the no-op upsert (which already
  wrote 0 / skipped 38). This points at Phase 8 (navigation churn) / Phase 11
  (`unsafeForcedSync`) rather than a semantic publish from the repository. The trace lets
  the next device run confirm no-op refresh does not publish a semantic change.
- **Status:** Instrumented; behavioral fix (if still needed) depends on Phase 8/11 device proof.

## Phase 8 — Navigation/onChange churn (PARTIAL mitigation)

- **Finding:** `NavigationRequestObserver` is a SwiftUI-internal observer, not an app type.
  The startup `onChange(of: String)` ×8 / `onChange(of: Bool)` warnings come from handlers
  that synchronously publish controller state mid-frame.
- **Implemented:** Coalesced the clearest offender — `HostBoardView`
  `.onChange(of: hostBoardOperationalLoading)` now defers `refreshHomeServicePresentation`
  by one runloop tick (`Task { @MainActor in await Task.yield(); … }`). That call publishes
  state which feeds back into `hostBoardOperationalLoading`, so a synchronous update inside
  onChange produced "tried to update multiple times per frame".
- **Files:** `Features/Reservations/HostBoardView.swift`.
- **Honest status:** This is a targeted mitigation, not a full fix. The remaining
  `onChange(of: String)` warnings (date-string observers across the header selector,
  settings `dateKey`, schedule filters) need device reproduction to attribute precisely;
  they were left untouched to avoid destabilizing working navigation without runtime proof.

## Phases NOT completed this pass (honest)

- **Phase 6 (coordinator into guest/profile/BI/settings):** NOT done. Foundation laid in
  Phase 5 (coordinator is now injected + authoritative for active window). Per-surface
  wiring deferred.
- **Phase 9 (Floor Plan save proof):** NOT proven. Requires running Set Up Tables → Save
  on device and capturing `restaurant_tables_put status=200` + `floor_plan … tables>0`.
  No save-wiring defect found in code review; backend simply has no saved layout yet.
- **Phase 10 (Host table-assignment canonical migration):** NOT done. Detail path is
  canonical-when-layout-exists (prior pass); Host assignment path still needs auditing
  + `[TABLE_ASSIGNMENT_TRACE] source=host`.
- **Phase 11 (SwiftData/concurrency cleanup):** NOT done. `unsafeForcedSync` correlates
  with refresh/navigation; needs a device-reproduced stack to fix safely.
- **Phase 12 (Intelligence/LLM verification):** Not re-verified this pass (build compiles;
  prior pass wired backend floor tables + broader history).
- **Phase 13 (polish):** Deferred until stability is device-proven.

## Build status after Phases 1–8 work

`xcodebuild -scheme "Tryzub Reservations" -destination generic/platform=iOS build-for-testing`
→ **TEST BUILD SUCCEEDED** after every phase (only a pre-existing MainActor note in
`GuestConfirmationMail.swift`). No new linter errors in touched files.

## Device proof required (cannot be produced in this environment)

These were verified to **compile**, but runtime/device proof must be captured on the
physical device by re-running the same flows:
1. Launch with cache → expect no `Loading today's operations…`; `[HOME_STATUS_TRACE]`
   shows `Checking available times…` / `Checking service…`; `[FRESHNESS_COORDINATOR]
   scope=activeWindow decision=use_cache`.
2. Arrival Flow → clear bar at 19:30 for the 2-reservation/4-guest day; `[ARRIVAL_CHART_TRACE] renderer=rounded_bars`.
3. Two-device stale mutation → `[MUTATION_RECONCILE] outcome=already_gone|already_changed`.
4. Any edit/status/table change → `[MUTATION_VERSION_TRACE] expected_updated_at=present`.
5. Manual refresh of unchanged data → `[NOOP_REFRESH_TRACE] publishSemanticChange=false`;
   Host should not flash to 0.
6. Navigation launch → Host → Floor → More → back: confirm reduction in
   `onChange … multiple times per frame` warnings.

---

# Final Runtime Stabilization Results (active-window TTL, availability coordinator, adaptive arrival chart, concurrency instrumentation)

This pass acted on the second device run, which confirmed the false-loading-state fix and
the rounded-bar chart are working, and surfaced three remaining runtime issues plus a chart
refinement request.

## Phases completed

### Phase 1 — Active-window FreshnessCoordinator TTL/key mismatch (FIXED)
- **Root cause:** `autoRefreshDashboardIfAllowed` gated only on `lastAutoRefreshAttemptAt`
  (nil at launch) and the `.automatic` path in `performActiveWindowRefreshBody` deliberately
  bypasses the `isScopeFresh` skip (so the 60s cadence keeps polling during live service).
  On a fresh-cache launch this produced `decision=use_cache reason=startup_cache_fresh`
  immediately followed by `decision=fetch reason=stale_automatic` — an instant redundant
  `active_window_delta`.
- **Key identity:** verified the `activeWindow(from:to:)` scope is built from the same
  `activeWindow()`/`activeWindowScope()` for startup, auto-refresh, and success-marking, so
  there is **no real key mismatch**. The `2026-06-09–2026-08-09` (en-dash, coordinator
  `description`) vs `2026-06-09...2026-08-09` (controller `ReservationSyncScope.description`)
  difference is cosmetic across two trace vocabularies; the Hashable key uses the raw
  `from`/`to` strings, which match.
- **Fix:** `autoRefreshDashboardIfAllowed` now consults active-window freshness
  (`isScopeFresh(scope, freshnessInterval: autoRefreshInterval)`) before attempting. If the
  window is fresh it records `[FRESHNESS_COORDINATOR] … decision=use_cache reason=fresh_automatic`,
  logs `[API] SKIP reason=scope_skip_fresh … auto refresh skipped because cache is fresh`,
  and returns. Manual pull-to-refresh still forces (unchanged). Host and Bookings share the
  same `activeWindow()` scope, so the key is identical for both.
- **Rule (final):** *Auto-refresh fetches the active window only after the
  `autoRefreshInterval` TTL elapses since the last successful sync, or on manual force. A
  fresh-cache launch never triggers an immediate automatic delta.*
- **Files:** `Import/ReservationsController.swift`.

### Phase 2 — Availability bundle moved onto FreshnessCoordinator (DONE)
- The availability bundle (`restaurant-day-availability` + `reservation-slots` +
  `restaurant-blocked-slots`, loaded serially in `loadAvailabilitySummary`) now records its
  decisions on `FreshnessScope.availabilityBundle(date:)`:
  - fresh cache → `record(.useCache(reason: "fresh"))`
  - already loading → `record(.joinInFlight(reason: "in_flight"))`
  - proceed → `record(.fetch(reason: "host_visible_stale"|"forced"))` + `markInFlight`
  - success → `markCompleted` (sets `lastFetchedAt`, becomes the TTL anchor)
  - genuine error → `markFailed(cooldown: 15)`
  - ignored/cancelled (selected date changed mid-flight) → `endInFlight` (new coordinator
    method: clears in-flight without faking freshness or starting a cooldown).
- The existing `HostBoardLifecycleCoordinator` `skip_availability reason=fresh/in_flight`
  dedup (proven working in the device log) is retained as the executor; the coordinator is
  now the visible authority via `[FRESHNESS_COORDINATOR] scope=availabilityBundle(date) …`.
- `DateLoadTrace.ignoredResponse` (date-change race protection) is unchanged and still fires.
- **Files:** `Import/ReservationsController.swift`, `Services/FreshnessCoordinator.swift`
  (added `endInFlight`).

### Phase 3 — unsafeForcedSync / gesture-timeout instrumentation (INSTRUMENTED + localized)
- Added `Import/DateSwitchTrace.swift` emitting:
  - `[DATE_SWITCH_TRACE] from=… to=… phase=begin` (in `noteHostBoardSelectedDate`)
  - `[DATE_SWITCH_TRACE] date=… phase=availability_start`
  - `[DATE_SWITCH_TRACE] date=… phase=availability_publish duration=…ms`
  - `[CONCURRENCY_TRACE] context=availability_completion modelContextUsed=false`
- **Finding (code-verified, device-confirm pending):** `HostBoardView` has **no `@Query`**;
  `reservations` is a passed-in array, and `loadAvailabilitySummary` touches only
  `@Published` in-memory dictionaries on the MainActor — it never opens or reads a
  SwiftData `ModelContext`. Therefore the `unsafeForcedSync` warning is **not** in the
  availability/date-switch completion path; it correlates instead with SwiftData
  framework-level access during reservation upsert/mutation, which is the documented
  remaining path. The `System gesture gate timed out` line coincides with the long
  first-load `restaurant_day_availability` (1.87s) request and is the gesture system noting
  the in-flight await, not a main-thread block in our code.
- Per the instructions ("instrument first, fix only obvious problems, do not rewrite
  persistence") no persistence rewrite was attempted; the remaining path is now tied to a
  named trace for the next device repro.
- **Files:** `Import/DateSwitchTrace.swift`, `Import/ReservationsController.swift`.

### Phase 4 — Professional adaptive 15-minute Arrival Flow chart (DONE)
- Data model already buckets every 15 minutes across the service range; this pass made the
  **labels** adaptive so the axis never crowds while bars stay at 15-minute granularity.
- Added `@Environment(\.horizontalSizeClass)` and a measured plot width
  (`measuredPlotWidth`, captured via `onAppear`/`onChange` on the chart's GeometryReader).
- `labelStrideMinutes`:
  - ≥34 pt per bucket → label every **15 min**
  - regular width (iPad) or ≥22 pt per bucket → label every **30 min**
  - otherwise (compact iPhone, dense day) → label **hourly**
- `xLabelIndices` now strides by `minute % stride == 0` with hour:minute de-duplication;
  30-minute labels render `displayTime` (e.g. `18:30`) via the existing axis-label fallback.
- Peak bucket emphasis, faint empty-bucket baseline, safe ratios (no NaN/zero-division),
  and bar-width cap are retained from the prior pass.
- Trace enriched: `[ARRIVAL_CHART_TRACE] buckets=… arrivals=… peak=… renderer=rounded_bars
  widthClass=compact|regular labelStride=…min`.
- **Files:** `Features/Reservations/ReservationDensityWaveChart.swift`.

## Phases requiring device proof (cannot be produced in this environment)

### Phase 5 — Floor Plan save proof (NOT proven; needs hardware run)
- No save-wiring defect found in code review; the device log simply shows `tables=0`
  because no layout has been saved to this restaurant yet. Capture on device:
  Floor → Set Up Tables → seed T1/T2/T3 → Save → expect
  `[API] START/END reason=restaurant_tables_put status=200`,
  `[FLOOR_PLAN_TRACE] event=layout_save_completed tables=…`, then
  `[FLOOR_PLAN_TRACE] event=load_completed … tables>0`.

### Phase 6 — Mutation reconcile real-path proof (NOT proven; needs hardware run)
- Reconcile policy is wired into `updateReservation` (edit/status), `hideWrongEntry`,
  `restoreHiddenReservation`, `hardDeleteReservation`, `confirmReservation`, and the Floor
  Plan assignment-conflict path. `expected_updated_at` is populated from the cached
  `rowVersion` for PATCH mutations. Capture on device by performing a real edit/status/hide
  /delete (and a stale 409 if dev tooling allows):
  `[MUTATION_VERSION_TRACE] action=… expected_updated_at=present` and
  `[MUTATION_RECONCILE] action=… outcome=already_gone|already_changed|table_conflict`.

## Files changed this pass
- `Tryzub Reservations/Import/ReservationsController.swift` — auto-refresh freshness gate;
  availability bundle coordinator wiring (decide/in-flight/complete/fail/endInFlight);
  date-switch + concurrency traces.
- `Tryzub Reservations/Services/FreshnessCoordinator.swift` — added `endInFlight(_:)`.
- `Tryzub Reservations/Features/Reservations/ReservationDensityWaveChart.swift` — adaptive
  width-class label stride, measured width, enriched trace.
- `Tryzub Reservations/Import/DateSwitchTrace.swift` — new instrumentation utility.

## Build status
`xcodebuild -scheme "Tryzub Reservations" -destination generic/platform=iOS build-for-testing`
→ **TEST BUILD SUCCEEDED** after Phases 1–4. No new linter errors in touched files.

## Expected device traces after this pass
- Fresh-cache launch: `[FRESHNESS_COORDINATOR] scope=activeWindow(…) decision=use_cache
  reason=startup_cache_fresh` is **no longer** followed by
  `decision=fetch reason=stale_automatic`; instead `decision=use_cache reason=fresh_automatic`
  + `[API] SKIP reason=scope_skip_fresh … auto refresh skipped because cache is fresh`.
- Date switching: `[FRESHNESS_COORDINATOR] scope=availabilityBundle(2026-06-11)
  decision=fetch reason=host_visible_stale` then `decision=use_cache reason=fresh_…s_of_300s`
  when returning to a recently loaded date; `decision=join_in_flight` on rapid toggles.
- Chart: `[ARRIVAL_CHART_TRACE] … widthClass=compact labelStride=60min` (iPhone) /
  `widthClass=regular labelStride=30min` (iPad).
- Date switch lifecycle: `[DATE_SWITCH_TRACE] … phase=begin/availability_start/availability_publish`
  and `[CONCURRENCY_TRACE] context=availability_completion modelContextUsed=false`.

## Remaining risks
- `unsafeForcedSync` is localized away from availability completion but its true source
  (SwiftData upsert/mutation framework access) still needs a device-reproduced stack.
- Availability bundle TTL anchor is `lastFetchedAt` set on full success; a partial failure
  mid-bundle (e.g. blocked-slots 4xx after day-availability 200) starts a 15s cooldown and
  re-fetches the whole bundle, which is acceptable but not granular per-endpoint.
- Floor Plan save and mutation reconcile remain unproven until the hardware run.

## Next recommended task
Capture the Phase 5 (Floor Plan Save) and Phase 6 (mutation reconcile) device logs, then
use a two-device stale-409 to confirm `[MUTATION_RECONCILE] outcome=…`. After that, attempt
the SwiftData `unsafeForcedSync` repro with `[CONCURRENCY_TRACE]` breadcrumbs to find the
exact mutation/upsert call that triggers it.

---

# Final Runtime Fix Pass — Floor Save 400, Bookings Refetch, Chart 0-Height

Device run confirmed startup cache-first, the active-window auto-refresh gate, the
availability-bundle coordinator, and the adaptive arrival chart are all working
(`[FRESHNESS_COORDINATOR] decision=use_cache reason=startup_cache_fresh`,
`[API] SKIP reason=scope_skip_fresh`, `[ARRIVAL_CHART_TRACE] widthClass=compact labelStride=30/60min`,
`[DATE_SWITCH_TRACE]` + `[CONCURRENCY_TRACE] modelContextUsed=false`). This pass fixed the
remaining blockers it surfaced.

## Phase 1 — Floor Plan layout save HTTP 400 (ROOT CAUSE FOUND + FIXED)
- **Root cause (backend-verified):** `includes/floor-plan.php` `tryzub_parse_restaurant_table_definitions`
  rejects unknown fields (`tryzub_unknown_restaurant_table_field`, HTTP 400). Its
  `$allowed_fields` = `[table_key, label, x, y, width_units, height_units, min_capacity,
  max_capacity, section, sort_order, is_active]` — it does **not** allow `restaurant_key`
  or `id`. The iOS `RestaurantTableUpsertDTO.encode` always sent `restaurant_key` (→
  `restaurant_key` after snake-case), so every PUT was rejected before any
  overlap/capacity check. The upsert is `partial_by_table_key` and the server derives the
  restaurant from auth, so those fields must not be sent.
- **Fix:** removed `restaurant_key` and `id` from `RestaurantTableUpsertDTO` CodingKeys and
  `encode(to:)`. The PUT body now contains only the backend's allowed fields. Backend was
  **not** changed — the client was sending fields the documented contract forbids.
- **Sanitized diagnostics added:**
  - Before PUT: `[FLOOR_PLAN_TRACE] event=layout_save_payload tables=3 keys=[T1,T2,T3] active=3 bounds=WxH`.
  - On failure: backend code/status threaded via new `FloorPlanError.serverValidation(code:status:message:)`
    → `[FLOOR_PLAN_TRACE] event=layout_save_failed code=… status=400 backendMessage="…"`.
    Staff copy stays "Could not save layout. Check the table positions and try again."
- **Files:** `Network/FloorPlanDTO.swift`, `Network/FloorPlanError.swift`,
  `Services/FloorPlanService.swift`, `Features/FloorPlan/FloorPlanStore.swift`.
- **Expected device proof:** `[API] END reason=restaurant_tables_put status=200` →
  `[FLOOR_PLAN_TRACE] event=layout_save_completed tables=3` →
  `[FLOOR_PLAN_TRACE] event=load_completed … tables>0`.

## Phase 2 — Floor save vs refresh overlap (FIXED)
- `FloorPlanStore.refresh(...)` gained `allowDuringSave` (default false). While
  `isSavingLayout == true`, any automatic/competing refresh is suppressed and logs
  `[FLOOR_PLAN_TRACE] event=refresh_suppressed reason=layout_save_in_flight`. Only the
  save's own post-success refresh passes `allowDuringSave: true`, so exactly one forced
  refresh runs after a 200.
- The Save button is already `.disabled(store.isSavingLayout || drafts.isEmpty)` in
  `FloorPlanLayoutSetupView` (verified), satisfying "disable while in flight".
- **Files:** `Features/FloorPlan/FloorPlanStore.swift`.

## Phase 3 — Bookings/schedule activation full-fetch (FIXED)
- **Root cause:** the startup cache-fresh `.skip` path updated `lastFreshnessCheckedAt`
  but never updated the active-window scope `lastSuccessAt`. So the 300s schedule TTL kept
  counting from the *old persisted* success time; tapping Bookings ~5 min after launch was
  legitimately stale and full-fetched (`decision=fetch reason=stale_schedule`).
- **Fix:** the startup `.skip` case now calls `markScopeRecentlyTouched(scope)`, anchoring
  the active-window freshness clock to the startup confirmation. This is **session-only**
  (not persisted — `markScopeRecentlyTouched` does not call `persistSyncMetadata`), so
  cross-launch staleness stays honest, but a Bookings tap within the 300s window after
  launch now uses cache. `scheduleBecameActive` also records
  `[FRESHNESS_COORDINATOR] decision=use_cache reason=fresh_schedule_activation` on skip.
- **TTL summary:** Host auto-refresh = 60s (Phase 1 of prior pass); schedule/Bookings
  activation = 300s (`scheduleFreshnessInterval`); manual refresh forces.
- **Files:** `Import/ReservationsController.swift`.
- **Expected device proof (relaunch + tap Bookings shortly after):**
  `[FRESHNESS_COORDINATOR] scope=activeWindow(…) decision=use_cache reason=fresh_schedule_activation`
  + `[API] SKIP reason=scope_skip_fresh … schedule activation skipped because cache is fresh`,
  no `active_window` GET. After ~5 min or manual refresh, the fetch is allowed again.

## Phase 4 — Arrival chart zero-height (`Failed to create 1206x0 image slot`) (HARDENED)
- The chart body already frames to a fixed plot height, so it should not be the 0-height
  layer; but to eliminate any transient 0-size pass and to pinpoint the source, the chart
  now: clamps to `minChartHeight = 64`, skips bar drawing (renders only the baseline) when
  `plotWidth <= 1`, and records measured width/height.
- Trace enriched: `[ARRIVAL_CHART_TRACE] … plotWidth=… plotHeight=… fallback=true|false`.
  If device logs still show the warning while `plotHeight>0 fallback=false`, the 0-height
  layer originates outside this chart (a sibling Host card element during the tab
  transition) and the chart is exonerated.
- **Files:** `Features/Reservations/ReservationDensityWaveChart.swift`.

## Phase 5 — unsafeForcedSync around Floor save (INSTRUMENTED + localized)
- Added `[CONCURRENCY_TRACE] context=floor_layout_save phase=payload_built modelContextUsed=false`,
  `phase=refresh_after_success onlyOnSuccess=true mainActor=true`, and
  `phase=publish_error mainActor=true modelContextUsed=false`.
- **Finding:** `FloorPlanStore` is `@MainActor` and the save path builds a value-type
  payload and calls the network service — it opens no SwiftData `ModelContext`. The
  `unsafeForcedSync` that follows `layout_save_failed` is therefore not in the Floor save
  code; it correlates with SwiftData framework access elsewhere (reservation upsert during
  the concurrent schedule/active-window sync that was also running). With Phase 2
  suppressing the competing floor refresh and Phase 3 reducing schedule full-fetches, the
  overlap window shrinks. Remaining repro needs a device stack with the new breadcrumbs.
- **Files:** `Import/DateSwitchTrace.swift`, `Features/FloorPlan/FloorPlanStore.swift`.

## Files changed this pass
- `Tryzub Reservations/Network/FloorPlanDTO.swift` — stop encoding `restaurant_key`/`id`.
- `Tryzub Reservations/Network/FloorPlanError.swift` — `serverValidation(code:status:message:)`.
- `Tryzub Reservations/Services/FloorPlanService.swift` — map WordPress errors to serverValidation.
- `Tryzub Reservations/Features/FloorPlan/FloorPlanStore.swift` — payload/error/concurrency
  traces; save-aware refresh suppression; success-only forced refresh.
- `Tryzub Reservations/Import/ReservationsController.swift` — startup-fresh anchors active
  window TTL; schedule activation coordinator trace.
- `Tryzub Reservations/Features/Reservations/ReservationDensityWaveChart.swift` — min height,
  zero-size fallback, plotWidth/plotHeight/fallback trace.
- `Tryzub Reservations/Import/DateSwitchTrace.swift` — `concurrencyPhase` emitter.

## Build status
`xcodebuild -scheme "Tryzub Reservations" -destination generic/platform=iOS build-for-testing`
→ **TEST BUILD SUCCEEDED** (only the pre-existing `GuestConfirmationMail` MainActor note).
No new linter errors in touched files.

## Remaining risks
- Floor save 400 fix is code-verified against the backend contract but still needs the
  device 200 + `tables>0` confirmation.
- The `unsafeForcedSync` true source (SwiftData upsert during concurrent sync) is localized
  but not yet eliminated; needs a device stack with the new `[CONCURRENCY_TRACE]` lines.
- `1206x0` warning: if it persists with `fallback=false plotHeight>0`, the source is a
  sibling Host element, not the chart.

## Next recommended task
Run the device proof: relaunch (cache), tap Bookings (expect skip), open Floor → Save seed
(expect `restaurant_tables_put status=200` + `tables>0`), watch for the 1206x0 warning and
`unsafeForcedSync`. If Floor save passes, proceed to mutation-reconcile device proof, then
the AI/LLM final pass.

---

# Final Intelligence / LLM Proof Pass (TestFlight)

This pass made the Host Intelligence / local-LLM layer **observable and provable**
without changing the backend, weakening the validator, or making model output
required for core operations. The pipeline (gate → sanitizer → writer → runtime →
validator → fallback) already existed and is robust; this pass added the missing
**named proof traces** plus a developer-only **validator proof harness**.

## Pipeline (verified)
```
HostBoardView.task(evaluationKey)
  → HostIntelligenceController.evaluate
    → HostIntelligenceEngine.evaluateHostDecisionSnapshot  (facts + template + HostLLMPacket)
    → [HOST_AI_FACTS_TRACE]
HostBoardView.task(enrichmentKey)
  → HostIntelligenceController.refreshBriefing
    → recordHostBoardGateDecision → [HOST_AI_GATE] allowed/reason/categories
    → (template-only) ManagerNarrativeTemplateBuilder + [HOST_AI_LIFECYCLE] model_skipped
    → (allowed) ManagerNarrativeWriter.write
        → ManagerNarrativePacketBuilder + ManagerNarrativePacketSanitizer
        → [HOST_AI_PACKET_TRACE] containsRawContact=false containsRawNotes=false
        → readiness check → [HOST_AI_LIFECYCLE] model_unavailable / fallback_used (if not ready)
        → HostLlamaBriefingRuntime.generateBriefing → [HOST_AI_LIFECYCLE] model_started/model_completed
        → ManagerNarrativeValidator.validationResult → [HOST_AI_VALIDATOR] result=pass|blocked reason=<token>
        → (block) [HOST_AI_LIFECYCLE] fallback_used reason=validator_blocked → deterministic fallback
    → stale result discarded on date change → [HOST_AI_LIFECYCLE] model_result_ignored + model_cancelled reason=date_changed
  → reset() on view hidden → [HOST_AI_LIFECYCLE] model_cancelled reason=view_hidden (only if inference active)
```

## What changed
- **`Import/HostAIProofTraces.swift`** (new) — `HostAIFactsTrace`, `HostAIPacketTrace`
  (with `looksLikeRawContact`), `HostAIValidatorTrace` (with a stable `classify` token
  map), `HostAITestTrace`. All `#if DEBUG`, OSLog category `HostAI`, `privacy: .public`.
- **`Import/HostAILifecycleTrace.swift`** — added `modelLoadStarted`, `modelReady`,
  `modelUnavailable`, `modelTimeout`, `modelCancelled`, `fallbackUsed`.
- **`Features/HostIntelligence/HostIntelligenceController.swift`** — emits
  `[HOST_AI_FACTS_TRACE]` after engine eval (facts/actions/categories/guestSignals/
  floorTables); emits `model_cancelled reason=date_changed` alongside the existing
  ignored-result guard; `reset()` now bumps the generation guard and logs
  `model_cancelled reason=view_hidden` when inference is active (stale model output can
  no longer reach UI after the board is hidden).
- **`Features/HostIntelligence/ManagerNarrativeWriter.swift`** — emits
  `[HOST_AI_PACKET_TRACE]` for the sanitized prompt; `[HOST_AI_VALIDATOR] result=pass|blocked`
  with stable reason token; `model_unavailable` + `fallback_used` on readiness miss;
  `fallback_used reason=validator_blocked` on rejection.
- **`Features/HostIntelligence/HostBriefingWriter.swift`** — `[HOST_AI_GATE]` main line now
  carries `categories=` inline so the allowed=true format matches `allowed=true
  reason=operational_tension categories=...`.
- **`Features/HostIntelligence/HostAIValidatorProofHarness.swift`** (new, DEBUG-only) — feeds
  crafted candidates through the **real** `ManagerNarrativeValidator` and emits
  `[HOST_AI_TEST] scenario=... result=pass|blocked`. Runs once per launch from
  `HostBoardView.onAppear` (DEBUG). Never runs the model, never reaches staff UI.

## Final TestFlight AI Safety Checklist
- [x] **AI facts packet verified** — `[HOST_AI_FACTS_TRACE]` shows deterministic facts/
  categories per date; guestSignals=server|local_bounded, floorTables=backend|local.
- [x] **AI gate verified** — `[HOST_AI_GATE]` reasons are explicit: `operational_tension`/
  `complex_packet` (allowed), `independent_simple_facts`, `no_meaningful_facts`,
  `model_not_ready`, `date_navigation`, `packet_unchanged` etc. (skip). No silent skips.
- [x] **Model runtime observable** — `model_started`/`model_completed` (duration) on AI-worthy
  cases; `model_unavailable` when the GGUF/runtime is missing.
- [x] **Validator verified** — `[HOST_AI_VALIDATOR] result=pass|blocked reason=<stable token>`;
  proof harness blocks raw contact, leaked labels, completed-status claims, guest-facing
  copy, invented "regular/always", and over-long output, and passes the calm supported case.
- [x] **Fallback verified** — `fallback_used reason=validator_blocked|model_unavailable`;
  deterministic template always present (never blank).
- [x] **No raw contact data** — sanitizer strips email/phone/JSON/evidence markers;
  `[HOST_AI_PACKET_TRACE] containsRawContact=false containsRawNotes=false` proves it.
- [x] **No invented guest facts** — validator semantic checks + `unsupported_*` operational
  claim rules; "regular/seen-before" requires backend pack evidence
  (`GuestHistorySemantics` profile-pack precedence).
- [x] **No invented table facts** — `unsupported_table_available_claim` rule; floor capacity
  only from backend tables when loaded.
- [x] **No blocking UI** — engine eval measured by `[UI_PRESSURE_TRACE] phase=host_engine_evaluate`
  (typically <15ms); model runs async; deterministic facts/actions render immediately.
- [x] **Guest Insights LLM boundary** — Guest Insights has **no** on-device model; guest
  message drafts (Reservation Detail) follow packet→writer→validator→staff review→compose,
  never auto-send, never mutate a reservation.

## Device proof required (capture on physical device)
1. Simple day → `[HOST_AI_GATE] allowed=false reason=independent_simple_facts` + `[HOST_CARD_TRACE] display=…` template/stable_empty.
2. AI-worthy tension → `[HOST_AI_GATE] allowed=true reason=operational_tension categories=…`,
   `[HOST_AI_PACKET_TRACE] containsRawContact=false`, `model_started` + `model_completed`,
   `[HOST_AI_VALIDATOR] result=pass`.
3. Validator block (rare in prod; harness proves it) → `[HOST_AI_TEST] scenario=attack_* result=blocked`,
   and on a real reject `[HOST_AI_VALIDATOR] result=blocked` + `fallback_used reason=validator_blocked`.
4. Date switch mid-generation → `[HOST_AI_LIFECYCLE] event=model_cancelled reason=date_changed`.
5. Performance → `[UI_PRESSURE_TRACE] phase=host_engine_evaluate duration=<50ms`.

## Remaining risks
- **Hard model-run proof is device-only.** `model_started`/`model_completed` and a real
  `[HOST_AI_VALIDATOR] result=pass` from genuine model output require a physical device with
  the GGUF bundled and an AI-worthy day. The validator-block path is proven offline by the
  `[HOST_AI_TEST]` harness; the *pass-on-real-model-output* path is not yet captured here.
- **No hard generation timeout / Task.cancel** on the llama runtime. Output is bounded by
  `maxOutputTokens=100` and stale results are discarded via the generation guard, but a
  truly hung inference is not force-killed. `model_timeout` trace exists but is not yet wired
  to a timer. Low risk for a 0.5B model with a 100-token cap; flagged for a follow-up.
- **Deterministic presentation edges (not LLM):** `GuestProfileViewState` can show
  "Seen before" for any loaded pack before the merge resolves; `RegularGuests` list uses
  local visit counts only. These are deterministic UI precedence issues, not model-invented
  facts — documented for a separate UX pass (out of scope: "no general UI polish").

## Release-build fix (TestFlight blocker)
`HostLLMPacketSampleFactory.groupedBookingDecisions()` referenced
`HostBookingFactGroupingSamples` (a `#if DEBUG`-only enum), but the factory itself is
**not** DEBUG-guarded and is used by the production settings smoke test. This compiled in
Debug but broke the **Release / "Any iOS Device"** archive with
`Cannot find 'HostBookingFactGroupingSamples' in scope`. Fixed by inlining the literal
sample strings in the factory (no behavior change; the factory no longer depends on
DEBUG-only code). Verified with a full `-configuration Release` device build → **BUILD
SUCCEEDED** (only the pre-existing `GuestConfirmationMail` MainActor note remains).

# Service Intelligence Refactor — Phase 1 (Foundation)

New module `Features/ServiceIntelligence` that wraps (does **not** replace) the existing
Host engine. It introduces a deterministic `ServiceMode` so live operational facts stop
leaking into after-close surfaces (the "A10 opened after cancellation" bug).

## Files added
- `Models/ServiceMode.swift` — `ServiceMode` enum (+ `allowsLiveOperationalFacts`,
  `isRecapContext`, `isAfterClose`).
- `Models/ReservationSignal.swift` — `ReservationSignal` + `ReservationSignalType`,
  `SignalConfidence`, `SignalSource`, `SignalPriority`. `depositMentioned ≠ depositVerified`;
  review-required signals default `requiresReview=true`.
- `Models/StaffActionIntent.swift` — `StaffActionIntent` + `StaffActionType`,
  `ActionPriority`, `ActionTiming`. `canAutoComplete` is `false` for every type (staff confirms).
- `Models/ServiceBriefing.swift` — `ServiceBriefing` + `BriefingSource`.
- `Engine/ServiceModeResolver.swift` — **pure** resolver: `now` + open/close + status
  histogram → `ServiceMode` + cleanup count. `summarize(statuses:)` builds the histogram from
  `ReservationStatus`.
- `Engine/ServiceIntelligenceEngine.swift` — deterministic `ServiceBriefing` assembler:
  Check now / Coming up / Review later / After close + honest recap. Live actions only
  `duringService`; after close it emits cleanup or a wrapped-up recap.
- `Actions/HostActionMapper.swift` — bridges existing `HostSuggestedAction` → `StaffActionIntent`.
- `Actions/ServiceAlertRouter.swift` — routing rules (host / detail / global / dev) with the
  "no duplicate fact everywhere" policy; after close, live facts never route to Host.
- `Diagnostics/ServiceIntelligenceTrace.swift` — `[SERVICE_INTELLIGENCE_TRACE]`,
  `[HOST_SERVICE_MODE_TRACE]`, `[SERVICE_ACTION_TRACE]`, `[SERVICE_ALERT_ROUTE_TRACE]`,
  `[SERVICE_INTELLIGENCE_TEST]`.
- `Diagnostics/ServiceIntelligenceProofHarness.swift` (DEBUG) — deterministic self-check for
  the mode transitions + after-close no-leak guarantee. Runs once from `HostBoardView.onAppear`.

## Not yet wired (by design)
Phase 1 is foundation only. The new engine is **not** yet rendered in Host Board or a Global
view — that is Phases 2–3. Nothing in the existing tab shell, Host card, or detail screens
changed, so the running app behaves exactly as before. This keeps the build safe while the
new layer is proven by `[SERVICE_INTELLIGENCE_TEST]` logs.

## Device proof (Phase 1)
On launch (DEBUG), expect:
```
[SERVICE_INTELLIGENCE_TEST] scenario=A_after_close_finished result=pass mode=afterCloseFinished …
[SERVICE_INTELLIGENCE_TEST] scenario=B_after_close_cleanup result=pass mode=afterCloseNeedsCleanup …
[SERVICE_INTELLIGENCE_TEST] scenario=C_during_service result=pass mode=duringService …
[SERVICE_INTELLIGENCE_TEST] scenario=before_service result=pass …
[SERVICE_INTELLIGENCE_TEST] scenario=future_planning result=pass …
[SERVICE_INTELLIGENCE_TEST] scenario=past_recap result=pass …
```

## Remaining backend / follow-up for later phases
- Attachments upload endpoint + structured note fields (Phases 5/6) — backend work TBD.
- No XCTest target exists in the project; Phase 1 uses the DEBUG proof harness instead. A
  formal test target is a follow-up.

---

# Service Intelligence Refactor — Phase 2 (Host Board wiring, cache-only)

Wires `ServiceMode` + `ServiceBriefing` into the Host card using **only cached
in-memory data** — no new GET requests. Fixes the after-close bug (live "A10 opened"
facts no longer appear once service is wrapped).

## Files added
- `ViewModels/HostServiceBriefingViewState.swift` — `HostServiceBriefingViewState` +
  pure, cached-only `HostServiceBriefingViewStateBuilder`. Reads `clockTick`,
  `selectedDate`, day `reservations`, `decisionSnapshot`, and cached open/close times.
  Measures duration and emits no-network/eval traces. Computes busiest-time label from
  cached `slotPressures` (no analytics fetch).
- `Views/HostServiceBriefingCard.swift` — deterministic staff-language card (headline,
  optional summary, primary/secondary action groups, today-summary lines). De-duplicates
  summary against headline/first action.

## Files changed
- `Features/Reservations/HostBoardView.swift`
  - `@State serviceBriefingState`, rebuilt via `.onChange(of: serviceBriefingStamp)` where
    the stamp includes the clock minute + snapshot generation (so mode transitions and
    status changes refresh it). `rebuildServiceBriefing()` is cache-only.
  - `hostIntelligenceSection` now dispatches: after-close (finished + cleanup), past recap,
    and future planning render `HostServiceBriefingCard`; live service (`duringService`/
    `beforeService`) keeps the existing `HostIntelligenceCard` (renamed body
    `liveHostIntelligenceSection`) — LLM wording stays until Phase 8 per the spec.
  - `handleServiceActionIntent` opens the related reservation for reservation-scoped
    actions; aggregate cleanup actions are non-tappable summaries.
  - Removed the DEBUG proof-harness calls from `onAppear`.
- `Features/HostIntelligence/HostIntelligenceDiagnosticsView.swift` — new DEBUG-only
  "Proof Harnesses (Debug)" section with buttons to run the Service Intelligence and AI
  validator proofs on demand (relocated off the normal Host appearance).
- `Diagnostics/ServiceIntelligenceTrace.swift` — added `evaluate(...)` (emits
  `source=cached`, `no_network=true`, `phase=evaluate durationMs=...`) and
  `hostCard(display:mode:)`.

## Display rules by ServiceMode
| Mode | Card | Content |
|------|------|---------|
| `duringService` | existing `HostIntelligenceCard` | live Check now / Coming up (unchanged) |
| `beforeService` | existing `HostIntelligenceCard` | upcoming (unchanged) |
| `afterCloseNeedsCleanup` | `HostServiceBriefingCard` | "Cleanup needed" + status-update actions |
| `afterCloseFinished` | `HostServiceBriefingCard` | "Service is wrapped." + today summary, no live facts |
| `pastRecap` | `HostServiceBriefingCard` | "Recap" + counts |
| `futurePlanning` | `HostServiceBriefingCard` | "Planning…" + setup/table actions, no "late"/"due" |

The slot-pressure strip and live suggested actions live only in `liveHostIntelligenceSection`,
so after-close/recap/planning surfaces cannot show "due in X" / "table opened".

## No new API
Service Intelligence reads `controller.availabilitySummary(for:)` (cache-only accessor) and
already-published `decisionSnapshot`; it never calls `ensureAvailabilitySummary` or any GET.
Proven by `[SERVICE_INTELLIGENCE_TRACE] no_network=true`.

## Old HostIntelligenceController / Engine
Untouched and still the live-service path + deterministic fallback. If the briefing maps to a
live mode, the existing card renders exactly as before.

## Proof harness
Moved out of normal Host appearance into the Dev diagnostics "Proof Harnesses" section
(`runOnceIfNeeded` no longer fires on Host tab open). Harnesses still runnable on demand.

## Device proof (expected)
After close, nothing active:
```
[HOST_SERVICE_MODE_TRACE] mode=afterCloseFinished afterClose=true cleanupNeeded=0
[SERVICE_INTELLIGENCE_TRACE] source=cached selectedDate=… mode=afterCloseFinished reservations=8 actions=0
[SERVICE_INTELLIGENCE_TRACE] no_network=true
[SERVICE_INTELLIGENCE_TRACE] phase=evaluate durationMs=<n>
[HOST_CARD_TRACE] display=service_briefing mode=afterCloseFinished
```
After close, unfinished statuses:
```
[HOST_SERVICE_MODE_TRACE] mode=afterCloseNeedsCleanup afterClose=true cleanupNeeded=2
[HOST_CARD_TRACE] display=service_briefing mode=afterCloseNeedsCleanup
```

## Remaining risks
- After-close detection needs a cached close time; if availability isn't cached,
  `serviceDensityBounds` falls back to slot bounds, and if both are missing the resolver stays
  `duringService` (safe — never a false "wrapped").
- Live service still uses the old card (intended); migrating it to the grouped briefing +
  model wording is Phase 8.

---

# Phase 4 — Review Details + Reservation Detail redesign (DONE)

## Review Details cleanup (`HostIntelligenceReviewView`)

**Problem (visible in screenshots):** "What to check" and "Check next" showed the same
reservation text twice. The "Watch" severity label meant nothing. "8 items flagged" at the
bottom was generic noise.

**Fix:**
- Replaced the old three-section structure (operationalPromptsSection + topFactsSection +
  suggestedActionsSection + signalsSummarySection) with two focused sections:
  - **"Check now"** — operational prompts first (with related reservation count), then
    deduplicated suggested actions whose title/reason don't already appear in a prompt.
    Empty: "Nothing to check right now." (not split across two headings).
  - **"Key details"** — up to 4 briefing facts that are not already captured in the
    headline, capped to avoid noise. Hidden entirely when there are no distinct facts.
- Removed the `signalsSummarySection` counter ("8 items flagged") — it added no new info.
- Removed the "Watch" severity label from prompt cards.
- Added `dedupedActions` computed property: filters suggested actions whose
  `title`/`reason` already appear verbatim in an operational prompt's `title`/`body`.

## Reservation Detail redesign (`ReservationDetailView`)

**Important card (new):**
- Added `importantCard(_:)` inserted between the hero/action bar and the contact card.
  Visible only when there is at least one flag. Flags are deterministic (no model, no fetch):
  - No table picked (orange `chair` icon — skipped for completed/cancelled/no-show)
  - Large party ≥ 7 (blue `person.3` icon, shows table if assigned)
  - Dietary or allergy keyword in notes (red `fork.knife.circle` — "Check guest notes before seating.")
  - Accessibility keyword in notes (purple `figure.roll` — "Check setup before seating.")
  - Deposit keyword in notes (green `banknote` — "Manager should verify.")
  - Preorder / banquet keyword in notes (orange `cart` — "Kitchen should review.")
- Backed by `ReservationImportantFlags.make(reservation:)` — a pure function, no I/O.

**Notes card:**
- Replaces flat `DetailDataRow` (generic label) with `DetailNoteRow` which maps
  `"Guest"` → `"Guest note"`, `"Staff"` → `"Staff note"`, etc., making the label
  self-explanatory without needing a section header.

**Details card:**
- Renamed from `"Reservation metadata"` (developer-speak) to `"Details"`.

## Files changed
- `Features/HostIntelligence/HostIntelligenceReviewView.swift`
- `Features/Reservations/ReservationDetailView.swift`

## Build
`** BUILD SUCCEEDED **` (Debug, generic/iOS), no linter errors.

---

# Service Intelligence — Phase 3 (Global view under More, DONE)

## Goal
Add a single staff-facing Service Intelligence hub: a combined action hub plus a backend
analytics summary and a guest-memory entry point, reachable under **More → Business**.
Keep Dev diagnostics / proof harness separate.

## What was added
- `Features/ServiceIntelligence/Views/GlobalServiceIntelligenceView.swift` (new) — a
  **cache-only** hub. It reuses the Phase 2 `HostServiceBriefingViewStateBuilder` +
  `HostServiceBriefingCard` to render today's action brain (Check now / Coming up /
  Cleanup / recap) for **all** modes (the Host Board only shows the card after close /
  recap / planning; the global hub always shows it). Action taps push the related
  `ReservationDetailView` via `navigationDestination(item:)`.
  - Optional **Business** block: shows already-cached `RestaurantSettingsStore.analyticsSummary`
    headline numbers (reservations, guests, avg party, range) with a deep link to the full
    `BusinessAnalyticsView`. If nothing is cached it shows a hint and the link — it never
    forces a fetch from the hub.
  - Optional **Guests** block: deep link to `RegularGuestsView` (Guest Memory).
  - **Upcoming** block: count of non-cancelled reservations beyond today, from the same
    `@Query` active-window pool (cache).
- `ServiceIntelligenceTrace.globalView(...)` (new) → `[SERVICE_GLOBAL_TRACE] surface=global
  mode=… actions=… analyticsCached=… upcoming=… no_network=true`.
- More wiring in `Features/Reservations/ReservationsListView.swift`: new
  `ReservationMoreDestination.serviceIntelligence`, a `NavigationLink` at the top of the
  **Business** section (`sparkles`), and the destination → `GlobalServiceIntelligenceView`.

## Cache-only guarantees
- The hub builds the briefing from the in-memory `HostDecisionSnapshot` + a SwiftData
  `@Query`; no controller refresh / availability fetch is triggered on appear.
- Analytics/guest sections read cached store state and otherwise just deep-link to the
  existing screens (those screens own their own loading, unchanged).
- Rebuild is gated by a stamp (today key + today reservation count + snapshot generation +
  clock minute) and a 60s timer, matching the Host Board pattern.

## Dev separation
`ServiceIntelligenceProofHarness` and the AI proof harness remain only in
`DeveloperDiagnosticsView` / `HostIntelligenceDiagnosticsView`. The global hub lives in the
staff **Business** section, not Developer / Support.

## Build
`** BUILD SUCCEEDED **` (Debug, generic/iOS), no linter errors.

---

# Active-Window Auto-Refresh TTL Fix

## Root cause
`autoRefreshDashboardIfAllowed` judged active-window freshness against
`autoRefreshInterval` (60s) — the same value that throttles how often the auto-refresh
*evaluates*. So a successful startup delta marked `lastSuccessAt = now`, the first idle
tick correctly skipped (`fresh_automatic`), but ~60s later `isScopeFresh(60)` returned
false and the automatic path fetched again (`stale_automatic`) with the startup success
time as its cursor. The freshness clock itself was already shared (the success path calls
both `markScopeSuccess` and `freshnessCoordinator.markCompleted`); only the TTL was wrong.

## Fix
- Added `activeWindowAutoRefreshTTL = 300`. Idle automatic refresh now judges freshness
  against 300s; the 60s `autoRefreshInterval` keeps its role as the evaluation throttle only.
- `mark_success` and `auto_check` traces via new `Import/ActiveWindowFreshnessTrace.swift`.
- Header copy: during an automatic background freshness check with cache already visible,
  the blocking secondary "Checking service…" is suppressed (just "Checked HH:mm"). Manual
  refresh (`isReservationRefreshInFlight`) and no-cache startup keep their progress copy;
  specific states ("Checking available times…", "Checking saved data…") are unaffected.

## Files changed
- `Import/ReservationsController.swift` — `activeWindowAutoRefreshTTL`; auto-refresh fresh
  gate uses it; emits `auto_check` (skip/fetch, elapsed/ttl) and `mark_success` (with
  `autoFreshUntil`, `cursorSaved`) on active-window success.
- `Import/ActiveWindowFreshnessTrace.swift` — new trace.
- `Features/Reservations/ReservationSharedUI.swift` — suppress background "Checking service…".

## Bypass matrix
| Path | Behavior |
|------|----------|
| Idle automatic (within 300s) | **skip** `reason=recent_success` |
| Idle automatic (after 300s) | fetch `reason=ttl_expired` → mark_success → fresh 300s |
| Manual pull/press | bypasses (separate `force` path, not this gate) |
| Mutation reconcile | bypasses (own refresh path; `markScopesTouched` keeps scope fresh) |
| Window/date change | bypasses (new scope) |

## Expected device proof (no-tap, 3+ min)
```
[STARTUP] cache hit; UI released=true
[API] START reason=active_window_delta … (startup)
[API] END reason=active_window_delta status=200
[ACTIVE_WINDOW_FRESHNESS_TRACE] event=mark_success source=startup_delta scope=… cursorSaved=true autoFreshUntil=…
… (idle ticks) …
[ACTIVE_WINDOW_FRESHNESS_TRACE] event=auto_check source=autoRefreshDashboard decision=skip reason=recent_success elapsed=72s ttl=300s
[FRESHNESS_COORDINATOR] decision=use_cache reason=fresh_automatic
[API] SKIP reason=scope_skip_fresh
```
No second `[API] START reason=active_window_delta` within 300s of startup success.
Service Intelligence unchanged: `[SERVICE_INTELLIGENCE_TRACE] no_network=true`.

---

# Phase 5 — Attachments MVP (DONE)

**Goal**: Local-first photo attachments for reservations. Staff attach deposit screenshots,
preorder confirmations, banquet photos, and setup notes. Images persist on device, indexed
by the reservation's backend ID so re-fetching the reservation never loses the photos.

## Architecture
- **`ReservationAttachmentRecord`** — SwiftData `@Model`. Foreign key is `reservationRemoteID: Int`
  (the stable backend ID). ID format `res-{reservationRemoteID}-{uuid}` encodes ownership.
  If the `ReservationRecord` SwiftData row is recreated by a backend refetch, all attachments
  are still found via `@Query(filter: reservationRemoteID == x)`.
- **`AttachmentFileStore`** — static disk I/O helpers. Images stored as compressed JPEG
  (≤1920px, 0.85 quality) in `Application Support/attachments/<uuid>.jpg`. Thumbnails
  generated via `CGImageSourceCreateThumbnailAtIndex` (no separate thumb file needed).
- **`AttachmentLabel`** — 7 categories: Deposit, Preorder, Banquet, Guest screenshot,
  Receipt, Setup, Other. Each has a `systemImage` and `reviewInstruction`.

## Backend status: NO remote endpoint yet
All images are device-local. Future backend endpoints documented in `ReservationAttachment.swift`:
- `POST /wp-json/tryzub/v1/reservation-attachments` (multipart)
- `GET  /wp-json/tryzub/v1/reservation-attachments?reservation_id={id}`
- `DELETE /wp-json/tryzub/v1/reservation-attachments/{id}`

`AttachmentFeatureFlag.localStorageEnabled = true` (device works)
`AttachmentFeatureFlag.remoteUploadEnabled = false` (backend not ready)

## UI flow
1. Staff opens Reservation Detail → Attachments card.
2. Tap "Add photo" → `PhotosPicker` from Photos library.
3. Pick photo → label `confirmationDialog` appears (7 options).
4. Staff picks label → JPEG compressed and saved to disk, `ReservationAttachmentRecord` inserted into SwiftData.
5. Thumbnail appears immediately; tap thumbnail → full-screen preview.
6. Swipe left on attachment row → Delete (removes file + SwiftData record).

## Files changed
- `Persistence/ReservationAttachmentRecord.swift` — new SwiftData model.
- `Persistence/AttachmentFileStore.swift` — new disk I/O helper.
- `Features/ServiceIntelligence/Models/ReservationAttachment.swift` — updated: removed old dead struct, `AttachmentLabel` + `AttachmentFeatureFlag` only.
- `Tryzub_ReservationsApp.swift` — added `ReservationAttachmentRecord.self` to `ModelContainer`.
- `Preview/ReservationPreviewData.swift` — added `ReservationAttachmentRecord.self` to preview container.
- `Features/Reservations/ReservationDetailView.swift` — `import PhotosUI`, attachment `@Query`, photo picker state, `attachmentsCard`, `AttachmentRow`, `AttachmentPreviewScreen`, `saveAttachment`, `deleteAttachment`.

## Build status
Debug build: `** BUILD SUCCEEDED **`

---

# Phase 6 — Note intelligence (DONE)

**Goal**: Convert free-text note fields into typed `ReservationSignal` objects using a
pure, deterministic analyzer. Show signals in Reservation Detail and the global hub.

## What's built
- `NoteSignalAnalyzer` — pure, no-network analyzer.  Scans `guestNote` + `staffNote`
  for deposit, preorder, banquet, dietary/allergy, accessibility, occasion, guest
  preference, kitchen, and bar keywords.  Returns `[ReservationSignal]` sorted by
  priority.  Evidence is trimmed to ≤60 chars, never raw PII.
- `NoteSignalTrace` — DEBUG-only `[SERVICE_NOTE_ANALYZER_TRACE]` logs per analysis run
  and per found signal (type, confidence, source, requiresReview).
- **Reservation Detail** — new `noteSignalsCard` shown below `importantCard` when
  signals exist.  Displays title, "Review" badge when staff must check, staff text,
  and short evidence snippet.
- **Global Service Intelligence hub** — new `noteSignalsSection` lists today's
  reservations that have actionable note signals (sorted by highest priority signal).
  Staff tap a row to navigate directly to that reservation's detail.

## Signal types produced
`depositMentioned`, `preorderMentioned`, `banquetMentioned`, `allergyOrDietary`,
`accessibility`, `occasion`, `guestPreference`, `kitchenNote`, `barNote`

## Safety rules
- `depositMentioned`, not `depositVerified` — always `requiresReview = true`.
- Allergy/dietary always `requiresReview = true`, priority `critical`.
- If no keywords match, returns empty array (silence is correct).
- Evidence snippet never contains raw phone/email (trimmed to note context window only).

## Files changed
- `Features/ServiceIntelligence/Analyzers/NoteSignalAnalyzer.swift` — new.
- `Features/ServiceIntelligence/Diagnostics/NoteSignalTrace.swift` — new.
- `Features/ServiceIntelligence/Diagnostics/ServiceIntelligenceTrace.swift` — added `noteSignals(count:)`.
- `Features/Reservations/ReservationDetailView.swift` — `noteSignalsCard`, `recomputeNoteSignals()`, signal icon/color helpers.
- `Features/ServiceIntelligence/Views/GlobalServiceIntelligenceView.swift` — `signalledReservations` state, `noteSignalsSection`, compute in `rebuild()`.

## Expected traces
```
[SERVICE_NOTE_ANALYZER_TRACE] reservation=42 signals=2 fallback=false
[SERVICE_NOTE_ANALYZER_TRACE] reservation=42 type=depositMentioned confidence=medium source=staffNote requiresReview=true
[SERVICE_NOTE_ANALYZER_TRACE] reservation=42 type=allergyOrDietary confidence=medium source=guestNote requiresReview=true
[SERVICE_GLOBAL_TRACE] section=note_signals count=1
```

## Build status
Debug build: `** BUILD SUCCEEDED **`

---

# Phase: Backend-Fed Service Intelligence (DONE)

**Goal**: Upgrade Service Intelligence from a cache-only view into a backend-fed operations
system. Instant first render + automatic enrichment when backend data arrives.

## Architecture: cache-first, never blocking

```
Host Board opens
→ render cached service briefing immediately (source=cache_only)
→ .onAppear schedules background loads (non-blocking Task priority=.utility)
→ GuestIntelligenceStore.load(dateKey:today) completes
→ BusinessIntelligenceStore.load(from:30d, to:today) completes
→ rebuildStamp changes (cacheStamps update)
→ rebuild() runs again with backend data
→ source upgrades to "mixed" or "backend_enriched"
→ "Guests to know today" section appears / business insights appear
```

## New models
- **`ServiceIntelligenceFreshness`** — tracks `guestSummaryStatus`, `businessSummaryStatus`,
  `profilePacksLoadedCount`. Derives `sourceToken` (cache_only / mixed / backend_enriched)
  and `briefingSource` (.deterministic / .mixed / .backend) for `ServiceBriefing.source`.
- **`ServiceIntelligenceContext`** — unified input packet: `selectedDate`, `serviceMode`,
  `dayReservations`, `guestSummaries`, `profilePacks`, `businessSummary`,
  `reservationAnalyticsSummary`, `freshness`. Has `prioritisedGuestsToKnow` computed
  (sorted: service issue > allergy > accessibility > occasion > returning).

## ServiceIntelligenceEngine changes
- `Input` now has optional `backendGuestSummaries`, `backendBusinessSummary`, `freshness`
  fields with defaults (nil/empty) → fully backward-compatible; no existing callers break.
- `resolvedSource` property derives `BriefingSource` from freshness.
- All `ServiceBriefing` objects use `resolvedSource` instead of hardcoded `.deterministic`.
- `recapLines()` prefers backend `BusinessIntelligenceFormatting.peakWindowLabel` for
  busiest-time over local slot analysis when `backendBusinessSummary` is available.

## GlobalServiceIntelligenceView changes
- Added `@EnvironmentObject var guestIntelligenceStore: GuestIntelligenceStore`
- Added `@EnvironmentObject var businessIntelligenceStore: BusinessIntelligenceStore`
- `scheduleBackendLoads()` called on `.onAppear` — non-blocking `Task(priority: .utility)`.
- `rebuildStamp` includes both store cache stamps → automatically rebuilds on backend arrival.
- New **"Guests to know today"** section from `ServiceIntelligenceContext.prioritisedGuestsToKnow`:
  - flags from `GuestIntelligenceSummaryDTO`: `hasPriorServiceIssue`, `hasAllergyNote`,
    `hasAccessibilityNote`, `hasSpecialOccasionNote`, returning guests (matchedVisitCount > 0)
  - each row shows badges and prior visit count; tap navigates to reservation detail
  - "Based on backend guest history." note at bottom
- **Business section** now uses `BusinessIntelligenceInsightBuilder.build(summary:)` when
  backend data is loaded; falls back to `ReservationAnalyticsSummaryDTO` metrics otherwise.
- Subtle `freshnessNote` shown at bottom when data is stale/absent (nil when current).

## New traces
```
[SERVICE_CONTEXT_TRACE] date=2026-06-12 reservations=8 guestSummary=loaded businessSummary=loaded profilePacks=0 source=backend_enriched
[SERVICE_BACKEND_FEED_TRACE] type=guest_date_summary status=scheduled
[SERVICE_BACKEND_FEED_TRACE] type=business_summary status=scheduled
[SERVICE_GLOBAL_TRACE] section=note_signals count=2
```

## Data boundaries maintained
- Local model NEVER invents history, allergy, or deposit truth.
- All guest signals come from `GuestIntelligenceSummaryDTO` (backend-structured fields).
- Business insight lines come from `BusinessIntelligenceInsightBuilder` (deterministic, no LLM).
- If backend is unavailable: `source=cache_only`, guest section empty, analytics falls back to cached.
- Staff sees no error message when backend is absent — only the subtle freshness note.

## Files changed
- `Features/ServiceIntelligence/Models/ServiceIntelligenceFreshness.swift` — new
- `Features/ServiceIntelligence/Models/ServiceIntelligenceContext.swift` — new
- `Features/ServiceIntelligence/Engine/ServiceIntelligenceEngine.swift` — extended Input
- `Features/ServiceIntelligence/Views/GlobalServiceIntelligenceView.swift` — full upgrade
- `Features/ServiceIntelligence/Diagnostics/ServiceIntelligenceTrace.swift` — context() + backendFeed()

## Build status
Debug build: `** BUILD SUCCEEDED **`

## Remaining backend gaps
None new. All data flows through existing `GuestIntelligenceStore` and `BusinessIntelligenceStore`
which already have proven API clients and correct TTLs. Profile packs (per-reservation) are
available via `GuestIntelligenceStore.profilePack(for:)` — wiring into individual reservation
detail can be a future enrichment pass.

---

## Phase 6 — Canonical Floor Table Setup + Connected Table Assignment (DONE)

### Goal
Make backend Floor Plan the canonical table system. Every assignment surface now uses
`PATCH /managed-reservations/{id}/tables` when a backend floor layout exists.

### Table path audit

| Screen | Assignment path | Conflict checks |
|---|---|---|
| `FloorPlanView` + `FloorPlanTableAssignmentSheet` | canonical — `PATCH /managed-reservations/{id}/tables` | yes (409) |
| `ReservationDetailView` | canonical when `hasBackendLayout`; legacy fallback otherwise | yes when canonical |
| `HostBoardView` | **now canonical** via `TableAssignmentCoordinator` | yes when canonical |
| `ReservationsListView` | **now canonical** via `TableAssignmentCoordinator` | yes when canonical |
| `ManualReservationFormView` | legacy `tableName` field in full PATCH | no (form submit) |

Legacy `tableName` remains **display compatibility** only. It is never the preferred path
when a floor layout is present.

`HostTableConfigStore` is **advisory/fallback only** for assignment chip display.
`ReservationTableOptionsStore` is **legacy fallback chip names** only.

### Canonical architecture

```
Backend restaurant tables
  → FloorPlanStore (layoutTables + viewState.tables)
  → TableAssignmentCoordinator (decision: canonical vs legacy)
  → Host Board / Reservation Detail / Schedule → PATCH /managed-reservations/{id}/tables
```

### New files

- `Features/FloorPlan/TableAssignmentCoordinator.swift` — single facade, canonical-vs-legacy decision
- `Features/FloorPlan/TableCapacitySummary.swift` — typed capacity summary for Service Intelligence
- `Import/FloorPlanTrace.swift` — extended with `layoutImportDefaults`, `layoutSaveStarted`, `layoutSaveCompleted`

### Files changed

- `Features/FloorPlan/TableAssignmentCoordinator.swift` — new
- `Features/FloorPlan/TableCapacitySummary.swift` — new
- `Features/FloorPlan/FloorPlanStore.swift` — added `capacitySummary` computed property
- `Features/FloorPlan/FloorPlanLayoutSetupView.swift` — added `tryzubDefaultTables`, "Import Tryzub default tables" button, save traces
- `Features/FloorPlan/FloorPlanView.swift` — improved unassigned reservation rows (note chips, "Assign table" CTA)
- `Features/FloorPlan/TableAssignmentTrace.swift` — added `fallback` trace
- `Features/Reservations/HostBoardView.swift` — `HostBoardReservationRow` uses `TableAssignmentCoordinator`, added `@EnvironmentObject floorPlanStore`
- `Features/Reservations/ReservationsListView.swift` — `ReservationNavigationRow` uses `TableAssignmentCoordinator`, added `@EnvironmentObject floorPlanStore`
- `Features/Reservations/RestaurantSettingsStore.swift` — improved legacy table capacity text section with guidance note

### Tryzub default tables

Floor Plan → Edit Layout → "Import Tryzub default tables" creates:

| Tables | Capacity | Grid row |
|---|---|---|
| A1–A5 | max 6 (2-top min) | Row 0 |
| A6–A7 | max 8 (booth) | Row 1 |
| A8–A15 | max 4 (4-top) | Row 2 |
| Bar | max 4 | Row 3 |
| Patio | max 4 | Row 3 |

Total: 17 tables, 88 seats maximum.

If layout already has tables, a confirmation dialog prevents accidental override.

### TableCapacitySummary

```swift
struct TableCapacitySummary {
    let tableCount: Int      // active tables from backend layout
    let totalSeats: Int      // sum of maxCapacity
    let activeSeats: Int     // same as totalSeats (active only)
    let sections: [String: Int]
    let largestTableCapacity: Int
    let hasBackendLayout: Bool
}
```

Exposed via `FloorPlanStore.capacitySummary`. Service Intelligence and BookingLoadAnalyzer
consume this — they never guess from free-form text when a real layout is available.

### Bar/Patio parser

The legacy text parser already handles `Bar: 4` correctly. Bare `"Bar"` without a capacity
fails and appears in `invalidLines`. The Settings UI now shows a clear hint:
"Each line must be Name: Capacity or Name Capacity. Bare names like 'Bar' without a number will be rejected."

The canonical path is Floor Plan → Edit Layout. Legacy text import is documented as fallback only.

### Traces

```
[TABLE_ASSIGNMENT_TRACE] path=floor_plan_backend  reservation=123 tableKeys=a6
[TABLE_ASSIGNMENT_TRACE] path=legacy_table_name_patch  reservation=123 tableName=A6
[TABLE_ASSIGNMENT_TRACE] fallback_reason=no_backend_layout  reservation=123
[TABLE_ASSIGNMENT_TRACE] fallback_reason=key_not_found  detail=A6  reservation=123
[TABLE_CAPACITY_TRACE] source=backend tables=17 seats=88
[FLOOR_PLAN_TRACE] event=import_defaults tables=17
[FLOOR_PLAN_TRACE] event=save_started tables=17
[FLOOR_PLAN_TRACE] event=save_completed tables=17
```

### Build status
Debug build: `** BUILD SUCCEEDED **` — no errors, no linter warnings.

### Architecture rules (authoritative)

- Backend floor tables are canonical. `FloorPlanStore` is the iOS read-model.
- `TableAssignmentCoordinator` is the only correct call site for table assignment.
- `HostTableConfigStore` is **deprecated as an assignment source** — advisory/chip display fallback only.
- `tableName` on `ReservationRecord` and `ReservationDTO` is **display compatibility** only.
- Canonical assignment endpoint: `PATCH /managed-reservations/{id}/tables`
- Conflict detection: backend 409 response. iOS shows staff-safe copy, refreshes floor plan.
- No auto-assignment. No LLM table decisions. Staff taps table; backend is final truth.

### Booking Load Suggestions readiness — UPGRADED (Phase 8)

`TableCapacitySummary` is now wired into both call sites via `BookingLoadSupport.plannedSeats(from:localCapacity:)`, which replaces the old raw-table scan. The analyzer input now carries `hasBackendLayout: Bool`, which propagates to `BookingLoadReport`. Staff see:

```
88 seats (backend tables) — known reservations only, walk-ins not counted.
```
instead of the generic "known reservations only" note when the floor plan is loaded.

When `hasBackendLayout = false` (no layout saved yet):
```
Known reservations only — walk-ins not counted. No table plan configured.
```

"Review close slot" from Global Service Intelligence now pre-selects the specific busy slot in `BlockedTimeSlotsView` so staff don't have to find it manually.

---

## Phase 8 — Booking Load + BlockedSlots Pre-selection (DONE)

### Goal
Connect booking load suggestions to real backend table capacity (Phase 6 result) and make the "Review close slot" action actionable by pre-selecting the specific slot in `BlockedTimeSlotsView`.

### Changes

**`BookingLoadAnalyzer.Input`** — added `hasBackendLayout: Bool = false`

**`BookingLoadReport`** — added `hasBackendLayout: Bool`; `knownOnlyNote` now shows seat count + source ("backend tables" / "local config" / "no plan"); added `capacitySourceLabel: String?` for inline display.

**`BookingLoadSupport`** — added `plannedSeats(from: TableCapacitySummary, localCapacity:) -> (seats: Int?, isBackendLayout: Bool)` to cleanly resolve both the seat count and the source flag from the typed summary.

**`HostBoardView.buildBookingLoadReport`** and **`GlobalServiceIntelligenceView.buildBookingLoadReport`** — both now call `floorPlanStore.capacitySummary` and use `BookingLoadSupport.plannedSeats(from:localCapacity:)` instead of the raw table array scan.

**`BlockedTimeSlotsView`** — added optional `preselectedSlotValue: String?` parameter. When set, the slot is auto-selected in the Available Public Slots grid on first appear.

**`GlobalServiceIntelligenceView`** — added `@State private var blockedSlotsPreselectedSlot: String?`. "Review close slot" now sets `blockedSlotsPreselectedSlot = item.slotValue` before presenting the sheet; `BlockedTimeSlotsView` receives that slot.

### Files changed
- `Features/ServiceIntelligence/Analyzers/BookingLoadAnalyzer.swift` — `hasBackendLayout` in `Input` + propagated to report
- `Features/ServiceIntelligence/Models/BookingLoadModels.swift` — `hasBackendLayout`, improved `knownOnlyNote`, `capacitySourceLabel`
- `Features/ServiceIntelligence/Analyzers/BookingLoadSupport.swift` — `plannedSeats(from:localCapacity:)` helper
- `Features/Reservations/HostBoardView.swift` — uses `capacitySummary` + `isBackendLayout`
- `Features/ServiceIntelligence/Views/GlobalServiceIntelligenceView.swift` — uses `capacitySummary` + `blockedSlotsPreselectedSlot`
- `Features/Reservations/RestaurantSettingsStore.swift` — `BlockedTimeSlotsView.preselectedSlotValue`

### Architecture rules
- `BookingLoadAnalyzer` is pure. It receives `hasBackendLayout` as a flag; it does not inspect `FloorPlanStore`.
- Call sites are the only point where `FloorPlanStore.capacitySummary` is read into the analyzer input.
- `BlockedTimeSlotsView` pre-selection is advisory only: the staff must still tap "Block Selected Slots".
- `hasBackendLayout` must not change booking threshold logic — only the transparency copy.

### Build status
Debug build: `** BUILD SUCCEEDED **` — no errors, no linter warnings.

---

## Phase 7 — Reservation Detail Operational File (DONE)

### Goal
Transform `ReservationDetailView` from a basic data view into an operational reservation file.
Staff can see all structured notes, deposit status, preorder info, and guest history in one place.

### New section order (narrow layout)
```
DetailHeroCard        — name, time, party, table, status
actionBar             — status actions (confirm / seat / complete / cancel)
importantCard         — Important flags
noteSignalsCard       — NoteSignal results from note text
notesCard             — raw guest note + staff note (backend)
structuredNotesSection — Manager / Kitchen / Bar / Setup notes (local)
depositSection        — Deposit status + amount + note (local, shown when signals exist)
preorderSection       — Preorder + banquet note (local, shown when signals exist)
attachmentsCard       — Photos with labels
guestInsightsSection  — Guest history (backend profile pack + local insights)
detailsCard           — Reservation metadata
contactCard           — Phone / email
draftMessageCard      — Guest messaging drafts
ReservationServiceLoadCard — Booking load for this date
```

### New SwiftData model: `ReservationStructuredNoteRecord`

Keyed by `reservationRemoteID` (unique, indexed). Local-first — no backend equivalent yet.

| Field | Type | Purpose |
|---|---|---|
| `managerNote` | `String?` | Payment, deposit decision, special instructions |
| `kitchenNote` | `String?` | Preorder, allergy, cake, specific dishes |
| `barNote` | `String?` | Drinks, champagne, bottle service |
| `setupNote` | `String?` | High chair, wheelchair, quiet table, decorations |
| `depositNoteText` | `String?` | Free-form deposit note |
| `depositStatusRaw` | `String` | `DepositStatus` enum value |
| `depositAmountText` | `String?` | e.g. "$200" |
| `preorderNoteText` | `String?` | Preorder details |
| `preorderStatusRaw` | `String` | `PreorderStatus` enum value |
| `banquetNoteText` | `String?` | Package / banquet details |

**`DepositStatus`**: `none` / `mentioned` / `needs_review` / `verified`
**`PreorderStatus`**: `none` / `mentioned` / `confirmed`

### Auto-seed from NoteSignals

On first open, if `noteSignals` contains `.depositMentioned` → `depositStatus = .mentioned`.
If `.preorderMentioned` / `.banquetMentioned` → `preorderStatus = .mentioned`.
This means staff never have to manually discover these from note text — the system flags them automatically.

### UI behavior

- **Structured notes section**: shows manager/kitchen/bar/setup notes when present; "Add staff notes" button opens `StructuredNoteEditorSheet`.
- **Deposit section**: shown when `depositStatus != .none` OR note signals found deposit. Shows status pill + amount + note.
- **Preorder section**: shown when `preorderStatus != .none` OR note signals found preorder. Shows status pill + notes.
- **`StructuredNoteEditorSheet`**: Form with all note fields, Picker for deposit/preorder status, saves to SwiftData on "Save".

### Staff copy examples

```
Deposit: Mentioned          ← orange pill
Manager should verify before service.

Preorder: Mentioned         ← orange pill
Kitchen should review before service.

Deposit: Verified           ← green pill
Amount: $200
Deposit note: Paid cash, per Bohdan
```

### Files changed

- `Persistence/ReservationStructuredNoteRecord.swift` — new SwiftData model
- `Features/Reservations/ReservationStructuredNoteUI.swift` — new: editor sheet + helper views
- `Tryzub_ReservationsApp.swift` — added `ReservationStructuredNoteRecord.self` to ModelContainer
- `Preview/ReservationPreviewData.swift` — same
- `Features/Reservations/ReservationDetailView.swift` — added @Query, @State, computed properties, 3 new sections, reordered detailContent

### Needed future backend fields

```
PATCH /managed-reservations/{id}:
  manager_note, kitchen_note, bar_note, setup_note,
  deposit_note, deposit_status, deposit_amount,
  preorder_note, preorder_status, banquet_note
```

When backend fields exist, `ReservationStructuredNoteRecord` fields should sync upstream on save.

### Build status
Debug build: `** BUILD SUCCEEDED **` — no errors, no linter warnings.

---

## Phase 9 — Attachment OCR / Image Intelligence (DONE)

### Goal
Extract text from locally stored attachment photos using Apple Vision, produce `ReservationSignal`s from the result, and surface those signals in both `ReservationDetailView` and `GlobalServiceIntelligenceView`.

### Two signal stages

**Stage 1 — Label-based (immediate, no OCR):**
As soon as staff labels an attachment, `AttachmentSignalAnalyzer` fires a signal based on the label:
- `Deposit` / `Receipt` → `depositMentioned` — "Manager should verify deposit before service."
- `Preorder` → `preorderMentioned` — "Kitchen should review preorder before service."
- `Banquet` → `banquetMentioned` — "Kitchen and manager should review banquet details."
- `Setup` → `setupNeeded` — "Check setup requirements before service."
- `Guest screenshot` / `Other` → `attachmentNeedsReview` — "Check this photo before seating."

**Stage 2 — OCR-based (additive, background):**
`AttachmentOCRService` runs `VNRecognizeTextRequest` (.accurate level) off the main thread via `Task.detached`. Result stored in `ReservationAttachmentRecord.extractedText`. `AttachmentSignalAnalyzer` re-runs `NoteSignalAnalyzer` on extracted text, remapping source to `.attachmentOCR` and appending "(from photo)" to `staffText`. OCR-based signals are deduplicated against label signals by type.

### New files

| File | Purpose |
|---|---|
| `Persistence/AttachmentOCRService.swift` | Vision OCR runner — pure async, no main actor |
| `Features/ServiceIntelligence/Analyzers/AttachmentSignalAnalyzer.swift` | Label + OCR → `[ReservationSignal]` |
| `Features/ServiceIntelligence/Diagnostics/AttachmentOCRTrace.swift` | `[SERVICE_ATTACHMENT_TRACE]` and `[SERVICE_ATTACHMENT_OCR_TRACE]` |

### Modified files

**`Persistence/ReservationAttachmentRecord.swift`** — added `extractedText: String?` and `ocrRanAt: Date?`. SwiftData handles lightweight migration automatically for new optional fields.

**`Features/ServiceIntelligence/Models/ReservationAttachment.swift`** — added `AttachmentFeatureFlag.ocrEnabled: Bool = true`.

**`Features/Reservations/ReservationDetailView.swift`**:
- `recomputeNoteSignals()` extended to also run `AttachmentSignalAnalyzer` on all `attachments`, populate `attachmentSignalsByID: [String: [ReservationSignal]]`, then merge + deduplicate by type (highest priority wins).
- `scheduleOCR(for:)` — runs `AttachmentOCRService.extractText` in a `Task.detached`, writes `extractedText` + `ocrRanAt` to SwiftData, calls `recomputeNoteSignals()` on main actor.
- `saveAttachment` calls `scheduleOCR` after successful save.
- `.onAppear` schedules OCR for any existing attachments that predate Phase 9 (`ocrRanAt == nil`).
- `.onChange(of: attachments)` triggers `recomputeNoteSignals()` so signals update when OCR completes.
- `AttachmentRow` gains `signals: [ReservationSignal]` parameter. Shows signal pills inline when present; shows `reviewInstruction` when no signals; shows "Text read" badge when OCR found content.

**`Features/ServiceIntelligence/Views/GlobalServiceIntelligenceView.swift`**:
- Added `@Query private var allAttachmentRecords: [ReservationAttachmentRecord]`.
- `rebuild()` note signals loop extended: for each today's reservation, also queries `allAttachmentRecords` filtered by `reservationRemoteID`, runs `AttachmentSignalAnalyzer`, deduplicates by type, merges with note signals.
- `rebuildStamp` includes `ocrCompleted` count so view rebuilds when OCR results arrive.

### Trace output examples

```
[SERVICE_ATTACHMENT_TRACE] event=saved reservation=42 filename=<uuid>.jpg label=Deposit
[SERVICE_ATTACHMENT_OCR_TRACE] event=started reservation=42 filename=<uuid>.jpg
[SERVICE_ATTACHMENT_OCR_TRACE] event=completed reservation=42 filename=<uuid>.jpg textChars=183 signals=2
[SERVICE_ATTACHMENT_TRACE] event=label_signal reservation=42 attachment=res-42-<uuid> type=depositMentioned
[SERVICE_ATTACHMENT_TRACE] event=label_signal reservation=42 attachment=res-42-<uuid> type=preorderMentioned
```

### Architecture rules
- `AttachmentOCRService` is pure: no SwiftData, no main actor, no stores.
- `AttachmentSignalAnalyzer` is pure: no network, no model, same keyword safety as `NoteSignalAnalyzer`.
- OCR runs via `Task.detached(priority: .utility)` — never blocks the main thread.
- `extractedText` is stored to disk (SwiftData) so OCR only runs once per attachment.
- Signals from OCR always have `requiresReview = true`. Source is `.attachmentOCR`.
- No signal says "deposit paid," "allergy confirmed," or "preorder verified" — only "mentioned, verify."

### Feature flag
```swift
AttachmentFeatureFlag.ocrEnabled = true   // Vision OCR on-device, no network
AttachmentFeatureFlag.remoteUploadEnabled = false  // backend endpoint not yet live
```

### Acceptance scenarios

| Scenario | Expected |
|---|---|
| Staff attaches a photo labeled "Deposit" | `depositMentioned` signal fires immediately in noteSignalsCard |
| OCR reads "$200 deposit paid" from image | `depositMentioned` (from photo) signal enriched with evidence |
| Image has no readable text | `ocrRanAt` set, `extractedText = nil`, no OCR signals, label signal still shows |
| Staff attaches "Preorder" | `preorderMentioned` in noteSignalsCard + Global Service Intelligence notes section |
| Old attachment (pre-Phase 9) | `.onAppear` schedules OCR; enriches on next detail open |

### Build status
Debug build: `** BUILD SUCCEEDED **` — no errors, no linter warnings.

---

## Is AI TestFlight-safe?
**Yes, with one caveat.** The model is strictly advisory: deterministic facts/actions and a
template briefing render without it, the gate keeps it off simple days, the sanitizer keeps
raw contact/notes out of the packet, and the validator (proven by the offline harness) blocks
unsupported claims with a deterministic fallback. Nothing the model produces is required for,
or can mutate, core operations. A **hard wall-clock inference timeout** is now wired into the
runtime (Phase 10) so a slow/hung generation falls back to the deterministic/template path
instead of blocking the surface. **Caveat:** the *pass-on-real-model-output* path still benefits
from a physical-device capture before final sign-off; the safety floor
(skip/sanitize/validate/fallback) does not depend on that capture.

---

## Phase 10 — LLM Task Configuration + Note Sentiment + Guest Draft Fix (DONE)

### Problem
All three model tasks (host briefing, guest message draft, note analysis) shared **one
hardcoded system prompt** (`"Rewrite the approved host facts into calm staff-facing prose"`)
and **one 100-token cap**. Consequences:
- Guest drafts inherited the *staff-facing* system prompt → "Dear staff, we are writing to
  provide a guest communication draft…" meta-output, and a full email + SMS JSON could not fit
  in 100 tokens (truncated → parse failure → template).
- Note analysis was purely deterministic keyword matching — no model, no sentiment.
- A slow inference could block the surface with no timeout, contributing to the Host tab
  "sometimes falls back to the default engine" symptom.

### Per-task model profiles
**`Features/HostIntelligence/HostLocalModelRuntime.swift`** — new `HostLocalModelTaskProfile`
(`taskName`, `systemPrompt`, `maxOutputTokens`, `echoStopMarkers`, `artifactPrefixes`,
`maxInferenceSeconds`). Three profiles: `.hostBriefing` (unchanged behavior — 100 tokens, host
markers), `.guestMessageDraft` (guest-facing system prompt, 360 tokens, JSON stop markers),
`.noteAnalysis` (classification system prompt, 300 tokens). Protocol gains
`generate(prompt:profile:)` with a default that routes to `generateBriefing` for safety.

**`Features/HostIntelligence/HostLlamaBriefingRuntime.swift`**:
- `generateBriefing(prompt:)` now routes through `.hostBriefing` (identical output).
- `generate(prompt:profile:)` wraps the Qwen instruct template with the profile's system
  prompt, uses the profile's token budget and stop markers, and sanitizes with the profile's
  artifact prefixes.
- Session `generate` gains a `deadline: Date`; the token loop throws `.timedOut` (or returns
  partial text) once the deadline passes. New `HostLocalModelRuntimeError.timedOut`.

### Guest draft fix (email + SMS)
**`Features/GuestMessaging/GuestMessageDraftWriter.swift`** — `LocalModelGuestMessageDraftWriter`
now calls `generate(prompt:, profile: .guestMessageDraft)` and emits `[MODEL_TASK_TRACE]`.
**`Features/GuestMessaging/GuestMessageDraftValidator.swift`** — new `staffFacingPhrases` list
blocks `dear staff`, `dear team`, `here is a draft`, `guest communication draft`, etc., so any
residual staff-addressed/meta output falls back to the template instead of reaching staff.
Default `useLocalModelForGuestMessageDrafts` flipped to **true** (staff still reviews every
draft before sending; template fallback always present).

### Model note sentiment + classification
**`Features/ServiceIntelligence/Analyzers/LocalModelNoteAnalyzer.swift`** (new, `actor`) —
additive on top of the deterministic `NoteSignalAnalyzer`. Asks the model for (1) a tone
(`positive` / `neutral` / `concerned`) and (2) signal *types* from a strict allowlist + short
evidence. **The model never writes staff-facing wording** — it only picks a category; the app
owns every sentence. This makes it structurally impossible for the model to claim "deposit
paid" or "allergy confirmed." Unknown/forbidden types and PII-bearing evidence are dropped.
New `ReservationSignalType.guestSentiment`; signals carry `source: .localModel`.

**`Features/Reservations/ReservationDetailView.swift`** — `enrichNoteSignalsWithModel()` runs
on `.onAppear` (non-blocking `Task`), stores `modelNoteSignals`, and `recomputeNoteSignals()`
merges them **additively** (deterministic + attachment signals win on type collisions).

### Settings + diagnostics
- New setting `useLocalModelForNoteAnalysis` (default **true**), toggle in
  `HostIntelligenceSettingsView`. Both detail-only model toggles are excluded from
  `hostDecisionFingerprint` (they do not affect Host board decisioning).
- New `Features/HostIntelligence/ModelTaskTrace.swift` → `[MODEL_TASK_TRACE]` (DEBUG only):
  `task=<hostBriefing|guestMessageDraft|noteAnalysis> status=<started|completed|blocked|fallback>`.

### Architecture rules
- The deterministic baseline always renders first; model output is additive enrichment.
- Each task is isolated by profile — no task can inherit another's system prompt again.
- Hard timeout per task; on timeout/parse-fail/validation-fail → deterministic/template path.
- No model output is auto-sent or auto-confirmed; staff reviews drafts before sending.

### Trace output examples
```
[MODEL_TASK_TRACE] task=guestMessageDraft status=started
[MODEL_TASK_TRACE] task=guestMessageDraft status=completed detail=source=localModel
[MODEL_TASK_TRACE] task=noteAnalysis status=started
[MODEL_TASK_TRACE] task=noteAnalysis status=completed detail=signals=2
[MODEL_TASK_TRACE] task=noteAnalysis status=fallback reason=parse_failed
```

### Build status
Debug build (`generic/platform=iOS`): `** BUILD SUCCEEDED **` — no errors, no linter warnings.
