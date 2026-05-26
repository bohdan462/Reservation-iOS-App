# Tryzub Reservations Architecture Diagrams

These diagrams describe the one-restaurant MVP architecture. The WordPress plugin REST API is the source of truth. SwiftData is a local cache. The iOS app must not call `POST /managed-reservations/import` during normal workflow.

## 1. High-Level Architecture

```mermaid
flowchart LR
    subgraph IOS["iOS App"]
        Views["SwiftUI views<br/>Today, Schedule, Pending, Details, More"]
        Controller["ReservationsController<br/>workflow coordinator"]
        Sync["ReservationSyncService<br/>read/sync flows"]
        Mutation["ReservationMutationService<br/>create/update/confirm flows"]
        Failures["ImportFailureService<br/>failed import lookup"]
        APIClient["ReservationsAPIClient<br/>authenticated REST client"]
        Repo["ReservationRepository<br/>cache upsert"]
        Cache[("SwiftData<br/>ReservationRecord cache")]
    end

    subgraph WP["WordPress / Tryzub Plugin"]
        REST["WordPress REST API<br/>/wp-json/tryzub/v1"]
        Managed[("Managed reservations table<br/>source of truth")]
        Failed[("Failed import table")]
        EmailLogs[("Email logs / sent timestamps")]
        Flamingo[("Flamingo submissions")]
    end

    Views --> Controller
    Views <--> Cache
    Controller --> Sync
    Controller --> Mutation
    Controller --> Failures
    Sync --> APIClient
    Mutation --> APIClient
    Failures --> APIClient
    Sync --> Repo
    Mutation --> Repo
    Repo --> Cache
    APIClient <--> REST
    REST <--> Managed
    REST --> Failed
    REST --> EmailLogs
    Flamingo --> Managed
    Flamingo --> Failed
```

Notes:
- The controller is the app's practical traffic cop. Views call controller workflow methods; they should not create API clients directly.
- Services are thin. They mostly make the controller easier to reason about by splitting reads, mutations, and failed import lookups.
- SwiftData is cache only. The backend managed reservations table remains truth.

## 2. Fetch / Sync Flow

```mermaid
sequenceDiagram
    participant View as SwiftUI View
    participant Controller as ReservationsController
    participant Sync as ReservationSyncService
    participant API as ReservationsAPIClient
    participant WP as WordPress REST API
    participant Repo as ReservationRepository
    participant Cache as SwiftData ReservationRecord

    View->>Controller: request refresh / tab activation / loadIfNeeded
    Controller->>Controller: guard busy state, cooldown, freshness
    Controller->>Sync: syncToday / syncScheduleWindow / syncReviewQueues
    Sync->>API: fetchReservations or fetchAllReservations
    API->>WP: GET /managed-reservations
    WP-->>API: ReservationsResponse DTOs
    API-->>Sync: decoded ReservationDTOs
    Sync->>Repo: upsert DTOs
    Repo->>Cache: insert or update ReservationRecord
    Cache-->>View: @Query redraws from local cache
    Controller-->>View: sync flags, notices, lastSyncedAt
```

Notes:
- Today fetches one page for the current date.
- Schedule fetches the configured date window, paged.
- Pending/review fetches `new` and `needs_review` queues.
- A failed network fetch should leave cached rows visible.

## 3. Mutation Flow

```mermaid
flowchart TD
    Staff["Staff action in SwiftUI"] --> Controller["ReservationsController"]

    Controller --> ConfirmOnly["Confirm Only<br/>updateStatus status=confirmed"]
    ConfirmOnly --> PatchConfirm["PATCH /managed-reservations/{id}<br/>status=confirmed<br/>no email"]

    Controller --> ConfirmEmail["Confirm + Email<br/>confirmReservation"]
    ConfirmEmail --> PostConfirm["POST /managed-reservations/{id}/confirm<br/>backend attempts email"]

    Controller --> Update["Update reservation<br/>table, status, notes, date/time, party size"]
    Update --> PatchUpdate["PATCH /managed-reservations/{id}"]

    Controller --> Create["Manual create<br/>call-in or fixed failed import"]
    Create --> PostCreate["POST /managed-reservations"]

    PatchConfirm --> API["ReservationsAPIClient"]
    PostConfirm --> API
    PatchUpdate --> API
    PostCreate --> API

    API --> WP["WordPress REST API"]
    WP --> Managed[("Managed reservations table")]
    WP --> EmailLogs[("Email status / sent timestamp<br/>confirm endpoint only")]
    WP -- "returned ReservationDTO" --> API
    API --> Service["ReservationMutationService"]
    Service --> Repo["ReservationRepository"]
    Repo --> Cache[("SwiftData ReservationRecord cache")]

    API -. "timeout or network lost after request may have reached server" .-> Uncertain["Uncertain mutation failure"]
    Uncertain --> Reconcile["reconcileReservation"]
    Reconcile --> GetOne["GET /managed-reservations/{id}"]
    GetOne --> API
```

