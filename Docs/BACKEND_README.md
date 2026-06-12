# Tryzub Reservations API

Controlled restaurant pilot backend for Tryzub Ukrainian Kitchen reservations.

This is a custom WordPress plugin that turns Contact Form 7 / Flamingo reservation submissions into a managed reservation backend for the iOS staff app.

This is not production SaaS infrastructure. It is a practical MVP for a restaurant test where email remains the backup.

DB schema version: `1.6.0`

## Project Overview

Core rule:

```text
Flamingo = raw intake/archive.
tryzub_reservations = managed operational source of truth.
iOS app = staff interface.
SwiftData = iOS local cache only.
```

The iOS app should read and update managed reservations. It should not read raw Flamingo for normal workflow, and it should not call the import endpoint as part of normal refresh.

For the restaurant pilot, confirmation email is primarily a manual Gmail/Mail workflow from iOS/staff. The backend can generate guest manage links and record manual email activity, but the manual Gmail path does not send email from the backend.

Operational docs:

```text
README.md       API routes, tables, floor plan, iOS handoff, test checklists
INTELLIGENCE.md guest intelligence, business intelligence, system status, pipeline diagnostics
```

## Data Flow

```text
Contact Form 7 public reservation form
-> Flamingo raw inbound message
-> backend auto-import after Flamingo saves
-> {prefix}tryzub_reservations managed table
-> private REST API
-> iOS staff app
```

If a form submission is clean, it becomes a managed reservation. If it is invalid or missing required data, it becomes a failed import record that authorized staff/developers can inspect. The raw Flamingo message remains available as backup.

## Production Contract / iOS Handoff

This section is the closing contract for production deploy and iOS integration. It summarizes what is public, what is protected, how CF7 maps into managed reservations, and what analytics may fire on the website.

### A. Public endpoints

| Endpoint | Auth | Purpose |
| --- | --- | --- |
| `GET /wp-json/tryzub/v1/ping` | Public | Health check |
| `GET /wp-json/tryzub/v1/reservation-slots?date=YYYY-MM-DD` | Public | Public bookable time chips for the website form |
| `GET /wp-json/tryzub/v1/reservation-self?token=...` | Public token | Guest-safe reservation card data |
| `POST /wp-json/tryzub/v1/reservation-self/change-request` | Public token | Compatibility/future guest change request path; not shown in the MVP guest UI |
| `POST /wp-json/tryzub/v1/reservation-self/cancel` | Public token | Guest cancellation request |

Public `GET /reservation-slots` response shape:

```json
{
  "success": true,
  "date": "2026-05-29",
  "is_open": true,
  "slots": [
    { "value": "17:00", "label": "5:00 PM" }
  ],
  "message": null
}
```

Closed-day example:

```json
{
  "success": true,
  "date": "2026-05-29",
  "is_open": false,
  "slots": [],
  "message": "Reservations are not available for this date."
}
```

Public response must NOT expose:

```text
blocked slot reasons
blocked_slots_count
internal availability source
guest data
staff notes
private reservation IDs
Flamingo IDs
import failure payloads
```

The endpoint is cache-busted on the client and returns `Cache-Control: no-store` headers so slot changes appear promptly after staff edits.

### B. Protected staff / iOS endpoints

All routes below require an authenticated WordPress user with `manage_tryzub_reservations` or `manage_options`, except permanent hard delete which requires `manage_options`. Unauthenticated or unauthorized requests must return `401` / `403`.

Protected route groups:

```text
GET    /managed-reservations
GET    /managed-reservations/{id}
PATCH  /managed-reservations/{id}
DELETE /managed-reservations/{id}?force=1
POST   /managed-reservations
POST   /managed-reservations/import
GET    /managed-reservations/import-failures
POST   /managed-reservations/{id}/confirm
POST   /managed-reservations/{id}/manual-email-log
POST   /managed-reservations/{id}/guest-manage-link
POST   /managed-reservations/send-due-reminders
GET    /reservation-analytics/summary
GET    /business-intelligence/summary
GET    /guest-intelligence
GET    /guest-intelligence/reservation/{id}
GET    /intelligence/system-status
GET    /intelligence/reservation-pipeline-diagnostics
GET    /restaurant-tables
PUT    /restaurant-tables
GET    /floor-plan
PATCH  /managed-reservations/{id}/tables
GET    /restaurant-setup
PATCH  /restaurant-setup
GET    /restaurant-hours
PATCH  /restaurant-hours
GET    /restaurant-day-availability
PATCH  /restaurant-day-availability
GET    /restaurant-blocked-slots
POST   /restaurant-blocked-slots
DELETE /restaurant-blocked-slots
GET    /reservations
```

`GET /ping` is public, but only authenticated reservation users receive `table_exists`.

### C. CF7 / Flamingo field mapping

The public website form must keep these Contact Form 7 field names:

| CF7 field | Meaning | Notes |
| --- | --- | --- |
| `text-583` | Guest name | |
| `email-90` | Guest email | |
| `tel-299` | Guest phone | Visible USA formatting; backend normalizes digits |
| `text-446` | Reservation date | Public form format `MM-DD-YYYY` |
| `text-196` | Reservation time | Submitted as `HH:mm`, not display label |
| `text-139` | Party size | Integer |
| `textarea-887` | Notes / occasion | Optional |
| `tryzub_client_request_id` | Client idempotency ID | Hidden field generated once per page/form instance |

On `/book-table`, wrap the CF7 form in `#tryzub-booking-v2` to enable the chip UI. The form still submits through CF7; hidden/synced fields keep the names above.

### D. Import behavior

```text
CF7 submission -> Flamingo inbound post -> backend auto-import -> tryzub_reservations
```

Rules:

```text
Flamingo remains raw intake/archive.
Managed table is the operational source for iOS after import.
source_submission_id prevents duplicate imports of the same Flamingo post.
tryzub_client_request_id prevents duplicate operational rows from repeated client submits.
submission_fingerprint prevents identical operational duplicates inside the short duplicate window.
Date/time are normalized during import.
Suspicious, large-party, or duplicate conditions may mark status needs_review.
iOS should read managed reservations, not raw Flamingo, for normal staff workflow.
```

Manual/admin import trigger:

```text
POST /managed-reservations/import
```

Normal iOS refresh must not call import.

### E. Booking availability hierarchy

```text
Weekly hours define the normal schedule.
Special day availability overrides one date.
GET /reservation-slots generates public bookable slots from effective availability.
Blocked slots remove specific generated slots for one date.
Capacity engine / table-capacity blocking is still deferred unless already implemented elsewhere.
```

Effective availability order:

```text
special day override -> weekly hours -> closed
generated slots -> remove blocked slots -> return public slots[]
```

### F. Analytics events (GTM dataLayer)

Implemented in `assets/js/reservations-form.js`.

| Event | When it fires |
| --- | --- |
| `book_table_cta_seen` | Landing-page CTA enters viewport once per page load |
| `book_table_cta_clicked` | Landing-page CTA clicked |
| `book_table_cta_hovered` | Landing-page CTA first hover, desktop intent only, once per page load |
| `reservation_form_started` | First interaction inside `#tryzub-booking-v2` |
| `reservation_date_selected` | Valid in-window date selected; no date value sent |
| `reservation_time_selected` | Valid time selected; no time value sent |
| `reservation_party_size_selected` | Party size selected with bucket only |
| `reservation_form_submitted` | CF7 `mail_sent` on V2 form |
| `reservation_form_error` | CF7 validation/spam/mail failure on V2 form |

Party-size buckets only:

```text
1-2
3-4
5-6
7+
```

Privacy rule:

```text
Never send PII to analytics.
Do not send name, email, phone, notes, exact reservation date, exact reservation time, or guest identity.
```

Landing CTA detection is resilient:

```text
Links/buttons whose href contains /book-table/
Optional class .tryzub-book-table-cta
No CTA on a page = analytics silently skips CTA events
```

### G. Manual production checklist

1. Logged-out `/book-table` loads with no validation warnings on first paint.
2. Public `GET /reservation-slots?date=YYYY-MM-DD` returns only `success`, `date`, `is_open`, `slots[]`, `message`.
3. Protected endpoints return `401` / `403` without auth.
4. Submit a controlled test reservation with `skip_mail:on` if needed.
5. Flamingo captures all mapped CF7 fields.
6. `POST /managed-reservations/import` imports the test reservation when testing manually.
7. `GET /managed-reservations` returns the imported row with auth.
8. iOS fetches and decodes the managed row.
9. Homepage CTA links to `/book-table/`.
10. GTM Preview shows analytics events without PII payloads.

## Plugin Structure

```text
tryzub-reservations-api.php
includes/
  activation.php
  assets.php
  business-intelligence.php
  emails.php
  floor-plan.php
  formatting.php
  guest-intelligence.php
  health.php
  import.php
  intelligence-helpers.php
  intelligence-system-status.php
  managed-reservations.php
  permissions.php
  raw-reservations.php
  reservation-analytics.php
  reservation-pipeline-diagnostics.php
  reservation-self-service.php
  reservation-slots.php
  restaurant-blocked-slots.php
  restaurant-hours.php
  restaurant-setup.php
  routes.php
  validation.php
assets/
  css/reservations-form.css
  js/reservations-form.js
```

`activation.php` is loaded before `register_activation_hook()` so `tryzub_reservations_activate()` exists when WordPress activates the plugin.

## Tables

### `{prefix}tryzub_reservations`

Managed reservation table. This is the operational source of truth for staff and iOS.

Important columns:

```text
id
source_submission_id
client_request_id
submission_fingerprint
duplicate_of_reservation_id
duplicate_reason
source_type
created_by_user_id
created_by_device
guest_name
email
phone
reservation_date
reservation_time
party_size
guest_notes
staff_notes
status
table_name
created_at
updated_at
confirmed_at
seated_at
completed_at
confirmation_email_sent_at
reminder_email_sent_at
superseded_by_id
is_hidden
hidden_at
hidden_reason
hidden_by_user_id
```

`confirmed_at`, `seated_at`, and `completed_at` are lifecycle timestamps. Each is set once, the first time the reservation enters that status (whether by staff edit, confirm endpoint, or the automatic past-date completion sweep), and is not overwritten on later status changes.

Important indexes:

```text
UNIQUE source_submission_id
client_request_id
submission_fingerprint
duplicate_of_reservation_id
reservation_date
reservation_time
status
created_at
updated_at
email
phone
source_type
is_hidden
reservation_date + status
reservation_date + reservation_time
reservation_date + is_hidden
reservation_date + status + is_hidden
```

`source_submission_id` is the Flamingo post ID. It is unique when present, which makes importing the same Flamingo post idempotent. Manual reservations may have `source_submission_id = null`.

