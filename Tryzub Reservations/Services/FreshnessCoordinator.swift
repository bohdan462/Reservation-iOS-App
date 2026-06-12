//
//  FreshnessCoordinator.swift
//  Tryzub Reservations
//
//  Centralized fetch/skip/join/cooldown decisions for all data scopes.
//  Does NOT perform network calls. Callers ask for a decision; they fetch if told to.
//
//  One shared instance should be created by AppReservationSession and passed into
//  stores/controllers as an environment object or injected dependency.
//  Never instantiate inside individual views.
//
//  Trace format: [FRESHNESS_COORDINATOR] scope=... decision=... reason=...
//

import Foundation
import OSLog

// MARK: - Scope

enum FreshnessScope: Hashable, CustomStringConvertible {
    case activeWindow(from: String, to: String)
    case reservationDate(String)
    case availabilityBundle(date: String)
    case guestIntelligenceDate(String)
    case guestProfile(reservationID: Int)
    case businessAnalytics(rangeKey: String)
    case intelligenceSystemStatus(rangeKey: String)
    case pipelineDiagnostics(rangeKey: String)
    case floorPlan(date: String)
    case restaurantTables
    case restaurantSetup
    case restaurantHours
    case restaurantDayAvailability(date: String)
    case restaurantBlockedSlots(date: String)

    var description: String {
        switch self {
        case .activeWindow(let from, let to):
            return "activeWindow(\(from)–\(to))"
        case .reservationDate(let d):
            return "reservationDate(\(d))"
        case .availabilityBundle(let d):
            return "availabilityBundle(\(d))"
        case .guestIntelligenceDate(let d):
            return "guestIntelligenceDate(\(d))"
        case .guestProfile(let id):
            return "guestProfile(\(id))"
        case .businessAnalytics(let k):
            return "businessAnalytics(\(k))"
        case .intelligenceSystemStatus(let k):
            return "systemStatus(\(k))"
        case .pipelineDiagnostics(let k):
            return "pipelineDiagnostics(\(k))"
        case .floorPlan(let d):
            return "floorPlan(\(d))"
        case .restaurantTables:
            return "restaurantTables"
        case .restaurantSetup:
            return "restaurantSetup"
        case .restaurantHours:
            return "restaurantHours"
        case .restaurantDayAvailability(let d):
            return "dayAvailability(\(d))"
        case .restaurantBlockedSlots(let d):
            return "blockedSlots(\(d))"
        }
    }

    /// Default TTL per scope in seconds. Callers may override via `decide(scope:ttl:)`.
    var defaultTTL: TimeInterval {
        switch self {
        case .activeWindow:
            return 60       // Active-window auto-refresh cadence
        case .reservationDate:
            return 60
        case .availabilityBundle:
            return 300      // Availability doesn't change minute-to-minute
        case .guestIntelligenceDate:
            return 180
        case .guestProfile:
            return 300
        case .businessAnalytics, .intelligenceSystemStatus, .pipelineDiagnostics:
            return 600
        case .floorPlan:
            return 60
        case .restaurantTables:
            return 300
        case .restaurantSetup:
            return 600
        case .restaurantHours:
            return 600
        case .restaurantDayAvailability:
            return 300
        case .restaurantBlockedSlots:
            return 120
        }
    }
}

// MARK: - Decision

enum FreshnessDecision: Equatable, CustomStringConvertible {
    case useCache(reason: String)
    case fetch(reason: String)
    case joinInFlight(reason: String)
    case blockedByCooldown(reason: String)

    var description: String {
        switch self {
        case .useCache(let r):   return "use_cache(\(r))"
        case .fetch(let r):      return "fetch(\(r))"
        case .joinInFlight(let r): return "join_in_flight(\(r))"
        case .blockedByCooldown(let r): return "blocked_by_cooldown(\(r))"
        }
    }

    var shouldFetch: Bool {
        if case .fetch = self { return true }
        return false
    }
}

// MARK: - Coordinator

@MainActor
final class FreshnessCoordinator: ObservableObject {

    // MARK: - State

