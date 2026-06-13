# Host AI Implementation Handoff

**Branch:** `intelligence`  
**Audience:** Implementation agent (stronger model) — read this file first; do not rescan the whole repo.  
**Purpose:** Make Host screen AI staff-trusted and operationally useful without making the local model authoritative.

---

## Current observed problems

### Product (staff-facing)

The Host Intelligence card is **technically safe** but **not operationally useful** during live service. Staff see a flat list of low-signal rows such as:

- “Seating preference.” / “Mark noted a booth by the wall.”
- “Check guest note” / “Deborah Zak mentioned a birthday.”
- “Seen before” / “Gabriella appears to have visited before.”

Each row has equal visual weight. The card does not answer:

- What needs attention **right now**?
- What is **about to happen**?
- Which guests need **special care**?
- Which reservations have **missing table / assignment risk**?
- What **pressure wave** is coming?
- What should staff **check next**?

### Architecture (working but incomplete)

| Area | Status |
|------|--------|
| Deterministic engine + backend evidence | ✅ Shipped |
| Floor source truth (`pendingBackend` → `backend`) | ✅ Fixed on `intelligence` |
| Floor fetch on first Host visibility | ✅ Fixed (independent of startup defer) |
| Local model as wording only | ✅ Enforced by validators |
| **Deterministic grouping for staff card** | ❌ Missing for guest-note / seen-before signals |
| **Model gate vs simple multi-guest days** | ⚠️ Too strict — template-only when facts are “independent” |
| **Action row policy** | ❌ One action per guest signal; `seenBefore` promoted to action |
| **Separated briefing prompts** | ✅ Exists (`HostOperationalBriefingPromptBuilder`) but **default off** |

### Device log symptoms (expected today)

```
[HOST_AI_GATE] surface=hostBoard allowed=false reason=independent_simple_facts
[HOST_AI] local model skipped: independent_simple_facts
[FACADE_TRACE] ... briefingSource=template usesModel=false
[HOST_AI_FACTS_TRACE] ... floorTables=pendingBackend|backend
```

These are **not bugs** by themselves — they mean the gate chose template because the packet lacked “operational tension.” The bug is that **template + flat actions** still fail the staff UX bar.

---

## Current pipeline map

Deterministic truth flows left → right. Wording-only stages are marked **(wording)**.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ SOURCES (truth)                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│ ReservationRecord (@Query, operational filter)     ReservationsListView      │
│ GuestIntelligenceStore (GET guest-intelligence)    GuestIntelligenceStore    │
│ FloorPlanStore (GET /floor-plan)                   FloorPlanStore            │
│ Availability bundle                                ReservationsController    │
│ HostTableConfigStore                               advisory only / legacy    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ HostBoardView.makeHostEngineInput()                                          │
│  • floorTableSource via FloorPlanStore.floorSourceStatus(for:)               │
│  • backendFloorTables / tableConfigs via HostFloorSourceSupport.resolve       │
│  • guestIntelligenceSummaries + profile packs                                │
│  Traces: [FLOOR_SOURCE_TRACE], [TABLE_CAPACITY_TRACE]                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ HostIntelligenceController.evaluate(input:stability:)  [DETERMINISTIC]       │
│  → HostIntelligenceEngine.evaluateHostDecisionSnapshot(input:)               │
│  Traces: [HOST_AI_FACTS_TRACE], [HOST_CARD_TRACE], [HOST_REEVAL_TRACE]       │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
     HostIntelligenceEngine.buildServiceDayContext   HostGuestIntelligenceSupport
     (tableConfigs empty unless .backend|.legacy)   buildGuestSignals / buildGuestSuggestedActions
                    │                                   │
                    └─────────────────┬─────────────────┘
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ HostDecisionSnapshot                                                         │
│  • briefingFacts (ranked)                                                    │
│  • suggestedActions (ranked, deduped)                                        │
│  • guestSignals, tableSignals, slotPressures, bookingDecisions               │
│  • templateBriefingText (HostBriefingService, max 2 facts)                   │
│  • llmPacket (top 5 facts → HostLLMFact)                                     │
│  • arrivalPressureFacts                                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          ▼                           ▼                           ▼
 HostBookingFactGrouping      ManagerNarrativeTemplateBuilder   buildLLMPacket
 (booking/largeParty only)    headline/why/checkNext (template)  topFacts for gate/model
          │                           │                           │
          └───────────────────────────┴───────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ HostIntelligenceController.refreshBriefing(hostBoardContext:)  async         │