`client_request_id` and `submission_fingerprint` harden the importer against two separate Flamingo posts caused by repeated public form submits. They are storage/debug fields and are not returned in normal iOS reservation DTOs.

`source_type` identifies how a managed row entered operations:

```text
form
manual_call_in
manual_walk_in
known_guest_manual
import_repair
```

Wrong manual entries are soft hidden with `is_hidden`, not deleted.

### `{prefix}tryzub_reservation_import_failures`

Durable failed-import table. A bad or incomplete CF7/Flamingo submission should be visible here instead of disappearing silently.

Stores:

```text
source_submission_id
error_code
error_message
reservation_snapshot_json
raw_fields_json
raw_payload_json
submission_status
status
staff_notes
submitted_at
submitted_at_gmt
resolved_at
created_at
updated_at
```

### `{prefix}tryzub_reservation_duplicate_imports`

Audit table for raw Flamingo submissions skipped by backend duplicate protection.

Stores:

```text
source_submission_id
existing_reservation_id
duplicate_reason
client_request_id
submission_fingerprint
reservation_snapshot_json
raw_fields_json
raw_payload_json
created_at
```

Reasons:

```text
client_request_id_match
fingerprint_recent_match
```

This table is for staff/developer debugging. It does not create another operational reservation row.

### `{prefix}tryzub_reservation_deletion_audit`

Admin/developer audit table for permanent reservation deletion.

Stores:

```text
reservation_id
source_submission_id
deleted_by_user_id
deleted_at
reason
reservation_snapshot_json
```

Hard delete does not delete the raw Flamingo post or email logs.

### `{prefix}tryzub_reservation_emails`

Outbound/backend email attempt and manual email activity log.

Used for confirmation, reminder, cancellation, and manual Gmail/Mail tracking.

Stores:

```text
reservation_id
email_type
to_email
from_email
reply_to_email
subject
body_snapshot
provider_message_id
provider
status
error_message
sent_at
created_at
updated_at
```

Email failure does not erase or hide the reservation.

### `{prefix}tryzub_restaurant_settings`

Restaurant setup and reservation policy foundation. Email identity fields remain here for existing confirmation/reminder behavior, but this phase does not change email sending.

Stores:

```text
restaurant_key
business_name
timezone
default_party_size
booking_window_days
slot_interval_minutes
max_online_party_size
large_party_review_threshold
same_day_booking_enabled
minimum_lead_time_minutes
call_in_placeholder_email
from_email
reply_to_email
created_at
updated_at
```

Default policy values:

```text
booking_window_days = 60
slot_interval_minutes = 15
max_online_party_size = 8
large_party_review_threshold = 7
same_day_booking_enabled = true
minimum_lead_time_minutes = 60
```

### `{prefix}tryzub_restaurant_weekly_hours`

Editable pilot weekly hours. The seeded defaults match the current live public website schedule.

Stores:

```text
restaurant_key
weekday     0 Monday through 6 Sunday
is_open
open_time
close_time
created_at
updated_at
```

Weekday convention:

```text
0 = Monday
1 = Tuesday
2 = Wednesday
3 = Thursday
4 = Friday
5 = Saturday
6 = Sunday
```

Seed defaults:

```text
Monday    closed
Tuesday   17:00-21:00
Wednesday 17:00-21:00
Thursday  17:00-21:00
Friday    17:00-22:00
Saturday  11:00-22:00
Sunday    11:00-21:00
```

Normal plugin upgrades seed only missing weekly rows and do not overwrite staff-edited restaurant settings or weekly hours. A guarded repair only replaces untouched rows that exactly match known obsolete seed snapshots; custom/staff-edited rows are left alone. If a pilot database has custom older hours, update it through the iOS/staff UI or PATCH `/restaurant-setup` and `/restaurant-hours` to match the live public website schedule.

### `{prefix}tryzub_restaurant_special_hours`

Date-specific overrides for today/special-day availability.

Stores:

```text
restaurant_key
reservation_date
is_open
open_time
close_time
reason
created_by_user_id
updated_by_user_id
created_at
updated_at
```

### `{prefix}tryzub_restaurant_blocked_slots`

Specific reservation times removed from one date. Weekly hours define the normal schedule, special hours define full-day or short-day overrides, and blocked slots remove individual generated times without changing the day's hours.

Stores:

```text
restaurant_key
reservation_date
slot_time
reason
created_by_user_id
created_at
updated_at
```

Important indexes:

```text
UNIQUE restaurant_key + reservation_date + slot_time
reservation_date
slot_time
```

`/reservation-slots` generates public slots from effective availability and then removes blocked slots. Staff-only blocked-slot reasons are not included in the public slot response.

### `{prefix}tryzub_restaurant_tables`

Persisted grid-based floor layout for staff floor plan views.

Stores:

```text
restaurant_key
table_key
label
x
y
width_units
height_units
min_capacity
max_capacity
section
sort_order
is_active
created_at
updated_at
```

Important indexes:

```text
UNIQUE restaurant_key + table_key
restaurant_key
is_active
x + y
```

Layout rules:

```text
width_units: 1, 2, or 3
height_units: 1 or 2
min_capacity >= 1
max_capacity <= 20
max_capacity >= min_capacity
overlapping grid cells are rejected
```

Default capacity guidance by width:

```text
1 cube -> 1-4 guests
2 cubes -> 4-6 guests
3 cubes -> 6-8 guests
```

Custom min/max capacity is allowed when validated.

### `{prefix}tryzub_reservation_table_assignments`

Per-date table assignments for managed reservations. Supports multi-table combinations.

Stores:

```text
reservation_id
reservation_date
table_key
assigned_by_user_id
assigned_at
updated_at
```

Important indexes:

```text
UNIQUE reservation_id + table_key
reservation_id
reservation_date
table_key
reservation_date + table_key
```

`tryzub_reservations.table_name` remains the compatibility/display field. Assignment PATCH updates `table_name` to a single label or joined labels such as `4 + 5`.

### `{prefix}tryzub_reservation_messages`

Future-ready communication thread table.

For this pilot, guest replies still go to `reservations@tryzubchicago.com` manually. Later, an inbound email provider webhook can attach replies to reservations using this table.

Stores:

```text
reservation_id
direction
channel
from_email
to_email
subject
body_text
body_html
raw_payload_json
provider_message_id
in_reply_to
reply_token
status
created_at
read_at
handled_at
```

### `{prefix}tryzub_reservation_guest_tokens`

Token table for guest self-service links.

Stores only token hashes:

```text
reservation_id
token_hash
purpose
expires_at
created_at
revoked_at
used_at
```

Raw guest tokens are generated and returned only once in the manage link response.

### `{prefix}tryzub_reservation_guest_requests`

Audit/work queue table for guest self-service actions.

Stores:

```text
reservation_id
request_type     change or cancel
requested_payload_json
status           open, applied, rejected
created_at
resolved_at
resolved_by_user_id
```

Guest change requests append staff notes and may mark the reservation `needs_review`. Successful online cancellations append a staff note and mark the reservation `cancelled`. Rejected/too-late cancellation attempts are audited without changing operational status. Guest endpoints never expose staff-only data to the guest.

## Authentication

Private endpoints require an authenticated WordPress user with either:

```text
manage_tryzub_reservations
manage_options
```

Activation creates a `tryzub_reservations_staff` role with `manage_tryzub_reservations`.

For the iOS app, use a limited WordPress user with an Application Password stored in Keychain. Avoid using a full admin account for real staff testing.

### Recommended Pilot WordPress Users

Create separate WordPress users for pilot testing:

```text
host.tryzub
manager.tryzub
developer.bohdan
```

Recommended credential approach:

```text
Create separate WordPress users.
Generate a WordPress Application Password for each iOS tester/account.
Do not use full admin credentials for staff/manager testing.
Developer/admin account is required only for hard delete and developer cleanup tools.
Host/manager should use manage_tryzub_reservations, not manage_options, unless intentionally granted admin access.
```

Backend-enforced separation for the pilot:

```text
manage_tryzub_reservations or manage_options can read/create/update operational reservations.
manage_tryzub_reservations or manage_options can view failed imports and legacy/raw-ish reservation diagnostics.
manage_options is required for permanent hard delete.
Public booking slots stay public and guest-free.
Guest self-service endpoints stay public-token-only and return guest-safe data only.
Unauthenticated/unauthorized protected requests should return 401/403.
```

Current pilot simplification:

```text
The backend has one staff capability: manage_tryzub_reservations.
It does not currently enforce separate host-vs-manager capabilities.
Host/manager workflow differences are iOS role/UI-enforced for the pilot.
Developer/admin cleanup remains backend-enforced through manage_options.
```

## Base URL

```text
https://tryzubchicago.com/wp-json/tryzub/v1
```

## Response DTO

Managed reservation responses use snake_case keys so iOS can decode with:

```swift
decoder.keyDecodingStrategy = .convertFromSnakeCase
```

Reservation DTO shape:

```json
{
  "id": 85,
  "source_submission_id": 123,
  "source_type": "form",
  "created_by_user_id": null,
  "created_by_device": null,
  "guest_name": "Name",
  "email": "guest@example.com",
  "phone": "1234567890",
  "reservation_date": "2026-05-19",
  "reservation_time": "19:00:00",
  "party_size": 4,
  "guest_notes": "",
  "staff_notes": "",
  "status": "confirmed",
  "table_name": null,
  "created_at": "2026-05-19 12:00:00",
  "updated_at": "2026-05-19 12:10:00",
  "confirmed_at": "2026-05-19 12:10:00",
  "confirmation_email_sent_at": null,
  "reminder_email_sent_at": null,
  "superseded_by_id": null,
  "is_hidden": 0,
  "hidden_at": null,
  "hidden_reason": null,
  "hidden_by_user_id": null
}
```

Do not rename these fields without updating iOS.

New fields are additive. Older iOS builds should ignore them. For manual call-ins/walk-ins with no guest email, the API returns `email` as an empty string even though the database may store the configured placeholder email internally.

## Endpoints

### `GET /ping`

Health check.

Auth: public. Authenticated reservation users also see `table_exists`.

Example response:

```json
{
  "success": true,
  "message": "Tryzub Reservations API is working",
  "time": "2026-05-19 12:00:00"
}
```

### `GET /restaurant-setup`

Fetch restaurant setup and reservation policy settings.

Auth: required.

Response:

```json
{
  "success": true,
  "data": {
    "restaurant_key": "tryzub",
    "business_name": "Tryzub Ukrainian Kitchen",
    "timezone": "America/Chicago",
    "default_party_size": 2,
    "booking_window_days": 60,
    "slot_interval_minutes": 15,
    "max_online_party_size": 8,
    "large_party_review_threshold": 7,
    "same_day_booking_enabled": true,
    "minimum_lead_time_minutes": 60,
    "call_in_placeholder_email": "callinreservation@tryzubchicago.com",
    "from_email": "reservations@tryzubchicago.com",
    "reply_to_email": "reservations@tryzubchicago.com",
    "created_at": "2026-05-27 12:00:00",
    "updated_at": "2026-05-27 12:00:00"
  }
}
```

