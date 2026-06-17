# Tryzub Reservations Intelligence Layer

Internal restaurant intelligence for Tryzub Ukrainian Kitchen. This layer helps staff and management understand who is coming, who is returning, what guest context matters, what demand and risk are forming, and what data quality looks like.

The backend returns deterministic evidence fields. iOS controls staff and manager wording.

Floor plan/table layout endpoints are documented in `README.md`. This file covers guest memory, business analytics, system health, and intake reconciliation only.

## Endpoints

All intelligence endpoints:

- require authentication via `manage_tryzub_reservations` or `manage_options`
- are read-only `GET` routes
- return `success` + `data`
- set `Cache-Control: private, no-store, max-age=0` and `Pragma: no-cache`
- use contract version `1.0` for business/guest/system-status payloads
- use contract version `1.1` for reservation pipeline diagnostics payloads

Because these are read-only, they are not part of the optimistic-concurrency contract: iOS does not send `expected_updated_at` here. Concurrency tokens (`row_version`), lifecycle timestamps (`seated_at`, `completed_at`), `409 tryzub_reservation_conflict`, the status transition map, and floor-plan advisory locking apply to the managed-reservation write endpoints and are documented in `README.md` (db `1.7.0` for activity history; reservations lifecycle columns from `1.6.0`).

### `GET /tryzub/v1/business-intelligence/summary?from=YYYY-MM-DD&to=YYYY-MM-DD`

Owner/manager aggregate analytics over a reservation date range.

- includes all `source_type` rows
- excludes `is_hidden = 1`
- excludes `superseded_by_id IS NOT NULL`
- max range: 366 days inclusive

### `GET /tryzub/v1/guest-intelligence?date=YYYY-MM-DD`

Compact per-reservation guest memory for one service date.

- excludes hidden and superseded rows from the selected-date base set
- returns one summary item per reservation on that date, keyed by `reservation_id`
- searches full managed reservation history internally by email/phone
- returns `guest_name` because staff already see selected-date guest names
- does not return raw email, phone, or note text
- each item includes `seen_before`, `safe_copy`, `history`, `signals`, and legacy evidence fields
- lightweight profile pointers only: `has_history_preview`, `has_prior_notes`, `profile_endpoint`
- full historical previews belong on the reservation profile endpoint, not the date-level list

### `GET /tryzub/v1/guest-intelligence/reservation/{id}`

Server-backed guest profile intelligence pack for one managed reservation.

Use this when iOS opens Reservation Detail, Guest Insights, or Guest tab profile views without downloading full reservation history.

- looks up the current reservation by managed ID
- searches full historical managed reservations by email/phone only
- excludes the current reservation from prior visit counts
- returns `identity`, `history`, `signals`, `debug`, and the full `item` block for parity with date-level intelligence
- adds `profile_pack_version` and management-ready sections:
  - `history.matched_visit_preview` — latest 3–5 prior visits with trimmed note previews
  - `profile_summary` — deterministic summary text and `management_notes`
  - `preferences` — usual time/day/party size, tables, source pattern, occasion
  - `note_intelligence` — aggregated prior note counts, previews, and signal buckets
  - `visit_analytics` — explicit visit/status/source breakdowns
  - `host_profile_packet` — compact staff-safe lines for Host Intelligence

### `GET /tryzub/v1/intelligence/system-status?from=YYYY-MM-DD&to=YYYY-MM-DD`

Operational health for the intelligence pipeline.

- no guest names, emails, phones, or notes
- counts and timestamps only
- manager summary + developer summary + checks + warnings
- includes `pipeline_diagnostics.summary` with explained vs unexplained non-spam intake gaps
- does not treat every missing managed row as a live operational problem
- includes `pipeline_diagnostics` with:
  - `summary`
  - `warnings`
  - `endpoint`
  - `manager_message`
  - `developer_message`
- `pipeline_diagnostics.summary` uses reservation-intake metrics, not all Flamingo forms

### `GET /tryzub/v1/intelligence/reservation-pipeline-diagnostics?from=YYYY-MM-DD&to=YYYY-MM-DD`

