//
//  ServiceTimelineView.swift
//  Tryzub Reservations
//
//  Full-screen Service Timeline. Scrollable horizontal tape chart of reservations
//  for the selected service day. Deterministic — no LLM, no network.
//
//  Modes:
//    Static — free horizontal + vertical scroll.
//    Live   — programmatically scrolls so the "now" line sits at ~30 % from left.
//

import SwiftUI

// MARK: - Main View

struct ServiceTimelineView: View {
    let reservations: [ReservationRecord]
    let selectedDate: Date
    let serviceOpen: Date?
    let serviceClose: Date?
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss

    // Navigation
    @State private var navigationPath: [Int] = []

    // Timeline state
    @State private var filter = ServiceTimelineFilter()
    @State private var liveFollowActive = false
    @State private var clockNow = Date()
    @State private var showFilters = false

    // Triggers the ScrollViewProxy to scroll to the nowAnchor
    @State private var liveScrollTick: UUID = UUID()

    private let liveTimerInterval: TimeInterval = 30

    // MARK: - Derived data (computed once per render pass, cheap)

    private var window: ServiceTimelineWindow {
        if let open = serviceOpen, let close = serviceClose, close > open {
            return ServiceTimelineWindow(open: open, close: close)
        }
        return ServiceTimelineLayoutEngine.defaultServiceWindow(for: selectedDate)
    }

    private var filteredReservations: [ReservationRecord] {
        filter.apply(to: reservations)
    }

    private var blocks: [ServiceTimelineBlock] {
        ServiceTimelineLayoutEngine.computeBlocks(from: filteredReservations, window: window)
    }

    private var totalWidth: CGFloat {
        ServiceTimelineLayoutEngine.totalContentWidth(window: window)
    }

    private var totalContentHeight: CGFloat {
        ServiceTimelineLayoutEngine.totalContentHeight(laneCount: blocks.count)
    }

    private var nowX: CGFloat {
        ServiceTimelineLayoutEngine.nowXOffset(window: window, now: clockNow)
    }

    private var ticks: [ServiceTimelineLayoutEngine.TimeTick] {
        ServiceTimelineLayoutEngine.timeTicks(window: window)
    }

