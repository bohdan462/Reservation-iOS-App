//
//  AppNotice.swift
//  Tryzub Reservations
//

import Foundation
import SwiftUI

enum AppNoticeSeverity: String, CaseIterable {
    case info
    case success
    case warning
    case error

    var symbolName: String {
        switch self {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .info:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

enum AppNoticeSource: String, CaseIterable {
    case startup
    case manualToday
    case autoToday
    case schedule
    case review
    case mutation
    case email
    case credentials
    case importFailures
    case admin
}

struct AppNotice: Identifiable, Equatable {
    let id: UUID
    let severity: AppNoticeSeverity
    let source: AppNoticeSource
    let title: String
    let message: String?
    let requestReason: ReservationAPIRequestReason?
    let errorCode: String?
    let createdAt: Date

    init(
        severity: AppNoticeSeverity,
        source: AppNoticeSource,
        title: String,
        message: String? = nil,
        requestReason: ReservationAPIRequestReason? = nil,
        errorCode: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.severity = severity
        self.source = source
        self.title = title
        self.message = message
        self.requestReason = requestReason
        self.errorCode = errorCode
        self.createdAt = createdAt
    }
}

