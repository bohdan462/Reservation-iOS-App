//
//  TryzubHostSummaryIntentService.swift
//  Tryzub Reservations
//

import Foundation
import OSLog
import SwiftData

@MainActor
enum TryzubHostSummaryIntentService {
    private static let apiBaseURL = URL(string: "https://tryzubchicago.com/wp-json/tryzub/v1")!
    private static let signInRequiredMessage = "Tryzub Reservations needs you to open the app and sign in first."
    private static let unavailableMessage = "Tryzub Reservations could not reach the reservation server, and no saved reservations were available for today."

    static func buildTodaySummary(now: Date = Date()) async -> String {
        TryzubSiriIntentTrace.start()

        let session = loadSavedSession()
        guard let credentials = session.credentials, credentials.isComplete else {
            TryzubSiriIntentTrace.credentialsMissing()
            return signInRequiredMessage
        }
        guard session.role == .manager || session.role == .developer else {
            TryzubSiriIntentTrace.roleNotAllowed()
            return signInRequiredMessage
        }

        let today = now.reservationDateString()
        let client = ReservationsAPIClient(
            baseURL: apiBaseURL,
            username: credentials.username,
            applicationPassword: credentials.applicationPassword,
            role: session.role
        )
        let builder = SpokenHostSummaryBuilder()

        do {
            let response = try await client.fetchReservations(
                page: 1,
                perPage: 100,
                date: nil,
                from: today,
                to: today,
                status: nil,
                search: nil,
                includeHidden: false,
                updatedSince: nil,
                reason: .siriHostSummary
            )
            TryzubSiriIntentTrace.networkFetchSucceeded(count: response.data.count)
            TryzubSiriIntentTrace.summarySource("network", reservations: response.data.count)
            return builder.build(from: response.data, dateKey: today, now: now)
        } catch {
            TryzubSiriIntentTrace.networkFetchFailedFallbackCache()
            guard let cached = loadCachedReservations(for: today), !cached.isEmpty else {
                return unavailableMessage
            }
            TryzubSiriIntentTrace.summarySource("cache", reservations: cached.count)
            return builder.build(from: cached, dateKey: today, now: now, prefix: "Based on saved data, ")
        }
    }

    private static func loadSavedSession() -> (credentials: AppCredentials?, role: AppUserRole?) {
        let roleStore = AppRoleStore()
        let credentialStore = AppCredentialStore()
        credentialStore.reload(for: roleStore.selectedRole)
        return (credentialStore.credentials, roleStore.selectedRole)
    }

    private static func loadCachedReservations(for dateKey: String) -> [ReservationRecord]? {
        do {
            try PersistenceDirectoryBootstrap.ensureApplicationSupportDirectoryExists()
            let container = try ModelContainer(
                for: ReservationRecord.self, ReservationAttachmentRecord.self, ReservationStructuredNoteRecord.self
            )
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ReservationRecord>(
                predicate: #Predicate<ReservationRecord> { record in
                    record.reservationDate == dateKey
                },
                sortBy: [
                    SortDescriptor(\ReservationRecord.reservationTime),
                    SortDescriptor(\ReservationRecord.remoteID)
                ]
            )
            return try context.fetch(descriptor).filter { !$0.isHidden }
        } catch {
            return nil
        }
    }
}

private enum TryzubSiriIntentTrace {
    #if DEBUG
    private static let logger = Logger(
        subsystem: "Bohdan-Solovey.Tryzub-Reservations",
        category: "SiriIntent"
    )

    static func start() {
        logger.debug("[SIRI_INTENT_TRACE] intent=get_host_summary phase=start")
    }

    static func credentialsMissing() {
        logger.debug("[SIRI_INTENT_TRACE] credentials=missing")
    }

    static func roleNotAllowed() {
        logger.debug("[SIRI_INTENT_TRACE] role=missing_or_unsupported")
    }

    static func networkFetchSucceeded(count: Int) {
        logger.debug("[SIRI_INTENT_TRACE] fetch=network_today success=true count=\(count, privacy: .public)")
    }

    static func networkFetchFailedFallbackCache() {
        logger.debug("[SIRI_INTENT_TRACE] fetch=network_today success=false fallback=cached")
    }

    static func summarySource(_ source: String, reservations: Int) {
        logger.debug("[SIRI_INTENT_TRACE] summary_source=\(source, privacy: .public) reservations=\(reservations, privacy: .public)")
    }
    #else
    static func start() {}
    static func credentialsMissing() {}
    static func roleNotAllowed() {}
    static func networkFetchSucceeded(count: Int) {}
    static func networkFetchFailedFallbackCache() {}
    static func summarySource(_ source: String, reservations: Int) {}
    #endif
}