│  1. Template narrative (always available)                                    │
│  2. HostBriefingHostBoardGate → allow/skip local model                       │
│  3. ManagerNarrativeWriter.write (Host Board path) **(wording)**            │
│     OR HostBriefingWriter.writeBriefing (non-host surfaces) **(wording)**    │
│  Traces: [HOST_AI_GATE], [HOST_AI], [HOST_AI_PACKET_TRACE],                  │
│          [HOST_AI_LIFECYCLE], [HOST_AI_VALIDATOR], [FACADE_TRACE]           │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ HostIntelligenceCard (HostBoardView.liveHostIntelligenceSection)             │
│  • narrativeBody: ManagerNarrative headline / why / checkNext                │
│  • attentionItems: ManagerAttentionItemBuilder.build(maxItems: 3)            │
│  • optional compactOperationalPrompts if useSeparatedBriefingPrompts         │
│  Traces: [HOST_CARD_TRACE], [FACADE_TRACE] briefingSource/usesModel          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step reference table

| Step | File | Type / function | Input | Output | Truth? | Traces |
|------|------|-----------------|-------|--------|--------|--------|
| Reservation pool | `ReservationsListView` | `selectedDateReservations` | `@Query` records | operational day rows | ✅ cache rows | `[HOST_FILTER_TRACE]` |
| Engine input | `HostBoardView` | `makeHostEngineInput` | stores, settings, date | `HostEngineInput` | ✅ | `[FLOOR_SOURCE_TRACE]` |
| Lifecycle loads | `HostBoardLifecycleCoordinator` | `scheduleFloorPlanIfNeeded` | date, stores | network tasks | ✅ fetch | `[HOST_LIFECYCLE]` |
| Evaluate | `HostIntelligenceController` | `evaluate` | `HostEngineInput` | `HostDecisionSnapshot` | ✅ | `[HOST_AI_FACTS_TRACE]` |
| Engine | `HostIntelligenceEngine` | `evaluateHostDecisionSnapshot` | `HostEngineInput` | snapshot | ✅ | `[UIPRESSURE_TRACE]` |
| Guest signals | `HostGuestIntelligenceSupport` | `buildGuestSignals` | reservations + backend DTOs | `[HostGuestSignal]` | ✅ hybrid | — |
| Guest actions | `HostGuestIntelligenceSupport` | `buildGuestSuggestedActions` | signals | `[HostSuggestedAction]` | ✅ titles from signals | — |
| Booking group | `HostBookingFactGrouping` | `groupedFacts` | facts + booking decisions | merged facts | ✅ | — |
| Template text | `HostBriefingService` | `buildTemplateBriefingFallback` | ranked facts | 1–2 sentences | ✅ | — |
| LLM packet | `HostIntelligenceEngine` | `buildLLMPacket` | top 5 facts | `HostLLMPacket` | ✅ facts only | — |
| Template narrative | `ManagerNarrativeTemplateBuilder` | `build` | snapshot | `ManagerNarrative` | ✅ | — |
| Model gate | `HostBriefingHostBoardGate` | `localModelSkipReason` / `hasOperationalTension` | packet + context | allow/skip | policy | `[HOST_AI_GATE]` |
| Model write | `ManagerNarrativeWriter` | `write` | `ManagerNarrativePacket` | `ManagerNarrative` | **wording** | `[HOST_AI_*]` |
| Validator | `ManagerNarrativeValidator` | validate parsed output | model text | pass/fail | safety | `[HOST_AI_VALIDATOR]` |
| Card rows | `ManagerAttentionItemBuilder` | `build(maxItems: 3)` | `suggestedActions` | `ManagerAttentionItem` | presentation | `[HOST_CARD_TRACE]` |
| Card UI | `HostIntelligenceCard` | `body` | snapshot + narrative | SwiftUI | presentation | — |

### Re-evaluation triggers (`HostBoardView`)

