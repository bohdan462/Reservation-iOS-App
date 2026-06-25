# Agent Handoff — Current Slice

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)

---

## Title

V1 stabilization + guest memory foundation: device verification, then Guests tab cache wiring

---

## Git state (2026-06-25)

| Location | State |
|----------|--------|
| **Root branch** | `audit-current-state` |
| **Root HEAD** | `0a89caa` — Wire manual intake to local guest cache and walk-ins |
| **Root vs remote** | Pushed to `origin/audit-current-state` at `0a89caa` (pending this doc commit) |
| **Backend submodule pointer** | `078a44a` — Document guest self-service cache contract |
| **Backend branch** | `AI` |
| **Backend HEAD** | `078a44a` |
| **Backend vs remote** | Pushed to `origin/AI` at `078a44a` |

**Recent root commits (newest first):**

- `0a89caa` — manual intake: local guest cache merge, call-in/walk-in, known-guest prefill, phone UX
- `0f06852` — persisted guest profile cache + background incremental sync (`updated_since`)
- `cf6e641` — harden V1 confirmation flow for service safety
- `48c6f87` — add second engineer context for V1 release
- `2b2bc8f` — align docs with sync/confirmation behavior
- `b910bd1` — iOS foreground/privacy-cover refresh

**Backend commits on pointer (newest first):**

- `078a44a` — document guest self-service cache contract (README)
- `d46713a` — guest self-service no-store headers, JS cache bust, POST cancel returns refreshed `data`
- `854b82d` / `6a30203` — guest-facing confirmation/cancellation/page copy
- `239b297` — guest cancellation email, cancelled dead-state UI, pipeline `developer_summary` flattening

**Deploy zip:** not tracked in git (`Backend/*.zip` ignored). Build locally from backend `HEAD` when deploying.

---

## Current slice goal

**Stabilization still open** (device verification). **Guest memory foundation shipped** on iOS.

### Completed (iOS guest memory — `0f06852` + `0a89caa`)

1. Backend guest profiles are **persisted server-side** in `{prefix}tryzub_guest_profiles`; iOS fetches list incrementally via `GET /guest-profiles?updated_since=…`.
2. **`GuestProfileCacheRecord`** in SwiftData — local disk cache of backend guest aggregates.
3. **Background list sync** after startup/noncritical deferral (`GuestProfileSyncService` + `AppReservationSession`).
4. **Manual intake** merges persisted guest cache with local `ReservationRecord` history in `GuestLookupStore` — **no network on phone keystroke**.
5. **Manual intake modes:**
   - Call-in → `manual_call_in` + `confirmed`
   - Walk-in → `manual_walk_in` + `seated` (optional table)
   - Known guest call-in → `known_guest_manual` + `confirmed`
   - Known guest walk-in → `manual_walk_in` + `seated` (walk-in analytics; identity from contact fields)
6. Known-guest card **below contact fields**; phone field uses `.textContentType(.none)` + `.phonePad`.
7. **Use** prefill fills name/phone/email/notes safely — does not overwrite typed guest/staff notes.
8. **No `guest_key` on create** — backend create contract does not support it yet; backend resolves identity from name/phone/email after insert.

### Still open (V1 stabilization)

1. Verify iOS data/fetch/storage on device (foreground/privacy refresh at `b910bd1`).
2. Confirm confirmation mode on restaurant iPad (Mail vs backend `/confirm`).
3. Final V1 smoke test on restaurant iPad.

**Not production-ready** until stabilization items 1–3 pass.

### Next product slice (after stabilization green)

**Guests tab + detail local-first guest cache wiring** — `GuestLookupView` and reservation detail still need read-through from `GuestProfileCacheRecord` (Guests tab search remains reservation-history based today).

### Product-scale follow-up (before broader release)

Replace broad in-memory guest filtering with **indexed / predicate-based local search**. Acceptable for Tryzub V1 pilot only.

