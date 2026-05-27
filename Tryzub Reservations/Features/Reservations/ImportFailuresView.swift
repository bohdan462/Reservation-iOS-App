//
//  ImportFailuresView.swift
//  Tryzub Reservations
//

import SwiftUI

struct ImportFailuresView: View {
    let environment: AppEnvironment
    let onCreateReservation: (ReservationCreateRequest) async throws -> ReservationDTO
    let onCreated: (ReservationDTO) -> Void

    @EnvironmentObject private var controller: ReservationsController

    @State private var failures: [ImportFailureDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if isLoading && failures.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Checking failed imports...")
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                } else if failures.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Failed Imports",
                            systemImage: "checkmark.seal",
                            description: Text("All normal Flamingo inbox submissions are represented in the managed table.")
                        )
                    }
                } else {
                    Section("Failed Imports") {
                        ForEach(failures) { failure in
                            NavigationLink {
                                ImportFailureDetailView(
                                    failure: failure,
                                    environment: environment,
                                    onCreateReservation: onCreateReservation,
                                    onCreated: onCreated
                                )
                            } label: {
                                ImportFailureRow(failure: failure)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Failed Imports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadFailures()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadFailures()
            }
            .refreshable {
                await loadFailures()
            }
        }
    }

    private func loadFailures() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            failures = try await controller.fetchImportFailures(page: 1, perPage: 100).data
        } catch {
            errorMessage = "Could not load form problems. Please retry."
        }
    }
}

private struct ImportFailureRow: View {
    let failure: ImportFailureDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(failure.reservation?.guestName?.nilIfBlank ?? "Unknown Guest")
                    .font(.headline)

                Spacer()

                Text("#\(failure.sourceSubmissionId.map(String.init) ?? "?")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(failure.errorMessage)
                .font(.subheadline)
                .foregroundStyle(.red)

            HStack(spacing: 12) {
                if let date = failure.reservation?.reservationDate {
                    Label(date, systemImage: "calendar")
                }
                if let time = failure.reservation?.reservationTime {
                    Label(time, systemImage: "clock")
                }
                if let email = failure.reservation?.email?.nilIfBlank {
                    Label(email, systemImage: "envelope")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ImportFailureDetailView: View {
    let failure: ImportFailureDTO
    let environment: AppEnvironment
    let onCreateReservation: (ReservationCreateRequest) async throws -> ReservationDTO
    let onCreated: (ReservationDTO) -> Void

    var body: some View {
        List {
            Section("Error") {
                row("Source", failure.sourceSubmissionId.map(String.init) ?? "Unknown")
                row("Code", failure.errorCode)
                Text(failure.errorMessage)
                    .foregroundStyle(.red)
            }

            Section("Submitted Reservation") {
                row("Name", failure.reservation?.guestName)
                row("Email", failure.reservation?.email)
                row("Phone", failure.reservation?.phone)
                row("Date", failure.reservation?.reservationDate)
                row("Time", failure.reservation?.reservationTime)
                row("Party", failure.reservation?.partySize.map(String.init))
                row("Submitted", failure.submittedAt)
                row("CF7 Status", failure.submissionStatus)
            }

            Section {
                NavigationLink {
                    ManualReservationFormView(
                        failure: failure,
                        onCreateReservation: { request in
                            let reservation = try await onCreateReservation(request)
                            onCreated(reservation)
                            return reservation
                        }
                    )
                } label: {
                    Label("Create Fixed Reservation", systemImage: "plus.circle.fill")
                }
            }

            Section("Raw JSON") {
                ScrollView(.horizontal) {
                    Text(failure.prettyJSONString)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Failed Import")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value?.nilIfBlank ?? "—")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension ImportFailureDTO {
    var prettyJSONString: String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "Unable to render JSON."
        }

        return json
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if DEBUG
#Preview("Failed Imports") {
    let environment = AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)

    ImportFailuresView(
        environment: environment,
        onCreateReservation: { _ in ReservationPreviewData.sampleDTOs[0] },
        onCreated: { _ in }
    )
    .environmentObject(ReservationsController(environment: environment))
}
#endif
