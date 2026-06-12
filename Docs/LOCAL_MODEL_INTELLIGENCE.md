# Local Model Intelligence

**Branch:** `intelligence`  
**Status:** Host/Home manager narrative (optional) + guest message drafts (template default, local model opt-in)

## Runtime

| Item | Detail |
|------|--------|
| Engine | On-device **llama.cpp** via **LlamaSwift** SPM (`mattt/llama.swift`) |
| Model file | `host-briefing-qwen2_5-0_5b-instruct-q4_k_m.gguf` (Application Support) |
| Ollama | **Not used** — no Ollama client or endpoint in this app |
| Cloud LLM | **Not used** — no OpenAI/Anthropic or other remote inference |
| Host/Home manager narrative | Optional, staff-gated (`useEnhancedBriefing`, `enhancedBriefingProvider = localModel`, `useLocalModelOnHostBoard`) |
| Guest message drafts | **Reservation Detail UI** shipped; **template drafts default** |
| Guest draft local model | **Opt-in** via Host Intelligence → `useLocalModelForGuestMessageDrafts` (default **off**, independent of Host board) |
| Business analytics narrative | **Not wired** — prototype packet only; remains deterministic |
| New Bookings narrative | **Not wired** — stays deterministic (row-level model adds PII risk, little value) |

## Intelligence boundaries

```
Backend intelligence  →  deterministic evidence (API)
Host engine           →  deterministic signals, decisions, HostLLMPacket
Local model           →  wording assistant only (manager narrative or message drafts)
Staff                 →  final sender; all Mail / Messages actions are manual
```

## Host/Home manager narrative

- **Wording only** — Host engine produces facts and actions; `ManagerNarrativePacket` is a minimal safe input; model rewrites headline / why / check-next
- **Settings** — uses existing Host local model toggles (`useEnhancedBriefing`, `useLocalModelOnHostBoard`); **not** the guest draft toggle
- **Input** — sanitized fact titles/details and existing action titles only; no raw reservations, notes, email, phone, evidence, or backend JSON
- **Output** — validator blocks technical terms, completion claims, unsupported check-next actions, and PII-like strings
- **Fallback** — deterministic `ManagerNarrativeTemplateBuilder` when model is off, unavailable, or output is unsafe
- **Diagnostics** — raw model output and prompt preview are developer-only (in-memory, not persisted)

The local model **must not**:

- Confirm, cancel, seat, or change reservation status
- Call `POST /confirm`, reminder endpoints, or any mutation API
- Auto-send email or SMS/iMessage
- Replace the Host engine or backend intelligence as a decision layer

## Guest communication drafts

### Reservation Detail UI (shipped)

- **Draft guest message** section: confirmation, reminder, clarification, large party, table ready
- Staff **reviews** subject, email body, and text in a sheet before sending
- **Send Email** → existing Mail composer (`GuestConfirmationMailPresenter.manualDraft`)
- **Send Text** → existing Messages composer (`GuestTextMessagePresenter`)
- **Copy Email / Copy Text** fallback on pasteboard
- **No auto-send**, **no reservation mutation** from draft generation or draft send prep
- **Template drafts** are the default when the setting is off or the model is unavailable
- **Local model draft mode** — Host Intelligence → **Use local model for guest message drafts** (default off; independent of Host board briefing toggle)
- Unavailable model, parse failure, or unsafe output → **template fallback** with optional review note; staff still sends manually

### Legacy vs new messaging

| Path | Notes in draft? | Sends? |
|------|-----------------|--------|
| Legacy confirmation-link email (`ManualEmailDraftService` + manage URL) | May include **guest notes** | Staff manual; optional manual-email log |
| Confirm + Email (`POST /confirm`) | Backend/provider path | Separate from draft UI |
| New AI-safe guest message drafts | **Exclude** raw guest notes, staff notes, email, phone, backend JSON, evidence | Staff manual after review |

### Rules (packet + output)

- **Drafts only** — staff review before sending
- **No automatic send** or reservation mutation
- **No internal staff notes** or raw guest notes in model input
- **No guest email or phone** in prompt packet or model output (restaurant contact allowlisted)
- Party size, table name, and boolean flags (large party, needs review) may appear when safe

### Allowed draft kinds

- `confirmation`, `reminder`, `clarificationRequest`, `largePartyConfirmation`, `tableReady`
- Custom follow-up (later)

### PII policy (prompt packet)

| Allowed | Not allowed |
|---------|-------------|
| Guest **first name** (optional) | Full name (avoid when possible) |
| Reservation date / time display | Raw email |
| Party size, table name | Guest email / phone |
| Restaurant name, phone, address | Guest notes |
| Manage URL (when staff already uses it) | Staff notes |
| Boolean flags (large party, needs review, etc.) | Guest history blobs |
| Policy hint strings (high level) | Backend evidence / JSON |

**Output safety:** guest phone-like strings in model output are blocked unless they match the allowlisted restaurant phone (normalized digits).

### Table / capacity context

- Drafts may use **party size** and **table name** flags from the allowlisted packet
- Table configuration comes from **`HostTableConfigStore`** (see `Docs/TABLE_CONFIGURATION.md`)
- Table fit and capacity signals are **advisory** — staff remains final operator and sender

### Output contract

```text
emailSubject
emailBody
shortMessageBody
safetyNote      (optional)
blockedReason   (optional)
```

Sources: `template`, `localModel`, `blocked`.

