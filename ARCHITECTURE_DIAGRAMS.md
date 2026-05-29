# Tryzub Reservations Architecture Diagrams

These diagrams describe the one-restaurant internal iOS app. The WordPress plugin REST API is the source of truth. SwiftData is a local cache only. The iOS app must not call `POST /managed-reservations/import` during normal workflow.

**REST base:** `https://tryzubchicago.com/wp-json/tryzub/v1`

---

## 1. High-Level Architecture

```mermaid
flowchart LR
    subgraph IOS["iOS App"]
        Shell["ReservationsListView<br/>Home · List · Review · More"]
        Views["Feature views<br/>HostBoard, Detail, Forms, Settings, Guest Insights"]
        SharedUI["ReservationSharedUI<br/>tokens, charts, chips, cards"]
        Controller["ReservationsController<br/>workflow coordinator"]
        SettingsStore["RestaurantSettingsStore<br/>restaurant ops UI + API"]
        Sync["ReservationSyncService<br/>read/sync flows"]
        Mutation["ReservationMutationService<br/>create/update/confirm/hide"]
        Failures["ImportFailureService<br/>failed import lookup"]
        GuestCtrl["GuestInsightsController<br/>read-only cache analysis"]
        APIClient["ReservationsAPIClient<br/>authenticated REST client"]
        Repo["ReservationRepository<br/>scoped cache upsert"]
        Cache[("SwiftData<br/>ReservationRecord cache")]
    end

    subgraph WP["WordPress / Tryzub Plugin"]
        REST["WordPress REST API<br/>/wp-json/tryzub/v1"]
        Managed[("Managed reservations<br/>source of truth")]
        Setup[("Restaurant setup / hours / slots")]
        Failed[("Failed import table")]
        Analytics[("Analytics summary")]
    end

    Shell --> Views
    Views --> SharedUI
    Views --> Controller
    Views --> SettingsStore
    Views --> GuestCtrl
    Views <--> Cache
    Controller --> Sync
    Controller --> Mutation
    Controller --> Failures
    SettingsStore --> APIClient
    Sync --> APIClient
    Mutation --> APIClient
    Failures --> APIClient
    Sync --> Repo
    Mutation --> Repo
    GuestCtrl --> Cache
    Repo --> Cache
    APIClient <--> REST
    REST <--> Managed
    REST <--> Setup
    REST --> Failed
    REST --> Analytics
```

Notes:
- Views call **controller workflow methods** for reservations; they do not create API clients directly.
- **RestaurantSettingsStore** owns restaurant-operations screens (hours, availability, blocked slots, analytics) and talks to the same shared API client.
- **Guest Insights** reads SwiftData only — no network, no mutations.
- SwiftData is cache only. The backend managed reservations table remains truth.

---

## 2. App Module Layout

```mermaid
flowchart TD
    App["Tryzub_ReservationsApp.swift"]
    App --> Creds["AppCredentialStore<br/>env + Keychain"]
    App --> Env["AppEnvironment<br/>apiClient + role + capabilities"]
    App --> Shell["ReservationsListView"]

    Shell --> Home["HomeDashboardView → HostBoardView"]
    Shell --> List["ReservationScheduleView"]
    Shell --> Review["ReservationReviewQueueView"]
    Shell --> More["ReservationMoreView"]

    More --> Settings["RestaurantSettingsStore views"]
    More --> GuestMem["RegularGuestsView → GuestInsightsView"]
    More --> Diag["DeveloperDiagnosticsView"]
    More --> Hidden["HiddenReservationsView"]

    Home --> Detail["ReservationDetailView"]
    List --> Detail
    Review --> Detail
    Detail --> Edit["ReservationEditFormView"]
    Detail --> Insights["GuestInsightsView"]

    Home --> Create["ManualReservationFormView"]
    Shared["ReservationSharedUI.swift<br/>TryzubColors · Charts · chips"]
    Shared -.-> Home
    Shared -.-> Detail
    Shared -.-> Settings
    Shared -.-> GuestMem
```

---

## 3. Fetch / Sync Flow