### `PATCH /restaurant-setup`

Update restaurant setup and policy settings.

Auth: required.

Allowed fields:

```text
business_name
timezone
default_party_size
booking_window_days
slot_interval_minutes
max_online_party_size
large_party_review_threshold
same_day_booking_enabled
minimum_lead_time_minutes
call_in_placeholder_email
from_email
reply_to_email
```

Validation:

```text
business_name non-empty
timezone valid timezone identifier
default_party_size 1-100
booking_window_days 1-365
slot_interval_minutes one of 15, 30, 45, 60
max_online_party_size 1-100
large_party_review_threshold 1-100
same_day_booking_enabled boolean
minimum_lead_time_minutes 0-1440
email fields valid if updated
```

Unknown fields are rejected.

Example request:

```json
{
  "booking_window_days": 60,
  "slot_interval_minutes": 15,
  "max_online_party_size": 8,
  "same_day_booking_enabled": true,
  "minimum_lead_time_minutes": 60
}
```

Example response:

```json
{
  "success": true,
  "data": {
    "restaurant_key": "tryzub",
    "slot_interval_minutes": 15,
    "max_online_party_size": 8
  }
}
```

### `GET /restaurant-hours`

Fetch weekly hours and special-day overrides.

Auth: required.

Query params:

```text
from optional YYYY-MM-DD
to   optional YYYY-MM-DD
```

Example response:

```json
{
  "success": true,
  "data": {
    "restaurant_key": "tryzub",
    "weekly_hours": [
      {
        "weekday": 0,
        "is_open": false,
        "open_time": null,
        "close_time": null
      }
    ],
    "special_hours": [
      {
        "reservation_date": "2026-05-29",
        "is_open": true,
        "open_time": "17:00:00",
        "close_time": "20:30:00",
        "reason": "Short hours"
      }
    ]
  }
}
```

### `PATCH /restaurant-hours`

Update weekly hours by `restaurant_key + weekday`.

Auth: required.

Example request:

```json
{
  "weekly_hours": [
    {
      "weekday": 0,
      "is_open": false,
      "open_time": null,
      "close_time": null
    }
  ]
}
```

Example response:

```json
{
  "success": true,
  "data": {
    "restaurant_key": "tryzub",
    "weekly_hours": [
      {
        "weekday": 0,
        "is_open": false,
        "open_time": null,
        "close_time": null
      }
    ],
    "special_hours": []
  }
}
```

### `GET /restaurant-day-availability`

Fetch effective availability for one date. Special hours override weekly hours.

Auth: required.

Query params:

```text
date required YYYY-MM-DD
```

Example response:

```json
{
  "success": true,
  "data": {
    "date": "2026-05-29",
    "weekday": 4,
    "source": "weekly",
    "is_open": true,
    "open_time": "17:00:00",
    "close_time": "21:30:00",
    "reason": null,
    "slot_interval_minutes": 15,
    "max_online_party_size": 8,
    "minimum_lead_time_minutes": 60
  }
}
```

### `PATCH /restaurant-day-availability`

Create or update a special-day override.

Auth: required.

Query params:

```text
date required YYYY-MM-DD
```

Example request:

```json
{
  "is_open": true,
  "open_time": "17:00",
  "close_time": "20:30",
  "reason": "Short hours"
}
```

Example response:

```json
{
  "success": true,
  "data": {
    "date": "2026-05-29",
    "weekday": 4,
    "source": "special",
    "is_open": true,
    "open_time": "17:00:00",
    "close_time": "20:30:00",
    "reason": "Short hours",
    "slot_interval_minutes": 15,
    "max_online_party_size": 8,
    "minimum_lead_time_minutes": 60
  }
}
```

### `GET /reservation-slots`

Public-safe slot list for the website reservation form.

Auth: public.

Query params:

```text
date required YYYY-MM-DD
```

No capacity logic, reservation-count blocking, guest PII, or staff-only blocked-slot reasons are included.

`close_time` is not the last bookable reservation time. The final bookable reservation start is `close_time - 30 minutes`.

For Friday 17:00-21:30 with 15-minute slots, the first slot is `17:00` / `5:00 PM`, the last slot is `21:00` / `9:00 PM`, and neither `21:15` nor `21:30` is bookable.

After generating slots from the effective weekly/special hours, the endpoint removes any matching rows from `{prefix}tryzub_restaurant_blocked_slots`.

Open example:

```json
{
  "success": true,
  "date": "2026-05-29",
  "is_open": true,
  "slots": [
    {
      "value": "17:00",
      "label": "5:00 PM"
    },
    {
      "value": "17:15",
      "label": "5:15 PM"
    }
  ],
  "message": null
}
```

Closed example:

```json
{
  "success": true,
  "date": "2026-05-29",
  "is_open": false,
  "slots": [],
  "message": "Reservations are not available for this date."
}
```

### `GET /restaurant-blocked-slots`

Fetch staff-managed blocked slots for one date.

Auth: required.

Query params:

```text
date required YYYY-MM-DD
```

Example response:

```json
{
  "success": true,
  "date": "2026-05-28",
  "data": [
    {
      "id": 1,
      "reservation_date": "2026-05-28",
      "slot_time": "18:00",
      "reason": "Held for manual booking",
      "created_by_user_id": 9,
      "created_at": "2026-05-28 12:00:00"
    }
  ]
}
```

### `POST /restaurant-blocked-slots`

Block specific generated reservation slots for one date.

Auth: required.

Example request:

```json
{
  "date": "2026-05-28",
  "slots": ["18:00", "18:15"],
  "reason": "Held for manual booking"
}
```

Rules:

```text
date must be YYYY-MM-DD
slots must be a non-empty array
maximum 100 slots per request
slot times must be valid 15-minute boundary times
slot times must match generated slots for that date
duplicate blocks do not error
unknown fields are rejected
```

After this example, public `/reservation-slots?date=2026-05-28` removes `18:00` and `18:15`; `18:30` and later generated slots remain available.

### `DELETE /restaurant-blocked-slots`

Remove blocked slots.

Auth: required.

Delete specific slots:

```json
{
  "date": "2026-05-28",
  "slots": ["18:00", "18:15"]
}
```

Delete all blocked slots for a date:

```text
DELETE /restaurant-blocked-slots?date=2026-05-28
```

### `GET /restaurant-tables`

Fetch active and inactive floor layout table definitions for staff setup.

Auth: required.

Example response:

```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "restaurant_key": "tryzub",
      "table_key": "T1",
      "label": "1",
      "x": 0,
      "y": 0,
      "width_units": 1,
      "height_units": 1,
      "min_capacity": 1,
      "max_capacity": 4,
      "section": "main",
      "sort_order": 1,
      "is_active": true,
      "created_at": "2026-06-10 12:00:00",
      "updated_at": "2026-06-10 12:00:00"
    }
  ]
}
```

### `PUT /restaurant-tables`

Upsert floor layout table definitions.

Auth: required.

Upsert contract:

```text
upsert_mode = partial_by_table_key
only provided table_key rows are inserted or updated
omitted tables are NOT deleted or auto-deactivated
unknown fields are rejected
duplicate table_key in one request is rejected
overlapping x/y cells are rejected
inactive tables are allowed but cannot receive new assignments
table_key is the stable identity used by assignments
```

Example request:

```json
{
  "tables": [
    {
      "table_key": "T1",
      "label": "1",
      "x": 0,
      "y": 0,
      "width_units": 1,
      "height_units": 1,
      "min_capacity": 1,
      "max_capacity": 4,
      "section": "main",
      "sort_order": 1,
      "is_active": true
    }
  ]
}
```

Example response:

```json
{
  "success": true,
  "upsert_mode": "partial_by_table_key",
  "contract_note": "Upserts only the provided table_key rows. Omitted tables are not deleted or auto-deactivated.",
  "data": []
}
```

No default floor layout is seeded on activation. iOS/setup tooling creates the first layout.

### `GET /floor-plan?date=YYYY-MM-DD`

Fetch tables, assignments, and reservations for one service date.

Auth: required.

Query params:

```text
date required YYYY-MM-DD
```

Behavior:

```text
calls tryzub_complete_past_active_reservations() before read so floor-plan status matches managed-reservations list behavior
returns active tables only
excludes hidden reservations
does not expose guest intelligence
```

Example response:

```json
{
  "success": true,
  "date": "2026-06-13",
  "server_time": "2026-06-10 12:00:00",
  "tables": [],
  "assignments": [
    {
      "reservation_id": 4007,
      "reservation_date": "2026-06-13",
      "table_keys": ["T4"],
      "table_label": "4",
      "assigned_at": "2026-06-10 12:00:00",
      "updated_at": "2026-06-10 12:00:00"
    }
  ],
  "reservations": []
}
```

`reservations[]` uses the normal managed reservation DTO shape.

### `PATCH /managed-reservations/{id}/tables`

Assign or clear tables for one reservation.

Auth: required.

Assign:

```json
{ "table_keys": ["T4", "T5"] }
```

Clear:

```json
{ "table_keys": [] }
```

Optional concurrency field (recommended): `expected_updated_at` = the reservation's last-seen `row_version`. A stale value returns `409 tryzub_reservation_conflict` (same shape as the PATCH endpoint).

Rules:

```text
reservation must exist
hidden reservations cannot be assigned
cancelled, completed, and no_show cannot receive NEW assignments
clearing tables on terminal rows is allowed
table keys must exist and be active
duplicate keys in one request are rejected
assignments replace atomically inside a transaction
reservation.table_name compatibility field is updated
empty assignment sets table_name to null
one table uses label or table_key
multiple tables join labels with " + "
```

Conflict blocking:

```text
same reservation_date
another active reservation already has the same table_key at the same reservation_time
statuses new, needs_review, confirmed block by same time
status seated blocks the table for the entire service date
cancelled, completed, no_show do not block
```

Conflict response (`409`):

```json
{
  "success": false,
  "code": "tryzub_table_assignment_conflict",
  "message": "Table is already assigned for this time or currently seated.",
  "conflicts": [
    {
      "reservation_id": 4001,
      "guest_name": "Daniil",
      "reservation_time": "19:00:00",
      "table_key": "T4",
      "table_label": "4",
      "status": "seated",
      "reason": "table_already_seated"
    }
  ]
}
```

Success (response includes `server_time`):

```json
{
  "success": true,
  "server_time": "2026-06-10 12:00:00",
  "data": {
    "reservation": {},
    "assignment": {
      "reservation_id": 4007,
      "reservation_date": "2026-06-13",
      "table_keys": ["T4"],
      "table_label": "4",
      "assigned_at": "2026-06-10 12:00:00",
      "updated_at": "2026-06-10 12:00:00"
    }
  }
}
```