Developer/staff diagnostics for Flamingo intake vs managed reservation reconciliation.

- protected; never public
- scans all `flamingo_inbound` posts in intake-date range (`DATE(post_date)`)
- distinguishes reservation-intake CF7 forms from other Flamingo forms before flagging unexplained gaps
- classifies each submission and explains failed imports, duplicate skips, hidden rows, terminal rows, hard deletes, spam/rejected, non-reservation forms, and unexplained reservation-intake gaps
- does not expose raw Flamingo payload, raw guest notes, email bodies, or phone numbers
- manual managed rows with `source_submission_id = null` are counted as `manual_rows_without_flamingo_source` and are not treated as missing Flamingo rows
- missing does not automatically mean broken operations

Optional query params:

- `include_items=0|1` (default `1`)
- `classification=managed_active|failed_import|duplicate_import|hard_deleted_test_row|unexplained_missing|non_reservation_form|...`
- `page` and `per_page` (default `100`, max `500`) with `items_meta.has_more`

Reservation form detection:

- uses CF7 `_wpcf7_contact_form` metadata when available (`form_id`, `form_title`)
- uses known reservation field signatures (`text-583`, `email-90`, `tel-299`, `text-446`, `text-196`, `text-139`, `textarea-887`, `tryzub_client_request_id`)
- `non_reservation_form` = other CF7/contact forms (newsletter, contact, etc.)
- `form_source_unknown` = ambiguous form source without a strong reservation field set
- `unexplained_missing` applies only to reservation-intake submissions

Classification priority when no managed row exists:

1. `spam_or_rejected`
2. `hard_deleted_test_row` (deletion audit)
3. `failed_import`
4. `duplicate_import`
5. `non_reservation_form` / `form_source_unknown`
6. `unexplained_missing`

Summary fields (iOS should use these names):

- `flamingo_inbound_total`
- `flamingo_non_spam_total`
- `reservation_intake_total`
- `reservation_intake_non_spam_total`
- `managed_active_with_source`
- `managed_hidden_with_source`
- `managed_terminal_with_source`
- `failed_imports`
- `duplicate_imports`
- `hard_deleted`
- `unexplained_missing`
- `spam_or_rejected`
- `non_reservation_form`
- `form_source_unknown`
- `manual_rows_without_flamingo_source` (canonical)
- `manual_without_source` (deprecated alias)
- `non_spam_reservation_intake_without_active_managed_row`
- `explained_missing_submissions`
- `unexplained_missing_submissions`

Top-level fields in the direct diagnostics response (also present for iOS developer mode):

- `manager_message` — non-alarming plain-text summary for staff
- `developer_message` — technical gap count sentence for developer mode
- `items_meta` — `{ total_items, filtered_items, page, per_page, has_more }`
- `warnings` — array of machine-readable warning strings

Item DTO fields:

- `source_submission_id`, `submitted_at`, `submission_status`
- `form_id`, `form_title`, `is_reservation_form`
- `classification`, `managed_reservation_id`, `managed_status`, `is_hidden`
- `duplicate_reason`, `failure_code`, `deletion_audit_id`, `explanation`

`/intelligence/system-status` remains summary-only via `pipeline_diagnostics.summary`.

Full item lists can be large for 366-day ranges. Use:

```text
include_items=0 on system-status companion calls when only summary is needed
classification=... on diagnostics endpoint to filter one bucket
page / per_page on diagnostics endpoint for pagination
```

## Guest profile pack (`GET /guest-intelligence/reservation/{id}`)

Top-level sections:

```text
identity
history
signals
profile_summary
preferences
note_intelligence
visit_analytics
host_profile_packet
debug
item
profile_pack_version
```

`history` includes:

```text
seen_before
prior_visit_count
last_seen_date
first_seen_date
safe_copy
matched_visit_preview
```

`matched_visit_preview[]` rows include trimmed note previews only. They do not expose raw email/phone or unlimited note text.

`matched_visit_preview[].signals` — each key is a **string or null** (string label when detected, null when absent):

