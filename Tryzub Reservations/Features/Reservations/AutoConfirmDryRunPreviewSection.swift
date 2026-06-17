//
//  AutoConfirmDryRunPreviewSection.swift
//  Tryzub Reservations
//
//  Shared read-only dry-run preview (GET /auto-confirm/candidates only).
//

import SwiftUI

struct AutoConfirmDryRunPreviewSection: View {
    let apiClient: any ReservationsAPIClientProtocol
    var defaultDate: Date = Date()
    var showsDatePicker: Bool = true
    var buttonTitle: String = "Preview Auto-Confirm for Today"

    @State private var dryRunDate: Date
    @State private var dryRunResponse: AutoConfirmCandidateResponse?
    @State private var dryRunError: String?
    @State private var isRunningDryRun = false

    init(
        apiClient: any ReservationsAPIClientProtocol,
        defaultDate: Date = Date(),
        showsDatePicker: Bool = true,
        buttonTitle: String = "Preview Auto-Confirm for Today"
    ) {
        self.apiClient = apiClient
        self.defaultDate = defaultDate
        self.showsDatePicker = showsDatePicker
        self.buttonTitle = buttonTitle
        _dryRunDate = State(initialValue: defaultDate)
    }

    private var eligibleCount: Int {
        dryRunResponse?.data.filter(\.eligible).count ?? 0
    }

    private var blockedCount: Int {
        dryRunResponse?.data.filter { !$0.eligible }.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsDatePicker {
                DatePicker("Preview date", selection: $dryRunDate, displayedComponents: .date)
                    .font(.subheadline)
            }

            Button {
                Task { await runDryRun() }
            } label: {
                if isRunningDryRun {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Running preview…")
                    }
                } else {
                    Label(buttonTitle, systemImage: "checklist")
                }
            }
            .disabled(isRunningDryRun)
            .font(.subheadline.weight(.semibold))

            if let dryRunError {
                Text(dryRunError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let dryRunResponse {
                AutoConfirmDryRunResultsSummary(
                    response: dryRunResponse,
                    eligibleCount: eligibleCount,
                    blockedCount: blockedCount
                )
            }
        }
    }

    @MainActor
    private func runDryRun() async {
        isRunningDryRun = true
        dryRunError = nil
        defer { isRunningDryRun = false }

        do {
            dryRunResponse = try await apiClient.fetchAutoConfirmCandidates(
                date: dryRunDate,
                reason: .autoConfirmCandidates
            )
        } catch {
            dryRunResponse = nil
            dryRunError = error.localizedDescription
        }
    }
}

struct AutoConfirmDryRunResultsSummary: View {
    let response: AutoConfirmCandidateResponse
    let eligibleCount: Int
    let blockedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Eligible", value: "\(eligibleCount)")
            LabeledContent("Blocked", value: "\(blockedCount)")
            LabeledContent("Date", value: response.date)

            if response.data.isEmpty {
                Text("No candidates returned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(response.data) { candidate in
                    AutoConfirmCandidateDiagnosticsRow(candidate: candidate)
                }
            }
        }
    }
}

struct AutoConfirmCandidateDiagnosticsRow: View {
    let candidate: AutoConfirmCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(candidate.reservationId)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(candidate.eligible ? "Eligible" : "Blocked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(candidate.eligible ? .green : .orange)
            }

            Text("Time \(candidate.reservationTime ?? "—") · Party \(candidate.partySize) · \(candidate.status) · \(candidate.sourceType)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let ruleID = candidate.matchingRuleId?.nilIfBlank {
                Text("Rule \(ruleID) · max party \(candidate.matchingRuleMaxPartySize ?? 0)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !candidate.blockedReasons.isEmpty {
                Text(
                    candidate.blockedReasons
                        .map(AutoConfirmBlockedReasonLabels.displayText(for:))
                        .joined(separator: " · ")
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