Race hardening:

```text
all assignments for one service date are serialized with a MySQL advisory lock (GET_LOCK)
assignment write runs in a transaction
matching assignment rows are locked with SELECT ... FOR UPDATE
conflicts are rechecked immediately before replace
```

If the per-date advisory lock cannot be acquired quickly (another device is mid-assignment), the API returns `409 tryzub_floor_plan_locked`; the client should simply retry. The advisory lock closes the previous residual race where two devices could assign the same brand-new table to two different reservations at the same instant.

iOS should treat the server response as source of truth and not invent floor layout locally.

## Public Reservation Form Slot Sync

The live public website currently uses 15-minute reservation slots and this schedule:

```text
Monday closed
Tuesday 17:00-21:00
Wednesday 17:00-21:00
Thursday 17:00-21:00
Friday 17:00-22:00
Saturday 11:00-22:00
Sunday 11:00-21:00
```

On the new `/book-table` page, wrap the Contact Form 7 form in `#tryzub-booking-v2` to enable the chip UI. The form still submits through CF7; the existing submitted fields remain `text-446` for date, `text-196` for time, and `text-139` for party size.

The public JS also ensures a hidden `tryzub_client_request_id` field exists once per form load. The value remains stable for that page/form instance and lets the backend skip duplicate operational imports if CF7/Flamingo receives repeated submits.

The public Contact Form 7 reservation form now tries `GET /reservation-slots?date=YYYY-MM-DD` first after a valid date is selected. When the backend responds, it is the preferred source for time chips, including special closed days, special short-hours days from `/restaurant-day-availability`, and specific date/time blocks from `/restaurant-blocked-slots`.

If the backend says the selected date is closed, the form shows `Reservations are not available for this date.` and leaves no selectable time. Closed special days return `slots: []`.

If the backend request fails or is unavailable, the existing hardcoded JavaScript schedule remains the fallback. Backend failure should not break the form; customers simply see the fallback 15-minute times.

Time chips display the backend `slot.label`, such as `5:00 PM`, but submit the backend `slot.value`, such as `17:00`, into CF7 field `text-196`. Party-size chips submit the selected number into CF7 field `text-139`. Party-size setup uses the public inline reservation setup when available, then safely falls back to `1-8`, default `2`, and large-party threshold `7`.

Normal upgrades do not destructively overwrite existing restaurant setup or weekly hours rows. If an existing staging/live database still has older pilot defaults, staff should update through the iOS app or use authenticated REST PATCH calls:

```json
{
  "slot_interval_minutes": 15
}
```

```json
{
  "weekly_hours": [
    { "weekday": 0, "is_open": false, "open_time": null, "close_time": null },
    { "weekday": 1, "is_open": true, "open_time": "17:00:00", "close_time": "21:00:00" },
    { "weekday": 2, "is_open": true, "open_time": "17:00:00", "close_time": "21:00:00" },
    { "weekday": 3, "is_open": true, "open_time": "17:00:00", "close_time": "21:00:00" },
    { "weekday": 4, "is_open": true, "open_time": "17:00:00", "close_time": "22:00:00" },
    { "weekday": 5, "is_open": true, "open_time": "11:00:00", "close_time": "22:00:00" },
    { "weekday": 6, "is_open": true, "open_time": "11:00:00", "close_time": "21:00:00" }
  ]
}
```

### `GET /reservation-analytics/summary`

Protected aggregate owner/iOS report for linked, non-spam Flamingo-backed managed reservations.

Auth: required.

Query params:

```text
from optional YYYY-MM-DD
to   optional YYYY-MM-DD
```

The response excludes guest names, phones, emails, notes, and raw payloads.

Example response:

```json
{
  "success": true,
  "range": {
    "from": "2026-05-08",
    "to": "2026-05-27"
  },
  "summary": {
    "reservations_count": 151,
    "guests_count": 494,
    "avg_party_size": 3.27,
    "first_reservation_date": "2026-05-08",
    "last_reservation_date": "2026-05-27",
    "first_submission_date": "2026-05-01 12:00:00",
    "last_submission_date": "2026-05-27 10:00:00"
  },
  "by_status": [],
  "by_month": [],
  "by_weekday": [],
  "by_hour": [],
  "by_party_size": [],
  "lead_time_buckets": [],
  "field_completeness": {},
  "pipeline_health": {
    "flamingo_inbound_total": 176,
    "managed_rows_with_source_submission_id": 151,
    "missing_non_spam_flamingo": 25
  }
}
```

Legacy `pipeline_health.missing_non_spam_flamingo` is coarse. For developer reconciliation, use `GET /intelligence/reservation-pipeline-diagnostics` or `pipeline_diagnostics.summary` inside `GET /intelligence/system-status`.

## Intelligence Layer

Detailed contract, privacy rules, matching logic, and iOS guidance live in `INTELLIGENCE.md`.

Protected intelligence endpoints:

```text
GET /business-intelligence/summary?from=YYYY-MM-DD&to=YYYY-MM-DD
GET /guest-intelligence?date=YYYY-MM-DD
GET /guest-intelligence/reservation/{id}
GET /intelligence/system-status?from=YYYY-MM-DD&to=YYYY-MM-DD
GET /intelligence/reservation-pipeline-diagnostics?from=YYYY-MM-DD&to=YYYY-MM-DD
```

All intelligence routes:

```text
require manage_tryzub_reservations or manage_options
are read-only GET
return success + data
use private, no-store cache headers
```

### `GET /guest-intelligence?date=YYYY-MM-DD`

Compact per-reservation guest memory for Host Board on one service date.

Use for:

```text
seen_before
safe_copy
signals
has_history_preview
has_prior_notes
profile_endpoint
```

Does not return full historical visit previews. Use the reservation profile endpoint for detail views.

### `GET /guest-intelligence/reservation/{id}`

Server-backed guest profile intelligence pack for Reservation Detail, Guest Insights, and Guest tab profile views.

Adds management-ready sections without requiring iOS to download full reservation history:

```text
history.matched_visit_preview
profile_summary
preferences
note_intelligence
visit_analytics
host_profile_packet
```

Existing top-level fields remain:

```text
identity
history.seen_before
history.prior_visit_count
history.last_seen_date
history.safe_copy
signals
item
debug
```

### `GET /intelligence/system-status?from=YYYY-MM-DD&to=YYYY-MM-DD`

Operational health summary for managers and developers.

Includes:

```text
manager_summary
developer_summary
checks
warnings
pipeline_diagnostics.summary
pipeline_diagnostics.manager_message
pipeline_diagnostics.developer_message
```

Does not treat every missing managed row as a live operational problem.

### `GET /intelligence/reservation-pipeline-diagnostics?from=YYYY-MM-DD&to=YYYY-MM-DD`

Developer/staff diagnostics for Flamingo intake vs managed reservation reconciliation.

Scans all `flamingo_inbound` posts in intake-date range, distinguishes reservation-intake CF7 forms from other Flamingo forms, and classifies each submission.

Optional query params:

```text
include_items=0|1          default 1
classification=...         optional item filter
page                       default 1
per_page                   default 100, max 500
```

Top-level fields iOS developer mode should use:

```text
manager_message    non-alarming staff summary string
developer_message  technical gap-count sentence
items_meta         { total_items, filtered_items, page, per_page, has_more }
warnings           array of machine-readable strings
```

Summary fields iOS should use:

```text
flamingo_inbound_total
flamingo_non_spam_total
reservation_intake_total
reservation_intake_non_spam_total
managed_active_with_source
managed_hidden_with_source
managed_terminal_with_source
failed_imports
duplicate_imports
hard_deleted
unexplained_missing
spam_or_rejected
non_reservation_form
form_source_unknown
manual_rows_without_flamingo_source   (canonical)
manual_without_source                 (deprecated alias)
non_spam_reservation_intake_without_active_managed_row
explained_missing_submissions
unexplained_missing_submissions
```

Does not expose raw Flamingo payload, raw notes, email bodies, or phone numbers.

### `GET /managed-reservations`

List managed reservations from `{prefix}tryzub_reservations`.

Auth: required.

Query params:

```text
page
per_page     max 100
date         valid reservation date
from         valid reservation date
to           valid reservation date
status       new, needs_review, confirmed, seated, completed, cancelled, no_show
search       matches guest_name, email, or phone
include_hidden  optional, 1 shows soft-hidden rows
updated_since   optional YYYY-MM-DD HH:mm:ss or ISO8601 timestamp
```

Normal list requests hide rows where `is_hidden = 1`. `GET /managed-reservations/{id}` can still fetch a hidden row by ID for reconciliation/detail/admin use.

When `updated_since` is provided, the response includes rows where `updated_at >= updated_since` or `created_at >= updated_since`, using the same filters for hidden/cancelled rows as normal list requests.

Response:

```json
{
  "success": true,
  "server_time": "2026-06-04 12:00:00",
  "page": 1,
  "per_page": 100,
  "total": 0,
  "total_pages": 0,
  "data": []
}
```

### `DELETE /managed-reservations/{id}?force=1`

Permanently delete a managed reservation for admin/developer test cleanup.

Auth: `manage_options` required. The normal `manage_tryzub_reservations` staff capability is not enough.

Rules:

```text
Soft hide remains the normal staff workflow.
Confirmed, seated, completed, and no_show rows require force=1.
An audit row is written before deletion.
Raw Flamingo posts and email logs are preserved.
```

Optional body:

```json
{
  "reason": "Test cleanup after deploy rehearsal"
}
```

Success:

```json
{
  "success": true,
  "deleted_id": 123,
  "message": "Reservation permanently deleted."
}
```

### `POST /managed-reservations/{id}/guest-manage-link`

Generate a guest self-service manage link for staff to paste into the manual Gmail confirmation flow.

Auth: required.

The backend stores only the token hash. Because the raw token is not recoverable, this endpoint creates a fresh link and revokes previous active manage tokens for that reservation.

Example response:

```json
{
  "success": true,
  "data": {
    "url": "https://tryzubchicago.com/manage-reservation/?token=RAW_TOKEN",
    "expires_at": "2026-07-04 12:00:00"
  }
}
```

The backend does not send email from this endpoint.

### `GET /reservation-self?token=...`

Public token-protected guest-safe reservation card data.

Auth: public token.

Returns only guest-safe fields:

```json
{
  "success": true,
  "data": {
    "restaurant_name": "Tryzub Ukrainian Kitchen",
    "guest_name": "Ihor",
    "reservation_date": "2026-06-04",
    "reservation_time": "17:00",
    "party_size": 3,
    "guest_notes": "2 adults and baby",
    "status": "needs_review",
    "can_request_change": true,
    "can_request_cancel": true
  }
}
```