    private var lastFetchedAt: [FreshnessScope: Date] = [:]
    private var inFlightScopes: Set<FreshnessScope> = []
    private var cooldownUntil: [FreshnessScope: Date] = [:]

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "FreshnessCoordinator"
    )

    // MARK: - Core Decision

    /// Ask whether a scope should be fetched, use cache, join in-flight, or wait.
    /// - Parameter force: Skip TTL check (but not in-flight dedup).
    func decide(
        scope: FreshnessScope,
        ttl: TimeInterval? = nil,
        force: Bool = false
    ) -> FreshnessDecision {
        let now = Date()
        let effectiveTTL = ttl ?? scope.defaultTTL

        // In-flight dedup: join rather than duplicate
        if inFlightScopes.contains(scope) {
            let decision = FreshnessDecision.joinInFlight(reason: "in_flight")
            log(scope: scope, decision: decision)
            return decision
        }

        // Cooldown after failure
        if let cooldown = cooldownUntil[scope], now < cooldown {
            let decision = FreshnessDecision.blockedByCooldown(reason: "failure_cooldown")
            log(scope: scope, decision: decision)
            return decision
        }

        // TTL check
        if !force, let lastFetch = lastFetchedAt[scope] {
            let age = now.timeIntervalSince(lastFetch)
            if age < effectiveTTL {
                let decision = FreshnessDecision.useCache(reason: "fresh_\(Int(age))s_of_\(Int(effectiveTTL))s")
                log(scope: scope, decision: decision)
                return decision
            }
        }

        let reason = force ? "forced" : (lastFetchedAt[scope] == nil ? "never_fetched" : "stale")
        let decision = FreshnessDecision.fetch(reason: reason)
        log(scope: scope, decision: decision)
        return decision
    }

    // MARK: - Lifecycle Signals

    /// Call when a fetch for this scope has started.
    func markInFlight(_ scope: FreshnessScope) {
        inFlightScopes.insert(scope)
    }

    /// Call when a fetch for this scope completed successfully.
    func markCompleted(_ scope: FreshnessScope) {
        inFlightScopes.remove(scope)
        lastFetchedAt[scope] = Date()
        cooldownUntil.removeValue(forKey: scope)
    }

    /// Call when a fetch for this scope failed; starts a cooldown.
    func markFailed(_ scope: FreshnessScope, cooldown: TimeInterval = 30) {
        inFlightScopes.remove(scope)
        cooldownUntil[scope] = Date().addingTimeInterval(cooldown)
    }

    /// Clear an in-flight marker without marking fresh or starting a cooldown.
    /// Use for ignored/cancelled responses (e.g., selected date changed mid-flight)
    /// so the scope is neither stuck in-flight nor falsely considered fresh.
    func endInFlight(_ scope: FreshnessScope) {
        inFlightScopes.remove(scope)
    }

    /// Mirror a decision made by an external owner (e.g. ReservationsController's existing
    /// scope-state machine) into the shared coordinator log so device proof shows one
    /// `[FRESHNESS_COORDINATOR]` vocabulary across all surfaces. State (lastFetchedAt /
    /// in-flight / cooldown) is still updated via markInFlight/markCompleted/markFailed.
    func record(scope: FreshnessScope, decision: FreshnessDecision) {
        log(scope: scope, decision: decision)
    }

    /// Invalidate a scope so the next decision will fetch.
    func invalidate(_ scope: FreshnessScope) {
        lastFetchedAt.removeValue(forKey: scope)
        cooldownUntil.removeValue(forKey: scope)
    }

    /// Invalidate all scopes keyed by a date (useful after manual refresh).
    func invalidateDate(_ date: String) {
        let dateScopes: [FreshnessScope] = [
            .reservationDate(date),
            .availabilityBundle(date: date),
            .guestIntelligenceDate(date),
            .floorPlan(date: date),
            .restaurantDayAvailability(date: date),
            .restaurantBlockedSlots(date: date),
        ]
        dateScopes.forEach { invalidate($0) }
    }

    /// Mark a scope fresh without a network fetch (e.g., just loaded from SwiftData cache).
    func markCacheHit(_ scope: FreshnessScope) {
        // Don't set lastFetchedAt — that's reserved for server responses.
        // But do log it so startup traces are complete.
        #if DEBUG
        log(scope: scope, decision: .useCache(reason: "cache_hit"))
        #endif
    }

    // MARK: - Convenience: decide-and-act helper

    /// Returns true if the caller should proceed with a fetch (marks scope in-flight).
    /// Returns false if cache is fresh, scope is in-flight, or cooldown applies.
    func shouldFetch(
        scope: FreshnessScope,
        ttl: TimeInterval? = nil,
        force: Bool = false
    ) -> Bool {
        let decision = decide(scope: scope, ttl: ttl, force: force)
        if decision.shouldFetch {
            markInFlight(scope)
            return true
        }
        return false
    }

    // MARK: - Debug snapshot

    struct ScopeSnapshot: Identifiable {
        let id: String
        let scope: FreshnessScope
        let lastFetchedAt: Date?
        let inFlight: Bool
        let cooldownUntil: Date?
    }

    var debugSnapshot: [ScopeSnapshot] {
        let allScopes = Set(lastFetchedAt.keys)
            .union(inFlightScopes)
            .union(cooldownUntil.keys)
        return allScopes.map { scope in
            ScopeSnapshot(
                id: scope.description,
                scope: scope,
                lastFetchedAt: lastFetchedAt[scope],
                inFlight: inFlightScopes.contains(scope),
                cooldownUntil: cooldownUntil[scope]
            )
        }.sorted { $0.id < $1.id }
    }

    // MARK: - Logging

    private func log(scope: FreshnessScope, decision: FreshnessDecision) {
        #if DEBUG
        let decisionKey: String
        let reason: String
        switch decision {
        case .useCache(let r):
            decisionKey = "use_cache"; reason = r
        case .fetch(let r):
            decisionKey = "fetch"; reason = r
        case .joinInFlight(let r):
            decisionKey = "join_in_flight"; reason = r
        case .blockedByCooldown(let r):
            decisionKey = "blocked_by_cooldown"; reason = r
        }
        FreshnessCoordinator.logger.debug(
            "[FRESHNESS_COORDINATOR] scope=\(scope.description, privacy: .public) decision=\(decisionKey, privacy: .public) reason=\(reason, privacy: .public)"
        )
        #endif
    }
}
