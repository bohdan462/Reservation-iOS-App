# Tryzub Reservations — Project Map

> **ARCHIVE / UNSAFE FOR IMPLEMENTATION.** Do not code from this file. Use [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) and [DOCS_INDEX.md](./DOCS_INDEX.md) first.

> **Reference index only. Not source of truth. Start with [DOCS_INDEX.md](./DOCS_INDEX.md) and [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md).**

> **Audit:** `audit-current-state` (2026-06-14) — see [DOCS_INDEX.md](./DOCS_INDEX.md). Confirm flow and shift reminders sections here may be stale; prefer [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md).

One-restaurant internal iOS app. **WordPress REST API is source of truth.** **SwiftData is cache only.**

**REST base:** `https://tryzubchicago.com/wp-json/tryzub/v1`

**Hard rule:** iOS must **not** call `POST /managed-reservations/import` during normal workflow (not in API client; diagnostics monitors for accidental use).

---

## 0. Open this file when you need…

| Need | File |
| --- | --- |
| Tab shell, navigation | `Features/Reservations/ReservationsListView.swift` |
| Today board | `Features/Reservations/HostBoardView.swift` |
| Reservation detail | `Features/Reservations/ReservationDetailView.swift` |
| Manual Gmail/Mail draft text + log | `Features/Reservations/ReservationDetailView.swift` (`ManualEmailDraftService`), `POST /manual-email-log` |
| Create / edit form | `Features/Reservations/ManualReservationFormView.swift` |
| Staff action buttons | `Features/Reservations/ReservationActionButtons.swift` |
| Design tokens, charts, slot grids | `Features/Reservations/ReservationSharedUI.swift` |
| Workflow coordinator | `Import/ReservationsController.swift` |
| Sync (GET → cache) | `Import/ReservationImportService.swift` (`ReservationSyncService`) |
| Mutations (POST/PATCH/DELETE) | `Services/ReservationMutationService.swift` |
| SwiftData writes | `Services/ReservationRepository.swift` |
| All HTTP | `Network/ReservationsAPIClient.swift` |
| SwiftData model | `Persistence/ReservationRecord.swift` |
| DTOs | `Network/ReservationDTO.swift` |
| Settings UI + store | `Features/Reservations/RestaurantSettingsStore.swift` |
| Floor plan (backend canonical) | `Features/FloorPlan/*`, `FloorPlanStore`, `Docs/TABLE_CONFIGURATION.md` |
| Table inventory (legacy advisory) | `Features/HostIntelligence/HostTableConfigStore.swift`, `Docs/TABLE_CONFIGURATION.md` |
| Activity history (backend-owned) | `ReservationActivityStore`, `Docs/ACTIVITY_HISTORY.md` |
| Business analytics UI | `Features/Reservations/BusinessAnalyticsView.swift`, `BusinessIntelligenceOverviewSection.swift` |
| Host intelligence | `Features/HostIntelligence/*`, `HostIntelligenceController.swift` |
| Guest messaging drafts | `Features/GuestMessaging/*`, `Docs/LOCAL_MODEL_INTELLIGENCE.md` |
| Local model docs | `Docs/LOCAL_MODEL_INTELLIGENCE.md`, `Docs/HOST_INTELLIGENCE_LOCAL_MODEL_RUNTIME_PROPOSAL.md` (historical) |
| Operational guest lookup | `Features/Guests/*` |
| Guest memory | `Features/GuestInsights/*` |
| Dev diagnostics | `Features/Reservations/DeveloperDiagnosticsView.swift` |
| Login role + capabilities | `Core/Roles/AppUserRole.swift`, `App/AppRoleStore.swift`, `Tryzub_ReservationsApp.swift` |
| Credentials | `App/AppCredentials.swift` |
| App entry | `Tryzub_ReservationsApp.swift` |

---

## 1. Source tree (~255 Swift files)

High-level layout (not an exhaustive file list):