Never returned:

```text
managed reservation ID
source_submission_id
phone
email
staff_notes
hidden metadata
deletion metadata
duplicate/correction warnings
raw Flamingo payload
diagnostics
token hash
raw DB row
```

Invalid, expired, revoked, or hidden-row tokens return a safe invalid/expired response.

### `POST /reservation-self/change-request`

Guest self-service change request.

Auth: public token.

Example:

```json
{
  "token": "RAW_TOKEN",
  "reservation_date": "2026-06-06",
  "reservation_time": "18:30",
  "party_size": 4,
  "guest_notes": "Correct date"
}
```

Behavior:

```text
Validates date, time, and party size.
Creates a tryzub_reservation_guest_requests row with status open.
Marks the reservation needs_review.
Appends staff note: Guest requested a reservation change from self-service link.
Does not silently overwrite reservation date/time/party fields.
Rejects cancelled, seated, completed, and no_show reservations.
```

### `POST /reservation-self/cancel`

Guest self-service cancellation request.

Auth: public token.

Example:

```json
{
  "token": "RAW_TOKEN",
  "reason": "Optional guest reason"
}
```

Behavior:

```text
new, needs_review, and confirmed reservations may be cancelled online until 2 hours before reservation time.
Same-day cancellation is allowed if the reservation is still more than 2 hours away.
Less than 2 hours before reservation time, online cancellation is rejected with a safe call/contact message.
cancelled, seated, completed, and no_show reservations cannot be cancelled from the guest link.
Hidden reservations are not manageable from a guest token.
Every valid cancellation attempt creates a tryzub_reservation_guest_requests row.
Successful online cancellation sets status cancelled and appends staff note: Guest cancelled reservation from self-service link.
Rejected/too-late cancellation attempts do not change operational reservation status.
```

### `GET /managed-reservations/{id}`

Fetch one managed reservation by managed table ID.

Auth: required.

Used by iOS after uncertain PATCH/network failures to reconcile server state.

Success:

```json
{
  "success": true,
  "data": {
    "id": 85,
    "guest_name": "Name"
  }
}
```

Missing reservation returns `WP_Error` with code:

```text
tryzub_reservation_not_found
```

### `PATCH /managed-reservations/{id}`

Update one managed reservation.

Auth: required.

Allowed editable fields:

```text
guest_name
email
phone
reservation_date
reservation_time
party_size
guest_notes
staff_notes
status
table_name
superseded_by_id
is_hidden
hidden_reason
```

Optional concurrency field (recommended for multi-device):

```text
expected_updated_at   the row_version the client last saw (see Optimistic Concurrency below)
```

Rules:

```text
Unknown fields are rejected (expected_updated_at is accepted and not treated as an editable column).
Status must be one of the allowed statuses.
Status changes must follow the allowed transition map (see Status Lifecycle below).
Phone is normalized to digits.
Date is normalized to YYYY-MM-DD.
Time is normalized to HH:mm:ss.
Party size must be positive and within the pilot limit.
updated_at changes on success.
confirmed_at is set when status becomes confirmed and confirmed_at is empty.
seated_at is set the first time status becomes seated.
completed_at is set the first time status becomes completed.
Generic PATCH does not send confirmation email.
PATCH is_hidden=true soft hides a wrong row and records hidden_at/hidden_by_user_id.
PATCH is_hidden=false restores a soft-hidden row and clears hide metadata.
If expected_updated_at is sent and no longer matches the current row_version, the write is rejected with 409.
```

Success (response includes `server_time`; DTO includes `row_version`):

```json
{
  "success": true,
  "server_time": "2026-06-10 12:00:00",
  "data": {
    "id": 85,
    "status": "confirmed",
    "seated_at": null,
    "completed_at": null,
    "updated_at": "2026-06-10 12:00:00",
    "row_version": "2026-06-10 12:00:00"
  }
}
```

Conflict (HTTP 409) when `expected_updated_at` is stale:

```json
{
  "success": false,
  "code": "tryzub_reservation_conflict",
  "message": "This reservation was changed on another device. Reload the latest version before saving.",
  "expected_updated_at": "2026-06-10 11:59:00",
  "current_version": "2026-06-10 12:00:30",
  "server_time": "2026-06-10 12:00:45",
  "data": { "id": 85 }
}
```

Common errors:

```text
tryzub_reservation_not_found
tryzub_unknown_update_field
tryzub_invalid_status
tryzub_invalid_status_transition   (HTTP 409, includes from/to/allowed_transitions)
tryzub_reservation_conflict        (HTTP 409, stale expected_updated_at)
tryzub_invalid_date
tryzub_invalid_time
tryzub_invalid_party_size
tryzub_no_update_fields
tryzub_database_error
```

### Optimistic Concurrency (multi-device safe writes)

Every managed reservation DTO includes a `row_version` field. It equals `updated_at`, or `created_at` for rows that have never been updated. It is the token the client uses to detect that another device changed the reservation first.

How iOS should use it:

```text
1. Read a reservation (list, single GET, floor-plan). Store its row_version.
2. When the user saves an edit, send expected_updated_at = the stored row_version.
3. If the server returns 200, take the new row_version from the response DTO.
4. If the server returns 409 tryzub_reservation_conflict, the row changed elsewhere:
   show the returned data (current server state), let the user re-apply their change,
   then retry with the new current_version.
```

Endpoints that honor `expected_updated_at`:

```text
PATCH  /managed-reservations/{id}
DELETE /managed-reservations/{id}
PATCH  /managed-reservations/{id}/tables
POST   /managed-reservations/{id}/confirm
```

Backward compatibility: `expected_updated_at` is optional. Requests that omit it keep working with last-write-wins behavior, so older iOS builds are not broken. New builds should always send it for staff edits.

All write responses now include `server_time` (MySQL `Y-m-d H:i:s`, restaurant timezone) so the client can correct clock skew when comparing timestamps.

### Status Lifecycle (allowed transitions)

`status` changes are validated against an allowed-transition map. A no-op (same status) is always allowed. Disallowed moves return `409 tryzub_invalid_status_transition` with `from`, `to`, and `allowed_transitions`.

```text
new           -> needs_review, confirmed, seated, completed, cancelled, no_show
needs_review  -> new, confirmed, seated, completed, cancelled, no_show
confirmed     -> new, needs_review, seated, completed, cancelled, no_show
seated        -> confirmed, completed, cancelled, no_show
completed     -> seated, confirmed                 (reopen a prematurely completed booking)
cancelled     -> new, needs_review, confirmed       (un-cancel)
no_show       -> new, needs_review, confirmed, seated
```

Lifecycle timestamps are stamped once on first entry into a status: `confirmed_at`, `seated_at`, `completed_at`. The automatic past-date sweep also sets `completed_at` when it completes a stale active reservation.

### `POST /managed-reservations`

Create a manual reservation from iOS/staff tooling.

Auth: required.

Body fields:

```text
source_type optional
source_submission_id optional
guest_name required
email required for form/import_repair, optional for manual call-ins/walk-ins/known guests
phone required
reservation_date required
reservation_time required
party_size required
guest_notes optional
staff_notes optional
status optional
table_name optional
created_by_device optional
```

If `source_submission_id` is supplied, it must point to a Flamingo inbound post and must not already have a managed reservation.

Allowed `source_type` values:

```text
form
manual_call_in
manual_walk_in
known_guest_manual
import_repair
```

Defaults:

```text
No source_submission_id: manual_call_in
With source_submission_id: import_repair
Imported CF7 rows: form
```

Manual call-ins, walk-ins, and known guest manual rows live in the main managed table. They do not use a separate table. If email is blank for those manual source types, the backend stores the configured call-in placeholder internally and returns `email: ""` in the DTO.

Manual creates do not send confirmation email. For the MVP manual Gmail/Mail flow, generate a guest manage link, draft/send in the external email client from iOS, then call `POST /managed-reservations/{id}/manual-email-log`. To confirm without email, PATCH `status=confirmed`. The `/confirm` endpoint remains available as the backend/provider email backup path.

Success status: `201`.

```json
{
  "success": true,
  "data": {
    "id": 90,
    "source_submission_id": null
  }
}
```

### `POST /managed-reservations/import`

Manual/admin import trigger.

Auth: required.

Normal iOS refresh should not call this endpoint. Backend auto-import runs after Flamingo saves a CF7 submission.

Response:

```json
{
  "success": true,
  "has_errors": true,
  "imported": 0,
  "skipped": 88,
  "failed": 1,
  "total_checked": 89,
  "errors": [
    {
      "source_submission_id": 357,
      "error_code": "tryzub_import_missing_required_fields",
      "error_message": "Required reservation fields are missing."
    }
  ]
}
```

`success` means the import job executed. `has_errors` means one or more source submissions failed validation/import and were recorded as operational failed-import records.

### `GET /managed-reservations/import-failures`

List failed import records.

Auth: required.

Query params:

```text
page
per_page max 100
```

Response:

```json
{
  "success": true,
  "page": 1,
  "per_page": 50,
  "total": 1,
  "total_pages": 1,
  "data": [
    {
      "id": 1,
      "source_submission_id": 357,
      "error_code": "tryzub_import_missing_required_fields",
      "error_message": "Required reservation fields are missing.",
      "reservation": {},
      "raw_fields": {},
      "raw_payload": {},
      "submitted_at": "2026-05-14 20:07:55",
      "submission_status": "mail_sent",
      "status": "open",
      "created_at": "2026-05-19 12:00:00"
    }
  ]
}
```

### `POST /managed-reservations/{id}/confirm`

Business action endpoint: confirm reservation and attempt backend/provider confirmation email.

Auth: required.

This is intentionally separate from generic PATCH.

This is the backend/provider email confirmation path. It may call Postmark or `wp_mail` and can send a real backend email. It remains available as the legacy/backup provider email flow.

Provider note:

```text
Define TRYZUB_POSTMARK_TOKEN or use the tryzub_postmark_token filter to send through Postmark.
If no Postmark token is present, the plugin falls back to wp_mail.
Do not hardcode provider tokens in plugin files.
```

Flow:

```text
Load reservation.
Reject cancelled, no_show, completed.
Set status confirmed if needed.
Set confirmed_at if empty.
Send confirmation email through Postmark when configured, otherwise wp_mail.
Log email attempt.
Set confirmation_email_sent_at only when email sends.
Return updated reservation.
```

Success with email sent:

```json
{
  "success": true,
  "email_status": "sent",
  "email_error": null,
  "data": {}
}
```

Success with email failure:

```json
{
  "success": true,
  "email_status": "failed",
  "email_error": "wp_mail failed",
  "data": {}
}
```

If already confirmed and a confirmation email was already sent or logged:

```json
{
  "success": true,
  "email_status": "already_sent",
  "message": "already_confirmed",
  "data": {}
}
```

