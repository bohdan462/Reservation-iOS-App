# Reservation workflows (staff)

**Status:** Current source of truth  
**Branch:** `audit-current-state`  
**Audit date:** 2026-06-14

## Confirmation (MVP)

**Flag:** `ReservationEmailWorkflow.isBackendConfirmEmailEnabled = false`

Normal staff flow is **Mail-first**, not `POST /confirm`.

### With guest email

1. Staff taps **Confirm** → `beginPrimaryConfirmFlow`
2. `generateGuestManageLink` if needed
3. `GuestConfirmationMailPresenter` styled HTML draft (`GuestEmailTemplateRenderer`)
4. `MFMailComposeViewController` opens
5. On `.sent`:
   - `POST /manual-email-log` (`email_type=confirmation`, `status=manual_sent`)
   - `PATCH` status → `confirmed`
6. Traces: `ConfirmFlowTrace`

### Without guest email

`markConfirmedWithoutEmail` → `PATCH` confirmed immediately (no mail).

### Not used in normal flow

- `POST /managed-reservations/{id}/confirm` — gated off; only if flag enabled
- Backend auto-send email

## Shift reminders

**Entry points:**

- Host tab → header **⋯** → **Shift reminders**
- Bookings tab → toolbar **bell badge**

**Sheet:** `ShiftReminderReviewSheet` — review before send per reservation.

| Channel | On sent |
|---------|---------|
| Email | `manual-email-log` `email_type=reminder`, `manual_sent` |
| Text | Staff composer only; no backend SMS log in V1 |

Does **not** PATCH status to confirmed.

## Manual reservation create

- `ManualReservationFormView` from Host, Bookings, Guests, More
- `POST /managed-reservations` → upsert cache
- **No** confirmation email on create
- Text “Table Ready” hidden on create (`showsEditControls` false)

## Edit reservation

- `ReservationEditFormView` → `PATCH /managed-reservations/{id}`
- Activity history written by backend

## Seat / complete / cancel / no-show

| Action | Endpoint | Caller |
|--------|----------|--------|
| Seat | PATCH status `seated` | Host, Detail |
| Complete | PATCH `completed` | Host, Detail |
| Cancel | PATCH `cancelled` | Host, Detail |
| No-show | PATCH `no_show` | Host, Detail |
| No-show recovery | PATCH `seated` | Detail |

## Hide / restore / hard delete

| Action | Who | Endpoint |
|--------|-----|----------|
| Hide wrong entry | Manager+ | PATCH `is_hidden` |
| Restore | Manager+ | PATCH unhide |
| Hard delete | Developer | `DELETE ?force=1` |

**Session hide:** `HiddenReservationsStore` overlays UI without server call.

Hard delete does not instantly remove row on other devices until sync.

## Guest messaging (draft → review → send)

**Coordinator:** `GuestCommunicationCoordinator`

| Kind | Template | Backend log on send |
|------|----------|---------------------|
| Confirmation draft | `GuestEmailTemplateRenderer` | If sent via draft review with confirmation kind |
| Reminder draft | Same styled HTML | `reminder` if logged |
| Manual question / clarification / table ready | Styled HTML + staff text | **Skipped** — trace `unsupported_email_type` |

Staff must review AI drafts; beta warning in `GuestMessageDraftReviewView`.

## Guest manage link

`POST /guest-manage-link` — private View Reservation URL for emails.

## Table assignment

See [FLOOR_PLAN_AND_TABLES.md](./FLOOR_PLAN_AND_TABLES.md).

## Activity history

Backend writes on mutation. iOS reads `GET /managed-reservations/{id}/activity` and `GET /activity?date=`.

## Related docs

- [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md)
- [FLOOR_PLAN_AND_TABLES.md](./FLOOR_PLAN_AND_TABLES.md)
- [DIAGNOSTICS_AND_TESTING.md](./DIAGNOSTICS_AND_TESTING.md)
