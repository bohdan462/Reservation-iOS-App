# Host intelligence

**Status:** Current source of truth
**Branch:** `audit-current-state`
**Audit date:** 2026-06-30
**HEAD:** `50b207a`

## What Host Intelligence is

Deterministic operational briefing for the selected service date. Helps staff prioritize without auto-acting. **`HostServiceIntelligenceSnapshot`** is the canonical service-day read model shared by Host Board and More → Service Intelligence.

## What it is not

- Not reservation truth (engine reads cache + APIs)
- Not auto-send email/SMS
- Not auto status/table mutation
- Local model does **not** decide facts or actions
- More → Service Intelligence does **not** build the canonical snapshot

## Pipeline

```
HostBoardView.makeHostEngineInput()
  → HostIntelligenceEngine (deterministic facts, actions, pressure, guestSignals)
  → HostAttentionGrouper (today live card presentation — transitional)
  → HostIntelligenceController.evaluate()
       → latestEvaluatedServiceIntelSourceFingerprint recorded

HostBoardView.rebuildServiceBriefing()
  → HostServiceIntelligenceSnapshotBuilder (deterministic analyzers + engine output)
  → HostIntelligenceController.updateServiceIntelligenceSnapshot(...)
       → HostIntelligenceController.serviceIntelligenceSnapshot  ← canonical read model
            ├─ Host Board: compact live card (HostIntelligenceCard) + planning/recap card headline
            └─ More → Service Intelligence: full briefing + Service facts (rankedFacts)

Optional (wording only, never facts/actions):
  HostIntelligenceController.refreshBriefing()
    → ManagerNarrativeWriter / HostBriefingWriter / HostLlamaBriefingRuntime
    → validator-protected; template fallback on failure
    → today live Host card only when enrichment gates pass
```

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
