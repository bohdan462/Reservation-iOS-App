# Reservation Attachments — Backend-Sync Handoff

**Purpose:** Implementation handoff for **private, backend-synced reservation image attachments**. Read this before any Agent coding on attachments.

**Navigation:** [DOCS_INDEX.md](./DOCS_INDEX.md) · [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md) · [IMPLEMENTATION_QUEUE.md](./IMPLEMENTATION_QUEUE.md)

**Audience:** GPT-5.5 Agent (backend/iOS), Composer 2.5 (audit/docs), Bohdan (deploy/device test).

**Status:** Backend **deployed and production-smoked** (plugin **0.5.5**, DB **1.12.0**, backend `a2422d3`). iOS **Slice C** at `17a0bee` (DTO/API/cache). iOS **Slice D** at `d947721` (Detail shared list/upload/download/delete). iOS **Slice E** at `9d2784d` (attachment management UI polish). `AttachmentFeatureFlag.remoteUploadEnabled` is **true**. Build **12** tracked (`f2e9be0`). **Live/cross-device verification still open** — do not claim passed. **Next practical step:** live verification checklist (§9) + TestFlight build 12 upload — **not** new attachment backend or Slice C/D/E implementation.

---

## 1. Current shipped state (2026-06-28)

### Repo / backend baseline

| Area | State |
|------|--------|
| Root branch | `audit-current-state` |
| Root HEAD | `f2e9be0` — Track build 12 project settings |
| Backend branch | `AI` |
| Backend HEAD (root pointer) | `a2422d3` — **deployed**, production-smoked |
| Plugin / DB | **0.5.5** / **1.12.0** — contract in [Backend README](../Backend/tryzub-reservations-api/README.md) |
| Device smoke Phases 1–4 | Code landed; **physical verification still open** |

### What is shipped (iOS + backend)

Reservation Detail **shared attachments** are **remote-backed** when staff credentials and a reservation id are present:

| Layer | Behavior |
|-------|----------|
| Backend | Source of truth for metadata + private file storage (`tryzub_reservation_attachments`, staff-auth routes — see Backend README) |
| iOS network | List / upload / PATCH / delete / download content via `ReservationsAPIClient` — **detail-scoped only** |
| Feature flag | `AttachmentFeatureFlag.remoteUploadEnabled` = **`true`** (gated at runtime by reservation id + credentials in Detail) |
| SwiftData | `ReservationAttachmentRecord` with remote fields (`remoteID`, sync state, server timestamps) — **no image blobs** |
| Disk cache | `AttachmentFileStore` — bytes downloaded on demand |
| OCR | On-device advisory only; **not** synced operational truth |
| Guest routes | Self-service **does not** expose attachments |

**Key iOS files:**

- `Features/ServiceIntelligence/Models/ReservationAttachment.swift` — labels, `AttachmentFeatureFlag`
- `Persistence/ReservationAttachmentRecord.swift` — metadata + remote upsert helper
- `Persistence/AttachmentFileStore.swift` — local byte cache
- `Features/Reservations/ReservationDetailView.swift` — shared attachment UI (Slices D + E)

Normal reservation active-window refresh **must not** auto-download attachment bytes or call `POST /managed-reservations/import`.

### Pre-sync legacy (historical only)

Attachments saved **before Slice D** may remain **local-only on the original device** — they were **not** auto-uploaded. Staff should **reattach** important old images if they need shared visibility on other devices.

### Still open (verification — not implementation)

| Item | Status |
|------|--------|
| Live/cross-device checklist (§9) | **Open** — device verification required |
| TestFlight build 12 upload | Release ops — build 12 tracked in project |
| Slice F — intelligence packet labels | Not started |
| Upload/list race duplicate rows | Fix only if observed during verify |

### Verdict

**Implemented in code; not production-verified until §9 checklist passes on physical devices.** Agents must **not** re-implement Slices C/D/E. Do **not** treat pre-sync local-only rows as multi-device operational truth.

---

## 2. Architecture decision

### Chosen model

