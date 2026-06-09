# Local Model Intelligence

**Branch:** `intelligence`  
**Status:** Host briefing + guest message draft foundation

## Runtime

| Item | Detail |
|------|--------|
| Engine | On-device **llama.cpp** via **LlamaSwift** SPM (`mattt/llama.swift`) |
| Model file | `host-briefing-qwen2_5-0_5b-instruct-q4_k_m.gguf` (Application Support) |
| Ollama | **Not used** — no Ollama client or endpoint in this app |
| Cloud LLM | **Not used** — no OpenAI/Anthropic or other remote inference |
| Current production use | **Host briefing rewrite** (optional, staff settings) |
| In progress | **Guest message drafts** (packet + template + local writer shell; UI in a later phase) |

## Intelligence boundaries

```
Backend intelligence  →  facts / evidence (API)
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

### Rules

- **Drafts only** — staff review before sending
- **No automatic send**
- **No automatic reservation mutation**
- **No internal staff notes** in model input
- **No raw guest notes** in model input
- **No raw backend JSON** or evidence arrays in model input
- **No guest email or phone** in the prompt packet (future product decision required to change this)

### Allowed draft kinds

- `confirmation`
- `reminder`
- `clarificationRequest`
- `largePartyConfirmation`
- `tableReady`
- Custom follow-up (later)

### PII policy (prompt packet)

| Allowed | Not allowed |
|---------|-------------|
| Guest **first name** (optional) | Full name (avoid when possible) |
| Reservation date / time display | Raw email |
| Party size, table name | Raw phone |
| Restaurant name, phone, address | Guest notes |
| Manage URL (when staff already uses it) | Staff notes |
| Boolean flags (large party, needs review, etc.) | Guest history blobs |
| Policy hint strings (high level) | Backend evidence / JSON |

Guest history may appear later only as **safe summarized flags**, never raw records.

### Output contract

```text
emailSubject
emailBody
shortMessageBody
safetyNote      (optional)
blockedReason   (optional)
```

Sources: `template`, `localModel`, `blocked`.

### Failure behavior

1. **Template fallback** — always available; existing manual templates are never blocked
2. **Local model unavailable** — return template draft (`source: template`)
3. **Parse / validation failure** — return template draft; optional `safetyNote`
4. **Unsafe packet** — do not call model; template or `source: blocked` with `blockedReason`

## Code map

| Area | Location |
|------|----------|
| Host briefing writer | `Features/HostIntelligence/HostBriefingWriter.swift` |
| Host LLM packet | `Features/HostIntelligence/HostIntelligenceModels.swift` |
| Guest message packet | `Features/GuestMessaging/GuestMessageDraftModels.swift` |
| Packet builder | `Features/GuestMessaging/GuestMessageDraftPacketBuilder.swift` |
| Template drafts | `Features/GuestMessaging/GuestMessageDraftTemplateWriter.swift` |
| Prompt builder | `Features/GuestMessaging/GuestMessageDraftPromptBuilder.swift` |
| Local writer | `Features/GuestMessaging/GuestMessageDraftWriter.swift` |
| Validator / parser | `Features/GuestMessaging/GuestMessageDraftValidator.swift`, `GuestMessageDraftOutputParser.swift` |

## Staff workflow (target — Phase 4B+)

1. Staff opens reservation detail
2. Taps **Draft confirmation** (or reminder, etc.)
3. App builds `GuestMessageDraftPacket` → template or local model → `GuestMessageDraft`
4. Staff reviews subject/body/SMS
5. Staff sends via existing **Mail** or **Messages** composer
6. Staff records sent status manually if needed

No step auto-sends or mutates the reservation.
