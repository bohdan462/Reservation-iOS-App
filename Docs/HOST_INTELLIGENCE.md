# Host intelligence

**Status:** Current source of truth
**Branch:** `audit-current-state`
**Audit date:** 2026-06-30
**HEAD:** `50b207a`

## What Host Intelligence is

Service Intelligence helps staff run the floor like a strong human host, admin, or manager would — briefing the team **before, during, and after service**. It is not a static dashboard or a technical signal dump.

The app substitutes parts of the admin/host job: surface what matters now on Host Board, explain the full day on More → Service Intelligence, and never auto-act on reservations.

**Architecture phrasing:**

| Layer | Meaning |
|-------|---------|
| **Canonical snapshot** | What is true |
| **Parent briefing packet** | All facts the system can safely talk about |
| **Narrative layer** | How a good host/admin says it |
| **LLM** | Wording only, never truth |

**`HostServiceIntelligenceSnapshot`** is the canonical service-day read model. The **parent Service Briefing Packet** (4D target) expands that truth with named facts from every intelligence input. Both Host Board and More → Service Intelligence must reuse the same canonical truth.

## What it is not

- Not reservation truth (engine reads cache + APIs)
- Not auto-send email/SMS
- Not auto status/table mutation
- Not generic “staff needs review” or “operational action required” copy
- Local model does **not** decide facts or actions
- More → Service Intelligence does **not** build the canonical snapshot

## Surfaces

| Surface | Role |
|---------|------|
| **Host Board** | Live work surface during service — compact, useful intelligence where staff actually work; quietly surfaces what matters now |
| **More → Service Intelligence** | Deeper briefing — explains the day, guests, timing, business context, and unresolved items; reuses the same truth as Host Board |

## Pipeline

```
Inputs (parent intelligence layer):
  reservations
  + floor / tables
  + seated timing
  + guest memory
  + guest notes + staff notes
  + attachments
  + reminder / confirmation state
  + business analytics
  + walk-ins / completed / no-shows
  + activity history
  + snapshot facts
  + optional LLM narrative (wording only)
    ↓
HostBoardView.makeHostEngineInput()
  → HostIntelligenceEngine / deterministic analyzers
    ↓
HostBoardView.rebuildServiceBriefing()
  → HostServiceIntelligenceSnapshotBuilder
    ↓
HostIntelligenceController.serviceIntelligenceSnapshot   ← canonical snapshot (what is true)
    ↓
Parent Service Briefing Packet (4D target)               ← all safe facts to talk about
    ↓
Template writer (immediate, deterministic prose)
    ↓
Optional local model writer (human host/admin tone)
    ↓
Validator (blocks wrong truth, unsupported actions, guest-facing tone)
    ↓
  ├─ Host Board — compact intelligence (live card + planning/recap)
  └─ More → Service Intelligence — full briefing + Service facts (rankedFacts)
```

**Today (4C shipped):** canonical snapshot is built on Host path and read by More. Template/narrative layers are partial — today live Host card still uses engine presentation + optional LLM on `HostDecisionSnapshot`; More reads snapshot facts directly.

## Tone rules

Write like a host/admin talking to the team:

**Say:**

- “6:30 · Julie, 5 guests. Birthday note. Seat with care.”
- “7:30 · Tristan, 4 guests. Already seated at A1 for 1h 24m.”
- “8:00 · Derek, 3 guests. Mom’s birthday.”
- “Four reservations are new guests.”
- “Five walk-ins completed so far.”
- “Nothing urgent right now. Keep an eye on A1.”

**Avoid:**

- “Staff needs review.”
- “Check guest note.”
- “Operational action required.”
- “Guest signal detected.”
- “Reservation has occasion metadata.”
- “Attention category: guestNote.”

## Safety (narrative layer)

- **LLM cannot change** counts, guest names, statuses, table facts, or actions.
- **LLM cannot invent** facts.
- **LLM should not expose** raw private notes or raw contact data in prose.
- **Validator blocks** wrong counts, wrong names, wrong status, unsupported actions, and guest-facing tone.
- On validation failure → template fallback; never show unvalidated model output as truth.

## Canonical snapshot lifecycle (4C)

| Rule | Behavior |
|------|----------|
| **Build owner** | Host path only — `HostBoardView.rebuildServiceBriefing()` → `updateServiceIntelligenceSnapshot` |
| **Read surfaces** | Host Board (partial: planning headline; today card still uses engine presentation) + More → Service Intelligence |
| **Host hide** | `resetVolatilePresentation(reason: "view_hidden")` — preserves snapshot + evaluated-date state |
| **Date transition** | `beginSelectedDateTransition` clears snapshot + source fingerprint |
| **Stale guard** | `serviceIntelligenceSourceFingerprint` — reservation-row fields; More calls `isServiceIntelligenceSnapshotCurrent` |
| **More fallback** | Legacy briefing + note analyzers when snapshot not ready or source stale |
| **LLM** | Does not run from More; does not own facts or actions |

