//
//  DeveloperDiagnosticsView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

struct DeveloperDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @ObservedObject private var requestLogStore = APIRequestLogStore.shared

    @Query private var reservations: [ReservationRecord]

    @State private var reservationIDText = ""
    @State private var isRunningTest = false
    @State private var testResults: [AdminFetchTestResult] = []

    let environment: AppEnvironment

    private var todayRows: [ReservationRecord] {
        reservations.filter(\.isToday)
    }

    private var latestFailure: APIRequestLogEvent? {
        requestLogStore.events.first { $0.outcome == .failed }
    }

    var body: some View {
        List {
            apiHealthSection
            syncScopeSection
            safeFetchTestsSection
            requestLogSection
            cacheSection
            noticeSection
            endpointChecklistSection
            safetySection
        }
        .navigationTitle("API Diagnostics")
    }

    private var syncScopeSection: some View {
        Section("Sync Scopes") {
            if controller.syncScopeSnapshots.isEmpty {
                Text("No scope activity yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.syncScopeSnapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(snapshot.scope.description)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if snapshot.isInFlight {
                                Text("In flight")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        scopeTimestampRow("Attempt", snapshot.lastAttemptAt)
                        scopeTimestampRow("Success", snapshot.lastSuccessAt)
                        scopeTimestampRow("Failure", snapshot.lastFailureAt)
                        scopeTimestampRow("Cooldown", snapshot.cooldownUntil)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var apiHealthSection: some View {
        Section("API Health") {
            row("Base URL", environment.apiClient.debugBaseURLDescription)
            row("Credentials", environment.apiClient.hasConfiguredCredentials ? "Present" : "Missing")
            row("Role", environment.role.displayName)
            row("Last sync", controller.lastSyncedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")

            if let latestFailure {
                row("Last failure", latestFailure.error ?? latestFailure.message ?? "Unknown")
                row("Failure reason", latestFailure.reason.rawValue)
            } else {
                row("Last failure", "None this session")
            }

            if controller.capabilities.canViewDeveloperDiagnostics {
                Text("Diagnostics are available because this session uses the developer capability.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var safeFetchTestsSection: some View {
        Section {
            ForEach(AdminFetchTest.allCases.filter { $0 != .fetchByID }) { test in
                Button {
                    run(test)
                } label: {
                    Label(test.title, systemImage: "network")
                }
                .disabled(isRunningTest)
            }

            HStack {
                TextField("Reservation ID", text: $reservationIDText)
                    .keyboardType(.numberPad)

                Button("Fetch") {
                    run(.fetchByID)
                }
                .disabled(isRunningTest || Int(reservationIDText) == nil)
            }

            if isRunningTest {
                ProgressView("Running safe GET test...")
            }

            ForEach(testResults.prefix(5)) { result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(result.succeeded ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.test.title)
                            .font(.subheadline.weight(.semibold))
                        Text(result.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result.durationText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Safe GET Tests")
        } footer: {
            Text("These buttons only perform GET requests. Contract tests cover ping, setup, hours, availability, public slots, managed reservations, analytics, and sync scopes.")
        }
    }

    private var requestLogSection: some View {
        Section {
            if requestLogStore.events.isEmpty {
                Text("No API events logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(requestLogStore.events.prefix(25)) { event in
                    APIRequestLogRow(event: event)
                }

                Button("Clear Request Log") {
                    requestLogStore.clear()
                }
            }
        } header: {
            Text("Request Log")
        } footer: {
            Text("The log stores method, endpoint, reason, status/error, body snippet, decode error, and duration. Credentials and guest payloads are not logged.")
        }
    }

    private var cacheSection: some View {
        Section("SwiftData Cache") {
            row("Cached reservations", "\(reservations.count)")
            row("Today cached", "\(todayRows.count)")
            row("New", "\(reservations.filter { $0.statusValue == .new }.count)")
            row("Needs review", "\(reservations.filter { $0.statusValue == .needsReview }.count)")
            row("Confirmed", "\(reservations.filter { $0.statusValue == .confirmed }.count)")
            row("Without table", "\(reservations.filter { !$0.hasTableAssignment }.count)")
            row("Latest local sync", latestLocalSyncText)
        }
    }

    private var noticeSection: some View {
        Section {
            if controller.notices.isEmpty {
                Text("No current notices.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.notices) { notice in
                    NoticeDetailRow(notice: notice) {
                        controller.dismissNotice(notice)
                    }
                }

                Button("Clear Notices") {
                    controller.clearAllNotices()
                }
            }
        } header: {
            Text("Notification Center Preview")
        }
    }

    private var endpointChecklistSection: some View {
        Section("Endpoint Contract Checklist") {
            endpointRow("GET /ping", pathFragment: "/ping")
            endpointRow("GET /restaurant-setup", pathFragment: "/restaurant-setup")
            endpointRow("GET /restaurant-hours", pathFragment: "/restaurant-hours")
            endpointRow("GET /restaurant-day-availability", pathFragment: "/restaurant-day-availability")
            endpointRow("GET /reservation-slots", pathFragment: "/reservation-slots")
            endpointRow("GET /restaurant-blocked-slots", pathFragment: "/restaurant-blocked-slots")
            endpointRow("GET /reservation-analytics/summary", pathFragment: "/reservation-analytics/summary")
            endpointRow("GET /managed-reservations?date=YYYY-MM-DD", pathFragment: "/managed-reservations")
            endpointRow("GET /managed-reservations", pathFragment: "/managed-reservations")
            endpointRow("GET /managed-reservations/{id}", pathFragment: "/managed-reservations/")
            endpointRow("PATCH /managed-reservations/{id}", pathFragment: "/managed-reservations/")
            endpointRow("POST /managed-reservations", pathFragment: "/managed-reservations")
            endpointRow("POST /managed-reservations/{id}/confirm", pathFragment: "/confirm")
            endpointRow("GET /managed-reservations/import-failures", pathFragment: "/managed-reservations/import-failures")
            endpointRow("POST /restaurant-blocked-slots", pathFragment: "/restaurant-blocked-slots")
            endpointRow("DELETE /restaurant-blocked-slots", pathFragment: "/restaurant-blocked-slots")

            HStack {
                Image(systemName: "nosign")
                    .foregroundStyle(.green)
                Text("NOT USED: POST /managed-reservations/import")
                Spacer()
                Text(didCallManualImportEndpoint ? "Check" : "Clean")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var safetySection: some View {
        Section("Danger Zone") {
            Text("No mutation tests are implemented here. Confirm, cancel, seat, create, and email-send flows must only happen through the normal reservation workflow with explicit staff action.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var latestLocalSyncText: String {
        reservations.compactMap(\.lastSyncedAt).max()?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    private var didCallManualImportEndpoint: Bool {
        requestLogStore.events.contains { event in
            event.method == "POST"
                && (event.pathAndQuery?.contains("/managed-reservations/import") ?? false)
                && !(event.pathAndQuery?.contains("/managed-reservations/import-failures") ?? false)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func scopeTimestampRow(_ title: String, _ date: Date?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(date?.formatted(date: .omitted, time: .standard) ?? "none")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func endpointRow(_ title: String, pathFragment: String) -> some View {
        HStack {
            Image(systemName: requestLogStore.hasSuccessfulCall(containing: pathFragment) ? "checkmark.circle" : "circle")
                .foregroundStyle(requestLogStore.hasSuccessfulCall(containing: pathFragment) ? .green : .secondary)
            Text(title)
            Spacer()
        }
    }

    private func run(_ test: AdminFetchTest) {
        Task {
            isRunningTest = true
            defer { isRunningTest = false }

            let reservationID = Int(reservationIDText)
            let result = await controller.runAdminFetchTest(test, reservationID: reservationID)
            testResults.insert(result, at: 0)
            if testResults.count > 10 {
                testResults.removeLast(testResults.count - 10)
            }
        }
    }
}

private struct APIRequestLogRow: View {
    let event: APIRequestLogEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(event.reason.rawValue)
                    .font(.caption.weight(.bold))
                Spacer()
                Text(event.createdAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(event.outcome.rawValue)
                if let method = event.method {
                    Text(method)
                }
                if let statusCode = event.statusCode {
                    Text("HTTP \(statusCode)")
                }
                if let duration = event.duration {
                    Text(duration)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let pathAndQuery = event.pathAndQuery {
                Text(pathAndQuery)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let error = event.error ?? event.message {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let responseBodySnippet = event.responseBodySnippet, !responseBodySnippet.isEmpty {
                Text("body: \(responseBodySnippet)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let decodingError = event.decodingError, !decodingError.isEmpty {
                Text("decode: \(decodingError)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
