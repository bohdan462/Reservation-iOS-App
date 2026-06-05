# Tryzub Reservations — Architecture Diagrams

**Source of truth:** WordPress REST API at `https://tryzubchicago.com/wp-json/tryzub/v1`  
**Local cache:** SwiftData `ReservationRecord` only — never authoritative  
**Hard rule:** iOS must **not** call `POST /managed-reservations/import` during normal workflow (not implemented in client; diagnostics tracks accidental use)

**Production note:** `Tryzub_ReservationsApp` hardcodes `role: .developer` today. Capability tables below reflect the role model; pilot builds should switch to `.staff` or `.manager` before boss testing.

---

## 1. High-level architecture

```mermaid
flowchart TB
    subgraph iOS["Tryzub Reservations iOS"]
        App["Tryzub_ReservationsApp"]
        Creds["AppCredentialStore / Keychain"]
        Env["AppEnvironment<br/>apiClient + role + capabilities"]
        Shell["ReservationsListView<br/>tab shell"]
        Ctrl["ReservationsController<br/>workflow coordinator"]
        Views["Feature views<br/>Home · List · Review · More"]
        Guest["GuestInsights<br/>cache-only"]
        Settings["RestaurantSettingsStore<br/>lazy settings UI"]
        SD["SwiftData<br/>ReservationRecord"]
    end

    subgraph Services["Services layer"]
        Sync["ReservationSyncService"]
        Mut["ReservationMutationService"]
        Repo["ReservationRepository"]
        IFail["ImportFailureService"]
    end

    subgraph Network["Network"]
        API["ReservationsAPIClient"]
        Log["APIRequestLogStore"]
    end

    WP["WordPress Tryzub plugin REST"]

    App --> Creds
    Creds --> Env
    App --> Shell
    Shell --> Ctrl
    Shell --> Views
    Views --> Ctrl
    Views --> Guest
    Views --> Settings
    Settings --> Ctrl
    Ctrl --> Sync
    Ctrl --> Mut
    Ctrl --> IFail
    Sync --> API
    Mut --> API
    IFail --> API
    Sync --> Repo
    Mut --> Repo
    Repo --> SD
    API --> Log
    API --> WP
```

**What matters**
- One shared `ReservationsAPIClient` per session; repositories/services are created per `ModelContext` operation.
- Views call **controller workflow methods** for reservations; settings screens mostly use `RestaurantSettingsStore` → controller.
- **Exception:** `HostBoardView` calls `environment.apiClient` directly for today availability/slots/blocked summary (lazy, 120s cache) — not through controller.
- `ReservationsController.operationState` mirrors refresh, mutation, reconcile, create, import-count, and offline state for granular UI/diagnostics without changing existing workflow methods.
- Guest Insights never touches network or SwiftData writes.

---

## 2. Startup & dependency graph

```mermaid
flowchart TD
    A["@main Tryzub_ReservationsApp"] --> B["AppCredentialStore.init()"]
    B --> C{Env vars TRYZUB_API_* ?}
    C -->|yes| D["credentials from environment"]
    C -->|no| E["Keychain load"]
    D --> F{credentials complete?}
    E --> F
    F -->|no| G["CredentialsSetupView"]
    G --> H["save → Keychain"]
    H --> F
    F -->|yes| I["ReservationsListView"]
    I --> J["ReservationsController(environment)"]
    I --> K["HiddenReservationsStore()"]
    I --> L[".modelContainer(ReservationRecord)"]
    I --> M[".task"]
    M --> N["loadIfNeeded → today full sync"]
    M --> O["loadRestaurantSetup → GET /restaurant-setup"]
```

**What matters**
- Credentials: env vars override Keychain on launch (simulator/dev); device uses Keychain after first save.
- SwiftData container is scene-level; all tabs share one cache.
- Startup network: today reservations (full replace) + restaurant setup (in-memory `@Published` on controller).
- No reservation fetch happens before credentials gate passes.

---

## 3. Tab shell & view ownership

```mermaid
flowchart LR
    subgraph Shell["ReservationsListView — all tabs MOUNTED"]
        H["Home<br/>HomeDashboardView → HostBoardView"]
        L["List<br/>ReservationScheduleView"]
        R["Review<br/>ReservationReviewQueueView"]
        M["More<br/>ReservationMoreView"]
    end

    TabBar["ReservationFloatingTabBar"] --> Shell
    Shell -->|opacity + hitTesting| Active["visible tab only"]
```

| Tab | Root view | `isActive` gating | Primary data source |
| --- | --- | --- | --- |
| Home | `HomeDashboardView` → `HostBoardView` | Yes — auto-refresh, clock, availability | `@Query` + today sync |
| List | `ReservationScheduleView` | Yes — activation fetch | `@Query` + schedule window |
| Review | `ReservationReviewQueueView` | Yes — activation fetch | `@Query` + review queues |
| More | `ReservationMoreView` | No | Navigation pushes only |

