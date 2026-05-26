# Tryzub Reservations MVP Gap List

Scope: one-restaurant internal reservation app for Tryzub Ukrainian Kitchen. This list avoids SaaS/platform ideas and only covers issues that can block a useful boss demo or staff pilot.

## A. Must Fix Before Boss Demo

### 1. Confirm vs Confirm + Email is ambiguous

Current state:
- Primary `.confirm` UI actions call `ReservationsController.confirmReservation`.
- That calls `POST /managed-reservations/{id}/confirm`.
- Backend sends/attempts the confirmation email.
- Button text sometimes appears as "Confirm", even though full title says "Confirm and Send Email".

Why it blocks MVP:
- Staff/manager can accidentally send guest email when they only meant to mark the reservation confirmed.

Required MVP outcome:
- Two concepts must be unmistakable:
  - Confirm without email = `PATCH /managed-reservations/{id}` with `status=confirmed`.
  - Confirm + Email = `POST /managed-reservations/{id}/confirm`.

Do not change backend endpoint behavior.

### 2. Review/New workflow does not match the desired "New/Pending" queue

Current state:
- Review tab has a segmented control: `New` or `Review`.
- It fetches both `status=new` and `status=needs_review`, but UI displays one segment at a time.
- Sorting inside each segment is `createdAt` ascending.

Why it blocks MVP:
- Staff need one practical queue of pending work, not a hidden split that can leave work unseen.

Required MVP outcome:
- The review/pending workflow should include both `new` and `needs_review`.
- The combined queue should sort by `created_at` ascending: oldest submitted first.

### 3. Staff notes need to be hard to miss

Current state:
- Detail has a Notes card with Guest and Staff notes.
- Needs-review detail shows a warning using staff notes.
- Rows only show staff notes in a limited `needsReview` wide-row case; otherwise they mostly show a generic `NOTES` indicator.

Why it blocks MVP:
- Staff notes are operational instructions. If they are buried, the app can fail during service even if sync works.

Required MVP outcome:
- Detail view makes `staff_notes` prominent.
- Rows make the existence of important notes obvious in a compact restaurant-facing layout.

### 4. Row layout must stay compact and service-friendly

Current state:
- Rows are much more compact than a generic CRUD list, which is good.
- There is still a lot of state/action density: badges, notes indicator, phone, table, context note, action buttons.

Why it blocks MVP:
- Host staff need to scan time, party size, table, name, status, and action fast.

Required MVP outcome:
- Today, Schedule, and Review rows should prioritize:
  - time
  - party size
  - guest name
  - table
  - status
  - notes indicator
  - one obvious primary action

No redesign needed; keep it practical.

### 5. Email status copy must not imply inbox delivery

Current state:
- Confirm + Email success notice says "Email sent."
- Detail says backend recorded the confirmation email timestamp.

Why it blocks MVP:
- Backend "sent" means WordPress/backend accepted or attempted sending. It does not prove Gmail inbox delivery.

Required MVP outcome:
- Staff-facing copy should communicate that the backend recorded/sent the confirmation, not that inbox delivery is guaranteed.

## B. Must Fix Before Staff Pilot

### 1. Manual call-in reservation requires email

Current state:
- `ManualReservationFormView.createReservation()` requires non-empty email.
- If a phone caller does not provide email, staff cannot create the reservation from the app.

Why it blocks pilot:
- Call-in reservations are a core workflow.

Required MVP outcome:
- Decide the MVP policy:
  - backend accepts missing email, or
  - app uses an explicit placeholder email, or
  - staff must collect email before creating.
- The UI should make that policy obvious.

### 2. Duplicate public-form submissions need operational handling

Current state:
- Duplicate resolution instructions exist in More and edit form supports `supersededById`.
- Known issue: duplicate submissions are coming from two Flamingo submissions, likely public form double-submit.

