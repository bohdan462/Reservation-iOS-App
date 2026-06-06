# Tryzub Reservations — Project Map

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
| Manual Gmail/Mail draft text | `Features/Reservations/ReservationDetailView.swift` (`ManualEmailDraftService`) |
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
| Guest memory | `Features/GuestInsights/*` |
| Dev diagnostics | `Features/Reservations/DeveloperDiagnosticsView.swift` |
| Roles + role picker | `Core/Roles/AppUserRole.swift`, `App/AppRoleStore.swift` |
| Credentials | `App/AppCredentials.swift` |
| App entry | `Tryzub_ReservationsApp.swift` |

---

## 1. Source tree (41 Swift files)

```
Tryzub Reservations/
├── Tryzub_ReservationsApp.swift          # @main, credentials gate, SwiftData container
├── App/
│   ├── AppCredentials.swift            # AppCredentialStore, Keychain
│   ├── AppEnvironment.swift            # apiClient + role + capabilities
│   └── AppNotice.swift                 # Notice model (severity, source)
├── Core/Roles/AppUserRole.swift        # staff | manager | developer + AppCapabilities
├── Features/
│   ├── GuestInsights/                  # 7 files — cache-only analytics
│   │   ├── GuestInsightsController.swift
│   │   ├── GuestInsightsModels.swift
│   │   ├── GuestInsightsView.swift
│   │   ├── GuestIdentityResolver.swift
│   │   ├── GuestReservationIntentDeduper.swift
│   │   ├── RegularGuestsController.swift
│   │   └── RegularGuestsView.swift
│   └── Reservations/                   # 18 files — main UI
│       ├── ReservationsListView.swift  # Root shell + tab views (private structs)
│       ├── HostBoardView.swift
│       ├── ReservationDetailView.swift
│       ├── ManualReservationFormView.swift   # Create + ReservationEditFormView
│       ├── ReservationRowView.swift
│       ├── ReservationSharedUI.swift
│       ├── ReservationActionButtons.swift
│       ├── ReservationPresentation.swift
│       ├── ReservationFloatingTabBar.swift
│       ├── RestaurantSettingsStore.swift     # Store + embedded settings views
│       ├── DeveloperDiagnosticsView.swift
│       ├── ImportFailuresView.swift
│       ├── HiddenReservationsStore.swift
│       ├── AppNoticeOverlay.swift
│       └── ReservationHaptics.swift
├── Import/
│   ├── ReservationsController.swift
│   └── ReservationImportService.swift  # class ReservationSyncService
├── Network/
│   ├── ReservationsAPIClient.swift
│   ├── ReservationDTO.swift
│   ├── ReservationsResponse.swift
│   ├── ReservationAPIError.swift
│   └── APIRequestLogStore.swift
├── Persistence/ReservationRecord.swift
├── Preview/ReservationPreviewData.swift
└── Services/
    ├── ReservationRepository.swift
    ├── ReservationMutationService.swift
    └── ImportFailureService.swift
```

---

## 2. App startup

| Step | What happens |
| --- | --- |
| 1 | `AppCredentialStore` loads env vars (`TRYZUB_API_USERNAME`, `TRYZUB_API_PASSWORD`) or Keychain |
| 2 | No credentials → `CredentialsSetupView` (save to Keychain) |
| 3 | Credentials OK but no role → `RoleSelectionView` (manager/developer) |
| 4 | Role selected → `ReservationsListView(environment:)` with one shared `ReservationsAPIClient` and selected capabilities |
| 5 | `.modelContainer(for: ReservationRecord.self)` at scene level |
| 6 | Root `.task` shows launch overlay and starts `performStartupNetworkPass` in background |
| 7 | Startup network pass serializes active-window full sync first, then `GET /restaurant-setup` |

**Audience:** All roles see credentials gate once per device. Current selectable roles are manager and developer; staff capability code exists but staff is not selectable in `AppRoleStore.selectableRoles`.

---

## 3. Tab shell

Custom `ReservationFloatingTabBar` — **not** `TabView`.

| Tab | Label | Root | Fetches when |
| --- | --- | --- | --- |
| `.home` | Home | `HomeDashboardView` → `HostBoardView` | Active-window cache; pull-refresh; 60s active-window delta/full auto-refresh when visible; cached availability summary |
| `.schedule` | List | `ReservationScheduleView` | Upcoming uses active-window cache; activation only ensures active window freshness; All mode pages history explicitly |
| `.review` | Review | `ReservationReviewQueueView` | Filters active-window pending rows; activation only ensures active window freshness |
| `.more` | More | `ReservationMoreView` | Child screens only on navigation |

