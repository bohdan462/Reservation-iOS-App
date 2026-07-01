# iOS architecture

**Status:** Current source of truth  
**Branch:** `audit-current-state`  
**Last reviewed:** 2026-07-01

## What this app is

Private iOS staff operations app for Tryzub Ukrainian Kitchen. Reads/writes **managed reservations** on WordPress backend. SwiftData is **cache only** — backend is authoritative.

## Data / fetch / storage model

| Rule | Implementation |
|------|----------------|
| Source of truth | Backend `GET /managed-reservations` (active window) + mutation responses |
| Local store | SwiftData `ReservationRecord` — operational cache, not truth |
| Startup | Cache-first; `performStartupActiveWindowRefresh` after local release |
| Refresh paths | Full replace vs delta upsert; bounded-full policy (see [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md)) |
| Delta cursor | `server_time` in `serverCursorByScope`; **persisted in UserDefaults** with scope success metadata — not an offline queue |
| Presentation state | `lastSyncedAt`, `lastFreshnessCheckedAt`, `cacheTrustSource` — session/UI only; not server truth |
| Normal refresh | **Must not** call `POST /managed-reservations/import` |
| Foreground / privacy | `b910bd1` — `refreshOperationalDataAfterUnlock` → `autoRefreshDashboardIfAllowed` |
| Freshness UI | `HomeServiceStatusPresenter`, `ScreenFreshnessState` — checked/updated/saved-data lines **already exist**; no duplicate stale-warning UI |
| Offline / degraded | Mutations blocked (`ensureMutationsAllowedOnline`); cache visible for viewing; **no offline create/edit queue** (not V1) |
| Confirmation | Both backend `/confirm` and manual Mail exist; active path is **device setting-dependent** (default may enable backend confirm). Delivery/provenance DTOs: [EMAIL_DELIVERY_TRUTH.md](./EMAIL_DELIVERY_TRUTH.md) |

### Current risks (stabilization focus)

- Production backend zip may not match submodule `HEAD` (zips not in git).
- Stale SwiftData if refresh skipped or delta-only without periodic full replace.
- Stale staff PATCH without `expected_updated_at` can overwrite server state (including guest cancel).
- Foreground/privacy refresh implemented but needs device verification.

## Entry and session

```
Tryzub_ReservationsApp
  └─ AppRootView
       ├─ AppLoginView (no credentials)
       ├─ TryzubProductIntroView (first launch)
       └─ ReservationsListView (session ready)
```

| Component | File | Role |
|-----------|------|------|
| Credentials | `App/AppCredentials.swift` | Keychain + env override |
| Roles | `App/AppRoleStore.swift` | Manager / Developer (persisted) |
| Session | `Services/AppReservationSession.swift` | One `ReservationsController` per login |
| Environment | `App/AppEnvironment.swift` | API client + `AppCapabilities` |
| Controller | `Import/ReservationsController.swift` | Sync, mutations, startup, notices |

**Login:** `AppLoginView` validates via `fetchRestaurantSetup`, saves credentials, selects role.

**Logout:** `prepareForLogout()` → clear role/credentials/session.

## Capabilities matrix

Defined in `Core/Roles/AppUserRole.swift` → `AppCapabilities`.

| Capability | Manager | Developer |
|------------|---------|-----------|
| Create manual reservations | ✓ | ✓ |
| Confirm / seat / complete | ✓ | ✓ |
| View developer diagnostics | ✗ | ✓ |
| Hard delete | ✗ | ✓ |
| View hidden reservations | ✗ | ✓ |

`AppRoleStore` is injected but views use `environment.capabilities` via controller.

## Tab shell

`ReservationsListView` → `StartupRootView` → `ReservationsTabShell`

| Tab | Root view | Key child |
|-----|-----------|-----------|
| Host | `HomeDashboardView` | `HostBoardView` — **critical stateful surface** (date SSOT, snapshot cache); see Host tab docs |
| Floor | `FloorPlanView` | `FloorPlanStore` |
| Bookings | `ReservationScheduleView` | schedule scopes |
| Guests | `GuestLookupView` | `GuestLookupStore` |
| More | `ReservationMoreView` | settings, diagnostics, activity |

All shell-scoped stores created in `ReservationsTabShell`:

- `RestaurantSettingsStore`, `HostTableConfigStore`, `HostIntelligenceSettingsStore`
- `HostIntelligenceController`, `GuestIntelligenceStore`, `BusinessIntelligenceStore`
- `IntelligenceSystemStatusStore`, `FloorPlanStore`, `ReservationActivityStore`
- Plus inherited: `controller`, `hiddenReservations`, `privacyCoverSettings`, `hostIntentStore`

## Navigation to reservation detail

`ReservationDetailDestinationView` (in `ReservationsListView.swift`):

- `@Query` by `remoteID`
- If missing → `controller.reconcileReservation` (GET by id)
- Wraps `ReservationDetailView`

## Services layer

| Service | File | Purpose |
|---------|------|---------|
| `ReservationSyncService` | `Import/ReservationImportService.swift` | Active-window full/delta |
| `ReservationMutationService` | `Services/ReservationMutationService.swift` | PATCH/POST/DELETE/reconcile |
| `ReservationRepository` | `Services/ReservationRepository.swift` | SwiftData upsert/replace |
| `FloorPlanService` | `Services/FloorPlanService.swift` | Floor API |
| `FreshnessCoordinator` | `Services/FreshnessCoordinator.swift` | Scope TTL (session-owned) |

## Read models / facades

| Facade | File |
|--------|------|
| `ManualReservationFacade` | `Features/ReadModels/` |
| `ReservationAvailabilityFacade` | `Features/ReadModels/` |
| `GuestProfileFacade` | `Features/ReadModels/GuestProfileFacade.swift` |
| `HostBoardViewStateStore` | `Features/ReadModels/HostBoardViewState.swift` |

## Key file index

| Area | Path |
|------|------|
| App entry | `Tryzub_ReservationsApp.swift` |
| Tab shell | `Features/Reservations/ReservationsListView.swift` |
| Host board | `Features/Reservations/HostBoardView.swift` |
| Detail | `Features/Reservations/ReservationDetailView.swift` |
| API client | `Network/ReservationsAPIClient.swift` |
| DTOs | `Network/ReservationDTO.swift` |
| SwiftData model | `Persistence/ReservationRecord.swift` |

## Related docs

- [HOST_TAB_ARCHITECTURE.md](./HOST_TAB_ARCHITECTURE.md) — Host board file map and ownership
- [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md) — selected date, snapshot, pressure, seated duration
- [HOST_TAB_UI_DESIGN_SYSTEM.md](./HOST_TAB_UI_DESIGN_SYSTEM.md) — glass, rows, AI strip
- [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md) — intelligence on Host tab
- [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md)
- [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md)
- [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)