```mermaid
sequenceDiagram
    participant View as SwiftUI View
    participant Controller as ReservationsController
    participant Sync as ReservationSyncService
    participant API as ReservationsAPIClient
    participant WP as WordPress REST API
    participant Repo as ReservationRepository
    participant Cache as SwiftData ReservationRecord

    View->>Controller: loadIfNeeded / tab activation / manual refresh
    Controller->>Controller: guard busy state, cooldown, freshness
    Controller->>Sync: syncToday / syncScheduleWindow / syncReviewQueues
    Sync->>API: fetchReservations or fetchAllReservations
    API->>WP: GET /managed-reservations
    WP-->>API: ReservationsResponse DTOs
    API-->>Sync: decoded ReservationDTOs
    Sync->>Repo: upsert or scoped replace
    Repo->>Cache: insert or update ReservationRecord
    Cache-->>View: @Query redraws from local cache
    Controller-->>View: sync flags, notices, lastSyncedAt
```

Notes:
- **Home/Today** fetches reservations for the selected service date.
- **List** syncs a 30-day window or paginated “All” mode.
- **Review** fetches `new` + `needs_review` queues (default **Pending** segment shows both, oldest submitted first).
- Failed network fetch leaves cached rows visible.

---

## 4. Mutation Flow

```mermaid
flowchart TD
    Staff["Staff action in SwiftUI"] --> Controller["ReservationsController"]

    Controller --> ConfirmOnly["Confirm Only<br/>updateStatus status=confirmed"]
    ConfirmOnly --> PatchConfirm["PATCH /managed-reservations/{id}<br/>status=confirmed · no email"]

    Controller --> ConfirmEmail["Confirm + Email<br/>confirmReservation"]
    ConfirmEmail --> PostConfirm["POST /managed-reservations/{id}/confirm<br/>backend sends email"]

    Controller --> Update["Update reservation<br/>table, notes, date/time, party, status"]
    Update --> PatchUpdate["PATCH /managed-reservations/{id}"]

    Controller --> Create["Manual create<br/>call-in / walk-in / known guest"]
    Create --> PostCreate["POST /managed-reservations"]

    Controller --> Hide["Hide wrong entry<br/>hideWrongEntry"]
    Hide --> PatchHide["PATCH /managed-reservations/{id}<br/>is_hidden=true"]

    PatchConfirm --> API["ReservationsAPIClient"]
    PostConfirm --> API
    PatchUpdate --> API
    PostCreate --> API
    PatchHide --> API

    API --> WP["WordPress REST API"]
    WP --> Managed[("Managed reservations table")]
    WP -- "returned ReservationDTO" --> API
    API --> Service["ReservationMutationService"]
    Service --> Repo["ReservationRepository"]
    Repo --> Cache[("SwiftData cache")]

    API -. "timeout / network lost" .-> Uncertain["Uncertain mutation failure"]
    Uncertain --> Reconcile["reconcileReservation"]
    Reconcile --> GetOne["GET /managed-reservations/{id}"]
    GetOne --> API
```

Notes:
- **Confirm Only** = PATCH `status=confirmed`. No email.
- **Confirm + Email** = POST `/managed-reservations/{id}/confirm` only.
- **Hide** = soft-hide via PATCH `is_hidden=true` (not hard delete).
- Manual create from Home often uses **`createAcceptedManualReservation`** (confirmed status, no email).

---

## 5. Restaurant Operations Flow

```mermaid
flowchart LR
    More["More tab"] --> Store["RestaurantSettingsStore"]
    Store --> SetupV["Restaurant Settings"]
    Store --> HoursV["Weekly Hours"]
    Store --> DayV["Today Availability"]
    Store --> BlockV["Blocked Time Slots"]
    Store --> AnalyticsV["Business Analytics"]

    Store --> API["ReservationsAPIClient"]
    API --> EP1["GET/PATCH /restaurant-setup"]
    API --> EP2["GET/PATCH /restaurant-hours"]
    API --> EP3["GET/PATCH /restaurant-day-availability"]
    API --> EP4["GET /reservation-slots"]
    API --> EP5["GET/POST/DELETE /restaurant-blocked-slots"]
    API --> EP6["GET /reservation-analytics/summary"]
```

Notes:
- Settings store loads date-scoped data (availability, public slots, blocked slots) through **`ensureDateOperations`** so view re-computation does not cancel in-flight requests.
- Public **`GET /reservation-slots`** is unauthenticated; staff blocked-slot endpoints require auth.

---

## 6. Guest Insights Flow (Read-Only)

