# Agent Handoff — Current Slice

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)

---

## Title

Production stabilization: self-service cancellation, auth, pipeline, data freshness

---

## Git state (2026-06-24)

| Location | State |
|----------|--------|
| **Root branch** | `audit-current-state` — clean working tree |
| **Root HEAD** | `7b3f3d4` — Stop tracking backend deploy zip artifacts |
| **Root vs remote** | **4 commits ahead** of `origin/audit-current-state` (not pushed) |
| **Backend submodule pointer** | `d46713a` — Prevent cached guest self-service status after cancellation |
| **Backend branch** | `AI` — clean working tree |
| **Backend HEAD** | `d46713a` |
| **Backend vs remote** | **2 commits ahead** of `origin/AI` (not pushed) |
| **iOS** | `b910bd1` committed on root — foreground/privacy-cover refresh |

**Recent root commits (newest first):**

- `7b3f3d4` — stop tracking `Backend/*.zip`; add gitignore rule
- `518bdc3` — fix deploy zip WordPress folder layout (historical; zips no longer tracked)
- `d3edd40` — submodule pointer → `d46713a` (cache fix)
- `b910bd1` — iOS foreground/privacy-cover refresh

**Backend commits on pointer (newest first):**

- `d46713a` — guest self-service no-store headers, JS cache bust, POST cancel returns refreshed `data`
- `854b82d` / `6a30203` — guest-facing confirmation/cancellation/page copy
- `239b297` — guest cancellation email, cancelled dead-state UI, pipeline `developer_summary` flattening
- `5a04af4` — auth role repair and diagnostics

**Deploy zip:** not tracked in git (`Backend/*.zip` ignored). Production package must be built locally from backend `HEAD` and verified separately from repo pointer.

---

## Current slice goal

Stabilize **production correctness** and **data fetch/freshness** before new product features.

1. Verify guest self-service cancellation end-to-end after cache fix (`d46713a`).
2. Confirm commit/push/deploy consistency (local vs remote vs WordPress).
3. Verify manager auth and pipeline diagnostics on live WordPress.
4. Verify iOS data/fetch/storage behavior on device (foreground/privacy refresh at `b910bd1`).

**Parked for v1:** offline manual reservation queue, offline create/edit, Host stale-warning UI (checked/fetched status already exists), broad Host redesign, SMS, new LLM work.

---

## Backend self-service cache fix (`d46713a`)

Implemented in `Backend/tryzub-reservations-api/includes/reservation-self-service.php`:

| Layer | Change |
|-------|--------|
| PHP | `tryzub_guest_self_service_no_cache_headers()` on GET `/reservation-self`, POST `/reservation-self/cancel`, POST `/reservation-self/change-request` |
| PHP | POST cancel returns refreshed guest-safe `data` when re-fetch succeeds |
| JS | `fetch(..., { cache: 'no-store' })` |
| JS | `loadReservation()` appends `&_ts=Date.now()` |
| JS | Cancel success applies POST `data` immediately; reconcile GET is cache-busted and non-fatal on failure |
| Product | Guest manage **token stays valid** after cancellation; page shows cancelled dead state |

**Status:** committed locally (`d46713a`), submodule pointer updated, **not pushed**, **production dead-state after reload not yet verified** after latest upload.

---

## Production deploy state (uncertainty)

| Item | Status |
|------|--------|
| Known uploaded zip SHA | **Unknown** — deploy zips are not in git |
| Submodule / backend code truth | `d46713a` |
| Mismatch risk | **High** if production zip was built from wrong layout (`git archive` flat root) or pre-`d46713a` commit |
| Zip build rule | Compress full folder: `zip -r tryzub-reservations-api.zip tryzub-reservations-api -x "tryzub-reservations-api/.git/*"` — must include `tryzub-reservations-api/` wrapper |

---

## Verified in production (known)

- Anonymous `GET /ping` → 200
- Protected routes without auth → 401
- Guest cancel route exists; empty/invalid token → safe 404
- Real guest cancellation email received (proves cancel handler ran; email text is hardcoded — does not alone prove GET returns `cancelled`)

## Not yet verified in production

