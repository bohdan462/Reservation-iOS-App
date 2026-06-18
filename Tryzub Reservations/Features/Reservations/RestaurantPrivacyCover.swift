//
//  RestaurantPrivacyCover.swift
//  Tryzub Reservations
//

import SwiftUI
import UIKit

// MARK: - Settings

@MainActor
final class RestaurantPrivacyCoverSettingsStore: ObservableObject {
    static let idleTimeoutOptions = [1, 2, 3, 5, 10, 15, 30]
    static let defaultIdleTimeoutMinutes = 5

    @Published private(set) var isEnabled: Bool
    @Published private(set) var idleTimeoutMinutes: Int

    private let enabledKey = "tryzub.privacyCover.enabled"
    private let idleMinutesKey = "tryzub.privacyCover.idleMinutes"

    var isFeatureAvailable: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var isActive: Bool {
        isFeatureAvailable && isEnabled
    }

    var idleInterval: TimeInterval {
        TimeInterval(idleTimeoutMinutes * 60)
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) != nil {
            isEnabled = defaults.bool(forKey: enabledKey)
        } else {
            isEnabled = true
        }

        if defaults.object(forKey: idleMinutesKey) == nil {
            idleTimeoutMinutes = Self.defaultIdleTimeoutMinutes
        } else {
            let storedMinutes = defaults.integer(forKey: idleMinutesKey)
            idleTimeoutMinutes = Self.idleTimeoutOptions.contains(storedMinutes)
                ? storedMinutes
                : Self.defaultIdleTimeoutMinutes
        }
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        persist()
    }

    func setIdleTimeoutMinutes(_ minutes: Int) {
        idleTimeoutMinutes = Self.idleTimeoutOptions.contains(minutes)
            ? minutes
            : Self.defaultIdleTimeoutMinutes
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        UserDefaults.standard.set(idleTimeoutMinutes, forKey: idleMinutesKey)
    }
}

struct RestaurantPrivacyCoverSettingsSection: View {
    @ObservedObject var settings: RestaurantPrivacyCoverSettingsStore

