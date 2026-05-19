# Diagnostic Report: Fetch Architecture & Architecture Risks

**Date:** May 19, 2026  
**Status:** CLEAN repository, app COMPILES successfully  
**Checkpoint:** Already clean (no edits needed before diagnostics)

---

## SECTION 1: GIT / CHECKPOINT STATUS

- **Repo State:** CLEAN (no modified, added, deleted, or untracked files)
- **Last Commit:** "Hard refactor" (recent refactoring completed)
- **App Compilation:** ✅ SUCCESS - Build succeeded with no errors
- **Checkpoint Needed:** No (repo already clean)
- **Status for Editing:** SAFE - Ready to make changes

---

## SECTION 2: FETCH TRIGGER MAP

### All Fetch Triggers Identified:

#### **2.1 App Launch Chain**
| Trigger | File | Method | Endpoint | Guard | Loop Risk |
|---------|------|--------|----------|-------|-----------|
| View appears | ReservationsListView | `.task { loadIfNeeded }` | GET /managed-reservations (all) | `hasAttemptedInitialLoad` flag | ❌ None - guard prevents repeat |
| First tab shown | TodayDashboardView | `.task { refreshImportFailureCount }` | GET /managed-reservations/import-failures | None | ❌ None - runs once |

**Architecture:** `ReservationsListView.task` → `controller.loadIfNeeded()` → checks `hasAttemptedInitialLoad` → if fresh sync needed (>5min), calls `refreshAll()` → upserts to SwiftData

---

#### **2.2 Manual Refresh Triggers**
| Screen | Trigger | Guard | Guard Strength |
|--------|---------|-------|-----------------|
| Today | Pull-to-refresh OR refresh button | `isSyncing` flag | ✅ Strong - prevents concurrent refresh |
| Schedule | Pull-to-refresh OR refresh button | `isSyncing` flag | ✅ Strong - prevents concurrent refresh |
| Review | Pull-to-refresh OR refresh button | `isSyncing` flag | ✅ Strong - prevents concurrent refresh |

**Architecture:** `refreshAll()` has `guard !isSyncing else { return }` - prevents overlapping fetches

---

#### **2.3 Import Failures Screen**
| Trigger | File | Method | Endpoint | Guard | Loop Risk |
|---------|------|--------|----------|-------|-----------|
| View appears | ImportFailuresView | `.task { loadFailures }` | GET /managed-reservations/import-failures | `isLoading` flag | ⚠️ Medium - see note |
| Manual refresh | ImportFailuresView | `.refreshable { loadFailures }` | GET /managed-reservations/import-failures | `isLoading` flag | ⚠️ Medium - see note |

**Note:** Both `.task` and `.refreshable` exist on same view, but they're independent events:
- `.task` runs on appear → sets `isLoading=true` → loads → sets `isLoading=false`
- `.refreshable` runs on pull → same logic
- **No unintended double-fetch because each has its own trigger**
- **But:** If view reappears while `.refreshable` is loading, `.task` could fire again (low probability, guarded by `isLoading`)

---

#### **2.4 Mutation Operations**
| Operation | File | Endpoint | Guard | Concurrency |
|-----------|------|----------|-------|-------------|
| updateReservation | ReservationDetailView / HostBoardView | PATCH /managed-reservations/{id} | `actionInProgressIDs.contains(id)` | ✅ Strong - per-reservation |
| confirmReservation | ReservationDetailView / HostBoardView | POST /managed-reservations/{id}/confirm | `actionInProgressIDs.contains(id)` | ✅ Strong - per-reservation |
| createReservation | ManualReservationFormView | POST /managed-reservations | None (quick form save) | ⚠️ Weak - button not disabled during save |
| updateStatus (seat/complete/cancel/noshow) | ReservationDetailView / HostBoardView | PATCH /managed-reservations/{id} | Via `updateReservation` → `actionInProgressIDs` | ✅ Strong |

**Mutation Pattern:**
```
User action (button click)
  ↓
add id to actionInProgressIDs (disables button UI)
  ↓
call API (network operation)
  ↓
if successful: upsert returned DTO to SwiftData
  ↓
remove id from actionInProgressIDs (enables button)
  ↓
@Query redraws with new data
  ↓
NO new network call (data updated locally)
```

