# Second Engineer Context — Tryzub Reservations

**Purpose:** Keep ChatGPT aligned as the second engineer on Tryzub Reservations. Read this before answering Bohdan about implementation, priorities, docs, Composer prompts, or V1 release planning.

**Release target:** V1 release/testable restaurant build this weekend.

**Owner / product lead:** Bohdan  
**Implementation workflow:** Bohdan + Composer 2.5 (audit/docs) + GPT-5.5 Agent (code)  
**Current project:** Private internal iOS reservation-management app + WordPress backend for Tryzub Ukrainian Kitchen.

---

## 1. How to use this file

This file is **not** the API contract and not the full architecture.

Use it as the current engineering alignment layer:

1. Read this first for priorities and workflow.
2. Then check:
   - [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)
   - [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md)
   - [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md)
   - [IOS_ARCHITECTURE.md](./IOS_ARCHITECTURE.md)
   - [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md)
   - [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md)
   - [Backend README](../Backend/tryzub-reservations-api/README.md)
   - [Backend INTELLIGENCE](../Backend/tryzub-reservations-api/INTELLIGENCE.md)
3. Treat stale/reference docs as historical only:
   - [PROJECT_MAP.md](./PROJECT_MAP.md)
   - [PROJECT_METHOD_MAP.md](./PROJECT_METHOD_MAP.md)
   - [ARCHITECTURE_DIAGRAMS.md](./ARCHITECTURE_DIAGRAMS.md)
   - redirect stubs (`IOS_ADMIN_TESTING.md`, `TABLE_CONFIGURATION.md`)

When this file conflicts with `CURRENT_SOURCE_OF_TRUTH.md` or backend plugin docs, **the source-of-truth docs win**.

---

## 2. Current repo state

Latest known **pushed** state:

| Area | State |
|------|-------|
| Backend branch | `AI` |
| Backend HEAD | `078a44a` — Document guest self-service cache contract |
| Backend cache fix (code) | `d46713a` — Prevent cached guest self-service status after cancellation |
| Root branch | `audit-current-state` |
| Root HEAD | `2b2bc8f` — Align docs with current sync and confirmation behavior |
| Root submodule pointer | Backend `078a44a` |
| iOS foreground/privacy refresh | `b910bd1` on root |
| Zip files | **Do not track.** `Backend/*.zip` is gitignored. Deploy zips are local-only. |
| Docs | Reconciled 2026-06-24 for cursor persistence, confirmation settings, offline policy, self-service cancellation. |

Before any implementation work, verify live git:

```bash
# Backend
cd Backend/tryzub-reservations-api
git status --short
git branch --show-current
git rev-parse --short HEAD
git log --oneline -5

# Root
cd ../..
git status --short
git branch --show-current
git rev-parse --short HEAD
git submodule status
```

**Production:** Guest self-service cancel + dead-state verified live (2026-06-24). App login works. Submodule pointer (`078a44a`) is repo truth; exact deployed plugin SHA is not tracked in git.

---

## 3. V1 focus (this weekend)

**Stabilize before new product features.**

Ordered work ([IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md)):

1. ~~**Guest self-service cancel + cache**~~ — **verified in production** (`d46713a`+ deployed; dead-state on reload confirmed).
2. ~~**Production auth**~~ — **app login works** in production; optional curl spot-check of `/ping` / `/restaurant-setup` remains available.
3. ~~**Pipeline diagnostics**~~ — **reviewed**; one `unexplained_missing` item is a known old pre-hardening test — **non-blocking for V1**.
4. **iOS data/fetch on device** — foreground/privacy refresh (`b910bd1`), bounded-full, no import on normal refresh — **still open**.
5. **Confirmation mode on restaurant iPad** — confirm Mail vs backend `/confirm` setting matches pilot intent — **still open**.
6. **Final V1 smoke test** — end-to-end staff ops on the restaurant iPad — **still open**.

**After open items:** walk-ins/wait room or guest persistence — Bohdan decides.

**Not production-ready:** V1 stabilization is not complete until device refresh, confirmation mode, and final smoke test pass.

---

## 4. Hard product rules

| Rule | Detail |
|------|--------|
| Backend is source of truth | SwiftData is operational cache only |
| No offline queue in V1 | No offline manual create/edit queue; mutations blocked when degraded; cache stays visible |
| No duplicate Host stale UI | `HomeServiceStatusPresenter` / `ScreenFreshnessState` already show Updated/Checked/Saved data |
| Guest token after cancel | Token **stays valid**; page shows **cancelled dead state**, not invalid link |
| No zip in git | Build locally; folder must be `tryzub-reservations-api/` inside zip |
| No backend contract duplication | API/schema live in backend README + INTELLIGENCE only |
| Normal iOS refresh | Must **not** call `POST /managed-reservations/import` |

**Parked / not V1:** offline queue, SMS automation, broad Host redesign, new LLM features, multi-tenant rewrite.

---

## 5. Code truths docs must match

### Sync / freshness (iOS)

