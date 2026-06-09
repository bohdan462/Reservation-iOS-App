# Local Model Intelligence

**Branch:** `intelligence`  
**Status:** Host briefing (optional) + guest message drafts (template default, local model opt-in)

## Runtime

| Item | Detail |
|------|--------|
| Engine | On-device **llama.cpp** via **LlamaSwift** SPM (`mattt/llama.swift`) |
| Model file | `host-briefing-qwen2_5-0_5b-instruct-q4_k_m.gguf` (Application Support) |
| Ollama | **Not used** — no Ollama client or endpoint in this app |
| Cloud LLM | **Not used** — no OpenAI/Anthropic or other remote inference |
| Host briefing | Optional, staff-gated (`useEnhancedBriefing`, `useLocalModelOnHostBoard`) |
| Guest message drafts | **Reservation Detail UI** shipped; **template drafts default** |
| Guest draft local model | **Opt-in** via Host Intelligence → `useLocalModelForGuestMessageDrafts` (default **off**) |

## Intelligence boundaries

```
Backend intelligence  →  deterministic evidence (API)
Host engine           →  deterministic signals, decisions, HostLLMPacket
Local model           →  wording assistant only (briefing or message drafts)
Staff                 →  final sender; all Mail / Messages actions are manual
```

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