## Deterministic vs local model

| Output | Source |
|--------|--------|
| `rankedFacts`, snapshot headline/subline | `HostServiceIntelligenceSnapshotBuilder` |
| Facts, severity, suggested actions, pressure (engine) | `HostIntelligenceEngine` → feeds builder |
| Today live card chips / attention rows | `HostAttentionGrouper` + `HostIntelligenceCardPresentation` |
| Briefing headline/body, manager narrative prose | Template default; optional local model (wording only) |
| Guest signals (allergy, returning, occasion) | Engine + backend guest intel when loaded; else `local_bounded` |

**Validators:** `ManagerNarrativeValidator`, `GuestMessageDraftValidator`, `HostBriefingWriterValidator` — leak or wrong counts → template fallback.

## Settings (`HostIntelligenceSettingsStore`)

| Toggle | Default | Effect |
|--------|---------|--------|
| `useEnhancedBriefing` | off | Local model briefing |
| `useLocalModelOnHostBoard` | off | Model on host card |
| `useLocalModelForGuestMessageDrafts` | off | AI guest drafts |
| `useLocalModelForNoteAnalysis` | off | Note enrichment |

## Guest intelligence input

`GuestIntelligenceStore` — 180s TTL, not on `FreshnessCoordinator`.

Mode: `"server"` when summaries/packs present; `"local_bounded"` otherwise.

**Note:** Backend guest-intel changes are not in 4C-3 reservation-source fingerprint — snapshot guest-signal facts may lag until Host re-evaluates or reservation rows change.

## Traces

| Trace | Purpose |
|-------|---------|
| `[SERVICE_INTEL_SNAPSHOT_TRACE]` | Snapshot build/skip on Host path |
| `[SERVICE_INTEL_LIFECYCLE_TRACE]` | preserve on hide, source stale/current, date transition clear |
| `[SERVICE_INTEL_UI_TRACE]` | More/Host planning: `use_snapshot` vs `legacy` |
| `[HOST_AI_GATE]` | Local model allowed/skipped on Host board |
| `[HOST_AI_VALIDATOR_TRACE]` | Briefing validation failures (wrong counts, etc.) |
| `HostAILifecycleTrace` | Model load/skip/cancel lifecycle |
| `ServiceIntelligenceTrace` | Service Intelligence section diagnostics |

## UI trust notes

- Production card may hide “local model” caption — see OPEN_WORK P2-2
- Attention card can preserve previous snapshot during re-eval (brief stale window)
- More must not show stale canonical snapshot after reservation-source sync — guarded by fingerprint (partial smoke open)

## Host tab integration

Host Intelligence **displays on** the Host board; it does **not** own selected-date state.

| Concern | Owner |
|---------|-------|
| `selectedDate` | `HomeDashboardView` — see [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md) |
| Board lists / pressure | `HostBoardSnapshot` — must match `selectedDateKey` (HT-1) |
| Canonical service intelligence | `HostIntelligenceController.serviceIntelligenceSnapshot` |
| Intelligence input | `HostBoardView.makeHostEngineInput` + `rebuildServiceBriefing` + optional `refreshBriefing` |

**Docs:** [HOST_TAB_ARCHITECTURE.md](./HOST_TAB_ARCHITECTURE.md), [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md), [HOST_TAB_UI_DESIGN_SYSTEM.md](./HOST_TAB_UI_DESIGN_SYSTEM.md) (AI strip contract).

## Related docs

- [LOCAL_MODEL_INTELLIGENCE.md](./LOCAL_MODEL_INTELLIGENCE.md) — runtime boundaries
- [HOST_TAB_ARCHITECTURE.md](./HOST_TAB_ARCHITECTURE.md) — Host board file map
- [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md) — date + snapshot rules
- [INTELLIGENCE.md](./INTELLIGENCE.md) — backend APIs
- [CURRENT_SOURCE_OF_TRUTH.md](./CURRENT_SOURCE_OF_TRUTH.md) (Host Intelligence rules)
- [AGENT_HANDOFF_CURRENT.md](./AGENT_HANDOFF_CURRENT.md) — 4C smoke status

## Historical

- `ARCHIVE/HOST_AI_IMPLEMENTATION_HANDOFF.md` — grouping shipped
- `ARCHIVE/HOST_INTELLIGENCE_LOCAL_MODEL_RUNTIME_PROPOSAL.md` — Phase 8A research
