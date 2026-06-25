# Reservation workflows (staff)

**Status:** Current source of truth  
**Branch:** `audit-current-state`  
**Last reviewed:** 2026-06-24

## Confirmation (staff)

**Both confirmation paths exist.** Active behavior depends on **Email Automation / This iPad Email Controls** (`EmailAutomationSettings.backendConfirmationEnabled`).

| Setting | Code default | Typical pilot intent |
|---------|--------------|----------------------|
| `backendConfirmationEnabled` | **`true`** | May be turned **off** on device for Mail-first review |

Do **not** assume Mail-first unless the pilot iPad setting is confirmed. Backend confirmation is **not** marked production-verified until live tests pass.

### Path A — Manual Mail (when backend confirmation is off, or staff uses reviewable send)

**With guest email:**

1. Staff taps **Confirm** → `beginPrimaryConfirmFlow`
2. `generateGuestManageLink` if needed
3. `GuestConfirmationMailPresenter` styled HTML draft (`GuestEmailTemplateRenderer`)
4. `MFMailComposeViewController` opens (external Mail/Gmail)
5. On `.sent` only:
   - `POST /manual-email-log` (`email_type=confirmation`, `status=manual_sent`)
   - `PATCH` status → `confirmed`
6. Traces: `ConfirmFlowTrace`

**Without guest email:** `markConfirmedWithoutEmail` → `PATCH` confirmed immediately (no mail).

### Path B — Backend confirmation (when `backendConfirmationEnabled` is on)

1. Staff taps **Confirm & Send** (wording varies by setting)
2. `POST /managed-reservations/{id}/confirm` sends through backend/provider
3. Status moves to `confirmed` only after backend send success when a usable guest email exists
4. Guest manage link may still be created for the email body

Manual Mail remains the fallback/reviewable path when backend confirmation is disabled.

### Not automatic in either path

- Sync, startup, or background refresh must **never** confirm reservations
- Backend auto-send on create (not used in MVP create flow)

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

`POST /guest-manage-link` — private View Reservation URL for emails. Guest opens `/manage-reservation/?token=...`.

## Guest self-service cancellation (public token page)

**Not staff workflow** — guest-facing WordPress shortcode + public REST.

| Step | Behavior |
|------|----------|
| Page load | Shortcode JS calls `GET /reservation-self?token=...&_ts=...` with `cache: 'no-store'` |
| Active booking | Status `new` / `needs_review` / `confirmed`; cancel button when `can_request_cancel` |
| Guest taps cancel | `POST /reservation-self/cancel` with token |
| Server | Validates token; updates status `cancelled`; re-fetches row; sends **cancellation email** (`239b297`) |
| Response | `{ success, message, data? }` — `data` is guest-safe refreshed row (`d46713a`) |
| After cancel | **Token stays valid.** Page shows dead state: “Reservation Cancelled”, “This reservation has been cancelled.”, status `cancelled`, no cancel button |
| Cache | Guest self-service GET/POST send `Cache-Control: no-store` (`d46713a`) — required so reload does not show stale Confirmed state |
| Staff path | Separate: Host/Detail PATCH `cancelled` |

**Pilot note:** Guest cancellation email is independent of staff confirmation path. Staff confirmation mode is **device setting-dependent** — see Confirmation section above.

Contract details: [Backend README — Guest self-service](../Backend/tryzub-reservations-api/README.md).

## Table assignment

See [FLOOR_PLAN_AND_TABLES.md](./FLOOR_PLAN_AND_TABLES.md).

## Activity history

Backend writes on mutation. iOS reads `GET /managed-reservations/{id}/activity` and `GET /activity?date=`.

## Related docs

- [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md)
- [FLOOR_PLAN_AND_TABLES.md](./FLOOR_PLAN_AND_TABLES.md)
- [DIAGNOSTICS_AND_TESTING.md](./DIAGNOSTICS_AND_TESTING.md)