    private var nowIsVisible: Bool {
        let x = nowX
        return x >= ServiceTimelineLayoutEngine.timelineHorizontalPadding
            && x <= totalWidth - ServiceTimelineLayoutEngine.timelineHorizontalPadding
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { proxy in
                ScrollViewReader { scrollProxy in
                    scrollableContent(containerWidth: proxy.size.width)
                        // Live mode: scroll on state trigger
                        .onChange(of: liveScrollTick) { _ in
                            guard liveFollowActive else { return }
                            withAnimation(.easeInOut(duration: 0.45)) {
                                scrollProxy.scrollTo("nowAnchor", anchor: UnitPoint(x: 0.30, y: 0.0))
                            }
                            #if DEBUG
                            print("""
                                [SERVICE_TIMELINE_LIVE_TRACE] \
                                event=tick \
                                now=\(clockNow.formatted(.dateTime.hour().minute())) \
                                nowX=\(Int(nowX)) \
                                liveFollow=true
                                """)
                            #endif
                        }
                        // Activate follow when entering live mode
                        .onChange(of: liveFollowActive) { active in
                            if active {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    scrollProxy.scrollTo("nowAnchor", anchor: UnitPoint(x: 0.30, y: 0.0))
                                }
                                #if DEBUG
                                print("[SERVICE_TIMELINE_LIVE_TRACE] event=followStart nowX=\(Int(nowX))")
                                #endif
                            } else {
                                #if DEBUG
                                print("[SERVICE_TIMELINE_LIVE_TRACE] event=followStop nowX=\(Int(nowX))")
                                #endif
                            }
                        }
                }
            }
            .background(TryzubColors.screenBackground)
            .navigationTitle("Service Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showFilters) { filterSheet }
            .navigationDestination(for: Int.self) { remoteID in
                reservationDestination(remoteID: remoteID)
            }
        }
        .onAppear {
            logOpened()
        }
        // Live timer — 30-second tick
        .onReceive(
            Timer.publish(every: liveTimerInterval, on: .main, in: .common).autoconnect()
        ) { now in
            clockNow = now
            if liveFollowActive {
                liveScrollTick = UUID()
            }
        }
    }

    // MARK: - Scrollable content

    @ViewBuilder
    private func scrollableContent(containerWidth: CGFloat) -> some View {
        if reservations.isEmpty {
            emptyState
        } else if !window.isValid {
            unavailableState
        } else if blocks.isEmpty {
            emptyFilteredState
        } else {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                timelineCanvas
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Timeline canvas (ZStack-based absolute positioning)

    private var timelineCanvas: some View {
        ZStack(alignment: .topLeading) {
            // Explicit frame anchors scroll content size
            Color.clear
                .frame(width: totalWidth, height: totalContentHeight)

            // Time header strip
            ServiceTimelineHeaderView(ticks: ticks, totalWidth: totalWidth)

            // Lane backgrounds
            ForEach(blocks.indices, id: \.self) { index in
                laneSeparator(for: index)
            }

            // Reservation blocks
            ForEach(blocks) { block in
                reservationBlock(block: block)
            }

            // Current-time line (only when within service window)
            if nowIsVisible {
                nowLineOverlay
            }

            // Invisible anchor for live-mode scroll targeting
            Color.clear
                .frame(width: 1, height: 1)
                .offset(x: nowX, y: 0)
                .id("nowAnchor")
        }
        .frame(width: totalWidth, height: totalContentHeight, alignment: .topLeading)
    }

    // MARK: - Lane background row

    private func laneSeparator(for index: Int) -> some View {
        let y = ServiceTimelineLayoutEngine.headerHeight
            + CGFloat(index) * (ServiceTimelineLayoutEngine.laneHeight + ServiceTimelineLayoutEngine.laneSpacing)
        let isEven = index % 2 == 0

        return Color(isEven
            ? UIColor.tertiarySystemGroupedBackground
            : UIColor.secondarySystemGroupedBackground)
            .frame(width: totalWidth, height: ServiceTimelineLayoutEngine.laneHeight)
            .offset(y: y)
    }

    // MARK: - Reservation block placement

    private func reservationBlock(block: ServiceTimelineBlock) -> some View {
        let blockHeight = ServiceTimelineLayoutEngine.laneHeight - ServiceTimelineLayoutEngine.blockVerticalInset * 2
        let laneY = ServiceTimelineLayoutEngine.headerHeight
            + CGFloat(block.laneIndex) * (ServiceTimelineLayoutEngine.laneHeight + ServiceTimelineLayoutEngine.laneSpacing)
        let blockY = laneY + ServiceTimelineLayoutEngine.blockVerticalInset

        return ServiceTimelineReservationBlock(
            block: block,
            blockHeight: blockHeight,
            onTap: {
                ReservationHaptics.selection()
                navigationPath.append(block.id)
            }
        )
        .offset(x: block.xOffset, y: blockY)
    }

    // MARK: - Now line

    private var nowLineOverlay: some View {
        ZStack(alignment: .top) {
            // Thin vertical line spanning full height
            Rectangle()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 1.5, height: totalContentHeight)

            // "Now" time label pill at top
            Text(ReservationFormatters.shortTime.string(from: clockNow))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor, in: Capsule())
                .offset(y: 6)
        }
        .frame(width: 1.5, height: totalContentHeight, alignment: .top)
        // Shift so the 1.5 pt line sits exactly at nowX
        .offset(x: nowX - 0.75, y: 0)
        .allowsHitTesting(false)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                dismiss()
            }
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 8) {
                filterToggleButton
                livePill
            }
        }
    }

    private var filterToggleButton: some View {
        let hasActiveFilters = filter.showOnlyNoTable
            || !filter.hideCompleted
            || !filter.hideCancelled

        return Button {
            showFilters = true
        } label: {
            Label("Filters", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.medium))
                .symbolRenderingMode(hasActiveFilters ? .hierarchical : .monochrome)
        }
        .accessibilityLabel(hasActiveFilters ? "Filters (active)" : "Filters")
    }

    private var livePill: some View {
        Button {
            liveFollowActive.toggle()
            if liveFollowActive {
                liveScrollTick = UUID()
            }
        } label: {
            HStack(spacing: 4) {
                if liveFollowActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
                Text(liveFollowActive ? "Live" : "Live")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(liveFollowActive ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                liveFollowActive
                    ? Color.accentColor.opacity(0.12)
                    : Color(.tertiarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    liveFollowActive ? Color.accentColor.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(liveFollowActive ? "Live mode on" : "Live mode off")
    }

    // MARK: - Filter sheet

    private var filterSheet: some View {
        NavigationStack {
            List {
                Section("Show / Hide") {
                    Toggle("Hide Completed", isOn: $filter.hideCompleted)
                    Toggle("Hide Cancelled & No-Shows", isOn: $filter.hideCancelled)
                }
                Section("Focus") {
                    Toggle("No-Table Only", isOn: $filter.showOnlyNoTable)
                }

                Section {
                    Button("Reset to Defaults") {
                        filter = ServiceTimelineFilter()
                    }
                    .foregroundStyle(TryzubColors.destructiveText)
                }
            }
            .navigationTitle("Timeline Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilters = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Navigation destination

    @ViewBuilder
    private func reservationDestination(remoteID: Int) -> some View {
        if let reservation = reservations.first(where: { $0.remoteID == remoteID }) {
            ReservationDetailView(reservation: reservation, environment: environment)
        } else {
            ContentUnavailableView(
                "Reservation Not Found",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Refresh the Host view and try again.")
            )
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        ContentUnavailableView(
            "No Reservations",
            systemImage: "calendar.badge.minus",
            description: Text("No reservations on \(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).")
        )
    }

    private var emptyFilteredState: some View {
        ContentUnavailableView(
            "No Matching Reservations",
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("Adjust the timeline filters to see more reservations.")
        )
    }

    private var unavailableState: some View {
        ContentUnavailableView(
            "Service Hours Unknown",
            systemImage: "clock.badge.questionmark",
            description: Text("Could not determine the service window for this date.")
        )
    }

    // MARK: - Trace

    private func logOpened() {
        #if DEBUG
        print("""
            [SERVICE_TIMELINE_TRACE] \
            event=opened \
            date=\(selectedDate.reservationDateString()) \
            reservations=\(reservations.count) \
            serviceStart=\(window.open.formatted(.dateTime.hour().minute())) \
            serviceEnd=\(window.close.formatted(.dateTime.hour().minute())) \
            mode=static
            """)
        #endif
    }
}