### `POST /managed-reservations/{id}/manual-email-log`

Manual Gmail/Mail tracking path for the iOS pilot flow.

Auth: required.

This endpoint does not send email. It does not call `wp_mail`, Postmark, or any other provider. It records what staff/iOS says happened in an external email client.

iOS should call this endpoint after staff sends or prepares the Gmail/Mail confirmation draft. `draft_created` does not mean delivered. `manual_sent` means staff reported/sent through external Mail/Gmail. The backend records `manual_sent`, but it cannot prove inbox delivery.

Request body:

```json
{
  "email_type": "confirmation",
  "status": "draft_created",
  "to_email": "guest@example.com",
  "subject": "Reservation Confirmation - Tryzub Ukrainian Kitchen",
  "body_snapshot": "optional email body snapshot or short text",
  "provider": "manual_gmail",
  "provider_message_id": null,
  "error_message": null
}
```

Allowed values:

```text
email_type: confirmation, cancellation, reminder, custom
status: draft_created, manual_sent, manual_failed, skipped
provider: external manual provider string starting with manual_, default manual_gmail
```

Behavior:

```text
Reservation ID must exist.
Unknown request fields are rejected.
to_email must be valid if provided.
subject is optional and whitespace-normalized.
body_snapshot is optional, token-scrubbed, and size-limited.
Raw guest manage tokens should not be stored in email logs.
sent_at is set only when status is manual_sent.
manual_sent for email_type confirmation sets confirmation_email_sent_at only if it is currently null.
draft_created does not set confirmation_email_sent_at.
Reservation status is not changed by this endpoint.
```

Success:

```json
{
  "success": true,
  "data": {
    "reservation_id": 123,
    "email_type": "confirmation",
    "status": "manual_sent",
    "provider": "manual_gmail",
    "confirmation_email_sent_at": "2026-06-06 18:30:00"
  }
}
```

Manual email log checklist:

1. Create test reservation with guest email.
2. Generate guest manage link.
3. Call `POST /managed-reservations/{id}/manual-email-log` with status `draft_created`.
4. Confirm email log row is created.
5. Confirm `confirmation_email_sent_at` remains null.
6. Call endpoint with status `manual_sent`.
7. Confirm second email log row is created.
8. Confirm `confirmation_email_sent_at` is set if it was null.
9. Confirm no actual email was sent by backend.
10. Confirm invalid email is rejected.
11. Confirm unauthorized user gets 401/403.
12. Confirm existing backend `/confirm` endpoint still works unchanged.

### `POST /managed-reservations/send-due-reminders`

Admin/debug trigger for reminder job.

Auth: required.

Finds confirmed reservations due within the next 3 hours where `reminder_email_sent_at IS NULL`.

Idempotency:

```text
If reminder_email_sent_at is set, no duplicate reminder is sent.
Email attempts are logged.
Failed reminders leave reminder_email_sent_at null so a later run may retry.
```

Response:

```json
{
  "success": true,
  "result": {
    "sent": 0,
    "failed": 0,
    "skipped": 0,
    "checked": 0
  }
}
```

The same reminder function is also attached to a WordPress hourly cron hook.

### `GET /reservations`

Legacy/raw-ish Flamingo debugging endpoint.

Auth: required.

Do not use this for normal iOS staff workflow.

## Auto Import

Auto-import hook:

```php
add_action('wpcf7_after_flamingo', 'tryzub_import_after_flamingo_submission', 20, 1);
```

The hook imports after Flamingo saves a CF7 inbound post. The same import logic is used by the manual import endpoint, so behavior stays consistent.

Idempotency:

```text
source_submission_id unique key prevents duplicate managed rows.
Same Flamingo post imports once.
tryzub_client_request_id prevents duplicate operational rows when the same page/form instance submits twice.
submission_fingerprint catches identical operational submissions inside a 5-minute window.
Skipped duplicate imports are written to tryzub_reservation_duplicate_imports.
Same guest/contact/date with changed time, party size, or notes creates a new managed row and may mark both rows needs_review.
Import does not depend on iOS.
```

## Failed Imports

Failed imports are operational, not just debug.

A bad submission should result in:

```text
Raw Flamingo message remains inspectable.
Failed import row is created or updated.
GET /managed-reservations/import-failures shows the problem.
iOS can show the raw/attempted data to staff/developer.
Staff can create a corrected manual reservation and link source_submission_id.
```

## Soft Hide

Wrong manual entries are not permanently deleted.

Use:

```text
PATCH /managed-reservations/{id}
```

Body:

```json
{
  "is_hidden": true,
  "hidden_reason": "Wrong call-in entry"
}
```

Normal `GET /managed-reservations` filters hidden rows out. Authorized users can include them with:

```text
GET /managed-reservations?include_hidden=1
```

`GET /managed-reservations/{id}` still returns a hidden row by ID.

## Hard Delete

Hard delete is only for admin/developer cleanup of test rows.

Use:

```text
DELETE /managed-reservations/{id}?force=1
```

Rules:

```text
Requires manage_options.
Normal reservation staff cannot hard delete.
Writes tryzub_reservation_deletion_audit before deleting.
Does not delete the raw Flamingo post.
Does not delete email logs.
Confirmed, seated, completed, and no_show rows require force=1.
```

Staff cleanup should continue to use soft hide.

## Email Behavior

Email remains backup during the pilot, but backend provider sending is not the primary MVP confirmation path.

Current direction:

```text
iOS/staff generate confirmation text and use the restaurant Gmail/manual flow.
Backend exposes reservation data and the guest manage link.
Backend confirmation/reminder endpoints remain for compatibility and backup.
Do not redesign provider sending in this pass.
```

Confirmation email:

```text
POST /managed-reservations/{id}/confirm
```

Generic PATCH does not send email.

Email attempts are written to `{prefix}tryzub_reservation_emails` with provider, status, error message, and optional provider message ID. A sent log means the backend/provider accepted the attempt; it does not prove inbox delivery.

Manual call-ins/walk-ins with no guest email are skipped for email and logged as `skipped` if the confirm endpoint is called.

Reminder email:

```text
tryzub_send_due_reservation_reminders()
POST /managed-reservations/send-due-reminders
WP-Cron hourly hook
```

Reply behavior for MVP:

```text
Reply-To: reservations@tryzubchicago.com
Staff handles replies manually.
```

Future inbound reply plan:

```text
Use Postmark, SendGrid, or Mailgun inbound parse.
POST /wp-json/tryzub/v1/email/inbound
Authenticate provider webhook with a secret.
Attach inbound message by reply_token or reservation ID in subject.
Store raw payload in tryzub_reservation_messages.
iOS shows unread guest replies.
```

## iOS Contract

iOS should:

```text
Fetch GET /managed-reservations for refresh (optionally with updated_since for incremental sync).
Cache decoded rows in SwiftData, including row_version per reservation.
Use SwiftData only as local cache.
Use server as source of truth.
Call GET /managed-reservations/{id} after uncertain PATCH/network failures.
Call PATCH /managed-reservations/{id} for edits, sending expected_updated_at = last-seen row_version.
Handle 409 tryzub_reservation_conflict by refreshing to the returned server state, then retrying.
Handle 409 tryzub_invalid_status_transition by respecting the returned allowed_transitions.
Persist row_version from every write response (it advances on success).
Call POST /managed-reservations for manual_call_in, manual_walk_in, known_guest_manual, and import_repair reservations.
Hide wrong manual rows with PATCH is_hidden, not DELETE.
Read GET /managed-reservations/import-failures for backend/form problems.
Use POST /managed-reservations/{id}/guest-manage-link when building manual Gmail confirmations.
Call POST /managed-reservations/{id}/confirm only if staff intentionally uses the legacy/backend email flow.
Use GET /floor-plan?date=... for shared floor state on the selected service date.
Use PUT /restaurant-tables for floor layout setup.
Use PATCH /managed-reservations/{id}/tables for server-confirmed table assignment/clear.
Use GET /guest-intelligence?date=... for Host Board guest memory on the selected date.
Use GET /guest-intelligence/reservation/{id} for Reservation Detail / Guest Insights profile truth.
Use GET /intelligence/system-status for manager/developer health summaries.
Use GET /intelligence/reservation-pipeline-diagnostics for developer intake reconciliation details.
```

iOS should not:

```text
Call POST /managed-reservations/import during normal refresh.
Treat SwiftData as the source of truth.
Read raw Flamingo for normal staff workflows.
Depend on backend provider email sending as the primary MVP confirmation path.
Invent floor layout locally without backend confirmation.
Infer returning-guest history from local cache alone when guest intelligence is available.
Treat every missing managed row in diagnostics as a broken production state.
Send blind status changes that skip the allowed transition map.
Overwrite a reservation without expected_updated_at when another device may have edited it.
```

## Backend Idempotency / Duplicate Protection

Public frontend duplicate protection is helpful, but the backend enforces the operational rule.

The public CF7 form includes:

```text
tryzub_client_request_id
```

This value is generated once per page/form instance and is stable across submit attempts from that loaded page.

Importer order:

```text
1. If source_submission_id already exists, skip.
2. If client_request_id already belongs to a managed row, skip and log duplicate.
3. Build submission_fingerprint from normalized guest/date/time/party/notes data.
4. If the same fingerprint exists within 5 minutes of the Flamingo submission timestamp, skip and log duplicate.
5. Otherwise insert a managed operational row.
```

Fingerprint fields:

```text
lowercased trimmed guest_name
lowercased trimmed email
phone digits only
reservation_date YYYY-MM-DD
reservation_time HH:mm:ss
party_size integer
guest_notes trimmed/collapsed whitespace
```

Identical duplicates do not create second active rows. Corrections with changed time/date/party/notes remain separate and go through the existing `needs_review` workflow.

## Duplicate / Correction Workflow

When a new imported reservation has the same date and same email or phone as an active row, the importer does not delete or merge anything automatically.

Instead:

```text
New row is inserted.
New row is marked needs_review.
Older active row is also marked needs_review.
staff_notes point to the related reservation ID.
```

Staff decides which one to keep in iOS.

Suggested pilot workflow:

```text
Open both reservations.
Keep the correct reservation active.
Cancel the duplicate.
Set superseded_by_id on the duplicate if useful.
Add staff_notes explaining the decision.
```

## Guest Self-Service Token Flow

Shortcode:

```text
[tryzub_manage_reservation]
```

Expected page:

```text
https://tryzubchicago.com/manage-reservation/?token=RAW_TOKEN
```

Flow:

```text
Staff/iOS calls POST /managed-reservations/{id}/guest-manage-link.
Backend creates a raw token, stores only token_hash, and returns the manage URL once.
Staff includes the URL in the manual Gmail confirmation flow.
Guest opens the manage page.
Shortcode fetches GET /reservation-self?token=...
Guest can review booking details and cancel online only when policy allows.
Guest change UI is hidden for the MVP; guests are asked to reply to confirmation email or call the restaurant for changes.
```