    var body: some View {
        if settings.isFeatureAvailable {
            Section {
                Toggle(
                    "Privacy screen",
                    isOn: Binding(
                        get: { settings.isEnabled },
                        set: { settings.setEnabled($0) }
                    )
                )

                if settings.isEnabled {
                    Picker(
                        "Turn on after",
                        selection: Binding(
                            get: { settings.idleTimeoutMinutes },
                            set: { settings.setIdleTimeoutMinutes($0) }
                        )
                    ) {
                        ForEach(RestaurantPrivacyCoverSettingsStore.idleTimeoutOptions, id: \.self) { minutes in
                            Text(Self.idleTimeoutLabel(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Privacy Screen")
            } footer: {
                if settings.isEnabled {
                    Text("Shows a glass privacy overlay after the screen is untouched for the selected time. Touch anywhere to return.")
                } else {
                    Text("Privacy screen is turned off.")
                }
            }
        }
    }

    private static func idleTimeoutLabel(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

// MARK: - Snapshot

struct RestaurantPrivacyCoverSnapshot: Equatable {
    let pastDueCount: Int
    let longSeatedCount: Int
    let newCount: Int
    let reviewCount: Int
    let noTableCount: Int
    let nextDueTimeText: String?
    let nextDueDetailText: String?
    /// Short service briefing text from host intelligence (replaces raw "No table" count).
    var serviceSummary: String?

    var hasAttentionItems: Bool {
        pastDueCount > 0
            || longSeatedCount > 0
            || newCount > 0
            || reviewCount > 0
            || noTableCount > 0
            || nextDueTimeText != nil
    }

    static let allClear = RestaurantPrivacyCoverSnapshot(
        pastDueCount: 0,
        longSeatedCount: 0,
        newCount: 0,
        reviewCount: 0,
        noTableCount: 0,
        nextDueTimeText: nil,
        nextDueDetailText: nil,
        serviceSummary: nil
    )
}

struct RestaurantPrivacyCoverWarning: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let value: String
    let subtitle: String?
}

// MARK: - Data Controller

enum RestaurantPrivacyCoverDataController {
    static let snapshotRefreshInterval: TimeInterval = 30

    static func conciseServiceSummary(from text: String) -> String {
        var output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        output = output.replacingOccurrences(of: "Guest notes to check.", with: "Guest notes:")
        output = output.replacingOccurrences(of: "Guest notes to check", with: "Guest notes")
        output = output.replacingOccurrences(of: "Check reservation.", with: "Check reservation")
        output = output.replacingOccurrences(of: "  ", with: " ")

        let sentences = output
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sentences.count > 2 {
            output = sentences.prefix(2).joined(separator: ". ") + "."
        }

        let maxLength = 96
        if output.count > maxLength {
            output = String(output.prefix(maxLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            output += "."
        }

        return output
    }

    static func snapshot(from reservations: [ReservationRecord], now: Date = Date()) -> RestaurantPrivacyCoverSnapshot {
        let todayKey = now.reservationDateString()
        let localSeatedTimestamps = TryzubSeatedDurationResolver.loadLocalSeatedTimestamps()

        var pastDueCount = 0
        var longSeatedCount = 0
        var newCount = 0
        var reviewCount = 0
        var noTableCount = 0
        var nextDueReservation: ReservationRecord?
        var nextDueDate: Date?

        for reservation in reservations where !reservation.isHidden && reservation.reservationDate == todayKey {
            switch reservation.statusValue {
            case .new:
                newCount += 1
                trackNextDue(reservation, now: now, nextDueDate: &nextDueDate, nextDueReservation: &nextDueReservation)
                if reservation.isPastDueForToday(now: now) {
                    pastDueCount += 1
                }
                if !reservation.hasTableAssignment {
                    noTableCount += 1
                }
            case .needsReview:
                reviewCount += 1
                trackNextDue(reservation, now: now, nextDueDate: &nextDueDate, nextDueReservation: &nextDueReservation)
                if reservation.isPastDueForToday(now: now) {
                    pastDueCount += 1
                }
                if !reservation.hasTableAssignment {
                    noTableCount += 1
                }
            case .confirmed:
                trackNextDue(reservation, now: now, nextDueDate: &nextDueDate, nextDueReservation: &nextDueReservation)
                if reservation.isPastDueForToday(now: now) {
                    pastDueCount += 1
                }
                if !reservation.hasTableAssignment {
                    noTableCount += 1
                }
            case .seated:
                if TryzubSeatedDurationResolver.hasLongSeatedWarning(
                    for: reservation,
                    now: now,
                    localTimestamps: localSeatedTimestamps
                ) {
                    longSeatedCount += 1
                }
            case .completed, .cancelled, .noShow:
                break
            }
        }

        let nextDueTimeText = nextDueReservation?.displayTime
        let nextDueDetailText = nextDueReservation.map { dueDetailText(for: $0, now: now) }

        return RestaurantPrivacyCoverSnapshot(
            pastDueCount: pastDueCount,
            longSeatedCount: longSeatedCount,
            newCount: newCount,
            reviewCount: reviewCount,
            noTableCount: noTableCount,
            nextDueTimeText: nextDueTimeText,
            nextDueDetailText: nextDueDetailText,
            serviceSummary: nil
        )
    }

    static func warnings(from snapshot: RestaurantPrivacyCoverSnapshot) -> [RestaurantPrivacyCoverWarning] {
        var rows: [RestaurantPrivacyCoverWarning] = []

        if snapshot.pastDueCount > 0 {
            rows.append(
                RestaurantPrivacyCoverWarning(
                    id: "past-due",
                    title: "Past due",
                    systemImage: "clock",
                    value: "\(snapshot.pastDueCount)",
                    subtitle: nil
                )
            )
        }
        if snapshot.longSeatedCount > 0 {
            rows.append(
                RestaurantPrivacyCoverWarning(
                    id: "seated-long",
                    title: "Seated long",
                    systemImage: "hourglass",
                    value: "\(snapshot.longSeatedCount)",
                    subtitle: nil
                )
            )
        }
        if let nextDueTimeText = snapshot.nextDueTimeText {
            rows.append(
                RestaurantPrivacyCoverWarning(
                    id: "next-due",
                    title: "Next due",
                    systemImage: "clock.badge.checkmark",
                    value: nextDueTimeText,
                    subtitle: snapshot.nextDueDetailText
                )
            )
        }
        // "No table" count removed — service summary replaces it (shown in PrivacyWarningsPanel).
        if snapshot.newCount > 0 {
            rows.append(
                RestaurantPrivacyCoverWarning(
                    id: "new",
                    title: "New",
                    systemImage: "tray",
                    value: "\(snapshot.newCount)",
                    subtitle: nil
                )
            )
        }
        if snapshot.reviewCount > 0 {
            rows.append(
                RestaurantPrivacyCoverWarning(
                    id: "review",
                    title: "Review",
                    systemImage: "tray.full",
                    value: "\(snapshot.reviewCount)",
                    subtitle: nil
                )
            )
        }

        return rows
    }

    private static func trackNextDue(
        _ reservation: ReservationRecord,
        now: Date,
        nextDueDate: inout Date?,
        nextDueReservation: inout ReservationRecord?
    ) {
        guard let serviceDate = reservation.serviceDateTime, serviceDate >= now else { return }
        guard nextDueDate == nil || serviceDate < nextDueDate! else { return }
        nextDueDate = serviceDate
        nextDueReservation = reservation
    }

    private static func dueDetailText(for reservation: ReservationRecord, now: Date) -> String {
        guard let serviceDate = reservation.serviceDateTime else {
            return "Time pending"
        }

        let minutes = max(0, Int(ceil(serviceDate.timeIntervalSince(now) / 60)))
        if minutes <= 15 {
            return "Due now"
        }
        return "In \(durationText(minutes: minutes))"
    }

    private static func durationText(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
    }
}

// MARK: - Controller

@MainActor
final class RestaurantPrivacyCoverController: ObservableObject {
    @Published private(set) var isCoverPresented = false
    @Published private(set) var cachedSnapshot = RestaurantPrivacyCoverSnapshot.allClear

    private var lastInteraction = Date()
    private var monitorTask: Task<Void, Never>?
    private var snapshotRefreshTask: Task<Void, Never>?

    func startMonitoringIfNeeded(settings: RestaurantPrivacyCoverSettingsStore) {
        guard settings.isActive else { return }
        guard monitorTask == nil else { return }

        lastInteraction = Date()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard settings.isActive else { continue }

                let idle = Date().timeIntervalSince(self.lastInteraction)
                if self.isCoverPresented {
                    continue
                }
                if idle >= settings.idleInterval {
                    self.isCoverPresented = true
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        stopSnapshotRefresh()
        isCoverPresented = false
    }

    func recordInteraction() {
        lastInteraction = Date()
        if isCoverPresented {
            withAnimation(.easeOut(duration: 0.28)) {
                isCoverPresented = false
            }
            stopSnapshotRefresh()
        }
    }

    func dismissCover() {
        recordInteraction()
    }

    func beginCoverSession(makeSnapshot: @escaping () -> RestaurantPrivacyCoverSnapshot) {
        refreshSnapshot(makeSnapshot)
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RestaurantPrivacyCoverDataController.snapshotRefreshInterval))
                guard !Task.isCancelled, isCoverPresented else { return }
                refreshSnapshot(makeSnapshot)
            }
        }
    }

    private func refreshSnapshot(_ makeSnapshot: () -> RestaurantPrivacyCoverSnapshot) {
        cachedSnapshot = makeSnapshot()
    }

    private func stopSnapshotRefresh() {
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        cachedSnapshot = .allClear
    }
}

@MainActor
enum RestaurantPrivacyCoverPolicy {
    static func setKeepsDisplayAwake(_ keepsAwake: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        UIApplication.shared.isIdleTimerDisabled = keepsAwake
    }
}

// MARK: - Modifier

private struct RestaurantPrivacyCoverModifier: ViewModifier {
    @EnvironmentObject private var privacyCoverSettings: RestaurantPrivacyCoverSettingsStore
    @StateObject private var controller = RestaurantPrivacyCoverController()
    let makeSnapshot: () -> RestaurantPrivacyCoverSnapshot

    func body(content: Content) -> some View {
        content
            .background {
                PrivacyCoverInteractionObserver(
                    isActive: privacyCoverSettings.isActive,
                    onInteraction: controller.recordInteraction
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
            .overlay {
                if privacyCoverSettings.isActive, controller.isCoverPresented {
                    RestaurantPrivacyCoverView(
                        snapshot: controller.cachedSnapshot,
                        onDismiss: controller.dismissCover
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(100)
                    .onAppear {
                        controller.beginCoverSession(makeSnapshot: makeSnapshot)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.32), value: controller.isCoverPresented)
            .onAppear {
                RestaurantPrivacyCoverPolicy.setKeepsDisplayAwake(true)
                restartMonitoring()
            }
            .onDisappear {
                controller.stopMonitoring()
                RestaurantPrivacyCoverPolicy.setKeepsDisplayAwake(false)
            }
            .onChange(of: privacyCoverSettings.isEnabled) { _, _ in
                restartMonitoring()
            }
            .onChange(of: privacyCoverSettings.idleTimeoutMinutes) { _, _ in
                restartMonitoring()
            }
    }

    private func restartMonitoring() {
        controller.stopMonitoring()
        if privacyCoverSettings.isActive {
            controller.startMonitoringIfNeeded(settings: privacyCoverSettings)
        }
    }
}

extension View {
    func restaurantPrivacyCover(snapshot: @escaping () -> RestaurantPrivacyCoverSnapshot) -> some View {
        modifier(RestaurantPrivacyCoverModifier(makeSnapshot: snapshot))
    }
}

// MARK: - Interaction Observer

private struct PrivacyCoverInteractionObserver: UIViewRepresentable {
    let isActive: Bool
    let onInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.monitor.isActive = isActive
        context.coordinator.monitor.onInteraction = onInteraction
        if let hostWindow = uiView.window ?? Self.keyWindow() {
            context.coordinator.monitor.install(on: hostWindow)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.monitor.remove()
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    @MainActor
    final class Coordinator {
        let monitor = PrivacyCoverWindowTouchMonitor()
    }
}

@MainActor
private final class PrivacyCoverGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    var isActive = false

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isActive, let hostWindow = gestureRecognizer.view as? UIWindow else { return false }

        if hostWindow.rootViewController?.presentedViewController != nil {
            return false
        }

        let location = gestureRecognizer.location(in: hostWindow)
        guard let hitView = hostWindow.hitTest(location, with: nil) else { return true }
        return !PrivacyCoverWindowTouchMonitor.isWithinNavigationChrome(hitView)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

@MainActor
private final class PrivacyCoverWindowTouchMonitor: NSObject {
    var isActive = false {
        didSet { gestureDelegate.isActive = isActive }
    }

    var onInteraction: (() -> Void)?

    private let gestureDelegate = PrivacyCoverGestureDelegate()
    private weak var attachedWindow: UIWindow?
    private var recognizers: [UIGestureRecognizer] = []

    func install(on hostWindow: UIWindow) {
        guard attachedWindow !== hostWindow else { return }

        remove()
        attachedWindow = hostWindow
        gestureDelegate.isActive = isActive

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleInteraction(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delegate = gestureDelegate
        hostWindow.addGestureRecognizer(tap)
        recognizers.append(tap)

        // Scrolling and drags count as activity — taps alone caused the saver to appear
        // while staff were still using lists and charts.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleInteraction(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delegate = gestureDelegate
        hostWindow.addGestureRecognizer(pan)
        recognizers.append(pan)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleInteraction(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delegate = gestureDelegate
        hostWindow.addGestureRecognizer(press)
        recognizers.append(press)
    }

    func remove() {
        if let attachedWindow {
            for recognizer in recognizers {
                attachedWindow.removeGestureRecognizer(recognizer)
            }
        }
        recognizers = []
        attachedWindow = nil
    }

    @objc private func handleInteraction(_ gesture: UIGestureRecognizer) {
        guard isActive else { return }
        switch gesture.state {
        case .began, .changed, .ended:
            onInteraction?()
        default:
            break
        }
    }

    fileprivate static func isWithinNavigationChrome(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate is UINavigationBar {
                return true
            }
            if candidate is UIControl, candidate.findNavigationBarAncestor() != nil {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}

private extension UIView {
    func findNavigationBarAncestor() -> UINavigationBar? {
        var current: UIView? = superview
        while let candidate = current {
            if let navigationBar = candidate as? UINavigationBar {
                return navigationBar
            }
            current = candidate.superview
        }
        return nil
    }
}

// MARK: - Cover View

private struct RestaurantPrivacyCoverView: View {
    let snapshot: RestaurantPrivacyCoverSnapshot
    let onDismiss: () -> Void

    private var warnings: [RestaurantPrivacyCoverWarning] {
        RestaurantPrivacyCoverDataController.warnings(from: snapshot)
    }

    var body: some View {
        ZStack {
            PrivacyCoverAuroraBackground()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PrivacyGlassBackdrop()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            GeometryReader { proxy in
                let panelWidth = min(max(proxy.size.width - 64, 260), 460)

                VStack(spacing: 18) {
                    PrivacyClockLabel()

                    PrivacyWarningsPanel(
                        warnings: warnings,
                        isAllClear: !snapshot.hasAttentionItems,
                        serviceSummary: snapshot.serviceSummary
                    )
                    .frame(width: panelWidth)

                    Text("Touch anywhere to continue")
                        .font(.caption)
                        .foregroundStyle(PrivacyCoverPalette.hint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(privacyAccessibilityLabel)
    }

    private var privacyAccessibilityLabel: String {
        if warnings.isEmpty {
            return "Privacy screen. All clear. Touch to return to reservations."
        }
        let summary = warnings.map { "\($0.value) \($0.title.lowercased())" }.joined(separator: ", ")
        return "Privacy screen. \(summary). Touch to return to reservations."
    }
}

// MARK: - Palette

private enum PrivacyCoverPalette {
    static let ink = Color.primary.opacity(0.42)
    static let inkEmphasis = Color.primary.opacity(0.52)
    static let inkMuted = Color.primary.opacity(0.32)
    static let hint = Color.primary.opacity(0.26)
}

// MARK: - Glass Backdrop

private struct PrivacyGlassBackdrop: View {
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.clear, in: .rect)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial.opacity(0.28))
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Cover Pieces

private struct PrivacyClockLabel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            let colonVisible = Calendar.current.component(.second, from: date) % 2 == 0

            HStack(alignment: .center, spacing: 8) {
                Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                Text(":")
                    .offset(y: -3)
                    .opacity(colonVisible ? 1 : 0.2)
                    .animation(.easeInOut(duration: 0.5), value: colonVisible)
                Text(date, format: .dateTime.minute(.twoDigits))
            }
            .font(.system(size: 44, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(PrivacyCoverPalette.inkEmphasis)
            .privacyGlassPanel()
        }
    }
}

private struct PrivacyWarningsPanel: View {
    let warnings: [RestaurantPrivacyCoverWarning]
    let isAllClear: Bool
    var serviceSummary: String?

    var body: some View {
        let fittedSummary = serviceSummary.map(RestaurantPrivacyCoverDataController.conciseServiceSummary(from:))

        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.caption2.weight(.medium))
                .foregroundStyle(PrivacyCoverPalette.hint)
                .textCase(.uppercase)
                .tracking(0.5)

            if isAllClear {
                Text("All clear")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PrivacyCoverPalette.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 7) {
                    ForEach(warnings) { warning in
                        PrivacyWarningRow(warning: warning)
                    }

                    if let summary = fittedSummary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(PrivacyCoverPalette.ink)
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .privacyGlassPanel(cornerRadius: 16)
        .task(id: privacyTraceKey(summary: fittedSummary)) {
            tracePrivacyFit(summary: fittedSummary)
        }
    }

    private func privacyTraceKey(summary: String?) -> String {
        "\(warnings.count)|\(summary ?? "")|\(isAllClear)"
    }

    private func tracePrivacyFit(summary: String?) {
        #if DEBUG
        let length = summary?.count ?? 0
        let lines = max(1, Int(ceil(Double(max(length, 1)) / 34.0)))
        let strategy: String = {
            guard let summary else { return "normal" }
            if summary.count < (serviceSummary?.count ?? 0) { return "shortened" }
            return lines > 1 ? "wrapped" : "normal"
        }()
        WorkflowCleanupTrace.log(
            "PRIVACY_SCREEN_TRACE",
            fields: [
                "contentLength": "\(length)",
                "lines": "\(min(lines, 3))",
                "fitted": "true",
                "strategy": strategy
            ]
        )
        #endif
    }
}

private struct PrivacyWarningRow: View {
    let warning: RestaurantPrivacyCoverWarning

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: warning.systemImage)
                .font(.caption.weight(.regular))
                .foregroundStyle(PrivacyCoverPalette.inkMuted)
                .frame(width: 14)

            Text(warning.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(PrivacyCoverPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(warning.value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PrivacyCoverPalette.inkEmphasis)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let subtitle = warning.subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(PrivacyCoverPalette.inkMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

private extension View {
    func privacyGlassPanel(cornerRadius: CGFloat = 18) -> some View {
        padding(12)
            .background {
                Group {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.38))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

#if DEBUG
#Preview("Restaurant Privacy Cover") {
    RestaurantPrivacyCoverView(
        snapshot: RestaurantPrivacyCoverSnapshot(
            pastDueCount: 3,
            longSeatedCount: 5,
            newCount: 0,
            reviewCount: 0,
            noTableCount: 3,
            nextDueTimeText: "21:30",
            nextDueDetailText: "In 46m"
        ),
        onDismiss: {}
    )
}
#endif
