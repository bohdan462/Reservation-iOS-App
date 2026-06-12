//
//  ServiceMode.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  ServiceMode is the deterministic answer to "what part of the day are we in?".
//  It is the fix for the bug where, after close with no active reservations, the
//  app still surfaced live operational facts ("A10 opened after cancellation").
//  Live table facts and "due in X" only make sense `duringService`. After close we
//  either need cleanup or we show a recap. The model never decides this — the
//  deterministic resolver does.
//

import Foundation

enum ServiceMode: String, Codable, Equatable, CaseIterable {
    /// Selected day is today and service has not started yet (before open, nothing seated).
    case beforeService
    /// Selected day is today and service is live (open window, or active/seated work exists).
    case duringService
    /// Selected day is today, service window is over, but reservations still need status cleanup.
    case afterCloseNeedsCleanup
    /// Selected day is today, service window is over, and nothing is left to resolve.
    case afterCloseFinished
    /// Selected day is in the future — planning only, never "live".
    case futurePlanning
    /// Selected day is in the past — recap only, never "live".
    case pastRecap

    /// Live operational facts (no-table-soon, "due in X", freed-table) are only
    /// meaningful while service is actually happening.
    var allowsLiveOperationalFacts: Bool {
        self == .duringService
    }

    /// Whether the surface should present a recap/summary rather than live actions.
    var isRecapContext: Bool {
        switch self {
        case .afterCloseFinished, .pastRecap:
            return true
        case .beforeService, .duringService, .afterCloseNeedsCleanup, .futurePlanning:
            return false
        }
    }

    var isAfterClose: Bool {
        self == .afterCloseNeedsCleanup || self == .afterCloseFinished
    }

    var traceLabel: String { rawValue }
}