```mermaid
flowchart LR
    Cache[("SwiftData<br/>ReservationRecord")] --> Resolver["GuestIdentityResolver"]
    Cache --> Deduper["GuestReservationIntentDeduper"]
    Resolver --> Analyzer["GuestInsightsController"]
    Deduper --> Analyzer
    Analyzer --> Report["GuestInsightReport"]
    Report --> UI["GuestInsightsView<br/>Swift Charts preferences"]
    Report --> Preview["Detail preview card"]
    Regulars["RegularGuestsView"] --> UI
```

Notes:
- No API calls. No mutations.
- Matching uses phone, email, and name with confidence levels.
- Entry: **More → Guest Memory** or **Detail → Guest Insights**.

---

## 7. App Lifecycle / Screen Triggers

```mermaid
flowchart TD
    Launch["App launch"] --> Creds["AppCredentialStore"]
    Creds --> HasCreds{"Credentials?"}
    HasCreds -- "no" --> Setup["CredentialsSetupView"]
    HasCreds -- "yes" --> Env["AppEnvironment"]
    Env --> Root["ReservationsListView<br/>all tabs mounted · opacity toggle"]
    Root --> Controller["ReservationsController"]
    Root --> InitialTask[".task loadIfNeeded + loadRestaurantSetup"]

    Root --> Home["Home tab"]
    Home --> ManualRefresh["Pull / toolbar refresh"]
    Home --> AutoLoop["HostBoardView auto-refresh<br/>while visible + app active"]
    AutoLoop --> AutoFetch["GET today reservations"]

    Root --> List["List tab"]
    List --> ScheduleActive["scheduleBecameActive"]
    ScheduleActive --> ScheduleFetch["GET window or paginated All"]

    Root --> Review["Review tab"]
    Review --> ReviewActive["reviewBecameActive"]
    ReviewActive --> ReviewFetch["GET status=new + needs_review"]

    Root --> More["More tab"]
    More --> SettingsLoad["RestaurantSettingsStore.loadInitialSettings"]
```

Notes:
- All four tabs stay mounted for fast switching (no NavigationStack rebuild lag).
- Home loads **restaurant setup** and **today availability/slots** for the stats card and service-load chart.
- Auto-refresh is guarded (not busy, no active interaction, cooldown passed).

---

## 8. Backend Data Flow

```mermaid
flowchart LR
    Guest["Guest website form"] --> CF7["Contact Form 7"]
    CF7 --> Flamingo[("Flamingo submission")]
    Flamingo --> Import["WordPress plugin import"]
    Import --> Valid{"Valid?"}
    Valid -- "yes" --> Managed[("Managed reservations")]
    Valid -- "no" --> Failed[("Failed imports")]

    Managed --> REST["REST /managed-reservations"]
    Failed --> FailureREST["REST /import-failures"]
    REST --> IOS["iOS API client"]
    FailureREST --> IOS
    IOS --> Repo["ReservationRepository"]
    Repo --> Cache[("SwiftData cache")]
    Cache --> Views["SwiftUI views"]

    IOS --> ManualCreate["Manual POST create"]
    ManualCreate --> REST

    IOS -. "never in normal workflow" .- Forbidden["POST /managed-reservations/import"]
```

---

## 9. UI System (Shared Components)

| Layer | Location | Purpose |
| --- | --- | --- |
| Design tokens | `ReservationSharedUI.swift` | `TryzubColors`, `TryzubTypography`, `TryzubSpacing`, `ReservationLayout` |
| Cards / sections | `ReservationSharedUI`, `RestaurantSettingsStore` | `TryzubSectionCard`, `ReservationServiceCard`, `SettingsCard` |
| Reservation rows | `ReservationRowView.swift` | Context-aware rows (Home vs Review insight logic) |
| Charts | `ReservationSharedUI.swift` | `ServiceLoadChart` (Swift Charts), `ServiceTimelineGraph` |
| Actions | `ReservationActionButtons.swift` | Confirm Only / Confirm + Email / seat / table / hide |
| Forms | `ManualReservationFormView.swift` | Create + **ReservationEditFormView** with confirm dialogs |
| Tab bar | `ReservationFloatingTabBar.swift` | Floating nav + badge counts |

**Theme:** Black / white / gray operational palette; red reserved for warnings and destructive actions.
