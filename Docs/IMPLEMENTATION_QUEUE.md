# Implementation Queue

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)

Ordered slices for V1 stabilization. One slice per commit series unless explicitly combined.

---

## 1. Backend guest cancel email + page copy + confirmation cleanup + pipeline flattening

| Field | Value |
|-------|-------|
| **Status** | **current** |
| **Scope** | `emails.php`, `reservation-self-service.php`, `intelligence-system-status.php` (backend only) |
| **Why** | Highest guest-facing gap; small diff; no iOS; unblocks trust in self-service |
| **Do not mix with** | iOS, auth dirty files (`activation.php`, `permissions.php`, `health.php`, `tryzub-reservations-api.php`), rate limits, walk-in, guest profile cache |

---

## 2. iOS foreground / privacy stale refresh

| Field | Value |
|-------|-------|
| **Status** | pending |
| **Scope** | `ReservationsListView`, `ReservationsController`, privacy cover dismiss hook |
| **Why** | Staff sees stale board after background/privacy unlock; scenePhase today only resets navigation |
| **Do not mix with** | Host Board task stabilization, guest profile SwiftData |

---

## 3. Host stale warning UI

| Field | Value |
|-------|-------|
| **Status** | pending |
| **Scope** | Host header / sync presentation when `lastSyncedAt` age exceeds TTL |
| **Why** | Makes 300s idle TTL visible without silent staleness |
| **Do not mix with** | Full Host Board refactor |

---

## 4. Walk-in creation mode

| Field | Value |
|-------|-------|
| **Status** | pending |
| **Scope** | `ManualReservationFormView` — pass `manual_walk_in` + seated default |
| **Why** | Backend already accepts walk-in; iOS never sends source type |
| **Do not mix with** | Backend schema changes (not required for basic path) |

---

## 5. Guest profile local cache / indexing

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | New SwiftData cache record + `GuestProfileStore` |
| **Why** | Profiles lost on restart; repeated network on detail |
| **Do not mix with** | Guest Insights Phase 2 UI polish |

---

## 6. Guest `updated_since` incremental sync

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | iOS API client + `GuestProfileStore` list fetch |
| **Why** | Backend supports `updated_since` on `/guest-profiles`; iOS does not pass it |
| **Do not mix with** | Full profile UI rewrite |

---

## 7. ReservationDetail guest fetch dedupe

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `ReservationDetailView` — remove redundant `GuestIntelligenceStore.loadProfile` when aggregate profile suffices |
| **Why** | Duplicate network on detail open |
| **Do not mix with** | SwiftData cache (can follow slice 5) |

---

## 8. Analytics local persisted cache

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `BusinessIntelligenceStore` disk or UserDefaults persistence |
| **Why** | Analytics screen cold-starts empty; backend already caches |
| **Do not mix with** | Host Board analytics fan-out |

---

## 9. Public guest token route rate limiting

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | `reservation-self-service.php` — per-token / per-IP limits |
| **Why** | Public routes use `__return_true`; no throttle today |
| **Do not mix with** | Guest cancel email slice (orthogonal) |

---

## 10. Feedback MVP

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | TBD — not in current codebase |
| **Why** | Product follow-up |
| **Do not mix with** | Intelligence pipeline work |

---

## 11. Daily operational summary

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | TBD |
| **Why** | Manager-facing digest |
| **Do not mix with** | Host Intelligence local model |

---

## 12. Floor-first Host mode

| Field | Value |
|-------|-------|
| **Status** | later |
| **Scope** | Host Board presentation mode |
| **Why** | Ops UX enhancement |
| **Do not mix with** | Floor plan backend changes |
