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