**What matters**
- Tabs stay in the tree (opacity/zIndex) to avoid NavigationStack + `@Query` rebuild lag.
- Inactive tabs do not run auto-refresh loops (`isActive` guards `.task` loops).
- More sub-screens fetch **only when navigated to** (settings, hidden, cancelled, diagnostics).

---

## 4. Fetch / sync lifecycle

```mermaid
sequenceDiagram
    participant V as View
    participant C as ReservationsController
    participant S as ReservationSyncService
    participant R as ReservationRepository
    participant API as API Client

    Note over V,API: Startup / manual today
    V->>C: loadIfNeeded / requestManualTodayRefresh
    C->>S: syncTodayFull
    S->>API: GET /managed-reservations?date=today
    S->>R: replaceDateScope(today) — deletes orphans
    C->>C: updateServerCursor(server_time)

    Note over V,API: Auto today (60s, Home visible)
    V->>C: autoRefreshDashboardIfAllowed
    alt cursor exists
        C->>S: syncTodayChanges(updated_since)
        S->>R: upsert only — no deletes
    else no cursor
        C->>S: syncTodayFull
    end

    Note over V,API: Schedule tab activation (stale > 300s)
    V->>C: scheduleBecameActive
    C->>S: syncScheduleWindowFull(today..today+30)
    S->>R: replaceDateWindow — deletes orphans in window

    Note over V,API: Review tab activation (stale > 120s)
    V->>C: reviewBecameActive
    C->>S: syncReviewQueues
    S->>R: replaceReviewQueue — upsert only, no deletes
```

### Sync strategy summary

| Scope | Trigger | Endpoint | Write mode | Deletes local orphans? | Cursor (`server_time`) |
| --- | --- | --- | --- | --- | --- |
| Today startup/manual | `loadIfNeeded`, pull-refresh | `GET ?date=today` | `replaceDateScope` | **Yes** (non-hidden) | Stored |
| Today auto | Home loop 60s | `GET ?date=today&updated_since=` | `upsert` | **No** | Stored |
| Schedule window | Tab active / refresh | `GET ?from&to` paged | `replaceDateWindow` | **Yes** in window | Stored |
| Review queues | Tab active / refresh | `GET ?status=needs_review` + `new` | `replaceReviewQueue` | **No** | None |
| Schedule All pages | Search / load more | `GET` paginated | `upsert` | **No** | None |
| Cancelled | More screen open | `GET ?status=cancelled` | `upsert` | **No** | None |
| Hidden archive | Hidden screen open | `GET ?include_hidden=1` | `upsert` | **No** | None |
| Import failure count | Admin/dev screen or explicit diagnostics | `GET /import-failures?per_page=1` | None | — | None |

**What matters**
- `server_time` cursor is **in-memory on controller only** — not persisted across app kill.
- Delta sync (`updated_since`) is **today auto-refresh only**; manual/startup always full-replace today.
- Empty delta response: upsert skipped; no deletes.
- Network failure: offline notice (60s cooldown); cache remains visible; scope failure cooldown applies (today manual 8s, auto failure 180s).

---

## 5. Mutation lifecycle

```mermaid
sequenceDiagram
    participant Staff as Staff UI
    participant C as ReservationsController
    participant M as ReservationMutationService
    participant API as API Client
    participant R as ReservationRepository

    Staff->>C: updateReservation / updateStatus / hide / restore
    C->>M: PATCH
    M->>API: PATCH /managed-reservations/{id}
    API-->>M: ReservationDTO
    M->>R: upsert
    C->>C: markScopesTouched

    Staff->>C: confirmReservation (Confirm + Email)
    C->>M: POST /confirm
    M->>R: upsert(response.data)
    C->>C: email status notice

    Staff->>C: createAcceptedManualReservation
    C->>M: POST /managed-reservations
    M->>R: upsert

    alt uncertain network on PATCH/confirm
        C->>C: reconcileReservation
        C->>M: GET /managed-reservations/{id}
        M->>R: upsert
    end

    Staff->>C: hardDeleteReservation (dev only)
    C->>M: DELETE ?force=1
    M->>R: deleteReservation(remoteID)
```

### Mutation rules