Security rules:

```text
Raw tokens are never stored.
Invalid, expired, revoked, or hidden-row tokens fail safely.
Guest-safe endpoints never return phone, email, staff notes, internal IDs, source IDs, raw payloads, or diagnostics.
```

Change request flow:

```text
POST /reservation-self/change-request
Kept for compatibility/future use, but not shown on the MVP guest page.
Creates tryzub_reservation_guest_requests status=open.
Marks reservation needs_review.
Appends a staff note for the request.
Does not overwrite reservation date/time/party automatically.
Rejects cancelled, seated, completed, and no_show reservations.
```

Cancellation flow:

```text
POST /reservation-self/cancel
new, needs_review, and confirmed reservations cancel directly until 2 hours before reservation time.
Same-day cancellation is allowed if more than 2 hours away.
Less than 2 hours before reservation time, guests see the call/contact message and status does not change.
cancelled, seated, completed, and no_show cannot be cancelled from the guest link.
Successful online cancellation appends: Guest cancelled reservation from self-service link.
```

## Security Notes

Before or during pilot:

```text
Use HTTPS only.
Use a limited WordPress user with Application Password.
Do not expose raw failed JSON publicly.
Do not leave Adminer public.
Do not commit credentials.
Protect wp-admin and plugin files normally.
Keep reservation emails active as backup.
```

Private endpoints require `manage_tryzub_reservations` or `manage_options`.

## Final Pilot Backend Checklist

1. Create host/manager/developer WordPress users.
2. Generate Application Passwords.
3. Confirm host/manager can use protected operational endpoints.
4. Confirm host/manager cannot hard-delete.
5. Confirm developer/admin can hard-delete test rows.
6. Confirm unauthenticated protected endpoints return 401/403.
7. Generate guest manage link.
8. Open valid guest link on mobile.
9. Confirm guest card is mobile-friendly.
10. Confirm guest card exposes no private/internal data.
11. Confirm guest can cancel more than 2 hours before reservation.
12. Confirm guest cannot cancel less than 2 hours before reservation and sees call message.
13. Confirm same-day cancellation works if more than 2 hours away.
14. Confirm invalid/expired/revoked token fails safely.
15. Confirm hidden reservation token fails safely.
16. Confirm iOS/manual Gmail flow can generate/copy guest manage link.
17. Confirm `manual-email-log` records `draft_created`.
18. Confirm `manual-email-log` records `manual_sent` and sets `confirmation_email_sent_at` when appropriate.
19. Confirm backend sends no email from `manual-email-log`.
20. Confirm manual call-in blank email still works.
21. Confirm soft hide still works.
22. Confirm no normal iOS workflow calls `POST /managed-reservations/import`.
23. Confirm floor layout can be created with `PUT /restaurant-tables`.
24. Confirm `GET /floor-plan?date=...` returns tables, assignments, and reservations.
25. Confirm `PATCH /managed-reservations/{id}/tables` updates assignment rows and `table_name`.
26. Confirm seated-table and same-time conflicts return `409` with `reason` and `table_label`.
27. Confirm `GET /guest-intelligence/reservation/{id}` returns profile pack sections.
28. Confirm `GET /intelligence/reservation-pipeline-diagnostics` explains non-reservation forms separately from unexplained reservation-intake gaps.

## Backend Test Checklist

### A. Health / Routes

1. `GET /ping`
2. `GET /restaurant-setup`
3. Confirm all routes exist.

### B. Auto Import

1. Submit website form.
2. Do not call manual import.
3. Confirm Flamingo has raw message.
4. Confirm managed table has clean reservation OR failed import has error.
5. `GET /managed-reservations` returns new reservation.

### B2. Public Form Duplicate Protection

1. Submit a normal reservation.
2. Double-click or double-tap submit aggressively.
3. Confirm the frontend lock prevents repeated CF7 requests when possible.
4. Submit the same reservation twice from the same page/form instance within 2 minutes.
5. Confirm Flamingo may contain multiple raw posts.
6. Confirm managed reservations contains only one operational row for the identical duplicate.
7. Confirm `{prefix}tryzub_reservation_duplicate_imports` records the skipped source.
8. Confirm the skipped duplicate reason is `client_request_id_match` or `fingerprint_recent_match`.

### B3. Importer Duplicate Boundaries

1. Re-run `POST /managed-reservations/import`.
2. Confirm an existing `source_submission_id` duplicate is skipped.
3. Submit same contact/date with changed time, party size, or notes.
4. Confirm it creates a separate managed row.
5. Confirm the existing duplicate/correction workflow marks rows `needs_review` as appropriate.

### C. List Endpoint

1. `GET /managed-reservations?per_page=10`
2. `GET /managed-reservations?date=YYYY-MM-DD`
3. `GET /managed-reservations?from=YYYY-MM-DD`
4. `GET /managed-reservations?status=needs_review`
5. `GET /managed-reservations?search=query`
6. Confirm empty result returns `success: true` and `data: []`.

### D. Single Fetch

1. `GET /managed-reservations/{existing_id}`
2. `GET /managed-reservations/{missing_id}`
3. Missing ID returns 404 `WP_Error`.

### E. PATCH

1. PATCH `staff_notes` only.
2. PATCH `status` to `confirmed`.
3. PATCH invalid status.
4. PATCH invalid date.
5. PATCH unknown field.
6. PATCH missing ID.
7. Confirm `updated_at` changes.
8. Confirm response returns updated row.
9. Confirm PATCH `status=confirmed` does not send email.

### F. Manual Create

1. POST clean reservation.
2. POST missing required fields.
3. Confirm created row appears in GET list.
4. POST `manual_call_in` with blank email.
5. POST `manual_walk_in` with `status=seated`.
6. POST `known_guest_manual`.
7. POST invalid `source_type`.
8. Confirm no email is sent by POST create.

### F2. Soft Hide

1. PATCH `is_hidden=true`.
2. Confirm normal `GET /managed-reservations` hides the row.
3. Confirm `GET /managed-reservations?include_hidden=1` shows the row.
4. Confirm `GET /managed-reservations/{id}` still returns the row.
5. PATCH `is_hidden=false`.
6. Confirm normal GET shows the row again.

### F3. Hard Delete

1. Confirm soft hide still works for normal staff cleanup.
2. As admin, DELETE `/managed-reservations/{id}?force=1` for a test row.
3. Confirm response includes `deleted_id`.
4. Confirm normal staff credentials cannot hard delete.
5. Confirm confirmed/seated/completed/no_show rows require `force=1`.
6. Confirm `{prefix}tryzub_reservation_deletion_audit` contains the full snapshot.
7. Confirm the raw Flamingo post still exists.
8. Confirm email logs are preserved.

### G. Failed Imports

1. Submit intentionally broken/test form.
2. Confirm failed import appears.
3. Confirm raw/attempted data is visible to authorized user only.

### H. Confirmation Email

1. `POST /managed-reservations/{id}/confirm`
2. Confirm status becomes `confirmed`.
3. Confirm `confirmed_at` is set.
4. Confirm email log row is created.
5. Confirm `confirmation_email_sent_at` is set only when sent.
6. Call confirm again.
7. Confirm duplicate email is not sent automatically.
8. Confirm failed email logs `failed` and leaves reservation confirmed.
9. Confirm no-email manual rows log `skipped` if confirm endpoint is called.

### I. Reminder Job

1. Create confirmed reservation due soon.
2. Run `POST /managed-reservations/send-due-reminders`.
3. Confirm reminder email log.
4. Confirm `reminder_email_sent_at` is set on success.
5. Run again.
6. Confirm no duplicate reminder.

### I2. Restaurant Setup

1. `GET /restaurant-setup` returns the default `tryzub` row.
2. PATCH `business_name`, `timezone`, `default_party_size`, policy fields, and email fields.
3. PATCH unknown field returns `tryzub_unknown_setup_field`.
4. Manual call-in blank email uses the configured placeholder internally.

### I3. Restaurant Hours

1. `GET /restaurant-hours` returns 7 weekly rows.
2. Confirm weekday convention is `0 = Monday` through `6 = Sunday`.
3. Confirm Monday row is closed: `{"weekday":0,"is_open":false,"open_time":null,"close_time":null}`.
4. PATCH `/restaurant-hours` with the full weekly schedule:

```json
{
  "weekly_hours": [
    {"weekday":0,"is_open":false,"open_time":null,"close_time":null},
    {"weekday":1,"is_open":true,"open_time":"17:00:00","close_time":"21:00:00"},
    {"weekday":2,"is_open":true,"open_time":"17:00:00","close_time":"21:00:00"},
    {"weekday":3,"is_open":true,"open_time":"17:00:00","close_time":"21:00:00"},
    {"weekday":4,"is_open":true,"open_time":"17:00:00","close_time":"22:00:00"},
    {"weekday":5,"is_open":true,"open_time":"11:00:00","close_time":"22:00:00"},
    {"weekday":6,"is_open":true,"open_time":"11:00:00","close_time":"21:00:00"}
  ]
}
```

5. `GET /restaurant-hours` again confirms Monday remains closed.
6. `GET /restaurant-hours?from=YYYY-MM-DD&to=YYYY-MM-DD` returns special hours in range.
7. PATCH invalid weekday returns validation error.
8. PATCH close_time before open_time returns validation error.

### I4. Day Availability

1. `GET /restaurant-day-availability?date=YYYY-MM-DD` returns weekly source when no special row exists.
2. PATCH a special open day with reason.
3. Confirm GET returns `source: "special"`.
4. PATCH a closed special day with null times.
5. Confirm closed response has null open/close times.
6. PATCH missing date returns validation error.

### I5. Public Slots

1. `GET /reservation-slots?date=YYYY-MM-DD` works without auth.
2. Open day returns slot values from open_time through close_time minus 30 minutes.
3. Closed day returns `slots: []`.
4. Blocked slots are removed from open-day slot output.
5. Confirm no guest PII or staff-only blocked-slot reason appears.

### I5a. Restaurant Blocked Slots

1. `GET /restaurant-blocked-slots?date=YYYY-MM-DD` requires auth.
2. POST `{"date":"2026-05-28","slots":["18:00","18:15"],"reason":"Held for manual booking"}`.
3. Confirm duplicate POST does not error.
4. Confirm GET returns two blocked rows.
5. Confirm public `/reservation-slots?date=2026-05-28` removes `18:00` and `18:15`.
6. Confirm `18:30` remains if it is inside generated slots.
7. POST invalid `18:07` returns validation error.
8. POST a slot outside generated hours returns validation error.
9. DELETE specific slots restores only those slots.
10. DELETE with `?date=YYYY-MM-DD` and no body removes all blocked slots for that date.