```text
occasion          string | null   — e.g. "birthday", "anniversary", "wedding"
dietary           string | null   — e.g. "vegetarian", "vegan", "gluten-free"
allergy           string | null   — e.g. "allergy"
table_preference  string | null   — e.g. "window seat", "booth", "quiet table"
accessibility     string | null   — e.g. "wheelchair", "stroller", "high chair"
service_issue     string | null   — e.g. "complaint", "bad experience"
```

`note_intelligence.all_note_signals` — each key is an **array of strings** (all detected labels across prior visits, empty array when none):

```text
occasion          string[]   — all occasion labels found across prior visits
dietary           string[]
allergy           string[]
table_preference  string[]
accessibility     string[]
service_issue     string[]
```

**iOS decoding note:** clients using automatic snake_case → camelCase key mapping must handle:

```text
table_preference  →  tablePreference
service_issue     →  serviceIssue
```

All other signal keys (`occasion`, `dietary`, `allergy`, `accessibility`) are already camelCase-safe.

`host_profile_packet` is a compact deterministic block for Host Intelligence / local model context:

```text
guest_name
identity_confidence
seen_before
safe_history_line
last_seen_line
preference_lines
risk_lines
service_lines
preview_count
```

Date-level `GET /guest-intelligence?date=...` stays lightweight:

```text
seen_before
safe_copy
signals
has_history_preview
has_prior_notes
profile_endpoint
```

## Privacy guarantees

- no raw email in intelligence responses
- no raw phone in intelligence responses
- no unbounded historical note text
- reservation profile note previews are trimmed to about 160 characters
- guest names only on selected-date guest intelligence items and floor-plan conflict payloads where staff already see guest names operationally
- `guest_key` is an HMAC hash, not reversible PII
- pipeline diagnostics expose `source_submission_id`, statuses, failure codes, and deterministic explanations only
- pipeline diagnostics do not expose raw Flamingo payload, raw guest notes, email bodies, or phone numbers

## Contract metadata

Business and guest intelligence responses include:

- `contract_version`
- `scope`
- `source`
- `data_quality`

`data_quality.warnings` contains machine-readable strings such as:

- `relationship_metrics_are_approximate`
- `note_flags_are_heuristic`
- `history_matching_limited_to_email_phone`
- `name_only_identity_not_used_for_history`
- `no_identity_keys_available`

## Business intelligence

Key sections:

- `summary`
- `demand`
- `guest_relationships`
- `risk`
- `breakdowns`
- `peak_windows`
- `pipeline`

Approximations in v1:

- guest relationship metrics are per-reservation occurrence, not a dedicated guest profile table
- returning, regular, and frequent counts use email/phone history matching only
- name-only identity is not used for historical relationship claims
- unique guest estimates use HMAC `guest_key` plus anonymous row fallback
- note flags are heuristic booleans, not exact semantic truth
- lead time uses `created_at`, not Flamingo post date
- peak window `sample_count` is distinct reservation dates per weekday/time group

iOS should not create strong guest-memory claims from `weak`, `unknown`, or name-only `possible` identity.

## Guest intelligence

Identity rules:

- email match: `exact`
- phone 10+ digits: `strong`
- phone 7-9 digits: `possible`
- full normalized name only: `possible`, but no history matching in v1
- weak or empty identity: `unknown`

Classification:

- `new`: 0 prior clean visits
- `returning`: 1-2
- `regular`: 3-5
- `frequent_regular`: 6+
- `needs_review`: current row needs review or possible duplicate
- `unknown`: weak or unknown identity

Clean visit statuses:

- `confirmed`
- `seated`
- `completed`

History matching:

- email and phone only
- excludes same-day rows from clean visit counts
- excludes hidden, superseded, and duplicate-marked rows from clean counts

## Note flag engine

`tryzub_intelligence_detect_note_flags()` is:

- deterministic
- multilingual
- English, Ukrainian Cyrillic, limited Russian, and sparse transliteration aware
- conservative and heuristic

Flags:

- `has_seating_preference`
- `has_allergy_note`
- `has_accessibility_note`
- `has_special_occasion_note`
- `has_prior_service_issue`

`has_special_occasion_note` includes family events such as birthdays, anniversaries, baby showers, baptisms/christenings, engagements, weddings, graduations, memorials, and family celebrations.