| Action | Endpoint | Email | Cache update |
| --- | --- | --- | --- |
| Confirm Only | PATCH `status=confirmed` | No | Upsert after success |
| Confirm + Email | POST `/{id}/confirm` | Backend sends/records | Upsert after success |
| Manual create | POST `/managed-reservations` | No | Upsert after success |
| Edit fields | PATCH | No | Upsert after success |
| Seat / cancel / complete / no-show | PATCH `status` | No | Upsert after success |
| Hide wrong entry | PATCH `is_hidden=true` | No | Upsert after success |
| Restore hidden | PATCH `is_hidden=false` | No | Upsert after success |
| Hard delete | DELETE `?force=1` | No | Local delete after success |
| Guest manage link | POST `/{id}/guest-manage-link` | **No** — copy link or local Gmail/Mail draft | None |

**Reconcile:** `updateReservation` and `confirmReservation` call `reconcileReservation` when `error.mayHaveReachedReservationServer` (timeout, connection lost, bad response).

### Operation / progress state

`ReservationsController` still exposes legacy flags (`isSyncing`, `isAutoRefreshing`, `actionInProgressIDs`, `isCreatingReservation`) and now also publishes a consolidated `ReservationOperationState` snapshot.

| State | Owner | UI intent |
| --- | --- | --- |
| Startup / manual / screen-active refresh | `activeSyncIntents` by `ReservationSyncScope` | Header/toolbar progress; keep cached rows visible |
| Quiet auto-refresh | `isAutoRefreshing` + `.automatic` sync intent | No blocking modal |
| Per-row mutation | `mutatingReservationIDs` | Disable/spinner only for affected row/action |
| Uncertain mutation reconcile | `reconcilingReservationIDs` | Keep affected row busy while server truth is checked |
| Manual create | `isCreatingReservation` | Saving state inside create form |
| Admin/import count | `isCheckingImportFailureCount` | Developer/admin progress only |
| Offline/network unavailable | `lastNetworkUnavailableAt` | Non-blocking saved-data notice |

---

## 6. Role & capability gating

```mermaid
flowchart TD
    Role["AppUserRole"] --> Cap["AppCapabilities.capabilities(for:)"]
    Cap --> UI["Views gate buttons / nav links"]
    Cap --> Ctrl["Controller throws permissionDenied"]

    subgraph Staff["staff"]
        S1["Seat · edit · assign table"]
        S2["No confirm · cancel · create · settings"]
    end

    subgraph Manager["manager"]
        M1["All reservation ops"]
        M2["Settings · analytics · hidden · manage link"]
        M3["No diagnostics · no hard delete"]
    end

    subgraph Dev["developer"]
        D1["Everything manager has"]
        D2["Diagnostics · hard delete"]
    end
```

| Capability | Staff | Manager | Developer |
| --- | :---: | :---: | :---: |
| `canSeatReservations` | ✓ | ✓ | ✓ |
| `canEditReservationDetails` | ✓ | ✓ | ✓ |
| `canConfirmReservations` | ✗ | ✓ | ✓ |
| `canCancelReservations` | ✗ | ✓ | ✓ |
| `canCreateManualReservations` | ✗ | ✓ | ✓ |
| `canGenerateGuestManageLinks` | ✗ | ✓ | ✓ |
| `canViewHiddenReservations` | ✗ | ✓ | ✓ |
| `canManageRestaurantSettings` | ✗ | ✓ | ✓ |
| `canViewAnalytics` | ✗ | ✓ | ✓ |
| `canViewFailedImports` | ✗ | ✓ | ✓ |
| `canViewDeveloperDiagnostics` | ✗ | ✗ | ✓ |
| `canHardDeleteReservations` | ✗ | ✗ | ✓ |

**UI quirk (verify before pilot):** Failed Imports nav link requires **both** `canViewFailedImports` **and** `canViewDeveloperDiagnostics` — managers cannot reach it in UI despite having import capability.

---

## 7. Restaurant operations / settings flow

```mermaid
flowchart TD
    More["More tab"] --> RS["RestaurantSettingsStore"]
    RS --> Ctrl["ReservationsController"]
    Ctrl --> API["ReservationsAPIClient"]

    RS --> Setup["RestaurantSettingsView<br/>GET/PATCH /restaurant-setup"]
    RS --> Hours["WeeklyHoursView<br/>GET/PATCH /restaurant-hours"]
    RS --> Day["TodayAvailabilityView<br/>GET/PATCH /restaurant-day-availability"]
    RS --> Blocked["BlockedTimeSlotsView<br/>blocked-slots CRUD"]
    RS --> Analytics["BusinessAnalyticsView<br/>GET /reservation-analytics/summary"]

    RS --> EDO["ensureDateOperations(date)"]
    EDO --> Slots["GET /reservation-slots"]
    EDO --> Avail["GET day-availability"]
    EDO --> BlockedGET["GET /restaurant-blocked-slots"]

    Home["HostBoardView today summary"] --> API2["apiClient direct<br/>same 3 GETs, 120s cache"]
```