1. **Backend is source of truth** for attachment metadata and file storage.
2. **Metadata** lives in backend database table `tryzub_reservation_attachments`.
3. **Image files** live on backend server disk in **private plugin-controlled storage** (not public WordPress media URLs).
4. **iOS stores local cache only** — metadata rows + downloaded JPEG files in `AttachmentFileStore`.
5. **Devices never fetch images from other staff devices.** Fresh install asks backend for metadata, then downloads bytes via **authenticated content route**.
6. **Normal reservation list sync** may include lightweight summary later (`attachment_count`); full attachment list is **detail-scoped fetch**.

### Explicitly rejected

| Rejected | Reason |
|----------|--------|
| Public WordPress media URLs | Receipts/deposits must not be world-readable |
| Guest token exposure | Self-service must never list or download staff attachments |
| Local-only source of truth | Boss requires cross-device sync |
| SwiftData blob storage | Large binaries bloat cache and sync |
| Large binaries in `ReservationRecord` | Violates reservation row equivalence / sync design |
| LLM / Apple summaries mutating tags | Tags are staff metadata; summaries are advisory/future only |
| iOS-only implementation claiming sync | Misleading and fails fresh-install recovery |
| PDF in V1 | Image-only unless Bohdan expands scope |

### Architecture rules (inherit from project)

- Do **not** create a second API client.
- Do **not** create a second reservation store.
- Do **not** create a duplicate attachment manager if extending existing types suffices.
- Preserve Reservation Detail confirmation/reminder/Manual Mail workflows.
- Normal iOS refresh must **not** call `POST /managed-reservations/import`.

---

## 3. WordPress private storage model

### Intended path

```
/wp-content/uploads/tryzub-private/reservation-attachments/
  {reservation_id}/
    {attachment_id}.jpg
```

Or equivalent **plugin-controlled private directory** under uploads (exact path documented in [Backend README](../Backend/tryzub-reservations-api/README.md)).

### Requirements

| Requirement | Detail |
|-------------|--------|
| Block direct browser access | `.htaccess`, nginx deny, or store outside web root |
| No public file URLs in API | Responses return attachment **ids** and **authenticated API paths** only |
| Staff auth on every byte | `GET .../content` checks `tryzub_can_read_reservations` (or stricter write capability for upload/delete) |
| Guest routes | Must **never** register attachment handlers under `/reservation-self/*` |
| File naming | Server-side path must not be guessable from reservation id alone without auth |

---

## 4. Backend database contract

### Table: `tryzub_reservation_attachments`

| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGINT PK AUTO_INCREMENT | Server attachment id |
| `reservation_id` | BIGINT NOT NULL | FK to managed reservation |
| `storage_path` | TEXT NOT NULL | Private relative path on server |
| `original_filename` | TEXT NULL | Display / audit |
| `mime_type` | VARCHAR(64) | e.g. `image/jpeg` |
| `file_size_bytes` | BIGINT | Enforce max on upload |
| `width` | INT NULL | Optional, from image probe |
| `height` | INT NULL | Optional |
| `label` | VARCHAR(64) NOT NULL | Staff tag (enum-aligned string) |
| `caption` | TEXT NULL | Optional staff note |
| `uploaded_by_user_id` | BIGINT NULL | WordPress user id |
| `created_at` | DATETIME NOT NULL | |
| `updated_at` | DATETIME NULL | |
| `deleted_at` | DATETIME NULL | Soft delete |

**Indexes:** `(reservation_id, deleted_at)`, `(reservation_id, created_at)`.

### Optional / future (not V1)

| Column | Notes |
|--------|-------|
| `thumbnail_storage_path` | Server-generated thumb; V1 may use iOS-side thumb from downloaded full image |
| `staff_verified_summary` | Future Apple/LLM summary **after staff review** |
| `ocr_text` | Future; if synced, treat as advisory not truth |
| `ocr_reviewed_at` | Future |

Bump `tryzub_get_reservations_db_version()` when table is added (`activation.php`).

---

## 5. Backend route contract (V1)

Base: `/wp-json/tryzub/v1`

| Method | Route | Purpose |
|--------|-------|---------|
| GET | `/managed-reservations/{id}/attachments` | List metadata for reservation (excludes soft-deleted unless `?include_deleted=1` dev-only) |
| POST | `/managed-reservations/{id}/attachments` | Multipart upload + `label` + optional `caption` |
| PATCH | `/managed-reservations/{id}/attachments/{attachment_id}` | Update `label` and/or `caption` only |
| DELETE | `/managed-reservations/{id}/attachments/{attachment_id}` | Soft delete (`deleted_at`) |
| GET | `/managed-reservations/{id}/attachments/{attachment_id}/content` | Stream image bytes after staff auth |