```
Tryzub Reservations/
├── Tryzub_ReservationsApp.swift          # @main, login gate, SwiftData container
├── App/                                # credentials, role, notices, session
├── Core/Roles/                         # AppUserRole, AppCapabilities
├── Features/
│   ├── Reservations/                   # tab shell, host, detail, schedule, more, diagnostics
│   │   └── ActivityHistory/            # backend activity read-model + UI
│   ├── FloorPlan/                      # backend floor layout + PATCH /tables assignment
│   ├── HostIntelligence/               # engine, controller, local model, arrival pressure
│   ├── GuestMessaging/                 # staff-reviewed draft messages (no auto-send)
│   ├── GuestInsights/                  # cache-only guest memory / regulars
│   ├── Guests/                         # operational call-in lookup tab
│   ├── ServiceIntelligence/            # More → Service Intelligence
│   ├── ServiceTimeline/                # host timeline preview + full-screen view
│   └── Siri/                           # host summary intents
├── Import/                             # ReservationsController, ReservationSyncService
├── Network/                            # API client, DTOs (incl. ReservationActivityDTO)
├── Persistence/                        # ReservationRecord + attachment/note records
├── Preview/                            # preview API client + sample data
└── Services/                           # repository, mutations, freshness, floor plan service
```

**Mounted stores** (from `ReservationsTabShell`): `RestaurantSettingsStore`, `HostTableConfigStore`, `HostIntelligenceSettingsStore`, `HostIntelligenceController`, `GuestIntelligenceStore`, `BusinessIntelligenceStore`, `IntelligenceSystemStatusStore`, `FloorPlanStore`, `ReservationActivityStore`.

---

## 2. App startup

| Step | What happens |
| --- | --- |
| 1 | `AppCredentialStore` loads env vars (`TRYZUB_API_USERNAME`, `TRYZUB_API_PASSWORD`) or Keychain |
| 2 | No complete saved session → `AppLoginView` |
| 3 | Login validates Manager/Developer credentials with lightweight `GET /restaurant-setup` |
| 4 | Successful login saves WordPress Application Password credentials to Keychain and selected role to `AppRoleStore` |
| 5 | Saved session → `ReservationsListView(environment:onLogout:)` with one shared `ReservationsAPIClient` and selected capabilities |
| 6 | `.modelContainer(for: ReservationRecord.self)` at scene level |
| 7 | Root `.task` shows launch overlay and starts `performStartupNetworkPass` in background |
| 8 | Startup network pass serializes active-window full sync first, then `GET /restaurant-setup` |

**Audience:** Manager and Developer sign in with their own WordPress username and Application Password. Staff capability code exists, but staff is not selectable for the current pilot. Logout is in More → Account and clears the saved Keychain session plus selected role.

---

## 3. Native tab shell

Root navigation now uses native SwiftUI `TabView(selection:)`. The custom `ReservationFloatingTabBar` is no longer used as the app shell; its file only keeps the tab enum for project stability.

| Tab | Label | Root | Fetches when |
| --- | --- | --- | --- |
| `.host` | Host / Dev | `HomeDashboardView` → `HostBoardView` | Active-window cache; pull-refresh; guarded active-window delta/full auto-refresh when visible; cached availability summary; guest intelligence on selected date (deferred) |
| `.floorPlan` | Floor | `FloorPlanView` | `GET /floor-plan?date=` when tab active / date changes; assignment via `PATCH /tables` |
| `.bookings` | Bookings | `ReservationScheduleView` | Upcoming/Needs Review/Cancelled filters use active-window cache; All mode pages history explicitly |
| `.guests` | Guests | `GuestLookupView` | Cache-derived search only; no network while typing |
| `.more` | More | `ReservationMoreView` | Child screens only on navigation (activity history, analytics, settings, etc.) |

**Navigation strategy:** Each visible tab owns a native `NavigationStack`. Review is not a top-level tab; pending and needs-review work now lives in the Bookings segmented filter. More uses a typed destination path to avoid cancelled-detail path mismatch crashes.

**Shared state:** `@EnvironmentObject ReservationsController`, `HiddenReservationsStore`.

---

## 4. Role & audience matrix

### Capabilities (`AppCapabilities.capabilities(for:)`)

