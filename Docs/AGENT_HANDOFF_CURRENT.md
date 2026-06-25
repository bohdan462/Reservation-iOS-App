# Agent Handoff — Current Slice

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md) · [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md)

---

## Title

Backend guest cancellation email + cancelled self-service dead state + confirmation copy cleanup + pipeline visibility flattening.

---

## Git state (audit 2026-06-19)

| Location | State |
|----------|--------|
| **Root** | `m Backend/tryzub-reservations-api` only (submodule pointer; iOS clean) |
| **Backend HEAD** | `253f251` — Add full guest booking history and notes payload |

**Backend dirty — unrelated; do not bundle:**

- `includes/activation.php`
- `includes/health.php`
- `includes/permissions.php`
- `tryzub-reservations-api.php`

---

## Allowed files

| File | Why |
|------|-----|
| `Backend/tryzub-reservations-api/includes/emails.php` | Cancellation email builders/send; confirmation HTML copy cleanup |
| `Backend/tryzub-reservations-api/includes/reservation-self-service.php` | Cancel handler email insert; guest page JS dead-state copy |
| `Backend/tryzub-reservations-api/includes/intelligence-system-status.php` | Flatten `pipeline_diagnostics.summary` into `developer_summary` for iOS probes |

## Read-only reference

| File | Why |
|------|-----|
| `Backend/tryzub-reservations-api/includes/routes.php` | Route registration (no change expected) |
| `Backend/tryzub-reservations-api/includes/managed-reservations.php` | `tryzub_get_managed_reservation_row_by_id` |
| `Backend/tryzub-reservations-api/includes/reservation-pipeline-diagnostics.php` | Classification logic and summary keys |

---

## Forbidden

- All iOS Swift files
- Schema / migration / `activation.php`
- `permissions.php`, `health.php`, `tryzub-reservations-api.php` (unless explicitly approved)
- Rate limits on public guest routes
- Walk-in mode
- Guest profile SwiftData cache
- Analytics local cache
- Zip files, build number changes

---

## Functions to modify

| File | Function | Current behavior | Required change |
|------|----------|------------------|-----------------|
| `emails.php` | `tryzub_send_reservation_email` (~1619) | HTML only for `confirmation`, `reminder` | Add `cancellation` branch |
| `emails.php` | `tryzub_build_reservation_email_subject` (~1936) | No cancellation subject | Add cancellation subject |
| `emails.php` | `tryzub_build_reservation_email_body` (~1944) | No cancellation body | Add cancellation plain text |
| `emails.php` | `tryzub_build_reservation_confirmation_email_html` (~2007) | Includes **"Request Different Time"** CTA (~2066) | Remove misleading CTA; keep manage link when `$manage_url` set |
| `emails.php` | **NEW** cancellation HTML/text builder | Missing | Mirror confirmation card styling; no manage/book CTAs |
| `reservation-self-service.php` | `tryzub_cancel_reservation_self` (~309) | Updates status, logs activity; **no email** | After update (~408): re-fetch row via `tryzub_get_managed_reservation_row_by_id`, call `tryzub_send_reservation_email($row, 'cancellation')`, then activity log |
| `reservation-self-service.php` | Shortcode JS `buildCardMarkup` (~830) | Hardcoded `Your Booking Details` | Cancelled dead-state title |
| `reservation-self-service.php` | `updateSubtitle` (~748) | Active: change-via-email copy; cancelled: hides subtitle | Cancelled: explicit dead-state message; active: accurate self-service copy |
| `reservation-self-service.php` | `updateStatusDisplay` / `renderCancelAction` | Cancelled pill; hides cancel UI | Verify reload path after cancel |
| `intelligence-system-status.php` | `tryzub_get_intelligence_system_status` (~3) | Nests pipeline summary under `pipeline_diagnostics` only | Merge key summary fields into `developer_summary` (snake_case keys iOS decodes) |

**Reuse:** `tryzub_log_reservation_email`, `tryzub_reservation_activity_log`, `tryzub_get_managed_reservation_row_by_id`, `tryzub_validate_guest_manage_token` (unchanged).

**Note:** `tryzub_update_reservation_for_guest_request` returns `true`, not a refreshed row — must re-fetch before email.

---

## Tests

1. Guest cancel success → 200, status `cancelled`, `guest_cancelled` activity.
2. Cancellation email → `tryzub_reservation_emails` row `email_type=cancellation`, `sent` or `skipped` (placeholder email).
3. Guest page reload → cancelled title/subtitle, no cancel button, cancelled pill.
4. Double cancel → 409 `already_cancelled`, no duplicate email.
5. Too-close cancel (<2h) → 409, no email.
6. Confirmation email → no **"Request Different Time"** button.
7. `GET /intelligence/system-status` → `developer_summary` includes flattened pipeline counts (`flamingo_inbound_total`, `managed_active`, `unexplained_missing`, etc.).
8. `GET /intelligence/reservation-pipeline-diagnostics?include_items=1` → can explain 300/338-style gap per `classification` + `explanation`.

---

## Command-line budget

```bash
git status --short
git diff --stat
php -l <each modified PHP file>
```

- No broad repo grep unless a function name is missing.
- Read only listed files/functions.
- Targeted `git diff` on modified paths only.

---

## Out of scope

iOS, rate limits, walk-in, guest profile cache, analytics persistence, auth dirty files.