### Rules

- **Staff auth required** on all routes (`tryzub_can_read_reservations`; confirm upload/delete capability with existing manager patterns).
- **Guest self-service** cannot access any attachment route or content URL.
- **GET list** returns metadata JSON only — no embeddable public URLs.
- **POST** accepts `multipart/form-data` with file field (e.g. `file`) + form fields `label`, optional `caption`.
- **PATCH** does not replace image bytes in V1.
- **DELETE** soft-deletes; physical file retention policy documented in README (delete immediately vs grace period).
- **GET content** sets appropriate `Content-Type` and `Content-Disposition: inline` for in-app preview; still requires auth header.
- **Image-only V1** — reject PDF and non-image MIME.
- **Max upload size:** **8 MB** backend limit (recommend; iOS already compresses before upload).
- **MIME allowlist:** `image/jpeg`, `image/png`, `image/heic`, `image/heif`.
- **Prefer iOS upload as JPEG** even when picker source is HEIC/PNG (existing resize pipeline).
- Log **`attachment_added`** / **`attachment_removed`** (and optionally `attachment_updated`) via `tryzub_reservation_activity_log`.
- Optional on GET `/managed-reservations/{id}`: `attachment_count`, `attachment_labels[]` summary — not required for Slice A.

### Example list item (metadata only)

```json
{
  "id": 42,
  "reservation_id": 1001,
  "label": "Deposit",
  "caption": "Zelle screenshot",
  "mime_type": "image/jpeg",
  "file_size_bytes": 245000,
  "width": 1200,
  "height": 1600,
  "uploaded_by_user_id": 3,
  "created_at": "2026-06-26T18:00:00+00:00",
  "updated_at": null,
  "content_path": "/tryzub/v1/managed-reservations/1001/attachments/42/content"
}
```

**Do not return** a bare `/wp-content/uploads/...` URL.

---

## 6. iOS contract (implemented — Slices C–E)

**Status:** **Done in code** at `17a0bee` / `d947721` / `9d2784d`. Do **not** re-implement. See §8 for commit references.

### API surface (`ReservationsAPIClient`)

- `listAttachments(reservationID:)`
- `uploadAttachment(reservationID: imageData: label: caption:)`
- `updateAttachment(reservationID: attachmentID: label: caption:)`
- `deleteAttachment(reservationID: attachmentID:)`
- `downloadAttachmentContent(reservationID: attachmentID:)` → bytes to `AttachmentFileStore`

### DTO

- `ReservationAttachmentDTO` mirroring backend metadata (no inline base64 in list).

### SwiftData — extend `ReservationAttachmentRecord`

Add remote fields; **do not store image bytes in SwiftData.**

| Field | Purpose |
|-------|---------|
| `remoteID` | Backend attachment id (nil while upload pending) |
| `reservationRemoteID` | Existing |
| `remoteCreatedAt` / `remoteUpdatedAt` / `remoteDeletedAt` | Server timestamps |
| `syncState` | e.g. pendingUpload, synced, pendingDelete, failed |
| `remoteLabel` / `remoteCaption` | Mirror server (or keep `labelRaw` + `note` mapped) |
| `localFullImageCacheFilename` | Disk cache key |
| `localThumbnailCacheFilename` | Optional separate thumb file |
| `filename` | Existing local cache file name |

Keep `AttachmentFileStore` as **local cache only**.

### UI behavior (Slice D + E — shipped)

- Reservation Detail **fetches attachment list on open** (and after upload/delete/manual refresh).
- Upload progress / error states; manage sheet; label + note edit (shared PATCH); fit-to-screen preview; manage delete.
- Fresh install: list from backend → download content on demand.
- `AttachmentFeatureFlag.remoteUploadEnabled` is **`true`** when Detail gates allow (reservation id + credentials).

### Local OCR (existing)

- May continue on-device for UX hints.
- **Do not** treat OCR text as synced truth unless product adds explicit staff-reviewed sync later (Slice F readiness only).

---

## 7. Labels / tags (V1)

### Fixed primary labels (one per attachment)