| Flag | Staff | Manager | Developer |
| --- | :---: | :---: | :---: |
| Seat | ✓ | ✓ | ✓ |
| Edit details / table | ✓ | ✓ | ✓ |
| Confirm / cancel | ✗ | ✓ | ✓ |
| Manual create | ✗ | ✓ | ✓ |
| Guest Lookup call-in booking | ✗ | ✓ | ✓ |
| Guest manage link | ✗ | ✓ | ✓ |
| Hidden reservations | ✗ | ✓ | ✓ |
| Restaurant settings | ✗ | ✓ | ✓ |
| Business analytics | ✗ | ✓ | ✓ |
| Failed imports (capability) | ✗ | ✓ | ✓ |
| Developer diagnostics | ✗ | ✗ | ✓ |
| Hard delete | ✗ | ✗ | ✓ |

### Screen audience

| Screen / feature | Staff | Manager | Developer |
| --- | :---: | :---: | :---: |
| Host / Bookings / Detail | ✓ | ✓ | ✓ |
| Seat, assign table, complete | ✓ | ✓ | ✓ |
| Confirm, cancel, no-show | ✗ | ✓ | ✓ |
| Manual create | ✗ | ✓ | ✓ |
| Guest Lookup / Book Call-In | ✗ | ✓ | ✓ |
| Guest manage link | ✗ | ✓ | ✓ |
| Guest Memory / Regulars | ✓ | ✓ | ✓ |
| Restaurant settings subtree | ✗ | ✓ | ✓ |
| Business analytics | ✗ | ✓ | ✓ |
| Hidden reservations archive | ✗ | ✓ | ✓ |
| Failed imports UI | ✗ | ✗* | ✓ |
| API diagnostics | ✗ | ✗ | ✓ |
| Hard delete on hidden screen | ✗ | ✗ | ✓ |

\*Manager has `canViewFailedImports` but nav link also requires `canViewDeveloperDiagnostics`.

---

## 5. Layer responsibilities

### ReservationsController (`Import/ReservationsController.swift`)

Owns: active-window sync scopes, `server_time` cursors, `operationState`, `isSyncing` / `isAutoRefreshing`, `actionInProgressIDs`, reconcile IDs, notices, import failure count, `restaurantSetup`, Home availability summary cache, local seated timestamps, admin tests.

Reservation views should call controller. Settings screens use `RestaurantSettingsStore` with the shared API client. Home availability summary is controller-cached and TTL guarded.

### ReservationSyncService (`Import/ReservationImportService.swift`)

GET list operations → repository replace or upsert. Current normal workflow uses active-window full/delta paths. Returns `ReservationSyncResult(rowCount, serverTime)`.

### ReservationMutationService

POST/PATCH/DELETE/confirm → repository upsert or delete.

### ReservationRepository

SwiftData upsert/replace/delete. Match key: `remoteID`.

### ReservationsAPIClient

All HTTP; Basic auth; sanitized request logging; one-at-a-time request serializer; 15s request timeout / 30s resource timeout; GET retry capped at one retry; non-GET no blind retry.

---

## 5b. Intelligence, analytics, messaging

### Backend intelligence (deterministic evidence)

API endpoints consumed by iOS stores (no raw guest notes / PII blobs in UI):

| Endpoint area | Store | UI |
| --- | --- | --- |
| `GET /business-intelligence/summary` | `BusinessIntelligenceStore` | Business Analytics overview cards |
| Guest intelligence summaries | `GuestIntelligenceStore` | Host pulse / guest signals (backend-first) |
| `GET /intelligence/system-status` | `IntelligenceSystemStatusStore` | System health strip in Business Analytics |

DTOs: `BusinessIntelligenceDTO.swift`, `GuestIntelligenceDTO.swift`, `IntelligenceSystemStatusDTO.swift`.

### Business Analytics (`BusinessAnalyticsView`)

- **Business intelligence overview** — demand, guest relationships, operational risk, system health (rolling window)
- **Meaningful charts** — arrival, weekday, new vs repeat (extracted helpers)
- **Legacy analytics** — original `ReservationAnalyticsSummaryDTO` charts preserved below BI section
- Loads in parallel; BI failure does not remove legacy charts

### Host Intelligence

