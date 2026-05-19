# Tryzub Reservations iOS MVP Notes

This app is the controlled restaurant pilot iOS app for Tryzub Ukrainian Kitchen staff.

The WordPress backend is the source of truth. SwiftData is a local cache only.

## Backend Base URL

`https://tryzubchicago.com/wp-json/tryzub/v1`

## Current Backend Contract

The iOS app uses these private endpoints:

- `GET /managed-reservations`
  - List managed reservations.
  - Supports `page`, `per_page`, `date`, `from`, `to`, `status`, and `search`.

- `GET /managed-reservations/{id}`
  - Fetch one managed reservation by server ID.
  - Used for reconciliation after uncertain mutation failures.

- `PATCH /managed-reservations/{id}`
  - Update allowed reservation fields.
  - Returns the updated reservation DTO.
  - Does not send email.

- `POST /managed-reservations`
  - Create a manual managed reservation.
  - Returns the created reservation DTO.

- `GET /managed-reservations/import-failures`
  - Lists failed backend imports from CF7/Flamingo.
  - Visible to manager/developer roles in the app.

- `POST /managed-reservations/{id}/confirm`
  - Confirms the reservation and asks the backend to send confirmation email.
  - Returns the updated reservation DTO plus email status.

The iOS app must not call the manual import endpoint during normal use.

## Data Flow

Website Contact Form 7 submission
-> Flamingo raw inbound message
-> backend auto-import
-> managed reservation table
-> private REST API
-> iOS app refresh
-> SwiftData cache upsert

## Important Models

`ReservationDTO` decodes the backend reservation response using snake_case to camelCase conversion.

Required reservation fields:

- `id`
- `sourceSubmissionId`
- `guestName`
- `email`
- `phone`
- `reservationDate`
- `reservationTime`
- `partySize`
- `guestNotes`
- `staffNotes`
- `status`
- `tableName`
- `createdAt`
- `updatedAt`
- `confirmedAt`
- `confirmationEmailSentAt`
- `reminderEmailSentAt`
- `supersededById`

`ReservationStatus` supports:

- `new`
- `needs_review`
- `confirmed`
- `seated`
- `completed`
- `cancelled`
- `no_show`

`ReservationConfirmResponse` supports email status:

- `sent`
- `failed`
- `already_sent`
- `skipped`
- `unknown`

Unknown email statuses decode as `unknown` instead of crashing.

## Architecture

Current layers:

- API
  - `ReservationsAPIClientProtocol`
  - `ReservationsAPIClient`
  - request/response DTOs

- Persistence/cache
  - `ReservationRecord`
  - `ReservationRepositoryProtocol`
  - `ReservationRepository`

- Services
  - `ReservationSyncServiceProtocol`
  - `ReservationSyncService`
  - `ReservationMutationServiceProtocol`
  - `ReservationMutationService`
  - `ImportFailureServiceProtocol`
  - `ImportFailureService`

- Controllers/UI state
  - `ReservationsController`

- Roles
  - `AppUserRole`
  - `AppCapabilities`
  - `AppEnvironment`

Views should not build raw URL requests. Use controller/service/repository flow.

## Mutation Rules

For create, patch, confirm:

1. Call backend first.
2. Decode the returned server DTO.
3. Upsert returned DTO into SwiftData.
4. Show visible success or failure.

The app must not pretend a mutation succeeded if the server call failed.

When a PATCH or confirm request fails with a network error that may have reached the server, `ReservationMutationService` attempts `GET /managed-reservations/{id}` to refresh server state.

## Confirmation Flow

Confirm buttons appear for `new` and `needs_review` reservations when the current role can confirm.

The user is asked:

`Confirm reservation?`

Confirm calls:

`POST /managed-reservations/{id}/confirm`

Results:

- `sent`: show "Reservation confirmed. Email sent."
- `already_sent`: show non-scary already-confirmed message.
- `failed`: show "Reservation confirmed, but confirmation email failed. Follow up manually."

Generic PATCH is not used to send confirmation email.

## Roles

Current MVP roles are local UI capability roles only. Backend permissions still matter.

Staff:

- view reservations
- refresh
- search
- seat confirmed reservations
- edit staff notes/details where enabled

Manager:

- staff abilities
- confirm
- cancel
- create manual reservations
- view failed imports

Developer:

- manager abilities
- developer diagnostics/raw failure details

## Manual Refresh

Manual refresh always calls the backend through `refreshAll(context:)`.

`loadIfNeeded(context:)` may skip refresh if recently synced.

## Screen Overview

- Today
  - Main host board for service.
  - iPad landscape uses a two-column board: `Seated / In House` and `Upcoming Today`.
  - iPhone uses a segmented board for Upcoming, Seated, and Review.
  - Shows reservations, guests, new, review, form problems, and no-table counts.

