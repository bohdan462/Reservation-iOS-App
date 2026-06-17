//
//  BusinessAnalyticsView.swift
//  Tryzub Reservations
//

import SwiftUI

struct BusinessAnalyticsView: View {
    @ObservedObject var settingsStore: RestaurantSettingsStore
    @EnvironmentObject private var businessIntelligenceStore: BusinessIntelligenceStore
    @EnvironmentObject private var intelligenceSystemStatusStore: IntelligenceSystemStatusStore

    var body: some View {
        BusinessAnalyticsLoadedView(
            settingsStore: settingsStore,
            businessIntelligenceStore: businessIntelligenceStore,
            intelligenceSystemStatusStore: intelligenceSystemStatusStore
        )
    }
}

private struct BusinessAnalyticsLoadedView: View {
    @ObservedObject var settingsStore: RestaurantSettingsStore
    @StateObject private var coordinator: BusinessAnalyticsCoordinator
    @State private var showingForceAdvancedRefreshConfirmation = false

    init(
        settingsStore: RestaurantSettingsStore,
        businessIntelligenceStore: BusinessIntelligenceStore,
        intelligenceSystemStatusStore: IntelligenceSystemStatusStore
    ) {
        self.settingsStore = settingsStore
        _coordinator = StateObject(
            wrappedValue: BusinessAnalyticsCoordinator(
                settingsStore: settingsStore,
                businessIntelligenceStore: businessIntelligenceStore,
                intelligenceSystemStatusStore: intelligenceSystemStatusStore
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Range", selection: rangeBinding) {
                    ForEach(AnalyticsRangeOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                Text(coordinator.selectedRange.managerRangeLabel())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                if let reservationError = coordinator.reservationError {
                    AnalyticsNoticeCard(message: reservationError, tint: .red)
                        .padding(.horizontal, 16)
                }

                if coordinator.isReservationLoading, coordinator.reservationSummary != nil {
                    AnalyticsNoticeCard(
                        message: "Refreshing reservation analytics…",
                        tint: .secondary,
                        systemImage: "arrow.clockwise"
                    )
                    .padding(.horizontal, 16)
                }

                if coordinator.isEnrichmentLoading {
                    AnalyticsNoticeCard(
                        message: "Refreshing advanced insight in the background…",
                        tint: .secondary,
                        systemImage: "sparkles"
                    )
                    .padding(.horizontal, 16)
                }

                if let enrichmentWarning = coordinator.enrichmentWarning {
                    AnalyticsNoticeCard(message: enrichmentWarning, tint: .orange)
                        .padding(.horizontal, 16)
                } else if let cacheNote = coordinator.advancedInsightCacheNote {
                    Text(cacheNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                if coordinator.isReservationLoading, coordinator.reservationSummary == nil {
                    TryzubSectionLoadingCard(
                        title: "Loading reservation analytics…",
                        systemImage: "chart.bar"
                    )
                    .padding(.horizontal, 16)
                } else {
                    BusinessIntelligenceOverviewSection(
                        summary: coordinator.businessIntelligenceSummary,
                        systemStatus: coordinator.intelligenceSystemStatus,
                        isEnrichmentLoading: coordinator.isEnrichmentLoading,
                        reservationAnalyticsAvailable: coordinator.reservationSummary != nil
                    )

                    if let summary = coordinator.reservationSummary {
                        BusinessAnalyticsLegacyContent(summary: summary)
                    } else if !coordinator.isReservationLoading {
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
                Menu {
                    Button {
                        coordinator.refresh(force: true)
                    } label: {
                        Label("Refresh analytics", systemImage: "arrow.clockwise")
                    }

                    Button {
                        showingForceAdvancedRefreshConfirmation = true
                    } label: {
                        Label("Force advanced refresh", systemImage: "sparkles")
                    }
                } label: {
                    if coordinator.isReservationLoading || coordinator.isEnrichmentLoading || settingsStore.analyticsLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(coordinator.isReservationLoading)
            }
        }
        .confirmationDialog(
            "Fetch advanced insight again?",
            isPresented: $showingForceAdvancedRefreshConfirmation,
            titleVisibility: .visible
        ) {
            Button("Force Advanced Refresh") {
                coordinator.forceAdvancedRefresh()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This bypasses today's cached business insight and may take up to a minute.")
        }
        .onAppear {
            coordinator.isScreenVisible = true
        }
        .onDisappear {
            coordinator.isScreenVisible = false
        }
    }

    private var rangeBinding: Binding<AnalyticsRangeOption> {
        Binding(
            get: { coordinator.selectedRange },
            set: { coordinator.setSelectedRange($0) }
        )
    }
}