**What matters**
- Settings loads are **lazy** — do not block Home/List/Review tab switches.
- `ensureDateOperations` owns Task lifecycle (prevents stuck spinners on date change).
- `GET /reservation-slots` is **public** (no auth).
- Home availability indicator uses direct API client, not `RestaurantSettingsStore`.

---

## 8. Admin / diagnostics flow

```mermaid
flowchart LR
    Dev["Developer role"] --> Diag["DeveloperDiagnosticsView"]
    Diag --> Tests["AdminFetchTest buttons<br/>GET only"]
    Diag --> Log["APIRequestLogStore<br/>last 100 events"]
    Diag --> Check["Endpoint contract checklist"]
    Diag --> Cache["SwiftData counts"]
    Diag --> Scopes["Sync scope snapshots"]

    Tests --> Ctrl["runAdminFetchTest"]
    Ctrl --> API["ReservationsAPIClient"]

    Hidden["HiddenReservationsView"] --> Load["loadHiddenReservations"]
    Hidden --> Hard["hardDeleteReservation<br/>dev only"]
```

**Danger zone:** Diagnostics intentionally has **no automated mutation tests**. Confirm, cancel, create, block slots, and import must go through normal staff UI.

---

## 9. Guest manage link & email direction

```mermaid
sequenceDiagram
    participant M as Manager UI
    participant C as ReservationsController
    participant API as API Client
    participant Mail as Manual Mail/Gmail

    Note over M,Mail: MVP manual email path
    M->>C: generateGuestManageLink
    C->>API: POST /guest-manage-link
    API-->>C: { url, expires_at? }
    C-->>M: URL copied to pasteboard
    M->>M: Optional local draft text helper
    M->>Mail: Staff pastes reviewed copy into confirmation email

    Note over M,Mail: Optional backend email path
    M->>C: confirmReservation
    C->>API: POST /confirm
    API-->>C: email_status + updated DTO
```

**Current direction (from code comments)**
- **Primary MVP for call-ins / no-auto-email:** Confirm Only (PATCH) + generate manage link + copy local draft + manual Mail/Gmail.
- **Confirm + Email:** POST `/confirm` — backend sends/attempts email; UI shows `emailStatus` notices.
- Manual create: always confirmed, **no email**.
- Guest manage link and local draft generation do **not** set `confirmationEmailSentAt`.

---

## 10. SwiftData cache flow

```mermaid
flowchart TD
    DTO["ReservationDTO from API"] --> Repo["ReservationRepository"]
    Repo --> Upsert["upsert — match remoteID"]
    Repo --> Replace["replaceDateScope / replaceDateWindow"]
    Repo --> Del["deleteReservation — hard delete only"]

    Upsert --> Record["ReservationRecord"]
    Replace --> Record
    Del --> Gone["local row removed"]

    Record --> Query["@Query in views"]
    Query --> UI["Lists filter isHidden via HiddenReservationsStore"]
```

**Visibility rules**
- Normal lists exclude `isHidden == true` via `HiddenReservationsStore.isHidden`.
- Hidden rows preserved during replace sync when `includeHidden: false` (default).
- Review queue sync never deletes rows that left `new`/`needs_review` locally.

---

## 11. Backend integration map

```mermaid
flowchart LR
    subgraph Public["Public — no auth"]
        P1["GET /ping"]
        P2["GET /reservation-slots"]
    end

    subgraph Protected["Protected — Basic auth"]
        R1["CRUD /managed-reservations"]
        R2["POST /confirm"]
        R3["POST /guest-manage-link"]
        R4["DELETE ?force=1"]
        R5["GET /import-failures"]
        S1["restaurant-setup"]
        S2["restaurant-hours"]
        S3["restaurant-day-availability"]
        S4["restaurant-blocked-slots"]
        S5["reservation-analytics/summary"]
    end

    subgraph Forbidden["Not used by iOS"]
        F1["POST /managed-reservations/import"]
    end
```

**API client defaults:** 30s request timeout, 60s resource timeout, GET retries ≥1 on timeout/connection lost, mutations no retry by default.

---

## Known weak spots (document, do not fix in this pass)

| Area | Issue |
| --- | --- |
| Role | Production hardcoded `.developer` — pilot needs explicit role selection |
| Failed Imports | Manager capability exists but UI requires developer |
| HostBoard availability | Direct `apiClient` bypasses controller |
| Guest Insights | Quality limited to cached history — no guest API |
| Cursors | Lost on app restart — first auto-refresh may full-replace |
| `createReservation` controller method | Exists but UI uses `createAcceptedManualReservation` only |
| Mutation progress | `actionInProgressIDs` disables buttons; verify in code if any view blocks entire screen |