- Manager `/ping` → `user.can_manage_tryzub_reservations: true`
- `GET /restaurant-setup` authenticated → 200
- `GET /intelligence/reservation-pipeline-diagnostics` authenticated
- Guest token page **after cache fix**: reload shows `Reservation Cancelled`, no cancel button, `status=cancelled`
- `GET /reservation-self` response headers include `Cache-Control: no-store`
- POST cancel response includes refreshed `data.status=cancelled`
- iOS foreground/privacy-cover refresh on physical device
- No stale staff PATCH reverting guest cancellation (check activity log if curl shows `confirmed` after cancel)

---

## Pending verification checklist

```bash
export BASE_URL="https://tryzubchicago.com/wp-json/tryzub/v1"
export TOKEN="guest_manage_token"   # disposable test only

# Headers + status after cancel
curl -sS -D - -o /dev/null "$BASE_URL/reservation-self?token=$TOKEN&_ts=$(date +%s)"
curl -sS "$BASE_URL/reservation-self?token=$TOKEN&_ts=$(date +%s)" | jq '.data.status, .data.can_request_cancel'

# Manager auth (requires Application Password)
curl -sS -u "$WP_USER:$WP_APP_PASSWORD" "$BASE_URL/ping" | jq '.user.can_manage_tryzub_reservations'
```

**WordPress admin:** confirm only one plugin folder `tryzub-reservations-api` is active; delete duplicate from bad zip upload if present. Purge page/CDN cache for `/manage-reservation/`.

---

## iOS state (`b910bd1`)

Implemented in `ReservationsListView.swift`:

- `scenePhase == .active` → `refreshOperationalDataAfterUnlock(reason: "foreground")`
- Privacy cover dismiss → `refreshOperationalDataAfterUnlock(reason: "privacy_cover")`
- Uses `autoRefreshDashboardIfAllowed` (not `requestManualTodayRefresh`)

**Data model reminders:**

- Backend is source of truth; SwiftData is operational cache only
- Cache-first startup; active-window full/delta refresh
- Active-window `server_time` cursors and scope success metadata **persist in UserDefaults** (`tryzub.sync.serverCursors.v1`) — resumes policy after relaunch; **not** an offline mutation queue
- `lastSyncedAt` / `lastFreshnessCheckedAt` / `cacheTrustSource` are presentation/session fields only
- Checked/updated/saved-data UI already exists (`HomeServiceStatusPresenter`, `ScreenFreshnessState`) — do not duplicate
- Offline: mutations blocked when degraded; cache visible; **no offline create/edit queue** (not V1)

**Device verification still required.**

---

## Next exact actions

1. **Push** backend `AI` (`d46713a`) then root `audit-current-state` (submodule + doc commits when approved).
2. **Build** deploy zip from full `tryzub-reservations-api/` folder (not bare `git archive`).
3. **Deploy** to WordPress; purge `/manage-reservation/` cache.
4. **Verify** guest cancelled dead-state on reload + no-store headers.
5. **Verify** manager ping, restaurant setup, pipeline diagnostics with credentials.
6. **Verify** iOS foreground/privacy refresh on device.
7. Only then pick product slice: walk-ins/wait room vs guest persistence (see [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md)).

---

## Forbidden until stabilization verified

- Offline manual reservation queue / offline edits (not v1)
- New Host stale-warning UI without proving a gap beyond existing checked/fetched lines
- Broad Host Board refactor
- Backend contract duplication into root `Docs/`
- Unrelated iOS feature work mixed into deploy verification commits

---

## Read-only reference

| Area | Files |
|------|--------|
| Guest self-service | `Backend/.../reservation-self-service.php` |
| Backend contracts | `Backend/.../README.md`, `INTELLIGENCE.md` |
| iOS refresh | `ReservationsListView.swift`, `ReservationsController.swift`, `FreshnessCoordinator.swift` |
| iOS sync | `ReservationImportService.swift`, `ReservationRepository.swift` |

---

## Command-line budget

```bash
# Backend
cd Backend/tryzub-reservations-api && git status --short && git log -3 --oneline

# Root
cd .. && git status --short && git submodule status
```

Audit first (Composer); implement only from approved handoff; one commit per concern.