---

### **2.5 Local Filtering (No Network Calls)**
| Screen | Action | Effect |
|--------|--------|--------|
| Schedule | Change Picker scope (Upcoming/All) | Filters local @Query data - no fetch |
| Schedule | Search text input | Filters local @Query data - no fetch |
| Review | Change Picker scope (Needs Review/New) | Filters local @Query data - no fetch |
| Review | Search text input | Filters local @Query data - no fetch |

---

## SECTION 3: SUSPECTED FETCH LOOP CAUSES

### Risk Assessment:

| Issue | Severity | Location | Root Cause | Current Guard |
|-------|----------|----------|-----------|----------------|
| **loadIfNeeded called multiple times** | **🟢 LOW** | ReservationsListView.task | Swift View recomputation | ✅ `hasAttemptedInitialLoad` prevents repeat |
| **SwiftData upsert triggers @Query redraw** | **🟢 LOW** | Repository.upsert → @Query | Automatic SwiftData invalidation | ✅ Query redraws only, no new fetch |
| **ImportFailuresView double-trigger** | **🟡 MEDIUM** | ImportFailuresView | `.task` + `.refreshable` on same view | ⚠️ `isLoading` flag + independent events |
| **Refresh button on every screen** | **🟢 LOW** | All tabs | Manual user action | ✅ `isSyncing` guard prevents overlap |
| **Mutation -> full refresh cascade** | **🟢 LOW** | ReservationDetailView → controller | User could rapidly tap buttons | ✅ `actionInProgressIDs` per-reservation lock |

### **Verdict on Fetch Loop:**
- **No uncontrolled fetch loop detected**
- **No circular dependency found** (upsert → query redraw → no fetch)
- **Most likely culprit if a loop exists:** Network retry logic on transient errors could cause repeated attempts if error recovery isn't clean

---

## SECTION 4: CONCURRENCY / MAINACTOR REVIEW

### **CRITICAL ISSUE: @MainActor on Network Services**

#### Problem Code:
```swift
@MainActor
final class ReservationSyncService: ReservationSyncServiceProtocol {
    // ❌ This class does network I/O
    func syncAllReservations() async throws {
        let reservations = try await client.fetchAllReservations(...)  // BLOCKS MAIN THREAD
        try repository.upsert(reservations)  // Then Main Thread UI updates
    }
}

@MainActor
final class ReservationMutationService: ReservationMutationServiceProtocol {
    // ❌ This class does network I/O
    func updateReservation(id: Int, request: ...) async throws -> ReservationDTO {
        let reservation = try await client.updateReservation(...)  // BLOCKS MAIN THREAD
        try repository.upsert(reservation)
        return reservation
    }
}
```

#### Impact:
- **Network calls happen on Main Thread** - if API is slow or drops connection, main thread is blocked
- **UI becomes unresponsive** during network wait
- **Not a fetch loop, but responsiveness issue**

#### Expected Pattern:
```swift
// ✅ Correct pattern
final class ReservationSyncService {  // NOT @MainActor
    func syncAllReservations() async throws {
        let reservations = try await client.fetchAllReservations(...)  // Background thread
        await MainActor.run {
            try repository.upsert(reservations)  // Only upsert on MainActor
        }
    }
}
```

---

### **Other Concurrency Observations:**

| Component | Status | Notes |
|-----------|--------|-------|
| ReservationRepository | ✅ Correct | @MainActor - SwiftData must be on main |
| ReservationsAPIClient | ✅ Correct | No @MainActor - network on background |
| ReservationsController | ✅ Correct | @MainActor - owns @Published state |
| Task blocks in views | ✅ Mostly Correct | `Task { await controller.method() }` - proper |
| Refresh button disabled during sync | ✅ Correct | `.disabled(controller.isSyncing)` |
| PATCH button disabled during mutation | ✅ Correct | Uses `actionInProgressIDs` check |
| POST button (create) not disabled | ❌ Issue | Button should be disabled during save |

---

### **Task Cancellation & Memory Leaks:**

