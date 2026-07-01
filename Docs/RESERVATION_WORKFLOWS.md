# Reservation workflows (staff)

**Status:** Current source of truth  
**Branch:** `audit-current-state`  
**Last reviewed:** 2026-07-01

## Confirmation (staff)

**Both confirmation paths exist.** Active behavior depends on **Email Automation / This iPad Email Controls** (`EmailAutomationSettings.backendConfirmationEnabled`).

| Setting | Code default | Typical pilot intent |
|---------|--------------|----------------------|
| `backendConfirmationEnabled` | **`true`** | May be turned **off** on device for Mail-first review |

Do **not** assume Mail-first unless the pilot iPad setting is confirmed.

**Delivery truth:** iOS must not treat send timestamps or `emailStatus=sent` as inbox delivered. See [EMAIL_DELIVERY_TRUTH.md](./EMAIL_DELIVERY_TRUTH.md).

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
3. Status moves to `confirmed` after backend send success when a usable guest email exists
4. Provider accept → DTO **`confirmation_delivery_status = pending_delivery`** — **not** delivered until webhook
5. Success notice uses **`emailDeliveryStatus`** from confirm response (fallback: DTO field, then legacy `emailStatus`)
6. Guest manage link may still be created for the email body
7. Next sync/webhook refresh may update DTO to **`delivered`** with timestamps

Manual Mail remains the fallback/reviewable path when backend confirmation is disabled.

### Auto-confirm (backend)

- Backend may auto-confirm eligible reservations (see backend README).
- iOS badge: **`confirmationSource == .autoConfirm`** on reservation DTO (list, host, detail) — **not** activity fetch.
- Activity `auto_confirmed` events are **history only** on the timeline.

### Email delivery correction

When confirmation failed, suppressed, or **`requiresEmailCorrection`**:

| Action | Route | iOS |
|--------|-------|-----|
| Resend confirmation | `POST …/resend-confirmation` | Detail banner / Resend |
| Confirm by phone | `POST …/confirm-by-phone` | Detail **Confirm by phone** |

Both upsert returned DTO. Resend → **pending delivery**, not delivered.

**Host Board:** **Email issue** label only for failed/needs-correction — not full delivery dashboard on every row.

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

**Delivery truth (backend-sent reminders):** DTO carries `reminder_delivery_status` and related fields. **`reminderEmailSentAt`** is attempt-only. Sheet buckets: delivered / waiting / issues / manual-legacy / no email, plus delivery watchlist. Failed reminders → manual follow-up (no `resend-reminder` route yet). Host stats **Handled** = on-record attempts — not inbox delivered. See [EMAIL_DELIVERY_TRUTH.md](./EMAIL_DELIVERY_TRUTH.md).

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

Backend writes on mutation. iOS reads `GET /managed-reservations/{id}/activity` and `GET /activity?date=`. Auto-confirm **badges** use DTO `confirmationSource`, not activity — see [ACTIVITY_HISTORY.md](./ACTIVITY_HISTORY.md).

## Related docs

- [EMAIL_DELIVERY_TRUTH.md](./EMAIL_DELIVERY_TRUTH.md)

- [IOS_LIFECYCLE_AND_SYNC.md](./IOS_LIFECYCLE_AND_SYNC.md)
- [FLOOR_PLAN_AND_TABLES.md](./FLOOR_PLAN_AND_TABLES.md)
- [DIAGNOSTICS_AND_TESTING.md](./DIAGNOSTICS_AND_TESTING.md)