| Label | Use |
|-------|-----|
| Deposit | Deposit receipt / payment proof |
| Receipt | General receipt |
| Preorder | Preorder screenshot / kitchen reference |
| Banquet | Banquet / group event document |
| Guest screenshot | Guest-provided image |
| Setup photo | Table/room setup reference |
| Signed agreement | Signed agreement photo |
| Reference image | Menu, reference, staff note image |
| Other | Uncategorized |

**Note:** Current iOS enum uses slightly different strings (e.g. “Guest screenshot”, “Setup”). Align iOS ↔ backend on deploy; migration map old local labels if needed.

### Rules

- **One primary label** per attachment in V1 (no multi-tag array).
- **Caption** optional free text.
- Labels are **staff metadata** chosen by staff — not LLM-generated.
- OCR / future Apple image summarization is **advisory** and must **not** auto-set labels or operational facts without staff review.

---

## 8. Implementation slices

### Slice A — Backend private storage + DB + routes

| | |
|--|--|
| **Goal** | Staff-auth CRUD + private file storage + activity log events |
| **Backend files** | New `includes/reservation-attachments.php`, `includes/routes.php`, `includes/activation.php`, `tryzub-reservations-api.php` loader, `README.md` |
| **Do not touch** | iOS, guest self-service, confirmation/reminder/email, device smoke Swift |
| **Acceptance** | curl: upload, list, patch label, delete, content download with auth; 401 without auth; reject oversize/non-image |
| **Commit** | Backend repo on `AI`; root pointer bump when ready |
| **Deploy** | WordPress plugin zip from backend HEAD — **required before iOS sync** |

### Slice B — Backend deployment + manual tests

| | |
|--|--|
| **Status** | **Done** — deployed to WordPress; production smoke **2026-06-26** |
| **Goal** | Deploy to WordPress; document private path + htaccess; curl checklist passed on production/staging |
| **Files** | Backend README, optional `Docs/DIAGNOSTICS_AND_TESTING.md` addendum later |
| **Production smoke** | Core staff attachment API **passed** (list/upload/metadata/content/PATCH/DELETE/guest self-service). **Direct image URL → 404** (no public bytes). **Unauthenticated REST content → 401**. **Directory marker URL → cached 200 text/html** — not blocking; host/nginx hardening for `tryzub-private/` remains recommended. HEIC/oversize/PDF optional; **iOS V1 should upload JPEG only**. |
| **Acceptance** | All backend tests in §9 backend subset pass on deployed server |

### Slice C — iOS DTO / API / cache metadata

| | |
|--|--|
| **Status** | **Done** — root `17a0bee` |
| **Goal** | Network client, DTOs, sync merge into `ReservationAttachmentRecord`, disk cache download |
| **iOS files** | `Network/ReservationsAPIClient*.swift`, new DTO, `ReservationAttachmentRecord.swift`, `AttachmentFileStore` (no second client) |
| **Do not touch** | Reservation Detail UI beyond wiring flags; Host/Bookings rows |
| **Acceptance** | Device + Simulator builds pass; API methods exist; `remoteUploadEnabled` **true** in code; Detail remote wiring in Slice D |
| **Commit** | `17a0bee` — Add reservation attachment iOS sync foundation |

### Slice D — Reservation Detail UI sync

| | |
|--|--|
| **Status** | **Done** — root `d947721` |
| **Goal** | Detail-scoped list/upsert/download/upload/delete; progress/errors; enable remote upload flag when wired |
| **iOS files** | `ReservationDetailView.swift`, `ReservationAttachment.swift`, `AttachmentFileStore.swift` |
| **Acceptance** | Device + Simulator builds pass; Detail wires shared attachments; API calls detail-scoped only; no normal refresh attachment downloads; no public URL usage |
| **Commit** | `d947721` — Wire reservation detail shared attachments |
| **Notes** | Old pre-sync **local-only** attachments remain on the original device only — **not** auto-uploaded. Staff should **reattach important old images** after update if they need shared visibility. Known follow-up if observed: upload/list race can duplicate rows if metadata refresh completes before upload applies `remoteID`. |

### Slice E — Attachment management UI polish