| Key | Includes | Task |
|-----|----------|------|
| `hostIntelligenceEvaluationKey` | reservations, seated stamp, settings, **layoutFingerprint** | `evaluate()` — deterministic |
| `hostIntelligenceEnrichmentKey` | availability, guest intel, analytics, profile packs, **layoutFingerprint** | `refreshBriefing()` — wording |
| `hostHistoryEnrichmentGenerationKey` | history cache generation | debounce log only |
| Lifecycle task | `isVisible`, defer flags, `canStartNoncriticalStartupLoads`, date | floor + optional loads |

**Date switch:** `HostIntelligenceController.evaluate` clears snapshot, bumps `briefingRefreshGeneration`, clears model cache when `selectedDateKey` changes.

**Hide Host tab:** `hostIntelligenceController.reset()` cancels in-flight model via generation bump.

---

## Why local model is skipped on Host Board

### Gate location

`HostBriefingHostBoardGate` in `HostBriefingWriter.swift` (also used by `ManagerNarrativeWriter` and `HostIntelligenceController.refreshBriefing`).

### Decision chain

1. Settings: `useEnhancedBriefing`, `enhancedBriefingProvider == .localModel`, `useLocalModelOnHostBoard`
2. `packet.hasMeaningfulBriefingFacts`
3. **`shouldUseTemplateOnlyOnHostBoard(packet)`** → if true, skip model
4. `localModelSkipReason` → startup defer, stabilization (20s), date navigation cooldown (4s), model not ready, etc.

### What `independent_simple_facts` means

When `shouldUseTemplateOnlyOnHostBoard` is true **and** `hasOperationalTension(packet)` is **false**, `HostIntelligenceController` logs skip reason `independent_simple_facts` (not a `SkipReason` enum case — a string alias for template-only simple packets).

`shouldPreferDeterministicHostSummary` returns true when:

```swift
guard packet.hasMeaningfulBriefingFacts else { return true }
return !hasOperationalTension(packet: packet)
```

### `hasOperationalTension` (model-worthy) requires combinations such as:

- `operationalTension` evidence flag
- `lateNoTable` + `longSeated`
- `lateNoTable` + `unresolvedLateCleanup`
- `lateNoTable` + (`capacityTableMismatch` | `servicePressure`)
- `capacityTableMismatch` + `servicePressure`
- `capacityTableMismatch` + `guestNoteOccasion`
- **OR** ≥2 themes from: `lateNoTable`, `unresolvedLateCleanup`, `longSeated`, `operationalTension`, `capacityTableMismatch`, `servicePressure`

**Guest-only days** (notes, seen-before, seating prefs) usually classify as `guestNoteOccasion` / `seenBeforeRegular` **without** table pressure → **no tension** → template only.

### Is the gate too strict?

**For model invocation:** Arguably yes for multi-guest note days — synthesis could help wording.  
**For staff UX:** The bigger gap is **deterministic grouping**, not forcing the model on every shift.

**Recommendation:** Keep gate for single low-risk facts; add deterministic `HostAttentionGrouper` **before** gate so template narrative is already service-ready. Optionally allow model when `guestNoteOccasion` count ≥ 2 **and** total complexityScore ≥ threshold — but only for **wording**, not new facts.

### Host Board model task

Host Board uses **`ManagerNarrativeWriter`** with profile **`HostLocalModelTaskProfile.managerNarrative`** (160 tokens, 12s timeout in doc; code says 160 tokens).  
It does **not** use `hostBriefing` profile on the Host home path when `hostBoardContext != nil`.

---

## Why raw facts/actions repeat in the UI

### Emission (engine)

`HostGuestIntelligenceSupport.buildGuestSuggestedActions` maps **every** signal kind to an action:

| Signal kind | Action title | Action kind |
|-------------|--------------|-------------|
| `seatingPreference` | “Seating preference” | `assignTable` |
| `specialOccasion` | “Check guest note” | `alertServer` |
| `regularGuest` / `importantGuest` | **“Seen before”** | `reviewReservation` |
| `noteReminder` | “Check guest note” / “Dietary note” | `alertServer` |

One reservation can produce **multiple** actions (seen-before + seating + occasion).

### Ranking (engine)

`HostIntelligenceEngine.rankSuggestedActions` sorts all actions; **no guest-signal grouping or cap by category**.

### Presentation (card)

`ManagerAttentionItemBuilder.build(from:maxItems: 3)` takes **first 3 ranked actions** as equal rows.

Each row shows:

- `title` ← action.title (e.g. “Seen before”)
- `detail` ← action.reason (e.g. “Gabriella appears to have visited before.”)
- `actionTitle` ← tap label (e.g. “Check reservation”)

### Narrative duplication

`ManagerNarrativeTemplateBuilder` builds headline/why from **top ranked facts**, while action rows repeat overlapping guest-note strings. `shouldHideCompactDetail` only suppresses some duplicates — not guest-signal rows.

### Existing grouping (partial)

| Layer | Scope | Used on Host card default? |
|-------|-------|----------------------------|
| `HostBookingFactGrouping` | booking / largeParty facts only | Facts only, not actions |
| `HostOperationalBriefingPromptBuilder` | category prompts | Only if `useSeparatedBriefingPrompts == true` (default **false**) |
| `ManagerAttentionItemBuilder` | maps actions → rows | Always (max 3) |

**Root cause:** No deterministic **guest-note / returning-guest action policy** between engine and card.

---

## Fact / action taxonomy audit

### `HostFactCategory` (engine facts)

| Category | Classify | Staff card rule |
|----------|----------|-----------------|
| `timing` | B / C | Group into “Timing” section; action if overdue/seated grace |
| `capacity` | B | Context in pressure narrative; action if ratio critical |
| `table` | **A** | Action when no-table / mismatch / turn risk |
| `guest` | C / D | **seen-before → context** unless VIP/issue paired |
| `allergy` | **A** | Always action-worthy |
| `largeParty` | **A** | Action + floor plan |
| `arrivalWave` | B | Wave chart + narrative; action if slot blocked |
| `cancellation` / `overdue` | **A** | Action |
| `opportunity` | B | Context unless freed table helps specific party |
| `bookingDecision` | **A** | Confirm/review actions |
| `analytics` | D | Manager-only; hide on staff card default |
| `sync` | D | Floor setup / unavailable — info, not urgent row |
| `note` / `preference` | C | **Group into “Guest notes to check”** |
| `duplicate` | **A** | Review action |

### `HostGuestSignalKind` (signals → actions today)

| Kind | Current action? | Proposed |
|------|-----------------|----------|
| `allergy` | Yes | **A** — keep |
| `accessibility` | Yes | **A** — keep |
| `seatingPreference` | Yes | **C** — group under guest notes |
| `specialOccasion` | Yes | **C** — group; include name + occasion type |
| `noteReminder` | Yes | **C** — group |
| `regularGuest` / `importantGuest` | Yes (“Seen before”) | **D → context** unless paired with note/issue/VIP |
| `previousServiceIssue` | Yes | **A** |
| `noShowRisk` / `cancellationRisk` | Yes | **A** |
| `possibleDuplicate` | Yes | **A** |
| `manualCallIn` | Yes | **A** |
| `vip` | nil | **A** when present |

### Floor source (`HostFloorTableSource`)

| Source | Card behavior |
|--------|-----------------|
| `pendingBackend` | Suppress table-capacity facts; optional “Loading floor plan…” |
| `backend` | Full table intelligence |
| `notConfigured` | Manager prompt only; no capacity claims |
| `unavailable` | Quiet diagnostic; no table-fit actions |
| `legacyFallback` | Advisory copy only if setting enabled |

---

## Source-of-truth rules (must preserve)

### Never truth

- Local model output (until validator passes — still wording only)
- `HostTableConfigStore` unless `floorTableSource == .legacyFallback` and `useLegacyAdvisoryTableFallback`
- SwiftData history pool for guest signals when backend `GuestIntelligenceSummaryDTO` / profile pack exists
- Raw note keyword inference without deterministic signal validation
- LLM-invented occasions, allergies, or table assignments

### Always truth

- `ReservationRecord` operational pool (backend-synced managed reservations)
- `GET /floor-plan` → `HostFloorTableSource.backend`
- `GET /guest-intelligence` summaries + profile packs
- `GET /activity` (read-only; not yet in Host engine — future context)
- Deterministic `HostIntelligenceEngine` math (slot pressure, arrival wave, booking decisions)
- `HostFloorTableSource` labeling

### Guest signal precedence (`HostGuestIntelligenceSupport`)

When `guestIntelligenceSummariesByReservationID[id]` exists:

