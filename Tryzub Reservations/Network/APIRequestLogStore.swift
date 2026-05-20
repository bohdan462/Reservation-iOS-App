//
//  APIRequestLogStore.swift
//  Tryzub Reservations
//

import Foundation

enum APIRequestLogOutcome: String {
    case started
    case succeeded
    case failed
    case cancelled
    case skipped
}

struct APIRequestLogEvent: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let outcome: APIRequestLogOutcome
    let reason: ReservationAPIRequestReason
    let method: String?
    let pathAndQuery: String?
    let statusCode: Int?
    let error: String?
    let duration: String?
    let message: String?

    init(
        outcome: APIRequestLogOutcome,
        reason: ReservationAPIRequestReason,
        method: String? = nil,
        pathAndQuery: String? = nil,
        statusCode: Int? = nil,
        error: String? = nil,
        duration: String? = nil,
        message: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = createdAt
        self.outcome = outcome
        self.reason = reason
        self.method = method
        self.pathAndQuery = pathAndQuery
        self.statusCode = statusCode
        self.error = error
        self.duration = duration
        self.message = message
    }
}

@MainActor
final class APIRequestLogStore: ObservableObject {
    static let shared = APIRequestLogStore()

    @Published private(set) var events: [APIRequestLogEvent] = []

    private let limit = 100

    private init() {}

    func append(_ event: APIRequestLogEvent) {
        events.insert(event, at: 0)
        if events.count > limit {
            events.removeLast(events.count - limit)
        }
    }

    func clear() {
        events.removeAll()
    }

    func hasSuccessfulCall(containing pathFragment: String) -> Bool {
        events.contains {
            $0.outcome == .succeeded
                && ($0.pathAndQuery?.contains(pathFragment) ?? false)
        }
    }
}
