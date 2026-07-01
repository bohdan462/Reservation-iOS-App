# Email Delivery Truth (iOS)

**Status:** Current source of truth  
**Last reviewed:** 2026-07-01  
**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md)

Backend contracts (webhook, DB migrations, correction routes) live in [Backend/tryzub-reservations-api/README.md](../Backend/tryzub-reservations-api/README.md) — **Email Delivery Truth** section. This doc covers **iOS decode, presentation, and staff UI** only.

---

## 1. Product rules (non-negotiable)

| Concept | Rule |
|---------|------|
| `reservation.status = confirmed` | Operational staff confirmation — **not** inbox delivery |
| `confirmationEmailSentAt` / `reminderEmailSentAt` | Attempt timestamps only — **not** delivery proof |
| `emailStatus = sent` (confirm response) | Provider accepted send — **not** delivered |
| `pending_delivery` | Waiting for provider webhook — **not** delivered |
| `delivered` | **Webhook only** — never inferred from send path or `_sentAt` |
| Failed / suppressed / complained | Needs correction or manual follow-up |
| Auto-confirm badge (current state) | `confirmationSource == .autoConfirm` from DTO — **not** activity fetch |
| Activity `auto_confirmed` events | **History only** — timeline decoration, not row badge source |

---

## 2. Backend DTO fields (snake_case → Swift)

Decoder: `ReservationsAPIClient` uses `.convertFromSnakeCase`.  
Types: `Network/ReservationDTO.swift` — `EmailDeliveryStatus`, `ConfirmationSource`, `ReservationDTO`.

### Confirmation / reminder delivery

```text
confirmation_delivery_status      → confirmationDeliveryStatus
confirmation_delivery_reason      → confirmationDeliveryReason
confirmation_delivery_updated_at  → confirmationDeliveryUpdatedAt
confirmation_delivered_at         → confirmationDeliveredAt
confirmation_provider_message_id  → confirmationProviderMessageId
requires_email_correction         → requiresEmailCorrection

reminder_delivery_status          → reminderDeliveryStatus
reminder_delivery_reason          → reminderDeliveryReason
reminder_delivery_updated_at        → reminderDeliveryUpdatedAt
reminder_delivered_at               → reminderDeliveredAt
reminder_provider_message_id        → reminderProviderMessageId
requires_reminder_correction        → requiresReminderCorrection
```

### Confirmation provenance

```text
confirmation_source        → confirmationSource
confirmation_source_label  → confirmationSourceLabel
auto_confirmed_at          → autoConfirmedAt
confirmed_by_user_id       → confirmedByUserId
```

### Confirm response (top-level)

```text
email_status           → emailStatus          (legacy send attempt)
email_delivery_status  → emailDeliveryStatus  (delivery truth; optional on old backend)
```

All delivery/provenance DTO fields are **optional** for old-backend compatibility.

---

## 3. SwiftData cache

**File:** `Persistence/ReservationRecord.swift`

- Delivery status stored as raw strings (`confirmationDeliveryStatusRaw`, `reminderDeliveryStatusRaw`)
- Provenance stored as raw strings + timestamps
- Mapped on `init(from:)` / `update(from:)` / `isContentEquivalent`
- **Additive migration** — new columns default nil/false; no custom `VersionedSchema`

**Stale cache risk:** Rows synced before backend db 1.13.0 may have `_sentAt` set but delivery raw nil until next refresh. Presentation uses **effective** status (see §5).

---

## 4. Presentation layer

**File:** `Features/Reservations/ReservationPresentation.swift` (`ReservationRecord` extension)

### Stored vs effective status

| Property | Meaning |
|----------|---------|
| `confirmationDeliveryStatus` | From server raw; nil/empty raw → `.notApplicable` |
| `effectiveConfirmationDeliveryStatus` | If stored is `.notApplicable`/`.unknown` **and** `confirmationEmailSentAt` set → treat as `.legacyRecorded` for **copy/labels only** |
| Same pattern | `reminderDeliveryStatus` / `effectiveReminderDeliveryStatus` / `reminderEmailSentAt` |

Server-sent `legacy_recorded` is preferred; effective mapping is a **local fallback** until refresh/backfill.

### Key helpers

| Helper | Logic |
|--------|--------|
| `isAutoConfirmedByBackend` | `confirmationSource == .autoConfirm` |
| `hasVerifiedConfirmationDelivery` | stored `confirmationDeliveryStatus == .delivered` only |
| `needsEmailCorrection` | `requiresEmailCorrection` OR failed/suppressed/complained |
| `needsReminderCorrection` | `requiresReminderCorrection` OR failed reminder delivery |
| `hasConfirmationEmailRecord` | Delivery status implies attempt OR legacy `_sentAt` |
| `hasReminderEmailRecord` | Same for reminder |

### Staff-facing copy (detail)

Uses `confirmationDeliveryDetailText` / `reminderDeliveryDetailText` via `effective*` status:

- **Pending** → waiting for delivery confirmation
- **Delivered** → only when status is `.delivered`
- **Failed/suppressed/complained** → correction / manual follow-up wording
- **Legacy** → recorded before delivery tracking
- **Phone / no email** → provenance overrides (no fake delivered)

---