- Cache-first startup; active-window full vs delta upsert.
- **`server_time` cursors persist in UserDefaults** (`tryzub.sync.serverCursors.v1`) — not in-memory only; **not** an offline mutation queue.
- Bounded-full: force full replace after 5 deltas or 2 hours without full.
- `lastSyncedAt`, `lastFreshnessCheckedAt`, `cacheTrustSource` = presentation/session fields, not server truth.

### Confirmation (staff)

- **Both paths exist:** manual Mail and `POST /managed-reservations/{id}/confirm`.
- Active behavior depends on **Email Automation / This iPad Email Controls** (`EmailAutomationSettings.backendConfirmationEnabled`).
- **Code default is `true`** — do not assume Mail-first unless pilot iPad setting is confirmed.
- Manual Mail: manage link → Mail composer → `manual-email-log` → PATCH `confirmed` on `.sent` only.
- Backend confirm: server send path; **confirmation mode on the restaurant iPad still needs explicit verification** (queue item #5).

### Guest self-service (backend `d46713a`+)

- Public `GET/POST /reservation-self*` with no-store headers.
- JS: `cache: 'no-store'`, `_ts` on GET, POST cancel returns refreshed guest-safe `data`.
- Cancellation email after status update + re-fetch (`239b297`).

---

## 6. Production verification

| Check | Status |
|-------|--------|
| Anonymous `/ping` | Done |
| Protected routes 401 without auth | Done |
| Guest cancel email received | Done |
| Guest cancelled page / dead-state after reload | Done |
| App login (manager/developer protected routes) | Done |
| Pipeline `unexplained_missing` item | Known old pre-hardening test — non-blocking for V1 |
| iOS foreground/privacy refresh on device | **Open** |
| Confirmation mode on restaurant iPad (Mail vs backend `/confirm`) | **Open** |
| Final V1 smoke test (staff ops on restaurant iPad) | **Open** |

Optional spot-checks (not blocking if app login already works): manager `/ping` curl, `Cache-Control: no-store` header audit on `/reservation-self`.

Guest cancel curl (disposable token only):

```bash
export BASE_URL="https://tryzubchicago.com/wp-json/tryzub/v1"
export TOKEN="..."   # never commit; never paste in chat

curl -sS -D - -o /dev/null "$BASE_URL/reservation-self?token=$TOKEN&_ts=$(date +%s)"
curl -sS "$BASE_URL/reservation-self?token=$TOKEN&_ts=$(date +%s)" | jq '.data.status, .data.can_request_cancel'
```

Manager + pipeline (Application Password in local env file only):

```bash
source ~/tryzub-local-api.env   # WP_USER, WP_APP_PASSWORD — never commit

curl -sS -u "$WP_USER:$WP_APP_PASSWORD" "$BASE_URL/ping" | jq '.user'

curl -sS -u "$WP_USER:$WP_APP_PASSWORD" \
  "$BASE_URL/intelligence/reservation-pipeline-diagnostics?from=$FROM&to=$TO&include_items=0" \
  | jq '.data.summary, .data.manager_message'
```

---

## 7. Deploy workflow (zip local-only)

```bash
cd Backend
zip -r tryzub-reservations-api.zip tryzub-reservations-api \
  -x "tryzub-reservations-api/.git/*" "tryzub-reservations-api/.git/**"
```

- Upload in WordPress → Plugins (must replace existing `tryzub-reservations-api` folder).
- Purge cache for `/manage-reservation/` after guest self-service deploy.
- Delete duplicate plugin folder if a bad flat zip created a second copy.

---

## 8. Agent workflow

| Role | Tool | Does |
|------|------|------|
| Audit / docs / prompts | **Composer 2.5** | Read-only audits, doc reconciliation, handoff packets |
| Code | **GPT-5.5 Agent** | Implements from exact handoff; allowed files only |
| Product / deploy | **Bohdan** | Priorities, credentials, WordPress upload, device testing |

**Rules:**

- Audit first, implement second.
- One commit per concern.
- Do not commit without Bohdan asking.
- Do not track zip files.
- Composer prompts: scope files explicitly; forbid unrelated dirty files.

---

## 9. What to tell Bohdan when he asks “what’s next?”

1. Device-test iOS refresh after background/privacy unlock (`b910bd1`).
2. Confirm confirmation mode on the restaurant iPad matches pilot intent.
3. Run final V1 smoke test on the restaurant iPad.
4. If all green → pick walk-ins or guest persistence.
5. Do **not** start offline queue, Host stale-warning UI, or broad refactors.
6. Do **not** treat the app as fully production-ready until open verification items pass.

---

## 10. Known risks

- Deployed plugin SHA is not tracked in git; submodule pointer is repo truth.
- Stale iOS PATCH without `expected_updated_at` can revert guest `cancelled` → `confirmed`.
- Pipeline may still surface historical `unexplained_missing` rows from pre-hardening tests — treat as known, not a live mystery.

---

*Last aligned: 2026-06-24 (production guest cancel + login verified). Update when repo HEAD, V1 slice, or verification status changes materially.*