| Location | Pattern | Risk |
|----------|---------|------|
| ReservationsListView.task | `await controller.loadIfNeeded()` | ⚠️ Task can be cancelled if view disappears - OK |
| Button actions | `Task { await ... }` | ⚠️ Task not stored/tracked - can run after view dismiss |
| ManualReservationFormView create button | `Task { await createReservation() }` | ⚠️ Low risk (sheet dismisses on success) |
| TodayDashboardView refresh | `Task { await controller.refreshAll() }` | ⚠️ Task runs even if tab hidden |

---

## SECTION 5: ARCHITECTURE BOUNDARY ISSUES

### **Current Architecture Layers:**

```
┌─ VIEW LAYER ─────────────────────────────────────┐
│ ReservationsListView                              │
│ TodayDashboardView, ReservationScheduleView, etc. │
│ • Displays data (@Query from SwiftData)           │
│ • Calls controller actions (no direct API calls)  │
│ • No URLSession, no JSON decode                   │
└──────────────────────────────────────────────────┘
           ↓ calls controller methods
┌─ CONTROLLER LAYER ────────────────────────────────┐
│ ReservationsController (@MainActor)               │
│ • Manages @Published state (isSyncing, etc.)      │
│ • Coordinates fetches & mutations                 │
│ • Creates fresh services for each operation       │
│ • No URLSession, no JSON                          │
└──────────────────────────────────────────────────┘
           ↓ creates/calls services
┌─ SERVICE LAYER ───────────────────────────────────┐
│ ReservationSyncService (@MainActor ❌ ISSUE)     │
│ ReservationMutationService (@MainActor ❌ ISSUE) │
│ ImportFailureService (OK)                         │
│ • Orchestrates API + Repository                   │
│ • Calls APIClient for network                     │
│ • Calls Repository for persistence                │
│ • ❌ Blocking on network due to @MainActor        │
└──────────────────────────────────────────────────┘
           ↓ calls
┌─ REPOSITORY LAYER ────────────────────────────────┐
│ ReservationRepository (@MainActor ✅ Correct)    │
│ • Wraps SwiftData ModelContext                    │
│ • Upsert, fetch local                             │
│ • Must be @MainActor (SwiftData requirement)      │
└──────────────────────────────────────────────────┘
           ↓ uses
┌─ PERSISTENCE LAYER ───────────────────────────────┐
│ ReservationRecord (SwiftData model)               │
│ • Stored in device SQLite                         │
└──────────────────────────────────────────────────┘

┌─ API LAYER ───────────────────────────────────────┐
│ ReservationsAPIClient (no @MainActor ✅ Correct) │
│ • Builds URLRequest                               │
│ • Adds auth headers                               │
│ • Calls URLSession.data                           │
│ • Validates HTTP response                         │
│ • Decodes JSON to DTO                             │
│ • Returns data or throws error                    │
│ • Handles transient retry (1 retry)               │
└──────────────────────────────────────────────────┘
```

### **Boundary Violations & Risks:**

| Violation | Severity | Details |
|-----------|----------|---------|
| Services marked @MainActor with network work | 🔴 HIGH | Blocks main thread during API calls |
| Services created fresh each time | 🟡 MEDIUM | Wasteful but not breaking - no state preservation needed |
| Repository also fresh each time | 🟡 MEDIUM | OK for read-only singleton context pattern |
| Controller creates fresh API client each call | ✅ OK | APIClient is stateless wrapper |
| Views calling controller (not API directly) | ✅ OK | Good separation |
| No business logic in view render | ✅ OK | Correct |

---

## SECTION 6: NETWORK FAILURE HANDLING REVIEW

### **API Client Error Handling:**

```swift
private func perform(_ request: URLRequest, retryCount: Int = 0) async throws -> Data {
    // Handles transient network errors with 1 retry (450ms backoff)
    // Returns ReservationAPIError
}

enum ReservationAPIError: Error {
    case invalidURL
    case invalidResponse
    case unauthorized
    case networkFailure(URLError)  // ← Handles network drops
    case serverError(statusCode: Int)
    case wordpressError(code: String, message: String, statusCode: Int)
    case decodingFailure(Error)
}
```

### **Retry Logic:**
- **GET requests:** 1 retry for transient errors (good)
- **PATCH/POST requests:** No retry (safe - mutation idempotency not guaranteed)
- **Backoff:** 450ms × attempt (prevents thundering herd)