Notes:
- Confirm Only is a status PATCH and must not send email.
- Confirm + Email is the only normal iOS path that should hit `/managed-reservations/{id}/confirm`.
- The app should not locally fake mutation success. Returned server DTOs are upserted into SwiftData.
- Reconcile is for ambiguous network failures where the server may have applied the mutation.

## 4. App Lifecycle / Screen Triggers

```mermaid
flowchart TD
    Launch["App launch"] --> Creds["AppCredentialStore<br/>environment or Keychain credentials"]
    Creds --> HasCreds{"Credentials present?"}
    HasCreds -- "no" --> Setup["CredentialsSetupView"]
    HasCreds -- "yes" --> Env["Create AppEnvironment<br/>API client + role + capabilities"]
    Env --> Root["ReservationsListView"]
    Root --> Controller["Create ReservationsController<br/>inject as environmentObject"]
    Root --> InitialTask[".task loadIfNeeded"]
    InitialTask --> InitialFetch["Startup Today fetch"]

    Root --> Today["Today tab"]
    Today --> ManualRefresh["Pull refresh / toolbar refresh"]
    ManualRefresh --> TodayFetch["requestManualTodayRefresh<br/>GET today reservations"]
    Today --> AutoLoop["HostBoardView auto-refresh loop<br/>while visible and app active"]
    AutoLoop --> AutoGuards{"Allowed?<br/>not busy, no interaction,<br/>cooldown passed"}
    AutoGuards -- "yes" --> AutoFetch["autoRefreshDashboardIfAllowed<br/>GET today reservations"]
    AutoGuards -- "no" --> Skip["skip and keep cached view"]

    Root --> Schedule["Schedule tab"]
    Schedule --> ScheduleActive["scheduleBecameActive"]
    ScheduleActive --> ScheduleFresh{"Schedule scope fresh?"}
    ScheduleFresh -- "yes" --> ScheduleCache["Use SwiftData cache"]
    ScheduleFresh -- "no" --> ScheduleFetch["GET /managed-reservations?from=&to="]

    Root --> Pending["Pending / Review tab"]
    Pending --> PendingActive["reviewBecameActive"]
    PendingActive --> PendingFresh{"Review scope fresh?"}
    PendingFresh -- "yes" --> PendingCache["Use SwiftData cache"]
    PendingFresh -- "no" --> PendingFetch["GET status=needs_review<br/>GET status=new"]
```

Notes:
- The initial app task loads Today once through a controller guard.
- Manual refreshes are staff-visible and post success/failure notices.
- Auto-refresh is deliberately guarded so it does not fight active staff interactions.
- Schedule and Pending use freshness checks before fetching.

## 5. Backend Data Flow

```mermaid
flowchart LR
    Guest["Guest submits public reservation form"] --> CF7["Contact Form 7"]
    CF7 --> Flamingo[("Flamingo submission")]
    Flamingo --> Import["WordPress plugin auto-import"]
    Import --> Valid{"Can normalize reservation?"}
    Valid -- "yes" --> Managed[("Managed reservations table<br/>source of truth")]
    Valid -- "no" --> Failed[("Failed import table")]

    Managed --> REST["REST API<br/>/managed-reservations"]
    Failed --> FailureREST["REST API<br/>/managed-reservations/import-failures"]
    REST --> IOS["iOS ReservationsAPIClient"]
    FailureREST --> IOS
    IOS --> Repo["ReservationRepository"]
    Repo --> Cache[("SwiftData ReservationRecord cache")]
    Cache --> Views["SwiftUI views"]

    IOS --> ManualCreate["Manual create from iOS"]
    ManualCreate --> REST
    REST --> Managed

    IOS -. "must not call during normal workflow" .- Forbidden["POST /managed-reservations/import"]
```

Notes:
- Public form data enters through Contact Form 7 and Flamingo before plugin import logic.
- Good submissions become managed reservations. Bad submissions become failed import records for manager/developer repair.
- iOS reads failed imports and may create a fixed manual reservation, but it should not trigger the backend import endpoint.
- This is enough for the restaurant MVP; do not add SaaS ingestion architecture before service actually needs it.