- **Deterministic engine** — `HostIntelligenceEngine` remains authoritative for signals and `HostLLMPacket`
- **Backend guest summaries first** — `GuestIntelligenceStore` keyed by reservation/date; local SwiftData guest memory as fallback
- **On-device briefing** — optional local model wording via `HostBriefingWriter` (staff-gated)
- Host board UI: `HostBoardView`, `HostIntelligenceController`

### Guest messaging (staff-controlled drafts)

- **Reservation Detail** — “Draft guest message” actions + review sheet
- **`GuestCommunicationCoordinator`** — draft prep, Mail/Text conversion, copy, staff-safe errors
- **`GuestMessageDraftService`** — packet → template/local writer → validation
- **Template drafts default**; local model guest draft mode planned opt-in later
- **Separate from** legacy Confirm + Email (`POST /confirm`) and confirmation-link email with guest notes (`ManualEmailDraftService`)
- See `Docs/LOCAL_MODEL_INTELLIGENCE.md`

### Table configuration (local)

## Table & floor (see `Docs/TABLE_CONFIGURATION.md`)

- **Canonical:** `FloorPlanStore` + backend `GET/PUT /restaurant-tables`, `GET /floor-plan`, `PATCH /managed-reservations/{id}/tables`
- **`ReservationRecord.tableName`** — display/cache field; not preferred assignment mutation when backend layout exists
- **`HostTableConfigStore`** — legacy local advisory inventory (chips, host intelligence fit); **not** production floor source of truth
- **`TableAssignmentOptionsBuilder`** — assignment chips; prefers backend layout labels when available
- **`ReservationTableOptionsStore`** — legacy chip fallback when local inventory empty
- **`HostTableCapacityTextParser`** — import text into local store; migration/fallback only
- **Advisory only** — fit/mismatch/suggestions warn; staff manual override always allowed

---

## 6. Screens reference

### Home — `HostBoardView`

- Service date picker, stats card, `ServiceLoadChart`, seated + upcoming panels
- Auto-refresh loop (60s) via `autoRefreshDashboardIfAllowed`
- Today availability line: controller `ensureAvailabilitySummary` → day-availability + slots + blocked (180s cache, in-flight de-duped, cancellable when Home hides)
- Staff actions → controller; confirm dialog splits Confirm Only / Confirm + Email
- Form Problems button: developer-only (both caps)

### Bookings — `ReservationScheduleView`

- Scopes: Upcoming, Needs Review, Cancelled (from active-window cache) or All (paginated server search)
- `scheduleBecameActive` on tab focus only ensures active-window freshness
- `schedule_all_page` only runs when Schedule is active, scope is `.all`, and the user selects All/searches/refreshes/loads more

### Review / Needs Review

- Review is a Bookings filter, not a visible top-level tab.
- It filters active-window cached pending rows (`new` + `needs_review`).
- It does not call a separate review queue fetch during tab switching.

### Guests — `GuestLookupView`

- Operational call-in lookup tab; V1 is **call-in only**.
- Builds `GuestLookupResult` profiles from cached, non-hidden `ReservationRecord` rows.
- Phone digits are the strongest identity key, email is secondary, and name-only matches stay weak/separate.
- Search activates only with at least 2 name characters or 4 phone digits.
- No network calls while searching; does **not** call `GuestInsightsController` or `RegularGuestsController`.
- Book Call-In opens `ManualReservationFormView(prefill:)`; lookup-prefilled calls require local “Phone confirmed with caller” before create.
- No backend guest profile table and no Walk-In UI yet.

### Detail — `ReservationDetailView`

- Layered cards: hero, actions, contact, notes, **history** (backend activity), service load, guest insights preview
- Edit sheet → `ReservationEditFormView`
- Table assignment sheet
- More menu: hide, restore, guest manage link (manager+)
- Manage-link flow can copy a local manual confirmation draft; it does not send email or call `/confirm`.
- Confirm dialog: Confirm Only / Confirm + Email

### Create / Edit — `ManualReservationFormView.swift`