### `tableReady` kind

- Staff-triggered when seating is ready — draft may say the table is ready
- Must **not invent a table number** when `tableName` is missing
- Non-`tableReady` drafts must not say the table is ready

### Guest messaging architecture

```
ReservationDetailView
  → sheet state, action routing
GuestCommunicationCoordinator
  → draft prep, Mail/Text conversion, copy, staff-safe errors
GuestMessageDraftService
  → packet build → writer → validation
Template / local writer
  → GuestMessageDraft
GuestMessageDraftReviewView
  → staff review
Mail / Messages presenters
  → platform composers (staff sends)
```

- Coordinator **never sends** and **never mutates** reservations
- **Confirm + Email** (`POST /confirm`) remains a separate legacy/backend path

### Failure behavior

1. **Template fallback** — always available
2. **Local model unavailable** — template draft (`source: template`)
3. **Parse / validation failure** — template draft; optional `safetyNote`
4. **Unsafe output** — template fallback; optional review `safetyNote` in the sheet

## Code map

| Area | Location |
|------|----------|
| Communication facade | `Features/GuestMessaging/GuestCommunicationCoordinator.swift` |
| Draft service | `Features/GuestMessaging/GuestMessageDraftService.swift` |
| Review UI | `Features/GuestMessaging/GuestMessageDraftReviewView.swift` |
| Host briefing writer | `Features/HostIntelligence/HostBriefingWriter.swift` |
| Manager narrative | `Features/HostIntelligence/ManagerNarrativeWriter.swift`, `ManagerNarrativePacketSanitizer.swift` |
| Host LLM packet | `Features/HostIntelligence/HostIntelligenceModels.swift` |
| Guest message models | `Features/GuestMessaging/GuestMessageDraftModels.swift` |
| Packet builder | `Features/GuestMessaging/GuestMessageDraftPacketBuilder.swift` |
| Template drafts | `Features/GuestMessaging/GuestMessageDraftTemplateWriter.swift` |
| Local writer / validator | `Features/GuestMessaging/GuestMessageDraftWriter.swift`, `GuestMessageDraftValidator.swift` |

## Staff workflow (current)

1. Staff opens reservation detail
2. Taps **Draft confirmation** (or reminder, etc.)
3. `GuestCommunicationCoordinator` → template or enhanced draft (per setting) → review sheet
4. Staff reviews subject / body / SMS
5. Staff sends via **Mail** or **Messages**, or copies to pasteboard
6. Staff records sent status manually if needed (legacy manual-email log path unchanged)

No step auto-sends or mutates the reservation.

## Final TestFlight AI Safety Checklist

The Host Intelligence / local-LLM layer is **advisory only**. Deterministic facts,
actions, and a template briefing always render; the model only improves wording when
there is real operational tension. Proof traces (all `#if DEBUG`, OSLog category `HostAI`):

| Trace | Emitted from | Proves |
|-------|--------------|--------|
| `[HOST_AI_FACTS_TRACE]` | `HostIntelligenceController.evaluate` | deterministic facts/categories per date; guestSignals=server\|local_bounded; floorTables=backend\|local |
| `[HOST_AI_GATE] allowed=… reason=… categories=…` | `HostBriefingHostBoardGate.logGateDecision` | model runs only for tension; skips simple days with an explicit reason |
| `[HOST_AI_PACKET_TRACE] containsRawContact=false containsRawNotes=false` | `ManagerNarrativeWriter.write` | sanitized packet; no raw email/phone/notes/JSON reach the model |
| `[HOST_AI_LIFECYCLE] event=model_started\|model_completed\|model_unavailable\|model_cancelled\|fallback_used` | `ManagerNarrativeWriter` / `HostIntelligenceController` | model actually runs, falls back, or is cancelled — never silent |
| `[HOST_AI_VALIDATOR] result=pass\|blocked reason=<token>` | `ManagerNarrativeWriter.write` | unsupported output is blocked before UI |
| `[HOST_AI_TEST] scenario=… result=pass\|blocked` | `HostAIValidatorProofHarness` (DEBUG, once per launch) | validator blocks raw contact, leaked labels, completed-status, guest-facing, invented "regular/always", over-long; passes calm supported case |

### Guarantees
- **Skip:** no facts / simple count / simple peak / unchanged packet / backgrounded / view hidden / model or validator unavailable.
- **Run:** no-table-soon, late attention, seated-too-long, table pressure, allergy/dietary/accessibility note, prior service issue, returning-guest context, multiple competing actions.
- **Sanitize:** `ManagerNarrativePacketSanitizer` strips email, phone, JSON-like text, evidence markers, invented occasion language; max 180 chars/line.
- **Validate:** blocks invented guest/table/status facts, "always/never", "regular/VIP" without evidence, raw phone/email, auto-action instructions, over-long output.
- **Fallback:** deterministic template is always available and never blank.
- **Non-blocking:** engine eval measured by `[UI_PRESSURE_TRACE] phase=host_engine_evaluate` (~<15ms); model runs async; actions stay tappable.

### Known limitations (device sign-off)
- `model_started`/`model_completed` and a real `[HOST_AI_VALIDATOR] result=pass` from genuine
  model output require a physical device with the GGUF bundled and an AI-worthy day.
- No hard inference timeout / `Task.cancel`; bounded instead by `maxOutputTokens=100` and the
  date-change/view-hidden generation guard. `model_timeout` trace exists but is not yet wired
  to a timer.
