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
        ZStack {
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

            if coordinator.shouldShowAdvancedLoadingOverlay {
                BusinessIntelligenceLoadingOverlay()
                    .padding(20)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.shouldShowAdvancedLoadingOverlay)
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

private struct BusinessIntelligenceLoadingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var isRotating = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(TryzubColors.info.opacity(isPulsing ? 0.18 : 0.08))
                    .frame(width: 112, height: 112)
                    .scaleEffect(isPulsing ? 1.08 : 0.94)

                Circle()
                    .stroke(TryzubColors.info.opacity(0.18), lineWidth: 8)
                    .frame(width: 94, height: 94)

                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(
                        TryzubColors.info,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 94, height: 94)
                    .rotationEffect(.degrees(isRotating ? 360 : 0))

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(TryzubColors.info)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Preparing intelligence")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Building today's business summary. This can take a moment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).opacity(0.86))
        .background(.ultraThinMaterial)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                isRotating = true
            }
        }
    }
}