- **Create:** review confirmation → `createAcceptedManualReservation` (confirmed, no email)
- **Guest lookup prefill:** `ManualReservationPrefill` sets name/phone/email, still submits `source_type=manual_call_in`, and requires local phone confirmation before create.
- **Edit (`ReservationEditFormView`):** save diff confirmation → PATCH; hide button for eligible manual rows
- Slot chips via `RestaurantSettingsStore.ensureDateOperations` or controller slot load

### More — `ReservationMoreView`

- Notices screen, Account/logout, Cancelled, Hidden, settings links, manual create, analytics, guest memory, **Activity History**
- Developer / Support section: Failed Imports sheet for roles with `canViewFailedImports`, API Diagnostics for developer
- Duplicate resolution instructions (manual supersede workflow)

### Hidden — `HiddenReservationsView` (in `ReservationsListView.swift`)

- `loadHiddenReservations` on open
- Restore per row; hard delete (developer only)

### Settings — embedded in `RestaurantSettingsStore.swift`

- `RestaurantSettingsView`, `WeeklyHoursView`, `TodayAvailabilityView`, `BlockedTimeSlotsView`, `BusinessAnalyticsView`

### Guest Insights

- `GuestLookupView` (Guests tab) — operational, cache-derived, lightweight call-in lookup
- `RegularGuestsView` (More) — all roles
- `GuestInsightsView` — from detail preview; **no network**
- Known performance risk: broad cache `@Query` plus repeated in-memory clustering; refactor into cached summaries before growing history.
- Operational Guest Lookup is separate from Guest Memory; do not reuse heavy clustering for call-in search.

### Diagnostics — `DeveloperDiagnosticsView`

- Safe GET tests, request log, endpoint checklist, cache stats, scope snapshots

---

## 7. Endpoint usage by feature

### Public (no auth)

| Endpoint | Used by |
| --- | --- |
| `GET /ping` | Diagnostics test |
| `GET /reservation-slots?date=` | Forms, settings, Home summary, diagnostics |

### Reservations — protected

| Endpoint | Used by | Normal workflow? |
| --- | --- | --- |
| `GET /managed-reservations` | Sync, schedule, review, hidden, cancelled, diagnostics | ✓ |
| `GET /managed-reservations/{id}` | Reconcile, fetch-by-ID test | ✓ (reconcile) |
| `POST /managed-reservations` | Manual create, import repair | ✓ |
| `PATCH /managed-reservations/{id}` | Edit, status, hide, restore | ✓ |
| `POST /managed-reservations/{id}/confirm` | Backend/provider Confirm + Email fallback | Disabled in MVP UI |
| `POST /managed-reservations/{id}/guest-manage-link` | Detail More menu | ✓ |
| `POST /managed-reservations/{id}/manual-email-log` | Detail manual Gmail/Mail activity | ✓ |
| `GET /managed-reservations/{id}/activity` | Reservation Detail history, full history sheet | ✓ (lazy on detail open) |
| `GET /activity?date=` | More → Activity History | ✓ (lazy on screen open) |
| Local manual confirmation draft | Detail More menu after manage link | Local compose/copy only |
| `DELETE /managed-reservations/{id}?force=1` | Hidden screen hard delete | Dev cleanup only |
| `GET /managed-reservations/import-failures` | Failed Imports screen, explicit diagnostics/count checks | Dev/support |
| `POST /managed-reservations/import` | — | **NOT USED** |

### Restaurant — protected

| Endpoint | Used by |
| --- | --- |
| `GET/PATCH /restaurant-setup` | Startup, settings |
| `GET/PATCH /restaurant-hours` | Weekly hours |
| `GET/PATCH /restaurant-day-availability?date=` | Today availability, Home summary |
| `GET/POST/DELETE /restaurant-blocked-slots` | Blocked slots settings |
| `GET /reservation-analytics/summary` | Business analytics |

---

## 8. Fetch timing cheat sheet