### I5b. Manual Insomnia Slot Sync Checks

1. `GET /ping`
2. `GET /restaurant-setup`
3. PATCH `/restaurant-setup` with `slot_interval_minutes = 15` if the DB is still old.
4. `GET /restaurant-hours`
5. PATCH `/restaurant-hours` with Monday closed and current weekly defaults if the DB is still old.
6. `GET /restaurant-hours` again confirms Monday remains closed.
7. `GET /reservation-slots?date=known-closed-Monday` returns `{"success":true,"is_open":false,"slots":[]}`.
8. `GET /reservation-slots?date=known-Thursday` confirms first slot `17:00` and last slot `20:30`.
9. `GET /reservation-slots?date=known-Friday` confirms last slot `21:30`.
10. `GET /reservation-slots?date=known-Saturday` confirms last slot `21:30`.
11. PATCH `/restaurant-day-availability?date=test-date` with closed hours.
12. `GET /reservation-slots?date=test-date` confirms `slots: []`.
13. PATCH `/restaurant-day-availability?date=test-date` with short hours.
14. `GET /reservation-slots?date=test-date` confirms shortened slots.
15. POST `/restaurant-blocked-slots` for an open date with `18:00` and `18:15`.
16. GET `/restaurant-blocked-slots?date=YYYY-MM-DD` confirms the blocked rows.
17. GET `/reservation-slots?date=YYYY-MM-DD` confirms `18:00` and `18:15` are removed but `18:30` remains.
18. DELETE `/restaurant-blocked-slots` for those slots.
19. GET `/reservation-slots?date=YYYY-MM-DD` confirms those slots are back.

### I5c. Public Form Browser Tests

1. Hard refresh `/book-table`.
2. Type invalid date like `13333`.
3. Confirm no usable time chips appear.
4. Enter/select valid date `05-28-2026`.
5. Confirm one valid `/reservation-slots` request.
6. Confirm time chips appear and display backend labels.
7. Confirm blocked slots do not appear.
8. Confirm `18:30` remains if only `18:00` and `18:15` are blocked.
9. Click a time chip and confirm selected chip state.
10. Confirm real CF7 time field `text-196` is synced to `HH:mm`.
11. Click party size `5` and confirm real CF7 attendee field `text-139` is `5`.
12. Click party size `7` or `8` and confirm the large-party helper appears.
13. Submit a test reservation.
14. Confirm CF7 success modal still works.
15. Confirm Flamingo has the correct date, time, and party size.
16. Confirm the managed reservation auto-imports.
17. Confirm iOS sees the reservation.
18. Confirm reCAPTCHA still works.
19. Confirm the old reservation page still works until the menu is switched.

### I6. Analytics Summary

1. `GET /reservation-analytics/summary` requires auth.
2. `GET /reservation-analytics/summary?from=YYYY-MM-DD&to=YYYY-MM-DD` applies reservation_date range.
3. Confirm spam Flamingo submissions are excluded.
4. Confirm response contains aggregate counts only.
5. Confirm no names, phones, emails, notes, or raw payloads appear.

### J. iOS Contract

1. GET list decodes in iOS.
2. GET by ID decodes in iOS.
3. PATCH returns updated row that iOS can upsert.
4. Confirm endpoint response can be decoded or ignored safely until iOS implements it.
5. Failed imports response still decodes.
6. Additive reservation fields decode or are ignored safely.
7. iOS does not call the import endpoint.
8. `GET /managed-reservations?updated_since=YYYY-MM-DD HH:mm:ss` returns changed rows only.
9. Empty changed-since response returns `success: true`, `total: 0`, and `data: []`.
10. `server_time` is present on list, single GET, create, PATCH, delete, tables, and confirm responses; older iOS builds ignore it safely.
11. Every reservation DTO includes `row_version`, `seated_at`, and `completed_at`.
12. PATCH with a stale `expected_updated_at` returns `409 tryzub_reservation_conflict` with current `data` and `current_version`.
13. PATCH with a matching `expected_updated_at` succeeds and returns an advanced `row_version`.
14. PATCH `status` from `completed` to `cancelled` returns `409 tryzub_invalid_status_transition` with `allowed_transitions`.
15. PATCH `status` to `seated` stamps `seated_at`; to `completed` stamps `completed_at` (once).

### K. Guest Self-Service

1. Generate guest manage link with `POST /managed-reservations/{id}/guest-manage-link`.
2. Open `/manage-reservation/?token=RAW_TOKEN`.
3. Confirm the card shows restaurant name, guest name, date, time, party size, status, and guest notes.
4. Confirm phone, email, source IDs, internal managed ID, staff notes, and diagnostics are not exposed.
5. Confirm invalid/expired/revoked token fails safely.
6. Confirm hidden reservation token fails safely.
7. Confirm the guest page shows change instructions, not a change-request form.
8. Cancel a `new`, `needs_review`, or `confirmed` reservation more than 2 hours before reservation time.
9. Confirm it becomes `cancelled`.
10. Confirm `{prefix}tryzub_reservation_guest_requests` has request_type `cancel` and status `applied`.
11. Confirm staff notes include: `Guest cancelled reservation from self-service link.`
12. Cancel less than 2 hours before reservation time.
13. Confirm the guest sees the call/contact message and operational status does not change.
14. Confirm same-day cancellation works if the reservation is still more than 2 hours away.
15. Confirm cancelled, seated, completed, and no_show cannot be cancelled from the guest link.

### I7. Floor Plan

1. `PUT /restaurant-tables` creates or updates layout rows.
2. Confirm omitted tables are not deleted automatically.
3. Confirm overlapping layout cells return validation error.
4. `GET /restaurant-tables` returns active and inactive tables.
5. `GET /floor-plan?date=YYYY-MM-DD` returns tables, assignments, and reservations.
6. `PATCH /managed-reservations/{id}/tables` with `["T4"]` updates assignment rows and `table_name`.
7. `PATCH /managed-reservations/{id}/tables` with `[]` clears assignments and sets `table_name` to null.
8. Assign the same table at the same time to another active reservation and confirm `409` conflict.
9. Assign to a table held by a `seated` reservation on the same date and confirm `409` with `reason=table_already_seated`.
10. Confirm terminal reservations cannot receive new assignments but may clear existing ones.
11. Confirm the tables PATCH response includes `server_time`.
12. Confirm a stale `expected_updated_at` on the tables PATCH returns `409 tryzub_reservation_conflict`.
13. Two near-simultaneous assignments of the same free table to different reservations: exactly one wins; the other gets a `409` conflict (or `tryzub_floor_plan_locked` to retry).

### I8. Intelligence / Pipeline Diagnostics

1. `GET /guest-intelligence?date=YYYY-MM-DD` returns per-reservation summaries with `profile_endpoint`.
2. `GET /guest-intelligence/reservation/{id}` returns profile pack sections.
3. `GET /intelligence/system-status?from=&to=` returns `pipeline_diagnostics.summary`.
4. `GET /intelligence/reservation-pipeline-diagnostics?from=&to=` classifies Flamingo intake rows.
5. Confirm non-reservation CF7 forms classify as `non_reservation_form`, not `unexplained_missing`.
6. Confirm hard-deleted managed rows classify as `hard_deleted_test_row` when audit exists.
7. Confirm `include_items=0` returns summary only.
8. Confirm `classification=unexplained_missing` filters items.
9. Confirm diagnostics do not expose raw notes, email, or phone.

## Known Limitations

```text
This is a controlled restaurant pilot backend, not production-ready SaaS.
Email remains backup.
Inbound guest replies are not automated yet.
Reminder delivery depends on WordPress cron unless the debug route is called.
The past-date completion sweep also depends on WordPress cron (hourly backstop) plus a throttled on-read sweep; near-immediate but not instant.
iOS still needs a strong offline/pending mutation queue for real operations.
Optimistic concurrency is opt-in via expected_updated_at; clients that omit it keep last-write-wins behavior.
Floor-plan assignment safety relies on MySQL advisory locks (GET_LOCK); a DB without lock support would fall back to the transaction + recheck only.
Legacy GET /reservations date filtering scans only the latest 100 raw Flamingo posts; use GET /managed-reservations for reliable date queries.
No Apple auth or multi-tenant architecture yet.
Guest self-service is token-link only, not a full account portal.
```

Explicitly deferred from Phase 2:

```text
Postmark/DNS/domain confirmation
Email template changes
Reminder changes
Capacity logic beyond current floor-plan conflict rules
Real-time websocket floor sync
SMS
Waitlist
Floor map
Full removal of hardcoded JS fallback
PostgreSQL/SaaS migration
```

## Deployment Notes

Before deploy:

```text
Backup plugin files.
Backup the database.
Confirm the current live form is working.
Deploy the plugin update.
Clear server/page cache if needed.
Test in an incognito/private browser.
Test on mobile.
Test on desktop.
Keep email backup active.
```

Schema upgrade (1.5.0 -> 1.6.0):

```text
On plugins_loaded, tryzub_maybe_upgrade_reservations_table runs automatically when the stored
db version differs from 1.6.0.
It adds the seated_at and completed_at columns to {prefix}tryzub_reservations if missing (idempotent ALTERs).
No data is dropped or rewritten; existing rows simply get NULL seated_at/completed_at until they next
enter those statuses.
If the upgrade does not trigger, deactivate and reactivate the plugin once to force schema creation.
After upgrade, GET /managed-reservations rows include seated_at, completed_at, and row_version.
```

After deploy:

```text
Submit one controlled test reservation.
Hide/cancel the test row in iOS after verifying.
Confirm no console errors.
Confirm no CF7 validation break.
Confirm no 500 errors in the browser network tab.
Confirm Flamingo records the inbound message.
Confirm managed auto-import creates the operational reservation.
Confirm iOS sees the reservation.
Confirm GET /managed-reservations rows include row_version, seated_at, completed_at.
Confirm a PATCH with stale expected_updated_at returns 409 tryzub_reservation_conflict.
```

## Current Backend MVP Status

[x] Health check verified

[x] Auth protection verified

[x] GET list verified

[x] GET by ID verified

[x] PATCH verified

[x] Manual create verified

[ ] Manual call-in blank email verified

[ ] Manual walk-in verified

[ ] Soft hide verified

[ ] Restaurant setup verified

[x] Auto import verified

[x] Manual import route verified with POST

[x] Duplicate/correction detection verified

[x] True failed import detection verified

[x] Confirmation email verified

[x] Duplicate confirmation prevention verified

[x] Confirm cancelled blocked

[x] Failed imports endpoint contains failed record 357

[ ] Reminder time-window fixed ----------NOT MVP

[ ] Reminder send verified --------------NOT MVP

[ ] iOS real phone decode/update verified

[ ] Visible PATCH failure in iOS

[ ] Restaurant pilot ready