- Schedule
  - Date-grouped reservation list for upcoming/all reservations.
  - Supports search by name, phone digits, email, and table.

- Review
  - Focused queue for `needs_review` and `new` reservations.
  - Manager/developer should use this for duplicates, suspicious entries, and large parties.

- Detail
  - Card-based operational view.
  - Top card shows time, date, guest, status, party, table, email state, and actions.
  - Contact and reservation facts are visible near the top instead of buried in a long list.

- More
  - Manual create and form problems/failed imports for roles that can access them.

## Reservation Row Behavior

Rows are compact and adaptive.

- iPad/regular width rows use columns: time, guest/contact, party, table, status, actions.
- iPhone rows use three compact lines with no vertical phone/date wrapping.
- Phone numbers are formatted for scanning and use monospaced digits.
- Missing table assignment shows as `No table`.
- Needs-review rows and next-up rows get stronger visual treatment.

Action rules:

- `new`: Confirm, Assign Table, Cancel.
- `needs_review`: Confirm/Review, Assign Table, Cancel.
- `confirmed`: Seat, Assign Table, Cancel, No Show.
- `seated`: Complete, Assign Table, Cancel, No Show.
- `cancelled`, `completed`, `no_show`: details only.

Confirm always calls the backend confirm endpoint and can send email. Seat/table/cancel actions use PATCH and do not send email.

## Host Board

Host Board is the main restaurant workflow screen.

- Upcoming includes `new`, `needs_review`, and `confirmed`.
- Seated includes `seated`.
- Done statuses are visually de-emphasized outside the main board.
- The next upcoming reservation is highlighted.
- If a confirmed reservation has no table, Seat asks whether to assign a table first or seat anyway.
- Form problems show as a warning banner for manager/developer roles.

## Detail View Behavior

Detail is designed for quick operational decisions:

- Hero card: time/date/status/guest/party/table/actions.
- Contact card: phone and email.
- Reservation card: date/time/party/table/status.
- Notes card: guest/staff notes with edit action.
- Operations card: IDs and server/email timestamps for manager/developer context.

The full edit form remains available through Edit Details.

## SwiftData Rule

SwiftData is local cache only.

Upsert key:

- `ReservationRecord.remoteID`

Server response overwrites local cached state.

Do not create local-only operational reservations for the pilot.

## Current iOS MVP Status

- [x] App launches/builds for iOS Simulator
- [ ] Auth works with limited WordPress app user
- [x] GET list refresh implemented
- [x] GET by ID implemented in API/mutation reconciliation
- [x] PATCH staff notes/details implemented through mutation service
- [x] PATCH status implemented
- [x] Manual create implemented
- [x] Confirm endpoint implemented
- [x] Confirm email sent status shown
- [x] Confirm email failed status shown
- [x] Duplicate confirm/already_sent handled
- [x] Visible PATCH/confirm failure implemented
- [x] Manual refresh always hits backend
- [x] SwiftData upsert implemented
- [x] Dashboard shows today/new/review/failures
- [x] Reservation row has compact adaptive host actions
- [x] Host Board added for iPad landscape and compact iPhone workflow
- [x] Detail view redesigned around hero/contact/facts/notes/operations cards
- [x] Table assignment sheet added
- [x] Staff/manager/developer capabilities applied
- [x] Failed imports screen decodes and supports manual fix flow
- [ ] iPad landscape checked on device/simulator
- [ ] iPhone Pro Max checked on device/simulator
- [ ] Verified on real iPhone against live restaurant account
- [ ] Ready for low-key restaurant pilot

## Pilot Test Checklist

Before calling the iOS app pilot-ready:

1. Install on a real iPhone and run on iPad landscape simulator/device.
2. Launch with a limited WordPress app user.
3. Pull to refresh Today.
4. Confirm Today Host Board, Schedule, Review, and More tabs load.
5. Verify iPad landscape shows seated/upcoming side by side.
6. Verify iPhone rows do not wrap phone/time/table vertically.
7. Create a manual reservation.
8. Edit staff notes and table assignment.
9. Confirm a `new` reservation and verify email status.
10. Seat a confirmed reservation.
11. Seat a confirmed reservation with no table and verify the no-table warning.
12. Cancel a test reservation.
13. Submit a broken website form and verify failed import appears.
14. Create a fixed manual reservation from a failed import.
15. Simulate network failure and confirm the UI shows visible failure.
16. Verify the app does not call the import endpoint.

## Known Limitations

- No full offline mutation queue yet.
- No Apple auth yet.
- No waitlist/table map yet.
- No direct inbound email reply capture yet.
- App credentials should move out of source code before broader testing.
- Email remains the operational backup during pilot.