| When | Network call | Blocks UI? |
| --- | --- | --- |
| App launch | Active-window full sync + restaurant setup | Shows cache first behind launch overlay |
| Home visible, every 60s | Active-window delta if cursor exists, else full | No — background |
| Home pull-refresh | Active-window full refresh | Refresh indicator |
| Bookings tab focus (stale) | Active-window full refresh | No |
| Bookings → Needs Review | Active-window cache filter | No |
| Guests search typing | Local cache search only | No |
| More → Hidden open | `include_hidden=1` upsert | Screen loading state |
| More → Cancelled open | Cancelled window upsert | Screen loading state |
| More → Settings child | Per-screen lazy GET | Screen loading state |
| More → Analytics | Summary GET | Screen loading state |
| More → Activity History | `GET /activity?date=` | Screen loading state |
| Reservation detail open | `GET /managed-reservations/{id}/activity` | No — section loads in background |
| Tab switch alone | **Nothing** | — |

**Do not fetch during normal tab switching** except gated auto-refresh on Home when already visible.

---

## 9. Mutation & email semantics

| UI label | Controller | Endpoint | Email |
| --- | --- | --- | --- |
| Confirm Only | `updateStatus(.confirmed)` | PATCH | No |
| Confirm + Email | `confirmReservation` | POST `/confirm` | Backend/provider path, disabled in MVP UI |
| Manual create | `createAcceptedManualReservation` | POST | No |
| Generate manage link | `generateGuestManageLink` | POST `/guest-manage-link` | No — copy link |
| Send/Copy confirmation draft | `ManualEmailDraftService` + `recordManualConfirmationDraftCreated` | POST `/manual-email-log` with `draft_created` | No — staff reviews/sends in Gmail/Mail |
| Record manual sent | `recordManualConfirmationSent` | POST `/manual-email-log` with `manual_sent`; reconcile by ID | No backend sending; staff reported manual send |
| Hide wrong entry | `hideWrongEntry` | PATCH `is_hidden` | No |
| Restore | `restoreHiddenReservation` | PATCH | No |
| Hard delete | `hardDeleteReservation` | DELETE `force=1` | No |

**MVP email direction:** Manual Gmail/Mail with pasted manage link for call-ins. `manual_sent` records staff-reported activity only; backend cannot prove inbox delivery. Optional backend/provider email remains `/confirm` and is not the normal pilot path.

**Activity history (schema 1.7.0):** Backend writes activity inside mutation endpoints. iOS **reads** history only — never logs a second activity row after mutations. Old reservations may show “No history yet” until changed after backend deploy (no backfill).

**Guest self-service truth:** Public guest page is “Your Booking Details.” Guests may cancel online until 2 hours before reservation time, including same-day bookings more than 2 hours away. Inside 2 hours they must call. Guest change-request UI is hidden for MVP.

---

## 10. SwiftData model — `ReservationRecord`

- Local `id: UUID`; server key `remoteID: Int`
- Mirrors `ReservationDTO` fields including `isHidden`, `hiddenReason`, email timestamps
- `lastSyncedAt` set on upsert; `updatedAt` on local update
- Hidden rows excluded from staff lists via `HiddenReservationsStore`

**When written:** After successful server response (sync upsert/replace, mutation upsert). Hard delete removes local row after server OK.

**When deleted locally:** `replaceDateScope` / `replaceDateWindow` orphans (non-hidden); `deleteReservation` after hard delete.

---

## 11. Shared UI — `ReservationSharedUI.swift`

| Symbol | Purpose |
| --- | --- |
| `TryzubColors`, `TryzubTypography`, `TryzubSpacing` | Design tokens |
| `ReservationLayout`, `ReservationUIStyle` | Layout constants |
| `ReservationSlotGridStyle` | Consistent time-slot chip spacing |
| `ServiceLoadChart`, `ServiceTimeline` | Swift Charts |
| `ReservationFormChange`, `ReservationFormChangeReview` | Edit save diff UI |
| `TryzubSectionCard`, `ReservationServiceCard` | Card components |
| `BottomSafeActionBar` | Bottom action chrome |

---

## 12. Notices & loading state

| State | Where | UI effect |
| --- | --- | --- |
| `controller.notices` | `AppNoticeOverlay` | Tab-filtered toasts + sheet |
| `actionInProgressIDs` | Action buttons | Disables per-reservation actions |
| `isCreatingReservation` | Create form | Disables create |
| `isSyncing` / `isAutoRefreshing` | Controller | Header/toolbar progress only; cached rows stay visible |
| `RestaurantSettingsStore.isLoading*` | Settings screens | Per-screen progress |

