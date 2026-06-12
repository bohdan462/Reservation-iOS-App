//
//  ServiceBriefing.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 1 foundation.
//
//  The ServiceBriefing is the structured output consumed by Host Board and the
//  Global Intelligence view. Structured actions are primary; the headline/summary
//  are short staff-language strings (deterministic by default, model-improved only
//  when useful). It is grouped so the same fact never repeats across sections.
//

import Foundation

enum BriefingSource: String, Codable, Equatable {
    case deterministic
    case localModel
    case backend
    case templateFallback
    case mixed
}

struct ServiceBriefing: Equatable, Codable {
    let mode: ServiceMode
    let headline: String
    let summary: String
    let checkNow: [StaffActionIntent]
    let comingUp: [StaffActionIntent]
    let reviewLater: [StaffActionIntent]
    let afterClose: [StaffActionIntent]
    let todaySummary: [String]
    let unresolvedCount: Int
    let source: BriefingSource

    /// Total actionable items surfaced (excludes pure summary lines).
    var totalActionCount: Int {
        checkNow.count + comingUp.count + reviewLater.count + afterClose.count
    }

    var hasActionableContent: Bool {
        totalActionCount > 0
    }

    static func empty(mode: ServiceMode) -> ServiceBriefing {
        ServiceBriefing(
            mode: mode,
            headline: "Nothing left to check.",
            summary: "",
            checkNow: [],
            comingUp: [],
            reviewLater: [],
            afterClose: [],
            todaySummary: [],
            unresolvedCount: 0,
            source: .deterministic
        )
    }
}