**Mount strategy:** All four tabs stay in `ZStack`; visibility via `opacity` / `allowsHitTesting` / `zIndex`. Each main tab has its own `NavigationStack`; More uses a typed destination path to avoid cancelled-detail path mismatch crashes.

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
| Home / List / Review / Detail | ✓ | ✓ | ✓ |
| Seat, assign table, complete | ✓ | ✓ | ✓ |
| Confirm, cancel, no-show | ✗ | ✓ | ✓ |
| Manual create | ✗ | ✓ | ✓ |
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

## 6. Screens reference

### Home — `HostBoardView`

- Service date picker, stats card, `ServiceLoadChart`, seated + upcoming panels
- Auto-refresh loop (60s) via `autoRefreshDashboardIfAllowed`
- Today availability line: controller `ensureAvailabilitySummary` → day-availability + slots + blocked (180s cache, in-flight de-duped, cancellable when Home hides)
- Staff actions → controller; confirm dialog splits Confirm Only / Confirm + Email
- Form Problems button: developer-only (both caps)

### List — `ReservationScheduleView`

- Scopes: Upcoming window (from cache) or All (paginated server search)
- `scheduleBecameActive` on tab focus only ensures active-window freshness
- `schedule_all_page` only runs when Schedule is active, scope is `.all`, and the user selects All/searches/refreshes/loads more

### Review — `ReservationReviewQueueView`

- Default filter: Pending = `new` + `needs_review`, oldest first
- Filters active-window cached pending rows
- `reviewBecameActive` on tab focus only ensures active-window freshness

### Detail — `ReservationDetailView`

- Layered cards: hero, actions, contact, notes, service load, guest insights preview
- Edit sheet → `ReservationEditFormView`
- Table assignment sheet
- More menu: hide, restore, guest manage link (manager+)
- Manage-link flow can copy a local manual confirmation draft; it does not send email or call `/confirm`.
- Confirm dialog: Confirm Only / Confirm + Email

### Create / Edit — `ManualReservationFormView.swift`

- **Create:** review confirmation → `createAcceptedManualReservation` (confirmed, no email)
- **Edit (`ReservationEditFormView`):** save diff confirmation → PATCH; hide button for eligible manual rows
- Slot chips via `RestaurantSettingsStore.ensureDateOperations` or controller slot load

### More — `ReservationMoreView`

- Notices screen, role picker, Cancelled, Hidden, settings links, manual create, analytics, guest memory
- Developer / Support section: Failed Imports sheet for roles with `canViewFailedImports`, API Diagnostics for developer
- Duplicate resolution instructions (manual supersede workflow)

### Hidden — `HiddenReservationsView` (in `ReservationsListView.swift`)

- `loadHiddenReservations` on open
- Restore per row; hard delete (developer only)

### Settings — embedded in `RestaurantSettingsStore.swift`

- `RestaurantSettingsView`, `WeeklyHoursView`, `TodayAvailabilityView`, `BlockedTimeSlotsView`, `BusinessAnalyticsView`

### Guest Insights

- `RegularGuestsView` (More) — all roles
- `GuestInsightsView` — from detail preview; **no network**
- Known performance risk: broad cache `@Query` plus repeated in-memory clustering; refactor into cached summaries before growing history.

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
| `POST /managed-reservations/{id}/confirm` | Confirm + Email only | ✓ |
| `POST /managed-reservations/{id}/guest-manage-link` | Detail More menu | ✓ |
| Local manual confirmation draft | Detail More menu after manage link | Local only |
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
| Schedule tab focus (stale) | Active-window full refresh | No |
| Review tab focus (stale) | Active-window full refresh | No |
| More → Hidden open | `include_hidden=1` upsert | Screen loading state |
| More → Cancelled open | Cancelled window upsert | Screen loading state |
| More → Settings child | Per-screen lazy GET | Screen loading state |
| More → Analytics | Summary GET | Screen loading state |
| Tab switch alone | **Nothing** | — |

**Do not fetch during normal tab switching** except gated auto-refresh on Home when already visible.

---

## 9. Mutation & email semantics

| UI label | Controller | Endpoint | Email |
| --- | --- | --- | --- |
| Confirm Only | `updateStatus(.confirmed)` | PATCH | No |
| Confirm + Email | `confirmReservation` | POST `/confirm` | Backend |
| Manual create | `createAcceptedManualReservation` | POST | No |
| Generate manage link | `generateGuestManageLink` | POST `/guest-manage-link` | No — copy link |
| Copy confirmation draft | `ManualEmailDraftService.confirmationDraft` | Local only | No — staff reviews/pastes into Gmail/Mail |
| Hide wrong entry | `hideWrongEntry` | PATCH `is_hidden` | No |
| Restore | `restoreHiddenReservation` | PATCH | No |
| Hard delete | `hardDeleteReservation` | DELETE `force=1` | No |

**MVP email direction:** Manual Gmail/Mail with pasted manage link for call-ins; optional backend email via Confirm + Email.

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

- Active-window cache now serves Home, Schedule upcoming, and Review.
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