1. Backend flags → signals (`buildBackendGuestSignals`)
2. Returning guest copy still uses local `GuestInsightReport` rules for visit counts
3. Local keyword signals skipped for that reservation (`continue` after backend block)

---

## Timing / stale-state risks

| Risk | Mitigation today | Gap |
|------|------------------|-----|
| First render before floor | `pendingBackend`, re-eval on `layoutFingerprint` | ✅ |
| Guest intel arrives late | `hostIntelligenceEnrichmentKey` → `refreshBriefing` | ⚠️ `same_packet` cache can skip if fingerprint unchanged |
| Floor arrives late | evaluation key includes fingerprint | ✅ |
| Date switch stale briefing | `evaluate` clears on date change; refresh generation bump | ✅ |
| Hidden tab model completes | `reset()` bumps generation | ✅ |
| enrichmentLoading flicker | `isEnrichmentLoading` + preserve previous attention card | OK |
| Stabilization 20s blocks model | `localModelSkipReason.stabilization_delay` | By design |
| Template shows before enriched guest intel | deterministic evaluate runs first | Expected; grouping should handle partial data |

**Investigate:** `refreshBriefing` early return on `cacheKey == lastBriefingCacheKey` when guest intel enrichment changes narrative-worthiness but `llmPacket.briefingFingerprint` unchanged.

---

## Local model task profiles (reference)

| Task | Profile | maxOutputTokens | maxInferenceSeconds | Host Board? |
|------|---------|-----------------|---------------------|-------------|
| Host briefing rewrite | `hostBriefing` | 100 | 12 | Non-host path only |
| **Manager narrative** | `managerNarrative` | 160 | 12 | **Yes — primary Host path** |
| Guest message draft | `guestMessageDraft` | 360 | 20 | Reservation Detail only |
| Note analysis | `noteAnalysis` | 300 | 15 | Service Intelligence |

**Wording file:** `LocalWordingModelProfile` → 3B → 0.5B → template via `HostLocalModelFileLocator.bestAvailableProfile()`.

**Validator:** `ManagerNarrativeValidator` + `HostBriefingWriterValidator` — block invented occasions, raw contact, announcement tone, staff-addressed output.

**Fallback:** Always `ManagerNarrativeTemplateBuilder` / `templateBriefingText`.

---

## Deterministic grouping proposal (new layer)

### Name

`HostAttentionGrouper` (+ `HostAttentionSection`, `HostActionPresentationPolicy`)

### Location

Call **after** `HostIntelligenceEngine.evaluateHostDecisionSnapshot`, **before** `ManagerAttentionItemBuilder` / `ManagerNarrativePacketBuilder`.

Suggested file: `Features/HostIntelligence/HostAttentionGrouper.swift`

### Input

```swift
struct HostAttentionGrouperInput {
  let selectedDateKey: String
  let snapshot: HostDecisionSnapshot  // raw engine output
  let floorTableSource: HostFloorTableSource
  let settings: HostIntelligenceSettings
}
```

### Output

```swift
struct HostAttentionPresentation {
  let sections: [HostAttentionSection]       // ordered service themes
  let primaryActions: [HostSuggestedAction]  // max 3 actionable
  let contextLines: [HostAttentionContext]  // non-tappable (seen-before, etc.)
  let suppressedActionIDs: [String]
  let narrativeSeed: HostNarrativeSeed         // headline/why/check for template+model
}

struct HostAttentionSection {
  let id: String
  let title: String           // e.g. "Guest notes to check"
  let summary: String         // deterministic joined copy
  let severity: HostSeverity
  let relatedReservationIDs: [Int]
  let sourceCategories: [String]
}
```

### Grouping rules (deterministic)

1. **Table / floor** — no-table, mismatch, turn risk, arrival peak (if `floorTableSource == .backend`)
2. **Timing / pressure** — arrival wave, overdue, seated-too-long
3. **Guest notes to check** — merge `seatingPreference`, `specialOccasion`, `noteReminder`, dietary (not allergy) into one section with per-guest clauses
4. **Returning guests** — `seenBefore` → `contextLines` only unless `importantGuest`, `vip`, or `previousServiceIssue` on same reservation
5. **Booking** — keep `HostBookingFactGrouping` behavior
6. **Allergies / accessibility / risks** — stay primary actions

### Model contract

