# Host intelligence

**Status:** Current source of truth  
**Branch:** `audit-current-state`  
**Audit date:** 2026-06-14

## What Host Intelligence is

Deterministic operational briefing for the selected service date on the Host tab. Helps staff prioritize without auto-acting.

## What it is not

- Not reservation truth (engine reads cache + APIs)
- Not auto-send email/SMS
- Not auto status/table mutation
- Local model does **not** decide facts or actions

## Pipeline

```
HostBoardView.makeHostEngineInput()
  → HostIntelligenceEngine (deterministic facts, actions, pressure)
  → HostAttentionGrouper (dedupe presentation rows)
  → HostIntelligenceController
       ├─ template briefing (default)
       └─ optional HostLlamaBriefingRuntime rewrite (wording only)
  → HostIntelligenceCard UI
```

## Deterministic vs local model

| Output | Source |
|--------|--------|
| Facts, severity, suggested actions, pressure | `HostIntelligenceEngine` |
| Briefing headline/body, manager narrative prose | Template default; optional local model |
| Guest signals (allergy, returning) | Backend guest intel when loaded; else `local_bounded` heuristics |

**Validator:** `ManagerNarrativeValidator`, `GuestMessageDraftValidator` — leak → template fallback.

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

## Traces

`HostAILifecycleTrace`, `ServiceIntelligenceTrace`, `BookingLoadTrace`

## UI trust notes

- Production card may hide “local model” caption — see OPEN_WORK P2-2
- Attention card can preserve previous snapshot during re-eval (brief stale window)

## Host tab integration

Host Intelligence **displays on** the Host board; it does **not** own selected-date state.

| Concern | Owner |
|---------|-------|
| `selectedDate` | `HomeDashboardView` — see [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md) |
| Board lists / pressure | `HostBoardSnapshot` — must match `selectedDateKey` (HT-1) |
| Intelligence input | `HostBoardView.makeHostEngineInput` + `refreshBriefing` |

**Docs:** [HOST_TAB_ARCHITECTURE.md](./HOST_TAB_ARCHITECTURE.md), [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md), [HOST_TAB_UI_DESIGN_SYSTEM.md](./HOST_TAB_UI_DESIGN_SYSTEM.md) (AI strip contract).

## Related docs

- [LOCAL_MODEL_INTELLIGENCE.md](./LOCAL_MODEL_INTELLIGENCE.md) — runtime boundaries
- [HOST_TAB_ARCHITECTURE.md](./HOST_TAB_ARCHITECTURE.md) — Host board file map
- [HOST_TAB_STATE_FLOW.md](./HOST_TAB_STATE_FLOW.md) — date + snapshot rules
- [INTELLIGENCE.md](./INTELLIGENCE.md) — backend APIs
- [AUDIT_CURRENT_STATE.md](./AUDIT_CURRENT_STATE.md) §7

## Historical

- `ARCHIVE/HOST_AI_IMPLEMENTATION_HANDOFF.md` — grouping shipped
- `ARCHIVE/HOST_INTELLIGENCE_LOCAL_MODEL_RUNTIME_PROPOSAL.md` — Phase 8A research