| | |
|--|--|
| **Status** | **Done** — root `9d2784d` |
| **Goal** | Staff-friendly rows; manage/details sheet; edit tag + note; fit-to-screen preview; manage delete; PATCH for shared rows |
| **iOS files** | `ReservationDetailView.swift` |
| **Acceptance** | UUID/original filenames hidden from default row UI; shared edit calls backend PATCH; local-only edit stays local; `deletedRemote` skipped by note signals; builds pass |
| **Commit** | `9d2784d` — Polish reservation attachment management UI |
| **Notes** | Save to Photos supported (build 12 adds `NSPhotoLibraryAddUsageDescription`). Old pre-sync local-only attachments remain device-only — staff should **reattach** if shared visibility needed. |

### Live verification — cross-device checklist (open)

| | |
|--|--|
| **Status** | **Open** — do not claim passed |
| **Goal** | Device A upload → Device B sees; B delete → A refresh clears; fresh install recovery; edit label/caption sync |
| **Files** | Fix-only across iOS/backend from test failures |
| **Acceptance** | Full §9 device checklist |
| **Note** | Separate from device smoke Phases 1–4; may share same hardware session |

### Slice F — Intelligence readiness (no summarization)

| | |
|--|--|
| **Goal** | Include synced **label + caption** in deterministic intelligence packets; optional blank `staff_verified_summary` field in schema for future |
| **Do not** | Ship Apple image summarization, auto-tag from OCR/LLM, or mutate reservation status from attachments |
| **Acceptance** | Service Intelligence sees backend-synced labels only; OCR remains local advisory |

---

## 9. Testing checklist

### Multi-device / recovery

- [ ] Device A uploads **multiple** images to one reservation
- [ ] Device B opens same reservation → sees same attachment metadata
- [ ] Device B downloads/views full images
- [ ] Fresh install (or cleared app data) on Device B → metadata from backend → can download images
- [ ] Device B deletes one attachment
- [ ] Device A refreshes detail → deleted attachment gone
- [ ] PATCH label/caption on A → B sees update after refresh

### Security / privacy

- [ ] Direct browser access to private storage path **blocked** (403/404)
- [ ] Unauthenticated `GET .../content` → **401/403**
- [ ] Guest self-service token routes **do not** include attachments
- [ ] API list response **does not** contain public `/wp-content/uploads/...` URLs

### Validation

- [ ] File **> 8 MB** rejected
- [ ] Non-image MIME (e.g. PDF) rejected
- [ ] HEIC upload accepted (stored/served as JPEG or HEIC per backend policy)

### Activity

- [ ] Upload logs `attachment_added`
- [ ] Delete logs `attachment_removed`

### Regression

- [ ] Reservation confirm/email/reminder flows unchanged
- [ ] Guest self-service cancel still works
- [ ] Normal reservation sync unchanged

---

## 10. Hard safety rules

1. **No public URLs** for attachment bytes.
2. **No guest access** to attachment list or content.
3. **No local-only success state** presented as synced — UI must show pending/failed until server confirms.
4. **No binary blobs in SwiftData.**
5. **No images embedded in `ReservationRecord`.**
6. **No iOS-only implementation** claiming cross-device sync.
7. **No Apple image summarization in V1.**
8. **No PDF support in V1** unless Bohdan explicitly expands scope.
9. **No LLM/OCR auto-tags** — staff labels only for truth; OCR local advisory until explicit future design.
10. **Slices A–E are shipped** — do **not** re-implement iOS sync or backend attachment routes unless a verified regression is found.

---

## 11. Agent order (verification only)

Slices A–E are **done**. Agents must **not** re-implement attachment sync.

1. Run §9 **live/cross-device checklist** on physical devices (device verification open).
2. Fix-only PRs if checklist finds regressions (upload/list race, auth, delete propagation).
3. **Slice F** only when product explicitly requests intelligence packet label inclusion.
4. Backend contract changes → edit [Backend README](../Backend/tryzub-reservations-api/README.md) first, not this file’s route tables.

---

## 12. Related local-only systems (out of scope for this handoff)

`ReservationStructuredNoteRecord` (manager/kitchen/bar/deposit/preorder notes) is also **local-only** today — separate backend project; do not conflate with attachment sync.

---

*Created: 2026-06-26. Updated: 2026-06-28. Align with root `f2e9be0`, backend pointer `a2422d3`, iOS Slices C–E shipped. Live device verification still open.*