- Model receives **only** `HostNarrativeSeed` + sanitized section summaries
- Model may rewrite `summary` wording **only**
- Model **must not** add facts, actions, reservation IDs, or urgency not in seed

### UI consumption

`HostIntelligenceCard` should prefer:

1. `narrativeSeed.headline` / model rewrite
2. Up to **2** `HostAttentionSection` summaries (not 3 duplicate action rows)
3. Up to **3** `primaryActions` with clear tap labels
4. Expandable “Context” for `contextLines` (seen-before, returning guests)

---

## UI rendering proposal

| Element | Current | Target |
|---------|---------|--------|
| Max tappable rows | 3 equal actions | 2 sections + 2–3 primary actions |
| Seen-before | Own action row | Context line in expandable area |
| Guest notes | 1 row per guest | One “Guest notes to check” block |
| Headline | Template or model | Operational theme first (pressure / no-table / notes) |
| Low-signal only | Still shows rows | “No urgent host actions” calm state |
| `pendingBackend` | pending copy in facts | Suppress table rows; show nothing or subtle status |
| Tap labels | Generic “Check” | “Check Mark’s seating note”, “Open floor plan” |
| `useSeparatedBriefingPrompts` | Off by default | Consider merging into grouper; avoid duplicate paths |

---

## Files and types to modify (next agent)

### Primary

| File | Change |
|------|--------|
| `HostAttentionGrouper.swift` | **NEW** — grouping + policy |
| `HostActionPresentationPolicy.swift` | **NEW** or nested — seenBefore/context rules |
| `HostGuestIntelligenceSupport.swift` | Stop emitting per-signal actions; emit signals only OR delegate to grouper |
| `HostIntelligenceEngine.swift` | Optional: call grouper internally or via controller |
| `HostIntelligenceController.swift` | Store `HostAttentionPresentation`; pass to narrative builders |
| `ManagerAttentionItemBuilder.swift` | Consume `primaryActions` not raw snapshot.actions |
| `ManagerNarrativeTemplateBuilder.swift` | Build from `HostNarrativeSeed` / sections |
| `ManagerNarrativePacketBuilder.swift` | Packet from grouped sections, not raw topFacts only |
| `HostIntelligenceCard.swift` | Section layout, context expansion, calm empty copy |
| `HostBriefingHostBoardGate.swift` | Optional complexity tweak for multi-guest note days |

### Secondary / traces

| File | Change |
|------|--------|
| `HostAIProofTraces.swift` or new `HostAttentionTrace.swift` | Proposed traces below |
| `HostBoardView.swift` | Pass grouped presentation to card if needed |
| `HostIntelligenceSettings.swift` | Optional: expose grouped briefing toggle |

### Do not change

- Backend APIs
- `HostLlamaBriefingRuntime` inference core
- Mutation paths / auto-confirm / auto-assign
- Template fallback removal
- `HostFloorTableSource` semantics
- Activity history read path (unless adding read-only context later)

---

## Model usage proposal

1. **Always** build deterministic `HostAttentionPresentation` first.
2. Run `HostBriefingHostBoardGate` on grouped packet / complexity score.
3. If allowed → `ManagerNarrativeWriter` rewrites **section summary + headline** only.
4. If skipped → `ManagerNarrativeTemplateBuilder` using same seed (must read well without model).
5. Never run model on raw per-guest action list.

---

## Validation / safety rules

- `ManagerNarrativeValidator` must reject output that introduces guests not in packet
- No raw phone/email/notes in prompts (`ManagerNarrativePacketSanitizer`)
- Grouped summaries must cite only `relatedReservationIDs` from deterministic inputs
- Floor pending → no table-capacity numbers in narrative
- Date key must match `latestSelectedDateKey` before publishing model output (already guarded)

---

## Trace logs to add

```
[HOST_ATTENTION_GROUP_TRACE] date=... rawFacts=12 rawActions=8 groups=3 suppressed=5
[HOST_ACTION_POLICY_TRACE] category=seenBefore decision=context reason=not_actionable_alone
[HOST_MODEL_PACKET_TRACE] date=... groups=3 modelAllowed=false reason=independent_simple_facts
[HOST_MODEL_VALIDATE_TRACE] status=accepted|rejected reason=...
[HOST_CARD_RENDER_TRACE] source=template|model|fallback groups=2 rows=2 context=3
```