### **Failure Scenarios & Current Handling:**

| Scenario | Current Behavior | UI Feedback | Risk |
|----------|-----------------|-------------|------|
| Network drops mid-sync | Retry once, then error | `errorMessage` alert | ✅ User sees error, can retry |
| Timeout (>30s) | Error immediately | `errorMessage` alert | ✅ User sees error |
| 401/403 Unauthorized | Throws `unauthorized` | `errorMessage` alert | ✅ Clear feedback |
| 400 Validation error | Shows WordPress error message | `errorMessage` alert | ✅ Clear feedback |
| 500 Server error | Shows HTTP 500 | `errorMessage` alert | ✅ Clear feedback |
| JSON decode fails | `decodingFailure` | `errorMessage` alert | ⚠️ Generic message |
| Confirm endpoint email_status failed | Caught, shown to user | Notice message | ✅ Handles all cases |
| Confirm endpoint email_status already_sent | Caught, shown to user | Notice message | ✅ Handles gracefully |
| Network drops on PATCH mutation | No auto-retry | `errorMessage` shows | ✅ Correct (don't blindly retry) |
| Uncertain if PATCH reached server | `mayHaveReachedReservationServer` check | Error shown | ✅ User sees "Retry or check" |

### **Error Recovery Pattern:**

```swift
func updateReservation(...) async throws -> ReservationDTO {
    do {
        let reservation = try await client.updateReservation(...)
        try repository.upsert(reservation)
        return reservation
    } catch {
        if error.mayHaveReachedReservationServer {
            // Fetch current state to reconcile
            _ = try? await reconcileReservation(id: id)
        }
        throw error  // Still shows error to user
    }
}
```

### **Verdict:**
- ✅ Network drops are handled
- ✅ Errors are user-visible
- ✅ No silent failures
- ✅ No automatic retry loops
- ✅ Reconciliation for uncertain mutations
- ⚠️ One opportunity: could offer "Retry" button on network failures

---

## SECTION 7: UI WRAPPING / LAYOUT ISSUES

### **ReservationRowView (Compact - iPhone):**

| Component | Issue | Severity | Likely Cause |
|-----------|-------|----------|--------------|
| Guest name | May wrap if long | 🟡 MEDIUM | `lineLimit(1)` but name can be 30+ chars |
| Pill row (time, party, table, phone) | **LIKELY WRAPS** | 🔴 HIGH | Multiple HStack pills in `lineLimit(1)` container - if any pill is long, they all may wrap |
| Phone number | May wrap vertically | 🟡 MEDIUM | `monospacedDigit()` + `lineLimit(1)` but (555)123-4567 can be 14 chars |
| Table display | May overflow | 🟡 MEDIUM | No truncation specified, just `lineLimit(1)` |
| Date/status row | May wrap | 🟡 MEDIUM | Multiple pills in second row also in `lineLimit(1)` |

**Example Wrapping Scenario on iPhone SE (narrow screen):**
```
Guest Name
19:30  4 people  Table 5  (555)...    ❌ Wraps to 2-3 lines
```

### **ReservationRowView (Regular - iPad/Wide):**

| Component | Issue | Severity |
|-----------|-------|----------|
| Time (82pt frame) | Should fit (82 points) | ✅ OK |
| Name/phone/date | Multiple lines | ✅ Designed for multi-line |
| Party size (42pt) | 1-3 digits fit | ✅ OK |
| Table name (92-140pt) | Fits most cases | ⚠️ Could overflow very long names |
| Status badge (116pt) | Should fit | ✅ OK |

### **ReservationDetailView Layout Issues:**

| Component | Issue | Severity | Notes |
|-----------|-------|----------|-------|
| Detail time (44pt font) | May split oddly | 🟡 MEDIUM | "19:30" OK, but "19 : 3 / 0" in some fonts |
| Time in hero card | Could vertically stack if squished | ⚠️ MEDIUM | Fixed layout but very large font |
| Pills in hero (party, table, email) | `lineLimit(1)` may wrap row | 🟡 MEDIUM | If any pill is long, row wraps |
| Contact info phone/email | Can wrap | 🟡 MEDIUM | Links can be very long |
| Contact phone formatted | Good - uses `monospacedDigit()` | ✅ OK |
| Date/time/party facts rows | Fixed layout OK | ✅ OK |
| Table name in facts | Orange text if no assignment | ✅ Good visual feedback |

### **HostBoardView (Today Screen) Layout:**

| Component | Issue | Severity |
|-----------|-------|----------|
| Summary card (sync time, counts) | Should fit | ✅ OK - designed for summary |
| Warning banners | `lineLimit(1)` - text may wrap | 🟡 MEDIUM |
| Reservation columns | Very good wide layout | ✅ OK |
| Compact board on iPhone | Should stack vertically | ✅ OK |

---

## SECTION 8: MINIMUM SAFE FIX PLAN

### **Phases (in order of importance):**

### **PHASE 1: Fix Critical Concurrency Issue** 🔴
**Impact:** Main thread blocking during network calls
1. Remove @MainActor from ReservationSyncService
2. Remove @MainActor from ReservationMutationService  
3. Wrap Repository calls with `await MainActor.run { }`
4. **Files:** ReservationImportService.swift, ReservationMutationService.swift
5. **Testing:** Should not change behavior, just fix responsiveness

### **PHASE 2: Fix UI Button States** 🟡
**Impact:** Prevent accidental double-clicks on mutations
1. Add `isLoading` guard to ManualReservationFormView create button
2. Disable create button during save (already has `isSaving` state, just use it)
3. **Files:** ManualReservationFormView.swift
4. **Testing:** Try rapid clicks during create - button should stay disabled

### **PHASE 3: Fix Row Wrapping on Compact** 🟡
**Impact:** Better layout on iPhone SE and narrow screens
1. Reduce pill count or change layout for narrow widths
2. Consider abbreviating or hiding less-critical pills
3. Use responsive `@Environment(\.horizontalSizeClass)` for ultra-compact
4. **Files:** ReservationRowView.swift, ReservationMetaPill
5. **Testing:** Test on iPhone SE (375pt width)

### **PHASE 4: Improve Detail View Layout** 🟡
**Impact:** Better use of space, less unnecessary scrolling
1. Review ReservationDetailView card sizing
2. Ensure pills don't wrap unnecessarily in hero card
3. Test iPad landscape layout
4. **Files:** ReservationDetailView.swift
5. **Testing:** Test on iPad Pro landscape (1112pt width)

### **PHASE 5: Add Error Retry UI** 🟢
**Impact:** Better UX on network failures
1. Add "Retry" button option to error alerts
2. Or: Add inline retry for specific failures
3. **Files:** ReservationsController.swift
4. **Testing:** Simulate network failure, verify retry works

---

## SECTION 9: SUMMARY OF KEY FINDINGS

### ✅ What's Working Well:
1. **No fetch loop detected** - `hasAttemptedInitialLoad` guard is effective
2. **Concurrent mutation prevention** - `actionInProgressIDs` prevents double-taps
3. **Good error handling** - Errors are visible to user
4. **Reconciliation on uncertain failures** - App fetches current state if uncertain
5. **Clean architecture** - Good separation between API/Service/Repository/View layers
6. **Local filtering only** - Search and pickers don't trigger network fetches
7. **Appropriate retry logic** - Transient errors retry, mutations don't (safe)

### 🔴 Critical Issues:
1. **@MainActor on network services** - Main thread blocks during API calls (HIGH PRIORITY)

### 🟡 Medium Issues:
1. **Create button not disabled during save** - Could allow double-submit
2. **Row wrapping on iPhone SE** - Pills may wrap awkwardly on narrow screens
3. **ImportFailuresView has .task + .refreshable** - Low risk due to `isLoading` guard, but worth reviewing

### 🟢 Low Issues:
1. **Generic decode failure message** - Could be more helpful
2. **No retry button in UI** - Could improve UX on network failures

---

## SECTION 10: SAFE EDIT CHECKPOINT

**Current Status:** ✅ SAFE TO EDIT
- Repo is clean
- App compiles
- No breaking changes needed to restore function
- Recommended: Start with Phase 1 (concurrency fixes)

---

**Report Date:** May 19, 2026  
**Prepared by:** Diagnostic Analysis  
**Next Steps:** Await approval to proceed with Phase 1 changes