## 5. Staff UI surfaces

### Reservation Detail

- **Confirmation email** row: delivery detail text (not "sent/recorded" as delivered)
- **Correction banner** when `needsEmailCorrection` or failed confirmation delivery
- **Actions:** Edit email (PATCH), **Resend** (`POST …/resend-confirmation`), **Confirm by phone** (`POST …/confirm-by-phone`)
- **Auto-confirm badge** on hero: `isAutoConfirmedByBackend` only

**Files:** `ReservationDetailView.swift`, `DetailActionBar`

### Bookings list rows (standard)

- Auto-confirm sparkle when `confirmationSource == .autoConfirm`
- Envelope/bell icons use `confirmationDeliveryLabel` / `reminderDeliveryLabel` (not `_sentAt` alone)
- **No** full delivery dashboard on every row

### Host Board rows

- **Lightweight:** only **"Email issue"** when confirmation failed or needs correction
- **No** pending/delivered/manual badge on every host row
- Auto-confirm sparkle same as list (DTO source)
- Reminder delivery detail → **Shift reminders sheet** / reminder stats, not host rows

**Files:** `ReservationRowView.swift`, `HostBoardReservationRow.swift`

### Shift reminders (`ShiftReminderReviewSheet`)

- Summary buckets: delivered, waiting, issues, manual/legacy, no email
- **Delivery watchlist** for reservations needing reminder attention
- Row label: `reminderDeliveryLabel` (not blanket "Reminder sent")
- Failed reminders: manual follow-up (no `resend-reminder` backend route yet)

### Service Intelligence / Staff Briefing

- Counts use delivery buckets: delivered, pending, failed, needs correction
- Prompt includes: *"do not claim delivery unless delivered"*
- `confirmationsSentCount` / `remindersSentCount` labeled **recorded/attempted** in prompt — not delivered

**Files:** `StaffBriefingPacketBuilder.swift`, `StaffBriefingPromptBuilder.swift`, `HostServiceIntelligenceSnapshotBuilder.swift`

---

## 6. API / mutation paths

| Action | Route | Service | Upsert |
|--------|-------|---------|--------|
| Confirm | `POST …/confirm` | `ReservationMutationService.confirmReservation` | `response.data` |
| Resend confirmation | `POST …/resend-confirmation` | `resendConfirmation` | returned DTO |
| Confirm by phone | `POST …/confirm-by-phone` | `confirmReservationByPhone` | returned DTO |
| Manual Mail log | `POST …/manual-email-log` | no delivery truth change on confirm status |

**Client:** `ReservationsAPIClient.swift`  
**Response type (correction):** `ReservationCorrectionResponse` in `ReservationsResponse.swift`

Confirm success notices branch on `emailDeliveryStatus` (fallback: DTO field, then legacy `emailStatus`). Pending → *"Email is waiting for delivery."*

---

## 7. Activity history vs auto-confirm

**File:** `ActivityHistory/ReservationActivityStore.swift`

- `hasBackendAutoConfirmEvidence` — **dead code**; zero call sites for badges
- Timeline may show `AutoConfirmedBadge` on `auto_confirmed` **events** — historic only
- **Do not** reintroduce activity inference for list/detail/host badges

After backend provenance backfill, old auto-confirmed rows should get `confirmation_source=auto_confirm` on refresh. Until then, badge may be hidden even if activity timeline shows historic auto-confirm.

---

## 8. Sync / freshness

Delivery fields participate in `ReservationRecord.isContentEquivalent`. When server `updated_at` changes (webhook, resend, correction), next active-window sync upserts local rows.

If detail looks wrong after backend deploy:

1. Pull refresh on Bookings/Host (active-window sync)
2. Re-open reservation detail (SwiftData `@Query` / passed record updates after upsert)
3. Verify backend db ≥ 1.13.0 backfill ran (see backend README)

---

## 9. Manual test checklist (iOS)

1. Confirm with email → detail **waiting for delivery**; notice matches
2. Webhook delivered (or simulated backend state) → refresh → **delivered** copy
3. Bounce/suppress → detail correction banner + Host **Email issue**
4. Resend after email fix → **waiting for delivery**; new attempt, not delivered
5. Confirm by phone → **Confirmed by phone**; email not marked delivered
6. Legacy row (`_sentAt` only, nil delivery raw) → **recorded before delivery tracking** (effective legacy)
7. Auto-confirm row with `confirmation_source=auto_confirm` → sparkle on list/host/detail
8. Row with `confirmation_source=legacy` → no sparkle; activity may still show historic event
9. Shift reminders sheet → bucket counts + watchlist for failed/pending reminders
10. StaffBriefing prompt → delivered vs attempted counts separated

---

## 10. Related docs

- [RESERVATION_WORKFLOWS.md](./RESERVATION_WORKFLOWS.md) — confirm/reminder/correction flows
- [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) — master rules §3
- [ACTIVITY_HISTORY.md](./ACTIVITY_HISTORY.md) — history-only auto-confirm decoration
- [DIAGNOSTICS_AND_TESTING.md](./DIAGNOSTICS_AND_TESTING.md) — full test matrix
- [Backend README — Email Delivery Truth](../Backend/tryzub-reservations-api/README.md)