Dedupe identical lines within 3s (mirror `FloorSourceTrace` pattern).

---

## Tests to run

### Device — Host board

1. Cold launch → Host tab; floor `pendingBackend` then `backend`
2. Day with 3+ guest notes, no table pressure → grouped “Guest notes to check”, no 3× “Seen before” rows
3. Day with no-table + wave pressure → table section leads
4. Date chip switch → no stale prior-day headline
5. Model disabled in settings → template grouped briefing still readable
6. `useLegacyAdvisoryTableFallback=false` → no local floor capacity

### Logs to capture

- `[HOST_ATTENTION_GROUP_TRACE]`
- `[HOST_AI_GATE]`
- `[HOST_CARD_RENDER_TRACE]`
- `[HOST_AI_FACTS_TRACE] floorTables=backend`

### Unit (if added)

- `HostAttentionGrouper` merges 3 seating/occasion signals → 1 section
- `seenBefore` alone → context not action
- `seenBefore` + `previousServiceIssue` → action remains

---

## Exact acceptance criteria

- [ ] Host card does **not** show raw duplicate rows for guest notes / seen-before
- [ ] Guest note, seating preference, birthday grouped into meaningful staff context
- [ ] Seen-before alone is **not** a top action row
- [ ] Local model does **not** invent facts
- [ ] Local model does **not** decide status, table, availability, capacity, or urgency
- [ ] Host Board works with **template fallback** (model off / skipped / failed)
- [ ] Host Board works with **local model disabled**
- [ ] `floorTables=backend` when floor loaded; `pendingBackend` while loading
- [ ] No local advisory floor unless explicit legacy fallback setting
- [ ] Floor pending/unavailable/notConfigured clear — no fake zero capacity
- [ ] Date switch never shows stale briefing as current
- [ ] Logs show source, gate, grouping, model usage, validator, render source

---

## Do-not-change rules

- Do not rewrite entire `HostIntelligenceEngine` monolith in one pass
- Do not change backend APIs or add cloud AI
- Do not make local model authoritative
- Do not auto-assign tables, auto-confirm, auto-seat, auto-cancel
- Do not auto-send email/SMS
- Do not remove template fallback
- Do not remove existing traces without deduped replacements
- Do not regress `HostFloorTableSource` / floor lifecycle scheduling

---

## Remaining uncertainties

1. **Exact staff copy tone** — needs Tryzub manager review (Ukrainian Kitchen service style).
2. **`same_packet` skip** — confirm whether guest intel enrichment should bump `briefingFingerprint` when signals change but topFacts IDs stable.
3. **Should `useSeparatedBriefingPrompts` merge into grouper** or remain a separate developer toggle?
4. **Activity history** — not wired into Host engine today; future read-only context for “what changed recently.”
5. **iPad vs iPhone row budget** — grouper may use `maxItems: 2` phone / `3` regular width.

---

## Files read for this audit

**Docs:** `PROJECT_MAP.md`, `ARCHITECTURE_DIAGRAMS.md`, `LOCAL_MODEL_INTELLIGENCE.md`, `TABLE_CONFIGURATION.md`, `BACKEND_INTELLIGENCE.md`, `PROJECT_METHOD_MAP.md` (partial), `ACTIVITY_HISTORY.md` (partial)

**Code:**  
`HostBoardView.swift`, `ReservationsListView.swift`, `HostBoardLifecycleCoordinator.swift`, `FloorPlanStore.swift`, `HostFloorTableSource.swift`, `HostIntelligenceController.swift`, `HostIntelligenceEngine.swift`, `HostIntelligenceCard.swift`, `HostGuestIntelligenceSupport.swift`, `HostBriefingWriter.swift` / `HostBriefingHostBoardGate`, `HostBriefingService.swift`, `HostBookingFactGrouping.swift`, `HostOperationalBriefingPromptBuilder.swift`, `ManagerAttentionItem.swift`, `ManagerNarrativeModels.swift`, `ManagerNarrativeWriter.swift`, `HostLocalModelRuntime.swift`, `HostAIProofTraces.swift`, `HostCardTrace.swift`, `FacadeTrace.swift`, `HostBoardViewState.swift`

**Files changed:** `Docs/HOST_AI_IMPLEMENTATION_HANDOFF.md` (this file only)
