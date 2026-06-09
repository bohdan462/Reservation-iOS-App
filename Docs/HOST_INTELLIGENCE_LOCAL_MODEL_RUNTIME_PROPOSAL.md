# Host Intelligence — On-Device Briefing Model Runtime Proposal (Phase 8A)

**Branch:** `intelligence`  
**Date:** 2026-05-29  
**Status:** Research spike only — no production code changes in Phase 8A

## Executive summary

Tryzub Reservations already has the right integration boundary for a future on-device briefing model:

- Deterministic `HostIntelligenceEngine` remains authoritative.
- `HostLLMPacket` is the only writer input (max 5 ranked facts, writing rules, forbidden behaviors).
- `HostBriefingWriter` + `HostBriefingWriterValidator` enforce presentation-only output (≤4 sentences, ≤500 chars).
- `LocalModelHostBriefingWriter` is a safe shell that falls back to template text today.
- `HostLocalModelReadinessProvider` is the single readiness source of truth.

This proposal compares four runtime options for **Phase 8B** integration. The use case is narrow: rewrite a small, sanitized packet into calm host prose — not chat, not tool use, not reservation mutation.

**Recommendation:** Implement **llama.cpp (via `swift-llama` or `mattt/llama.swift`) + a small bundled GGUF model** in Phase 8B for predictable TestFlight coverage. Add **Apple Foundation Models** as an optional fast path in a later phase when device gating is acceptable.

---

## Use-case constraints (this app)

| Constraint | Current implementation |
|---|---|
| Input boundary | `HostLLMPacket` only — no raw `Reservation` records |
| Output limits | ≤4 sentences, ≤500 characters |
| Decision authority | Engine only; writer is presentation-only |
| Fallback | `templateBriefingText` via validator + `.failedFallback` |
| Refresh trigger | Host board `.task(id:)` after `evaluate()` — not continuous inference |
| Typical packet size | ≤5 facts + rules; ~300–1,200 input tokens estimated |
| Deployment target | iOS **18.4** (today) |
| Distribution | TestFlight / internal staff devices |
| Privacy | No reservation data to external APIs |
| Offline | Required when enhanced briefing is enabled |

---

## Option comparison

### 1. Apple Foundation Models framework

| Dimension | Assessment |
|---|---|
| **Dependencies** | System framework (`import FoundationModels`). No SPM package. May require capability / entitlement configuration in Xcode. |
| **iOS / device constraints** | iOS **26+**, iPadOS 26+, macOS 15+. Requires **Apple Intelligence–eligible hardware** (e.g. iPhone 15 Pro+, M-series iPad) and user-enabled Apple Intelligence. Regional / language availability applies. |
| **Model bundling** | **No app bundle.** ~3B-parameter model ships with the OS (downloaded with Apple Intelligence). |
| **App size impact** | **~0 MB** added to IPA. |
| **Memory / CPU** | OS-managed. Peak RAM not charged to app budget in the same way as bundled runtimes. Low latency on supported hardware. |
| **Swift integration complexity** | **Low.** `SystemLanguageModel.default.availability` check → `LanguageModelSession` → `respond(to:)`. Supports instructions + guided generation (`@Generable`) for structured output. |
| **App Store / TestFlight risk** | **Low** for review (first-party API). **High product risk:** feature silently unavailable on many staff devices unless fallback is solid. Must document Apple Intelligence dependency for internal rollout. |
| **Plug-in to `LocalModelHostBriefingWriter`** | Check `HostLocalModelReadinessProvider` → if `.ready`, serialize packet to prompt → `LanguageModelSession.respond` → validate → return `.localModel` source (new enum case) or `.failedFallback`. |
| **Fully offline** | **Yes** on supported devices with Apple Intelligence enabled. **No** on ineligible devices (use template fallback). |
| **Small model candidates** | N/A — fixed OS model (~3B). Quality likely sufficient for 4-sentence rewrites. |

**Pros:** Best privacy story, zero bundle size, native Swift, no model file management, Apple-maintained.  
**Cons:** Cannot rely on for all TestFlight devices; requires iOS 26+ if used as sole runtime; availability depends on user settings and region; less control over model/version.