Why it blocks pilot:
- Duplicate reservations create real service mistakes: overbooking, duplicate emails, and confused staff.

Required MVP outcome:
- Staff must have a simple playbook for duplicates:
  - keep the correct reservation active
  - cancel the duplicate
  - set `superseded_by_id`
  - add staff note
- The public form double-submit source should be fixed or at least monitored before staff rely on the app.

### 3. Today must keep active reservations visible after reservation time passes

Current state observed:
- `HostBoardSnapshot.upcoming` filters by status, not by current time, so same-day active reservations should remain visible after their time.
- `nextReservationID` uses current time only to choose the next marker.

Why it matters:
- A late, unseated, or unresolved reservation must not disappear during service.

Required MVP outcome:
- Preserve this behavior and verify manually before staff pilot.
- Active same-day statuses `new`, `needs_review`, `confirmed`, and `seated` must remain visible until staff explicitly changes status.

### 4. Developer/sync details should not distract staff

Current state:
- `ReservationDetailView` includes `ReservationOperationalCard` labeled "Developer / Sync Info".
- More tab includes duplicate-resolution text and diagnostics gated by capability.
- App startup currently hardcodes role `.developer`.

Why it blocks pilot:
- Staff should not have to think about sync internals, remote IDs, or developer diagnostics during service.

Required MVP outcome:
- Pilot devices should use the intended role/capability level.
- Developer-only diagnostics should stay out of staff flow.

### 5. Failed import workflow must stay manager/developer-only

Current state:
- Failed imports are gated by `canViewFailedImports`.
- The app currently launches with `.developer`, so all tools are visible.

Why it blocks pilot:
- Failed public-form import repair is operational/admin work, not normal host-board work.

Required MVP outcome:
- Staff pilot role should hide failed import tools unless the staff member is responsible for fixing form problems.

## C. Can Wait

### 1. Protocol cleanup

Current state:
- `ReservationsAPIClientProtocol` is useful.
- `ReservationRepositoryProtocol` is harmless.
- `ReservationMutationServiceProtocol`, `ReservationSyncServiceProtocol`, and `ImportFailureServiceProtocol` are mostly unused as injected dependencies.

Why it can wait:
- They do not change behavior.
- Removing them before MVP creates churn without helping staff.

### 2. Controller decomposition

Current state:
- `ReservationsController` owns refresh workflows, mutations, notices, diagnostics, import count, and sync-scope state.

Why it can wait:
- It is large but traceable.
- Splitting it now risks regression.

Clean later:
- Separate diagnostics/import-failure count from core reservation workflow if the file keeps growing.

### 3. Stale file/folder names

Current state:
- `Import/ReservationImportService.swift` contains `ReservationSyncService`.

Why it can wait:
- Misleading, but not behavior-breaking.
- User explicitly requested no renames now.

Clean later:
- Rename only after MVP or when making a focused architecture cleanup commit.

### 4. Notice system simplification

Current state:
- Notices are scoped by source and stored in a list.
- This is helpful for debugging but may be too much for staff.

Why it can wait:
- It does not block core reservation handling.
- The main risk is noise, not incorrect data.

Clean later:
- Reduce staff-facing notice volume after real service testing.

### 5. Unique local constraint on `remoteID`

Current state:
- Repository upsert keys by `remoteID`.
- SwiftData model does not enforce uniqueness.
- Existing duplicate local rows with the same `remoteID` could remain.

Why it can wait:
- Normal server DTO upserts should not create duplicates from scratch.
- This is a cache hygiene issue unless duplicate local rows appear in testing.

Clean later:
- Add a safe local dedupe/unique plan after backing up cache expectations.

### 6. Offline queue / incremental sync / platform features

Do not work on these before MVP:

- Offline mutation queue.
- `after_id` / `updated_since` sync.
- SMS reminders.
- Inbound email capture.
- PostgreSQL/SaaS architecture.
- Advanced roles.
- New backend endpoints.