These are not medical, legal, or operational truth. They are evidence booleans for staff UI.

## System status

`pipeline_diagnostics.manager_message` is intentionally non-alarming:

```text
Some reservation-intake form submissions are not active managed reservations.
Most are explained by failed imports, duplicates, hidden rows, terminal statuses, deleted test rows, or non-reservation forms.
Review developer diagnostics for details.
```

`pipeline_diagnostics.developer_message` calls out only true reservation-intake gaps:

```text
There are X unexplained reservation-intake Flamingo submissions without an active managed reservation row.
```

Missing does not automatically mean broken operations.

Manager summary helps answer:

- are reservations available?
- are new imports waiting?
- are review items present?
- are hidden, superseded, or duplicate rows affecting trust?

Developer summary helps answer:

- how many managed rows are in range?
- how many are form vs manual?
- how many import failures are open?
- how much spam was seen in Flamingo intake dates?

Spam support:

- `spam_or_rejected_submission_count` uses Flamingo `_submission_status = SPAM` filtered by Flamingo `post_date`
- rejected submissions are not tracked as a first-class metric yet

## What iOS should use

- Host Board selected date: `GET /guest-intelligence?date=...`
- Reservation Detail / Guest Insights / Guest tab profile: `GET /guest-intelligence/reservation/{id}`
- Manager/system health: `GET /intelligence/system-status`
- Developer intake reconciliation: `GET /intelligence/reservation-pipeline-diagnostics?from=...&to=...`
- Owner range analytics: `GET /business-intelligence/summary`
- Floor layout and assignments: see `README.md` (`GET /floor-plan`, `PUT /restaurant-tables`, `PATCH /managed-reservations/{id}/tables`)
- Reservation change history / service-day recap: `GET /managed-reservations/{id}/activity`, `GET /activity?date=...` (see `README.md`)

Activity history is deterministic operational evidence written by backend mutations. iOS may use it for Reservation Detail timelines and manager recap, but should not expose raw `old_value` / `new_value` debug blobs to staff UI.

## What iOS should trust

- evidence fields and counts from backend
- `seen_before` and `safe_copy` from guest intelligence endpoints, not local cache alone
- exact prior visit counts only when `identity.confidence` is `high` and `prior_visit_count` is non-null
- classifications only when `identity_confidence` is `exact` or `strong`
- `possible` identity only with caution
- note flags as hints, not facts
- `data_quality.warnings` when deciding how strongly to phrase guest memory

## What iOS should not do

- no auto-confirm from intelligence
- no auto-cancel from intelligence
- no returning-guest claims from `weak` or `unknown` identity
- no display of raw historical notes from intelligence endpoints
- no caching of intelligence responses in shared caches
- no treating `unexplained_missing_submissions` as production outage without reviewing `non_reservation_form` and explained buckets
- no calling `POST /managed-reservations/import` during normal refresh

## Legacy analytics

`GET /tryzub/v1/reservation-analytics/summary` remains unchanged for compatibility.

It is form/Flamingo scoped and is not the same contract as business intelligence.

## Performance and caching

Current indexes (db `1.6.0` for reservations intelligence queries; floor-plan tables documented in `README.md`):

- `email`, `phone`, `reservation_date`, `status`, `source_submission_id`
- composite: `email_reservation_date`, `phone_reservation_date`, `reservation_date_hidden_superseded`, `status_reservation_date`, `source_type_reservation_date`

Guest intelligence cost model:

- date endpoint: 1 service-date query + 1 batched history query by collected emails/phones
- reservation endpoint: 1 reservation lookup + 1 batched history query
- no full-table scan; history can still be large for guests with long email/phone match history

Caching:

- intelligence responses are not cached server-side in v1
- responses use `private, no-store` headers
- recommended future improvement: short-lived transient cache per date or reservation, bust on managed reservation import/update

## Future improvements

- dedicated guest profile table
- normalized email column and stronger identity merge
- richer import failure and rejected-submission metrics
- revenue or POS integration
- optional note language classification if needed later
- server-side transient cache with import/update busting
