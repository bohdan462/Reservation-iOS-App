//
//  ScreenFreshnessState.swift
//  Tryzub Reservations
//

import Foundation

// MARK: - Freshness Policy

struct DataFreshnessPolicy: Equatable {
    let availabilityTTL: TimeInterval
    let slotsTTL: TimeInterval
    let blockedSlotsTTL: TimeInterval
    let guestIntelligenceTTL: TimeInterval
    let restaurantSetupTTL: TimeInterval

    static let standard = DataFreshnessPolicy(
        availabilityTTL: 300,
        slotsTTL: 300,
        blockedSlotsTTL: 300,
        guestIntelligenceTTL: 180,
        restaurantSetupTTL: 300
    )
}

// MARK: - Screen Freshness

enum ScreenFreshnessState: Equatable {
    case fresh(checkedAt: Date)
    case stale(lastCheckedAt: Date?)
    case loading
    case unavailable(reason: String)

    var isFresh: Bool {
        if case .fresh = self { return true }
        return false
    }

    var lastCheckedAt: Date? {
        switch self {
        case let .fresh(checkedAt):
            return checkedAt
        case let .stale(lastCheckedAt):
            return lastCheckedAt
        case .loading, .unavailable:
            return nil
        }
    }

    static func from(
        loadedAt: Date?,
        ttl: TimeInterval,
        now: Date = Date(),
        isLoading: Bool = false,
        unavailableReason: String? = nil
    ) -> ScreenFreshnessState {
        if let unavailableReason {
            return .unavailable(reason: unavailableReason)
        }
        if isLoading, loadedAt == nil {
            return .loading
        }
        guard let loadedAt else {
            return .stale(lastCheckedAt: nil)
        }
        if now.timeIntervalSince(loadedAt) < ttl {
            return .fresh(checkedAt: loadedAt)
        }
        return .stale(lastCheckedAt: loadedAt)
    }

    func statusLine(now: Date = Date()) -> String? {
        switch self {
        case let .fresh(checkedAt):
            return Self.relativeFreshnessLine(checkedAt: checkedAt, now: now)
        case let .stale(lastCheckedAt):
            if let lastCheckedAt {
                return Self.relativeFreshnessLine(checkedAt: lastCheckedAt, now: now, stale: true)
            }
            return nil
        case .loading:
            return "Refreshing available times…"
        case let .unavailable(reason):
            return reason
        }
    }

    private static func relativeFreshnessLine(
        checkedAt: Date,
        now: Date,
        stale: Bool = false
    ) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(checkedAt)))
        let prefix = stale ? "Times last checked" : "Times checked"
        if seconds < 60 {
            return "\(prefix) just now"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(prefix) \(minutes) minute\(minutes == 1 ? "" : "s") ago"
        }
        let hours = minutes / 60
        return "\(prefix) \(hours) hour\(hours == 1 ? "" : "s") ago"
    }
}
