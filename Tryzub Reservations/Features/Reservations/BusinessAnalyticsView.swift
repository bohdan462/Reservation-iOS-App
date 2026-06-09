//
//  BusinessAnalyticsView.swift
//  Tryzub Reservations
//

import SwiftUI

struct BusinessAnalyticsView: View {
    @ObservedObject var settingsStore: RestaurantSettingsStore
    @EnvironmentObject private var businessIntelligenceStore: BusinessIntelligenceStore
    @EnvironmentObject private var intelligenceSystemStatusStore: IntelligenceSystemStatusStore

    @State private var summary: ReservationAnalyticsSummaryDTO?
    @State private var range: AnalyticsRangeOption = .all
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Range", selection: $range) {
                    ForEach(AnalyticsRangeOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                Text(range.managerRangeLabel())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                if let errorMessage {
                    AnalyticsNoticeCard(message: errorMessage, tint: .red)
                        .padding(.horizontal, 16)
                }

                if isLoading && summary != nil {
                    AnalyticsNoticeCard(message: "Updating analytics...", tint: .secondary, systemImage: "arrow.clockwise")
                        .padding(.horizontal, 16)
                }

                if isLoading && summary == nil {
                    ProgressView("Loading analytics...")
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    BusinessIntelligenceOverviewSection(
                        summary: businessIntelligenceSummary,
                        systemStatus: intelligenceSystemStatus,
                        isLoading: isBusinessIntelligenceLoading,
                        errorMessage: businessIntelligenceErrorMessage
                    )

                    if let summary {
                        BusinessAnalyticsLegacyContent(summary: summary)
                    } else {
                        ContentUnavailableView(
                            "No Analytics",
                            systemImage: "chart.bar",
                            description: Text("Refresh to load backend summary data.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 112)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Business Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load(force: true) }
                } label: {
                    if isLoading || settingsStore.analyticsLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
        }
        .task(id: range) {
            await load()
        }
    }

    private var intelligenceDateKeys: (from: String, to: String) {
        range.resolvedIntelligenceDateRange()
    }

    private var businessIntelligenceSummary: BusinessIntelligenceSummaryDTO? {
        let keys = intelligenceDateKeys
        return businessIntelligenceStore.response(from: keys.from, to: keys.to)
    }

    private var intelligenceSystemStatus: IntelligenceSystemStatusDTO? {
        let keys = intelligenceDateKeys
        return intelligenceSystemStatusStore.response(from: keys.from, to: keys.to)
    }

    private var isBusinessIntelligenceLoading: Bool {
        let keys = intelligenceDateKeys
        return businessIntelligenceStore.isLoading(from: keys.from, to: keys.to)
            || intelligenceSystemStatusStore.isLoading(from: keys.from, to: keys.to)
    }

    private var businessIntelligenceErrorMessage: String? {
        let keys = intelligenceDateKeys
        guard businessIntelligenceStore.error(from: keys.from, to: keys.to) != nil else {
            return nil
        }
        return "Business intelligence is unavailable right now."
    }

    private func load(force: Bool = false) async {
        guard !isLoading else { return }
        if summary == nil, let cached = settingsStore.analyticsSummary {
            summary = cached
        }
        isLoading = true
        errorMessage = nil

        let intelligenceRange = range.resolvedIntelligenceDateRange()
        Task {
            await businessIntelligenceStore.load(
                from: intelligenceRange.from,
                to: intelligenceRange.to,
                force: force
            )
            await intelligenceSystemStatusStore.load(
                from: intelligenceRange.from,
                to: intelligenceRange.to,
                force: force
            )
        }

        defer {
            isLoading = false
        }

        do {
            let dateRange = range.dateRange()
            summary = try await settingsStore.loadReservationAnalyticsSummary(
                from: dateRange.from,
                to: dateRange.to,
                force: force
            )
        } catch {
            if !error.isCancellationLike {
                errorMessage = error.localizedDescription
            }
        }
    }
}