**Known UX risk:** Long mutations block individual reservation actions, not entire tab. Some sheets may still need clearer per-button progress copy during the next UI polish pass.

---

## 13. Current MVP status

| Area | Status |
| --- | --- |
| Today board + service ops | Implemented |
| Schedule / review queues | Implemented |
| Confirm Only vs Confirm + Email | Implemented |
| Manual create (confirmed, no email) | Implemented |
| Guest manage link copy | Implemented |
| Manual Gmail/Mail draft boundary | Implemented (copy text only; compose/send deferred) |
| Soft hide + hidden archive | Implemented |
| Restaurant settings / blocked slots | Implemented |
| Business analytics | Implemented |
| Guest Insights (cache-only) | Implemented |
| Developer diagnostics | Implemented |
| Hard delete (dev cleanup) | Implemented |
| Role picker at runtime | Implemented for manager/developer; staff exists in code but is not selectable |
| Manager Failed Imports UI | Implemented as a sheet when `canViewFailedImports` |
| Backend cancel/confirmation emails from iOS | Partial — Confirm + Email only; cancel says no email yet |
| Persistent sync cursor across restarts | **Not implemented** |

---

## 14. Known weak spots — do not break during pilot

1. **Staff role exists but is not selectable** — decide whether pilot should expose staff mode.
2. **`POST /import` must stay unused** — backend import is separate pipeline.
3. **Review queue replace does not delete** — stale `needs_review` rows may linger until status PATCH or full date replace.
4. **Guest Insights** depends on cache depth — incomplete history on fresh install.
5. **Guest Memory broad query** — can become the next major jank source as cache grows.
6. **`createReservation` controller method** — dead path; UI uses `createAcceptedManualReservation`.
7. **Cursors in-memory** — app restart loses `updated_since` optimization.

---

## 15. Current Engineering Audit

### Strong

- Native `TabView` now owns Host / Bookings / Guests / More navigation.
- Active-window cache now serves Home, Bookings upcoming, and Bookings needs-review.
- `updated_since` delta is scoped to the active window and upsert-only.
- Mutations are server-first and row-scoped; uncertain failures reconcile by ID.
- Offline/degraded mode keeps cache readable and blocks unsafe mutations.
- Availability/setup/slot reads are TTL guarded and in-flight de-duped.
- API diagnostics show request reasons, skip/fresh/in-flight decisions, and sanitized snippets.

### Fragile / Risky

- `ReservationsController` is still too broad. It coordinates sync, mutations, settings setup cache, availability cache, notices, diagnostics, and local seated timestamps.
- Guest Memory is the top performance risk. `RegularGuestsView` observes all reservations; its summaries must stay cached/memoized rather than rebuilt from SwiftUI body.
- Guest Insights is cache-only but CPU-heavy. Detail/Guest Insights should render precomputed reports rather than scanning broad reservation arrays during body evaluation.
- Mounted tabs reduce navigation churn but still observe SwiftData writes; large upserts can trigger recomputation across hidden tabs.
- More uses a typed navigation path. Child screens should not add nested path-based `NavigationStack`s unless carefully isolated.
- Legacy sync helpers remain in the controller; avoid using old today/schedule/review replace paths for normal tab activation.

### Next Refactor Chunks

1. Move guest-analysis work to lightweight snapshots/off-main analysis if cache grows beyond pilot size.
2. Move Add/Edit slot loading and closed-day validation into a focused form store before visual redesign.
3. Split controller availability/setup caches only if it reduces churn without changing routes.
4. Extract availability operations from `ReservationsController` only after the form/store boundary is clear.
5. Persist active-window cursor by window key.
6. Remove or quarantine legacy sync helpers after call-site audit.

---

## 16. What not to touch during pilot

- Backend route paths and DTO field names
- `replaceDateScope` / `replaceDateWindow` delete semantics
- Confirm Only vs Confirm + Email split
- `include_hidden` and `is_hidden` PATCH contract
- Auth header format (WordPress Application Password)
- SwiftData `ReservationRecord` schema without migration plan