**Parked / not started:** offline queue, broad Host redesign, full AI clustering / “knows each other” / local semantic tags, VIP editor (no backend guest-notes contract).

---

## Backend self-service cache fix (`d46713a`)

**Status:** committed, pushed, **verified in production** — guest cancel email + cancelled dead-state on reload.

---

## Production deploy state

| Item | Status |
|------|--------|
| Guest self-service cache fix | **Live and verified** |
| App login | **Works** in production |
| Guest profile aggregates (backend table) | **Live** — iOS syncs incrementally |
| Deployed zip SHA in git | **Not tracked** |

---

## Verified in production (known)

- Anonymous `GET /ping` → 200
- Protected routes without auth → 401
- Guest cancellation email + cancelled dead-state on reload
- App login (manager/developer protected routes)
- Pipeline diagnostics reviewed; `unexplained_missing` old test — **non-blocking**

## Not yet verified in production / device

- iOS foreground/privacy-cover refresh on physical device
- Confirmation mode on restaurant iPad
- Final V1 smoke test (staff ops on restaurant iPad)
- Guest profile background sync on pilot iPad (post-`0f06852` install)
- Manual walk-in + known-guest intake on pilot iPad (post-`0a89caa` install)

---

## iOS guest memory (`0f06852` + `0a89caa`)

| Component | Role |
|-----------|------|
| `GuestProfileCacheRecord` | SwiftData disk cache of list aggregates |
| `GuestProfileRepository` | Upsert, search, phone match |
| `GuestProfileSyncService` | Paginated `/guest-profiles` + `updated_since` cursor in UserDefaults |
| `GuestProfileStore` | Memory TTL + optional disk write-through when `ModelContext` passed |
| `GuestLookupStore` | Merges cache + reservation history for manual intake lookup |
| `ManualReservationFormView` | Call-in/walk-in segmented mode, known-guest card, prefill |

**Rules:**

- List sync only in background — **no detail/history prefetch**, no `/guest-profiles/rebuild`, no `/guest-intelligence` on keystroke.
- Phone normalization: `GuestLookupPhoneNormalizer.digits` everywhere (typed phone, cache, reservation history).
- **Guests tab** (`GuestLookupView`) does **not** pass `ModelContext` to lookup yet — still reservation-history search only.

**Data model reminders:**

- Backend is source of truth; SwiftData (reservations + guest profiles) is operational cache only.
- No offline mutation queue in V1.

---

## Next exact actions

1. **Device-test** iOS foreground/privacy refresh (`b910bd1`).
2. **Confirm** confirmation mode on restaurant iPad.
3. **Run** final V1 smoke test; include guest cache sync + manual walk-in/known-guest spot-checks.
4. If green → **Guests tab + detail local-first cache wiring** ([IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) #5).
5. Before broader product release → **indexed local guest search** (queue #6).

---

## Forbidden until stabilization verified

- Offline manual reservation queue / offline edits (not v1)
- Broad Host Board refactor
- Full AI clustering / graph mapping / local semantic tags
- VIP editor without backend contract
- Backend contract duplication into root `Docs/`

---

## Read-only reference

| Area | Files |
|------|--------|
| Guest cache | `GuestProfileCacheRecord.swift`, `GuestProfileRepository.swift`, `GuestProfileSyncService.swift`, `GuestProfileStore.swift` |
| Manual intake | `ManualReservationFormView.swift`, `GuestLookupStore.swift` |
| Guest self-service | `Backend/.../reservation-self-service.php` |
| Backend contracts | `Backend/.../README.md`, `INTELLIGENCE.md` |
| iOS refresh | `ReservationsListView.swift`, `ReservationsController.swift`, `FreshnessCoordinator.swift` |

---

## Command-line budget

```bash
# Backend
cd Backend/tryzub-reservations-api && git status --short && git log -3 --oneline

# Root
cd .. && git status --short && git submodule status && git log -3 --oneline
```

Audit first (Composer); implement only from approved handoff; one commit per concern.