---

### 2. llama.cpp / llama.swift with GGUF

| Dimension | Assessment |
|---|---|
| **Dependencies** | SPM: [`mattt/llama.swift`](https://github.com/mattt/llama.swift) (XCFramework re-export) or [`profclaw/swift-llama`](https://github.com/profclaw/swift-llama) (higher-level Swift actor API). Underlying: [`ggml-org/llama.cpp`](https://github.com/ggml-org/llama.cpp) prebuilt XCFramework. |
| **iOS / device constraints** | `mattt/llama.swift`: iOS **16+**. `swift-llama`: iOS **17+**. Metal GPU acceleration on Apple Silicon. Physical device recommended for realistic perf testing. |
| **Model bundling** | **Bundle** in app resources (TestFlight/offline) or **download once** to Application Support (smaller IPA, needs first-launch download UX). |
| **App size impact** | **+350 MB – +2.0 GB** depending on model/quantization. For this task, target **+350–800 MB**. |
| **Memory / CPU** | 0.5B–1B Q4: ~0.5–1.2 GB peak RAM — safe on most staff iPhones. 3B Q4: ~2–3.5 GB peak — needs `com.apple.developer.kernel.increased-memory-limit` on some devices. Inference is bursty (acceptable for host board refresh). |
| **Swift integration complexity** | **Medium.** Load GGUF once (singleton actor), build prompt from packet, generate with low `n_predict` (~120 tokens), validate. `swift-llama` reduces boilerplate vs raw C API. |
| **App Store / TestFlight risk** | **Low–medium.** Large IPA may slow TestFlight installs. No network requirement if bundled. Review generally fine for on-device inference; declare in privacy nutrition label if needed. |
| **Plug-in to `LocalModelHostBriefingWriter`** | Readiness checks model file on disk → lazy-load `LlamaActor` → `HostLLMPacketPromptBuilder.build(packet:)` → generate → `HostBriefingWriterValidator` → result. |
| **Fully offline** | **Yes** when model is bundled or previously downloaded. |
| **Small model candidates** | **Qwen2.5-0.5B-Instruct** Q4_K_M (~350 MB) — best size/quality tradeoff for rewrites. **Llama-3.2-1B-Instruct** Q4_0 (~700 MB) — backup. Avoid 7B+ for iOS. |

**Pros:** Broad device support at current iOS 18.4 target; predictable behavior; fully offline; mature Metal path; matches existing shell architecture.  
**Cons:** App size; memory tuning per device class; maintain model file + SPM dependency; must ship prompt engineering.

---

### 3. MLX Swift / mlx-swift-lm

| Dimension | Assessment |
|---|---|
| **Dependencies** | SPM: [`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift) + [`ml-explore/mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm). Optional Hugging Face download helpers. |
| **iOS / device constraints** | iOS **17.4+** for MLX Swift on device. **Simulator not supported** for inference — device-only testing. Apple Silicon required for GPU path. |
| **Model bundling** | Bundle MLX weights (`.safetensors` + config) or download from Hugging Face (`mlx-community/*` 4-bit models). |
| **App size impact** | Similar to llama.cpp: **+400 MB – +2 GB** for 0.5B–3B 4-bit models. |
| **Memory / CPU** | Comparable to llama.cpp for same parameter count. Unified memory friendly on Apple Silicon. Thermal throttling under sustained load (less relevant for single briefing refresh). |
| **Swift integration complexity** | **Medium–high.** `LLMModelFactory` / `ChatSession` API is ergonomic, but dependency graph is larger than llama.swift. More moving parts (tokenizer, weight layout, mlx-swift versions). |
| **App Store / TestFlight risk** | **Low–medium** (same large-binary concerns). CI/device testing friction due to no simulator support. |
| **Plug-in to `LocalModelHostBriefingWriter`** | Same pattern as llama.cpp: readiness → load container → `ChatSession` with system instructions from packet rules → respond → validate. |
| **Fully offline** | **Yes** with bundled weights. |
| **Small model candidates** | `mlx-community/Qwen2.5-0.5B-Instruct-4bit`, `mlx-community/Llama-3.2-1B-Instruct-4bit`, `mlx-community/Phi-3.5-mini-instruct-4bit` (larger). |

**Pros:** Apple-first stack; clean `ChatSession` API; good WWDC / MLX ecosystem alignment.  
**Cons:** Heavier dependency tree; simulator gap hurts development; less battle-tested in production iOS apps than llama.cpp XCFramework path.

---

### 4. MLC LLM iOS

| Dimension | Assessment |
|---|---|
| **Dependencies** | Local Swift package `ios/MLCSwift` + **Python `mlc_llm package`** build step producing `dist/lib/` and `dist/bundle/`. Manual Xcode linker flags (`-lmodel_iphone`, `-lmlc_llm`, etc.). |
| **iOS / device constraints** | Physical device only. Memory limits strict: **3B q4** marginal on non-Pro iPhones; project docs/issues suggest **q3** or smaller for reliable iOS deployment. |
| **Model bundling** | `bundle_weight: true` in `mlc-package-config.json` or HF download at runtime. |
| **App size impact** | **+1.5–3+ GB** for 3B bundled; smaller for 0.5B–1B MLC-converted models. |
| **Memory / CPU** | Highest operational risk. KV cache + weights exceed model file size. Requires aggressive `context_window_size` / `prefill_chunk_size` overrides. `Increased Memory Limit` entitlement often required. |
| **Swift integration complexity** | **High.** Separate packaging pipeline, linker configuration, `MLCEngine.reload`, model lib hashes, copy build phases. Designed for chat demo apps, not a thin writer hook. |
| **App Store / TestFlight risk** | **Medium.** Large binary + entitlement scrutiny. Build reproducibility across machines is harder. |
| **Plug-in to `LocalModelHostBriefingWriter`** | Possible but requires substantial infrastructure wrapper; poor fit for a single `writeBriefing` call site. |
| **Fully offline** | **Yes** when bundled. |
| **Small model candidates** | `HF://mlc-ai/gemma-2b-it-q4f16_1-MLC`, `HF://mlc-ai/Llama-3.2-3B-Instruct-q4f16_1-MLC` (pushing memory limits), custom 0.5B conversions. |

**Pros:** Optimized mobile GPU kernels; official iOS Swift SDK exists.  
**Cons:** Worst integration cost for this app; Python toolchain; fragile memory on common staff phones; overkill for ≤120-token outputs.

---

## Side-by-side matrix

| Criterion | Foundation Models | llama.cpp + GGUF | MLX Swift LM | MLC LLM |
|---|---|---|---|---|
| Offline (all targeted devices) | Partial | **Yes** | **Yes** | **Yes** |
| App size (realistic) | **0 MB** | +350–800 MB | +400–900 MB | +1.5–3 GB |
| iOS 18.4 compatible | No (needs 26+) | **Yes** | **Yes** (17.4+) | **Yes** |
| Swift integration effort | Low | **Medium** | Medium–high | High |
| TestFlight predictability | Low (device gate) | **High** | High | Medium |
| No external API calls | **Yes** | **Yes** | **Yes** (if bundled) | **Yes** (if bundled) |
| Fits `LocalModelHostBriefingWriter` | **Excellent** | **Excellent** | Good | Poor |

---

## Recommendations

### 1. Recommended runtime (Phase 8B)

**llama.cpp via `swift-llama` (preferred) or `mattt/llama.swift`**

Rationale for this app:

- Matches **iOS 18.4** deployment target without forcing an OS upgrade.
- **Fully offline** on all TestFlight devices when a small model is bundled.
- Task is tiny (rewrite ≤5 facts) — a **0.5B–1B** model is sufficient; no need for MLC’s heavy mobile stack.
- Integrates cleanly into the existing `HostBriefingWriter` protocol and validator.
- `swift-llama` provides actor isolation, chat templates, and optional HF download — useful for internal builds that want smaller IPAs.

### 2. Backup runtime

**Apple Foundation Models framework (Phase 8C or 9A)**

Use as an **optional tier** inside `LocalModelHostBriefingWriter`:

1. If `SystemLanguageModel.default.isAvailable` → use Foundation Models (zero bundle).
2. Else if bundled GGUF present → llama.cpp.
3. Else → template fallback (current behavior).

This gives Apple Intelligence devices a zero-size fast path without sacrificing coverage on older staff phones.

### 3. Model choice

| Tier | Model | Format | Approx. size | Notes |
|---|---|---|---|---|
| **Primary (llama.cpp)** | `Qwen2.5-0.5B-Instruct` | GGUF Q4_K_M | ~350 MB | Best fit for short rewrites; low RAM |
| **Alternate (llama.cpp)** | `Llama-3.2-1B-Instruct` | GGUF Q4_0 | ~700 MB | Slightly better prose, more RAM |
| **Foundation Models tier** | OS on-device model | System | 0 MB in app | Use when available; no file management |

**Do not** ship 3B+ as the default for Phase 8B — unnecessary for 4-sentence output and risky on 6 GB RAM devices.

---

## Integration steps (Phase 8B)

### Step 1 — Prompt boundary (no runtime yet)

Add `HostLLMPacketPromptBuilder` that converts `HostLLMPacket` → system + user prompt strings:

- Include `serviceState`, `pressureScore`, `topFacts` (title/detail only — no raw IDs required in prose).
- Inject `forbiddenBehaviors` and `writingRules` as system instructions.
- Explicitly instruct: "Rewrite only. Do not add facts. Max 4 sentences."

Unit-test prompt builder with fixtures — no model required.

### Step 2 — Runtime adapter

Add `HostLocalModelRuntime` (actor):

- Owns lazy model load / unload.
- `generateBriefing(prompt:) async throws -> String` with hard `maxTokens` (~120).
- Never accepts types other than prompt strings derived from `HostLLMPacket`.

### Step 3 — Readiness

Extend `HostLocalModelReadinessProvider.currentReadiness()`:

| Status | Condition |
|---|---|
| `.runtimeMissing` | SPM linked but runtime init failed |
| `.modelMissing` | Runtime OK, GGUF not in bundle / Application Support |
| `.ready` | Model loaded or loadable |
| `.unavailable` | Feature disabled or device explicitly unsupported |

### Step 4 — Writer implementation

Replace shell body in `LocalModelHostBriefingWriter`:

```text
readiness → build prompt → runtime.generate → validator → HostBriefingWriterResult
```

On any failure: return `fallbackText`, `.failedFallback`, `failedReason`.

Add `HostBriefingWriterSource.localModel` for successful inference (distinct from `.localPlaceholder`).

### Step 5 — Controller / UI (minimal)

- `HostIntelligenceController.refreshBriefing()` — **no logic change** if writer returns correct result types.
- `HostIntelligenceCard` — show subtle caption for `.localModel` (e.g. "Enhanced briefing"); never show runtime errors.
- Settings / diagnostics — show readiness, model name, last failure reason.

### Step 6 — Build configuration

- Add SPM dependency (`swift-llama` recommended).
- Add GGUF to a **Downloadable Resource** or **On-Demand Resource** if IPA size is a concern; otherwise bundle for internal TestFlight simplicity.
- Enable **Increased Memory Limit** only if 1B+ model testing requires it.
- Add `Scripts/` or `Makefile` target documenting model download + SHA256 verification (not committed to git).

### Step 7 — Validation gate

Before shipping TestFlight:

- Run diagnostics writer test on device.
- Confirm validator rejects execution language.
- Confirm empty-packet path returns template text.
- Confirm airplane mode works with bundled model.

---

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Large IPA slows TestFlight adoption | Medium | Use 0.5B model; ODR or post-install download for production |
| OOM on older iPhones | Medium | Cap model at 0.5B–1B; lazy load; unload after inference; readiness gating |
| Model hallucinates facts | Medium | Strict validator + packet-only input + "do not invent" rules; fallback on validation failure |
| Slow host board refresh | Low | Single inference per `.task(id:)` refresh; cache last result in controller if needed (no timers) |
| SPM / xcframework breakage on Xcode updates | Medium | Pin exact package version; CI device build |
| Staff device fragmentation | High (FM only) | Prefer llama.cpp for 8B; add Foundation Models tier later |
| App Review questions on local AI | Low | On-device only; no data collection; privacy manifest unchanged |

---

## Estimated implementation complexity

| Phase | Scope | Effort |
|---|---|---|
| **8B — llama.cpp core** | Prompt builder, runtime actor, writer, readiness, settings/diagnostics, bundled 0.5B model | **3–5 days** |
| **8C — polish** | ODR/download path, device matrix testing, memory tuning | **2–3 days** |
| **9A — Foundation Models tier** | Availability gating, dual runtime, iOS 26 bump decision | **1–2 days** |

Overall Phase 8B: **Medium** complexity — mostly adapter + packaging, not engine changes.

---

## Exact files to modify in Phase 8B

### New files

| File | Purpose |
|---|---|
| `Features/HostIntelligence/HostLLMPacketPromptBuilder.swift` | Packet → prompt (no runtime) |
| `Features/HostIntelligence/HostLocalModelRuntime.swift` | Actor wrapping llama.cpp load/inference |
| `Resources/Models/` (gitignored) or ODR tag | GGUF weight storage |
| `Scripts/fetch-host-briefing-model.sh` | Documented model download + checksum |

### Modified files

| File | Change |
|---|---|
| `HostBriefingWriter.swift` | Implement `LocalModelHostBriefingWriter`; add `.localModel` to `HostBriefingWriterSource` |
| `HostLocalModelReadiness.swift` | Real filesystem / runtime checks |
| `HostBriefingWriterFactory.swift` | Unchanged switch (already routes `.localModel`) |
| `HostIntelligenceModels.swift` | Optional: writer source display names |
| `HostIntelligenceSettingsView.swift` | Ready vs missing states; download/bundle notice |
| `HostIntelligenceDiagnosticsView.swift` | Live inference test, token/latency debug |
| `HostIntelligenceCard.swift` | Caption for `.localModel` success |
| `Tryzub Reservations.xcodeproj/project.pbxproj` | SPM package, entitlements if needed |
| `.gitignore` | Ignore `*.gguf` / `Resources/Models/` |

### Unchanged (by design)

- `HostIntelligenceEngine.swift`
- `HostIntelligenceController.swift` (unless adding `.localModel` source handling in UI consumers)
- Sync, repository, API, schema, reservation mutation paths

---

## Rollback plan

1. **Settings rollback:** Set `enhancedBriefingProvider = .template` or `useEnhancedBriefing = false` — immediate template briefing (no code deploy).
2. **Code rollback:** Revert `LocalModelHostBriefingWriter` to Phase 7C shell (returns fallback + `runtimeMissingReason`).
3. **Dependency rollback:** Remove SPM package from Xcode project; delete `HostLocalModelRuntime.swift` and prompt builder.
4. **Binary rollback:** Remove bundled GGUF / ODR tag — app returns to pre-8B IPA size.
5. **Readiness rollback:** `HostLocalModelReadinessProvider` returns `.runtimeMissing` — diagnostics show shell state.

No database migrations or server changes are involved. Rollback is a client-only revert with zero reservation data impact.

---

## Acceptance checklist (Phase 8A — this document)

- [x] Build unchanged (no production code modified)
- [x] Four runtimes compared against app constraints
- [x] Recommended + backup runtime identified
- [x] Model choice specified
- [x] Integration steps, risks, complexity, file list, rollback documented

---

## Suggested phase sequence after 8A

| Phase | Goal |
|---|---|
| **8B** | llama.cpp + Qwen2.5-0.5B bundled; real `LocalModelHostBriefingWriter` |
| **8C** | Optional model download / ODR; device test matrix |
| **9A** | Apple Foundation Models tier for eligible devices |
| **9B** | Prompt tuning + validator hardening from real device output logs (diagnostics only) |
