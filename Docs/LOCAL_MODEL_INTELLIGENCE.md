# Local Model Intelligence

**Status:** Current source of truth — wording assistant only  
**Branch:** `audit-current-state`  
**Audit date:** 2026-06-14  
**Host pipeline:** [HOST_INTELLIGENCE.md](./HOST_INTELLIGENCE.md)

Template fallback always available.

**Historical research:** `Docs/ARCHIVE/HOST_INTELLIGENCE_LOCAL_MODEL_RUNTIME_PROPOSAL.md`

## Runtime (current code)

| Item | Detail |
|------|--------|
| Engine | On-device **llama.cpp** via **LlamaSwift** SPM (`mattt/llama.swift`) |
| Runtime implementation | `HostLlamaBriefingRuntime` only (`HostLocalModelRuntimeFactory`) |
| Ollama | **Not used** |
| Cloud LLM | **Not used** |
| Apple Foundation Models | **Not implemented** — proposal only in historical doc |
| Model resolution | `HostLocalModelFileLocator.bestAvailableProfile()` prefers **3B → 0.5B → template** |
| 0.5B file | `host-briefing-qwen2_5-0_5b-instruct-q4_k_m.gguf` (`LocalWordingModelProfile.smallFastLocal`) |
| 3B file | `host-wording-qwen2_5-3b-instruct-q4_k_m.gguf` (`LocalWordingModelProfile.betterLocal3B`) |
| 3B bundling | Optional build flag `REQUIRE_3B_HOST_MODEL=1` bundles 3B as primary wording model |
| File locations | Application Support first, then app bundle; staff can import `.gguf` from Files |
| Copy script | `Scripts/copy-host-briefing-model-to-bundle.sh` (build phase) |

## Intelligence boundaries

```
Backend intelligence  →  deterministic evidence (API) — source of truth for guest signals
Host engine           →  deterministic signals, decisions, facts, actions
Local model           →  wording assistant only (never decides status, tables, or facts)
SwiftData             →  cache only — not guest-intelligence truth
Staff                 →  final sender; Mail / Messages are manual
```

The local model **must not**:

- Confirm, cancel, seat, or change reservation status
- Call any mutation API (`POST /confirm`, `PATCH`, table assignment, etc.)
- Auto-send email or SMS/iMessage
- Decide table availability or floor layout
- Replace backend guest intelligence or invent guest history
- Invent facts not present in sanitized packets

All model output is **validated or falls back** to deterministic templates.

## Task profiles (`HostLocalModelTaskProfile`)

Per-task system prompt, token budget, stop markers, and **wall-clock timeout**:

| Task | Profile | maxOutputTokens | maxInferenceSeconds | Production use |
|------|---------|-----------------|---------------------|----------------|
| Host briefing rewrite | `hostBriefing` | 100 | 12 | Optional via `useEnhancedBriefing` + `useLocalModelOnHostBoard` |
| Manager narrative | `managerNarrative` | 100 | 12 | Host board when operational tension gate passes |
| Guest message draft | `guestMessageDraft` | 360 | 18 | Opt-in via `useLocalModelForGuestMessageDrafts` (default **off**) |
| Note analysis | `noteAnalysis` | 120 | 10 | Service Intelligence local note analyzer (when enabled) |

**Wording profile vs task profile:** `LocalWordingModelProfile` picks which GGUF file (3B/0.5B/template). `HostLocalModelTaskProfile` picks inference tuning per task.

Guest draft path uses `bestAvailableProfile()` when local model is enabled — same 3B→0.5B priority as host briefing.

## Host / manager narrative (shipped)

- Deterministic `HostIntelligenceEngine` + `ManagerNarrativePacketSanitizer` produce facts
- Model rewrites headline / why / check-next only when gate allows (busy day signals)
- Fallback: `ManagerNarrativeTemplateBuilder` / template briefing
- Settings: `useEnhancedBriefing`, `useLocalModelOnHostBoard` (Host Intelligence Settings)
- Traces: `[HOST_AI_*]`, `[HOST_MANAGER_SUMMARY_TRACE]`

## Guest communication drafts (shipped)

- **Default:** template drafts (`GuestCommunicationCoordinator.templateOnly()`)
- **Opt-in local model:** Host Intelligence → **Use local model for guest message drafts**
- Reservation Detail: draft kinds — confirmation, reminder, clarification, large party, table ready
- Staff reviews in `GuestMessageDraftReviewView` before Mail/Messages/copy
- **No auto-send**, **no reservation mutation**
- Legacy Confirm + Email (`POST /confirm`) is a separate path

### PII policy

Packet excludes raw guest notes, staff notes, email, phone, backend JSON, evidence blobs. Output validator blocks phone-like strings except allowlisted restaurant phone.

### Table context in drafts

- Packet may include `tableName` and party size flags when safe
- Table layout truth comes from **backend floor plan** when loaded; local `HostTableConfigStore` is advisory fallback only (see `Docs/FLOOR_PLAN_AND_TABLES.md`)

## Readiness & packaging

- `HostLocalModelReadinessProvider` / `HostLocalModelReadiness` — single readiness source
- `HostLocalModelAutoPrepareCoordinator` — prepares bundled model into Application Support
- On-device support banner in More tab when model missing
- TestFlight: model must be bundled or imported; template path works without model

## Code map

| Area | Location |
|------|----------|
| Runtime protocol | `HostLocalModelRuntime.swift` |
| Llama implementation | `HostLlamaBriefingRuntime.swift` |
| Model file locator | `HostLocalModelFileLocator.swift`, `LocalWordingModelProfile.swift` |
| Host briefing writer | `HostBriefingWriter.swift` |
| Manager narrative | `ManagerNarrativeWriter.swift`, `ManagerNarrativePacketSanitizer.swift` |
| Guest drafts | `Features/GuestMessaging/*` |
| Settings toggles | `HostIntelligenceSettingsView.swift` |
| Diagnostics | `HostIntelligenceDiagnosticsView.swift`, `HostLocalModelDiagnosticsCoordinator.swift` |

## Not wired to local model

- Business analytics narrative — deterministic only
- New Bookings intelligence card — deterministic only
- Activity history — backend only, no LLM summarization

## Known limitations

- Physical device recommended for realistic inference timing
- If 3B is not bundled, runtime falls back to 0.5B or template without blocking staff workflows
- Guest draft local model shares `bestAvailableProfile()` — there is no separate per-task model picker in settings today
