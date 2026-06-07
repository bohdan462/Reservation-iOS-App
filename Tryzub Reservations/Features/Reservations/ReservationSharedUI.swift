//
//  ReservationSharedUI.swift
//  Tryzub Reservations
//

import SwiftUI
import Charts

// MARK: - Layout Safety

extension CGFloat {
    var tryzubFiniteLayoutValue: CGFloat {
        isFinite ? self : 0
    }

    var tryzubFiniteNonNegativeLayoutValue: CGFloat {
        Swift.max(tryzubFiniteLayoutValue, 0)
    }

    static func tryzubSafeRatio(numerator: CGFloat, denominator: CGFloat) -> CGFloat {
        guard numerator.isFinite,
              denominator.isFinite,
              denominator > 0 else {
            return 0
        }

        let value = numerator / denominator
        guard value.isFinite else { return 0 }
        return Swift.min(Swift.max(value, 0), 1)
    }
}

// MARK: - Tryzub Design System

enum TryzubColors {
    static let screenBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let secondaryCardBackground = Color(.systemBackground)
    static let border = Color.primary.opacity(0.08)
    static let mutedText = Color.secondary
    static let primaryText = Color.primary.opacity(0.86)
    static let attentionBackground = Color(.systemRed).opacity(0.10)
    static let attentionBorder = Color(.systemRed).opacity(0.30)
    static let dueSoonBackground = Color(.tertiarySystemGroupedBackground)
    static let successBackground = Color(.systemGreen).opacity(0.10)
    static let primaryControl = Color.accentColor
    static let destructiveText = Color(.systemRed)

    // Semantic accents used by status/warning chips so labels read consistently.
    static let warning = Color(.systemOrange)
    static let danger = Color(.systemRed)
    static let success = Color(.systemGreen)
    static let info = Color(.systemBlue)
    static let neutralChip = Color.secondary
}

// MARK: - Staff Status Dot

/// Small live-status indicator for staff surfaces (Home header, Bookings tab, etc.).
/// Views pass a style only; sync/network logic lives in the controller layer.
enum TryzubStaffStatusDotStyle: Equatable {
    /// Live and healthy — cache is fresh, network is up, nothing in flight.
    case greenStatic
    /// Activity — fetch/sync in progress or attention-worthy live event (e.g. new booking).
    case greenFlashing
    /// Warning — usable but degraded (e.g. sync older than threshold, partial failure).
    case yellowStatic
    /// Offline or hard failure — no reliable network path.
    case redFlashing

    var color: Color {
        switch self {
        case .greenStatic, .greenFlashing:
            return TryzubColors.success
        case .yellowStatic:
            return TryzubColors.warning
        case .redFlashing:
            return TryzubColors.danger
        }
    }

    var isFlashing: Bool {
        switch self {
        case .greenFlashing, .redFlashing:
            return true
        case .greenStatic, .yellowStatic:
            return false
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .greenStatic:
            return "Live"
        case .greenFlashing:
            return "Updating"
        case .yellowStatic:
            return "Warning"
        case .redFlashing:
            return "Offline"
        }
    }
}

struct TryzubStaffStatusDot: View {
    var style: TryzubStaffStatusDotStyle
    var diameter: CGFloat = 6

    private let flashPeriod: TimeInterval = 0.9

    var body: some View {
        Group {
            if style.isFlashing {
                TimelineView(.animation(minimumInterval: flashPeriod / 2)) { context in
                    let opacity = flashingOpacity(at: context.date)
                    Circle()
                        .fill(style.color)
                        .frame(width: diameter, height: diameter)
                        .opacity(opacity)
                        .animation(.easeInOut(duration: flashPeriod / 2), value: opacity)
                }
            } else {
                Circle()
                    .fill(style.color)
                    .frame(width: diameter, height: diameter)
            }
        }
        .accessibilityLabel(style.accessibilityLabel)
    }

    private func flashingOpacity(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: flashPeriod)
        return phase < flashPeriod / 2 ? 1.0 : 0.24
    }
}

/// Status dot with an optional offline glyph for staff headers.
struct TryzubStaffStatusIndicator: View {
    var style: TryzubStaffStatusDotStyle
    var showsOfflineIcon = false
    var dotDiameter: CGFloat = 6

    var body: some View {
        HStack(spacing: 4) {
            if showsOfflineIcon {
                Image(systemName: "wifi.slash")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TryzubColors.danger)
                    .accessibilityLabel("No internet connection")
            }

            TryzubStaffStatusDot(style: style, diameter: dotDiameter)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Segmented control that supports a small attention dot on individual segments.
/// SwiftUI's segmented `Picker` strips custom segment views, so Bookings uses this instead.
struct TryzubSegmentedControl<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        var attentionDotStyle: TryzubStaffStatusDotStyle?

        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                segmentButton(segment, isSelected: selection == segment.value)
            }
        }
        .padding(2)
        .background(Color(.systemGray5), in: Capsule())
    }

    private func segmentButton(_ segment: Segment, isSelected: Bool) -> some View {
        Button {
            guard selection != segment.value else { return }
            ReservationHaptics.selection()
            selection = segment.value
        } label: {
            HStack(spacing: 4) {
                Text(segment.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let attentionDotStyle = segment.attentionDotStyle {
                    TryzubStaffStatusDot(style: attentionDotStyle, diameter: 5)
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Pure resolver for the staff status dot. Controllers map live state into a style.
enum TryzubStaffStatusResolver {
    static let staleSyncThreshold: TimeInterval = 120

    static func resolve(
        isNetworkDegraded: Bool,
        isNetworkActivityInFlight: Bool,
        lastSyncedAt: Date?,
        pendingReviewCount: Int,
        now: Date = Date()
    ) -> TryzubStaffStatusDotStyle {
        if isNetworkDegraded {
            return .redFlashing
        }
        if isNetworkActivityInFlight || pendingReviewCount > 0 {
            return .greenFlashing
        }
        guard let lastSyncedAt else {
            return .yellowStatic
        }
        if now.timeIntervalSince(lastSyncedAt) > staleSyncThreshold {
            return .yellowStatic
        }
        return .greenStatic
    }
}

/// Seated-duration thresholds for reservation row attention dots.
enum TryzubSeatedDurationResolver {
    static let greenFlashingMinutes = 80
    static let yellowStaticMinutes = 100
    static let redFlashingMinutes = 120
    static let localSeatedTimestampsKey = "tryzub.localSeatedTimestamps"

    static func dotStyle(elapsedMinutes: Int) -> TryzubStaffStatusDotStyle? {
        if elapsedMinutes >= redFlashingMinutes {
            return .redFlashing
        }
        if elapsedMinutes >= yellowStaticMinutes {
            return .yellowStatic
        }
        if elapsedMinutes >= greenFlashingMinutes {
            return .greenFlashing
        }
        return nil
    }

    static func loadLocalSeatedTimestamps() -> [Int: Date] {
        guard let raw = UserDefaults.standard.dictionary(forKey: localSeatedTimestampsKey) as? [String: TimeInterval] else {
            return [:]
        }
        return raw.reduce(into: [Int: Date]()) { result, pair in
            guard let id = Int(pair.key), pair.value.isFinite else { return }
            result[id] = Date(timeIntervalSince1970: pair.value)
        }
    }

    static func seatedAt(
        for reservation: ReservationRecord,
        localTimestamps: [Int: Date] = loadLocalSeatedTimestamps()
    ) -> Date? {
        guard reservation.statusValue == .seated else { return nil }

        if let seatedAt = localTimestamps[reservation.remoteID] {
            return seatedAt
        }

        guard let value = reservation.apiUpdatedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return ReservationFormatters.serverDateTime.date(from: value)
            ?? ReservationFormatters.serverDateMinute.date(from: value)
    }

    static func elapsedSeatedMinutes(
        for reservation: ReservationRecord,
        now: Date = Date(),
        localTimestamps: [Int: Date] = loadLocalSeatedTimestamps()
    ) -> Int? {
        guard let seatedAt = seatedAt(for: reservation, localTimestamps: localTimestamps) else {
            return nil
        }
        return max(0, Int(now.timeIntervalSince(seatedAt))) / 60
    }

    static func hasLongSeatedWarning(
        for reservation: ReservationRecord,
        now: Date = Date(),
        localTimestamps: [Int: Date] = loadLocalSeatedTimestamps()
    ) -> Bool {
        guard let minutes = elapsedSeatedMinutes(for: reservation, now: now, localTimestamps: localTimestamps) else {
            return false
        }
        return dotStyle(elapsedMinutes: minutes) != nil
    }
}

#Preview("Staff Status Dot") {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
            TryzubStaffStatusDot(style: .greenStatic)
            Text("Green static — live")
        }
        HStack(spacing: 10) {
            TryzubStaffStatusDot(style: .greenFlashing)
            Text("Green flashing — fetching / new activity")
        }
        HStack(spacing: 10) {
            TryzubStaffStatusDot(style: .yellowStatic)
            Text("Yellow static — warning / stale sync")
        }
        HStack(spacing: 10) {
            TryzubStaffStatusDot(style: .redFlashing)
            Text("Red flashing — offline")
        }
    }
    .font(.caption)
    .padding()
}

// Single source of truth for native tab-safe bottom spacing.
enum ReservationLayout {
    /// Extra clearance used by pushed bottom action bars; native TabView owns the tab safe area.
    static let floatingTabBarClearance: CGFloat = 16
    /// Small bottom inset for scroll content on top-level tab screens.
    static let scrollBottomInset: CGFloat = 16
}

/// Consistent spacing for time/table slot chip grids across the app.
enum ReservationSlotGridStyle {
    static let columnSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 10
    static let minChipWidth: CGFloat = 68

    static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minChipWidth), spacing: columnSpacing)]
    }

    static var fourColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 4)
    }
}

// MARK: - Form Confirmation Helpers

struct ReservationFormChange: Identifiable {
    let field: String
    let oldValue: String
    let newValue: String
    var id: String { field }
}

struct ReservationFormChangeReview: View {
    var changes: [ReservationFormChange] = []
    var createSummary: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if createSummary.isEmpty && changes.isEmpty {
                Text("No changes to review.")
                    .font(.subheadline)
                    .foregroundStyle(TryzubColors.mutedText)
            }

            if !createSummary.isEmpty {
                ForEach(createSummary, id: \.0) { item in
                    summaryRow(label: item.0, value: item.1)
                }
            }

            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.field)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                    HStack(spacing: 6) {
                        Text(change.oldValue)
                            .foregroundStyle(TryzubColors.mutedText)
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TryzubColors.mutedText)
                        Text(change.newValue)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(TryzubColors.mutedText)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TryzubColors.primaryText)
        }
    }
}

struct ReservationFormConfirmationSheet<Content: View>: View {
    let title: String
    var subtitle: String?
    let confirmTitle: String
    var cancelTitle = "Back to Form"
    let isProcessing: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        content()
                    }
                    .padding(TryzubSpacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                }
                .padding(TryzubSpacing.screenPadding)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle) {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onConfirm()
                } label: {
                    Group {
                        if isProcessing {
                            ProgressView()
                                .tint(Color(.systemBackground))
                        } else {
                            Text(confirmTitle)
                                .font(TryzubTypography.button)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(.systemBackground))
                .background(TryzubColors.primaryControl, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .padding(.horizontal, TryzubSpacing.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(.bar)
                .disabled(isProcessing)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

enum TryzubTypography {
    static let screenTitle = Font.title2.weight(.semibold)
    static let sectionTitle = Font.headline.weight(.semibold)
    static let rowTitle = Font.subheadline.weight(.semibold)
    static let rowSubtitle = Font.caption.weight(.medium)
    static let caption = Font.caption
    static let badge = Font.caption.weight(.semibold)
    static let button = Font.subheadline.weight(.semibold)
}

enum TryzubSpacing {
    static let screenPadding: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 14
    static let chipSpacing: CGFloat = 4
    static let cornerRadius: CGFloat = 8
    static let controlCornerRadius: CGFloat = 8
}

enum ReservationUIStyle {
    static let cardCorner = TryzubSpacing.cornerRadius
    static let controlCorner = TryzubSpacing.controlCornerRadius
    static let selectedControlColor = TryzubColors.primaryControl
    static let serviceTitleColor = Color.primary
    static let cancelColor = TryzubColors.destructiveText
}

// MARK: - Shared Components

struct TryzubSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var spacing = TryzubSpacing.rowSpacing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Label(title, systemImage: systemImage)
                .font(TryzubTypography.sectionTitle)
                .foregroundStyle(TryzubColors.primaryText)

            content
        }
        .padding(TryzubSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: TryzubSpacing.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TryzubSpacing.cornerRadius, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }
}

struct TryzubInfoChip: View {
    let title: String
    var value: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TryzubColors.mutedText)
                .frame(width: 15, height: 15)

            Text(title)
                .font(TryzubTypography.badge)
                .foregroundStyle(TryzubColors.mutedText)
                .lineLimit(1)

            if let value {
                Text(value)
                    .font(TryzubTypography.badge)
                    .foregroundStyle(TryzubColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(TryzubColors.secondaryCardBackground, in: RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }
}

struct TryzubStatusBadge: View {
    let title: String
    var tint: Color = TryzubColors.mutedText
    var minHeight: CGFloat?
    var horizontalPadding: CGFloat?

    var body: some View {
        Text(title)
            .font(TryzubTypography.badge)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, horizontalPadding ?? 8)
            .frame(minHeight: minHeight ?? 26)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.12), lineWidth: 1)
            }
    }
}

struct TryzubPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TryzubTypography.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(TryzubColors.primaryControl, in: RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct TryzubSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TryzubTypography.button)
            .foregroundStyle(TryzubColors.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(TryzubColors.secondaryCardBackground, in: RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct TryzubDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TryzubTypography.button)
            .foregroundStyle(TryzubColors.destructiveText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(TryzubColors.secondaryCardBackground, in: RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous)
                    .stroke(TryzubColors.destructiveText.opacity(0.18), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct TryzubLoadingRow: View {
    let title: String

    var body: some View {
        HStack {
            Spacer()
            ProgressView(title)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 72)
    }
}

struct TryzubEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct TryzubErrorState: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(TryzubTypography.rowTitle)
                .foregroundStyle(.red)

            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(TryzubTypography.badge)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReservationDashedLine: View {
    var isVertical = false

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width.tryzubFiniteNonNegativeLayoutValue
                let height = proxy.size.height.tryzubFiniteNonNegativeLayoutValue
                if isVertical {
                    path.move(to: CGPoint(x: width / 2, y: 0))
                    path.addLine(to: CGPoint(x: width / 2, y: height))
                } else {
                    path.move(to: CGPoint(x: 0, y: height / 2))
                    path.addLine(to: CGPoint(x: width, y: height / 2))
                }
            }
            .stroke(
                Color.primary.opacity(0.14),
                style: StrokeStyle(lineWidth: 1, dash: [4, 5], dashPhase: 0)
            )
        }
    }
}

struct ReservationServiceCard<Content: View>: View {
    let title: String
    let systemImage: String
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct ReservationChoiceChip: View {
    let title: String
    var subtitle: String?
    var isSelected: Bool
    var minWidth: CGFloat = 78
    var minHeight: CGFloat = 40
    var fillsWidth = true
    var selectedColor: Color = ReservationUIStyle.selectedControlColor

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.82) : .secondary)
            }
        }
        .foregroundStyle(isSelected ? Color.white : .primary)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight)
        .frame(minWidth: minWidth)
        .padding(.horizontal, 12)
        .background(isSelected ? selectedColor : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(Color.primary.opacity(isSelected ? 0 : 0.10), lineWidth: 1)
        }
    }
}

struct ReservationInfoChip: View {
    let title: String
    var value: String?
    let systemImage: String

    var body: some View {
        TryzubInfoChip(title: title, value: value, systemImage: systemImage)
    }
}

struct ReservationSecondaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }
}

struct ReservationServiceDateSelector: View {
    @Binding var selectedDate: Date
    var quickDayCount = 7

    private var quickDates: [Date] {
        (0..<quickDayCount).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Date())
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            dateStrip
                .frame(maxWidth: .infinity)
            ReservationOpenCalendarButton(selectedDate: $selectedDate)
        }
    }

    private var dateStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                    dateButton(for: date)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                        dateButton(for: date)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func dateButton(for date: Date) -> some View {
        Button {
            selectedDate = date
            ReservationHaptics.selection()
        } label: {
            ReservationChoiceChip(
                title: chipTitle(for: date),
                subtitle: chipSubtitle(for: date),
                isSelected: Calendar.current.isDate(selectedDate, inSameDayAs: date),
                minWidth: 56,
                minHeight: 40,
                fillsWidth: false
            )
        }
        .buttonStyle(.plain)
    }

    private func chipTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func chipSubtitle(for date: Date) -> String? {
        guard Calendar.current.isDateInToday(date) else {
            return nil
        }

        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

struct ReservationOptionalDateFilter: View {
    @Binding var filterDate: Date?
    @Binding var calendarAnchor: Date
    var quickDayCount = 7

    private var quickDates: [Date] {
        (0..<quickDayCount).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Date())
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            dateStrip
                .frame(maxWidth: .infinity)
            ReservationOpenCalendarButton(selectedDate: calendarSelection)
        }
    }

    private var calendarSelection: Binding<Date> {
        Binding(
            get: { filterDate ?? calendarAnchor },
            set: { newValue in
                calendarAnchor = newValue
                filterDate = newValue
            }
        )
    }

    private var dateStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                allDatesButton
                ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                    dateButton(for: date)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    allDatesButton
                    ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                        dateButton(for: date)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var allDatesButton: some View {
        Button {
            filterDate = nil
            ReservationHaptics.selection()
        } label: {
            ReservationChoiceChip(
                title: "All",
                subtitle: nil,
                isSelected: filterDate == nil,
                minWidth: 56,
                minHeight: 40,
                fillsWidth: false
            )
        }
        .buttonStyle(.plain)
    }

    private func dateButton(for date: Date) -> some View {
        Button {
            filterDate = date
            calendarAnchor = date
            ReservationHaptics.selection()
        } label: {
            ReservationChoiceChip(
                title: chipTitle(for: date),
                subtitle: chipSubtitle(for: date),
                isSelected: filterDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false,
                minWidth: 56,
                minHeight: 40,
                fillsWidth: false
            )
        }
        .buttonStyle(.plain)
    }

    private func chipTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func chipSubtitle(for date: Date) -> String? {
        guard Calendar.current.isDateInToday(date) else {
            return nil
        }

        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

struct ReservationOpenCalendarButton: View {
    @Binding var selectedDate: Date
    var title = ""
    @State private var showsCalendarPicker = false

    var body: some View {
        Button {
            showsCalendarPicker = true
            ReservationHaptics.selection()
        } label: {
            Image(systemName: "calendar")
                .fixedSize()
                .frame(width: 42, height: 40)
              
//            Label(title, systemImage: "calendar")
//                .font(.subheadline.weight(.semibold))
//                .frame(width: 42, height: 40)
//                .foregroundStyle(.primary.opacity(0.78))
                
        }
        .buttonStyle(ReservationHeaderIconButtonStyle())
        .popover(isPresented: $showsCalendarPicker) {
            DatePicker("Service date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .frame(minWidth: 320, minHeight: 360)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Responsive Width Helper

private struct CappedWidthModifier: ViewModifier {
    // nil = no cap (small screens fill naturally, no extra .infinity frame).
    let maxWidth: CGFloat?

    func body(content: Content) -> some View {
        if let maxWidth {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// Caps and centers content only on wide layouts. On small screens (nil)
    /// nothing is applied, so no `.infinity` frame affects iPhone sizing.
    func cappedContentWidth(_ maxWidth: CGFloat?) -> some View {
        modifier(CappedWidthModifier(maxWidth: maxWidth))
    }
}

// MARK: - Service Timeline (busy-by-time graph)

struct ServiceTimelineSlot: Identifiable {
    let hour: Int
    var reservationCount: Int
    var guestCount: Int

    var id: Int { hour }

    var hourLabel: String {
        let adjusted = hour % 12 == 0 ? 12 : hour % 12
        return "\(adjusted)\(hour < 12 ? "a" : "p")"
    }
}

enum ServiceTimeline {
    /// Buckets expected guests by service hour for the busy-by-time graph.
    /// When a service `window` (open...close hour) is provided, the x-axis spans
    /// the full window even for hours that have no reservations.
    static func slots(
        from reservations: [ReservationRecord],
        window: ClosedRange<Int>? = nil
    ) -> [ServiceTimelineSlot] {
        var buckets: [Int: ServiceTimelineSlot] = [:]
        for reservation in reservations where reservation.isExpectedGuest {
            guard let hour = Int(reservation.reservationTime.prefix(2)) else { continue }
            var slot = buckets[hour] ?? ServiceTimelineSlot(hour: hour, reservationCount: 0, guestCount: 0)
            slot.reservationCount += 1
            slot.guestCount += reservation.partySize
            buckets[hour] = slot
        }

        let lower: Int
        let upper: Int
        if let window {
            lower = min(window.lowerBound, buckets.keys.min() ?? window.lowerBound)
            upper = max(window.upperBound, buckets.keys.max() ?? window.upperBound)
        } else if let minHour = buckets.keys.min(), let maxHour = buckets.keys.max() {
            lower = minHour
            upper = maxHour
        } else {
            return []
        }

        guard lower <= upper else { return [] }

        return (lower...upper).map { hour in
            buckets[hour] ?? ServiceTimelineSlot(hour: hour, reservationCount: 0, guestCount: 0)
        }
    }

    static func peakHour(in slots: [ServiceTimelineSlot]) -> Int? {
        slots.filter { $0.guestCount > 0 }.max { $0.guestCount < $1.guestCount }?.hour
    }

    static func hourLabel(_ hour: Int) -> String {
        let adjusted = hour % 12 == 0 ? 12 : hour % 12
        return "\(adjusted)\(hour < 12 ? "a" : "p")"
    }
}

/// Native Swift Charts bar chart of guests per service hour. Peak hour is
/// emphasized and an optional hour can be highlighted (e.g. this reservation).
struct ServiceLoadChart: View {
    let slots: [ServiceTimelineSlot]
    var highlightHour: Int?
    var height: CGFloat = 82

    private var peakHour: Int? { ServiceTimeline.peakHour(in: slots) }
    private var maxGuests: Int { max(slots.map(\.guestCount).max() ?? 0, 1) }
    private var xDomain: ClosedRange<Double> {
        guard let first = slots.first?.hour,
              let last = slots.last?.hour else {
            return 0...1
        }

        let lower = min(Double(first), Double(last)) - 0.5
        let upper = max(Double(first), Double(last)) + 0.5
        guard lower.isFinite, upper.isFinite, lower < upper else {
            return 0...1
        }
        return lower...upper
    }

    var body: some View {
        if slots.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar")
                    .foregroundStyle(.secondary)
                Text("No reservations")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            Chart(slots) { slot in
                BarMark(
                    x: .value("Time", slot.hour),
                    y: .value("Guests", slot.guestCount),
                    width: .fixed(slots.count > 9 ? 9 : 14)
                )
                .foregroundStyle(barStyle(for: slot))
                .cornerRadius(2.5)
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0...Double(maxGuests))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(TryzubColors.border)
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text("\(count)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(TryzubColors.mutedText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: slots.map { Double($0.hour) }) { value in
                    AxisValueLabel {
                        if let hour = value.as(Double.self) {
                            Text(ServiceTimeline.hourLabel(Int(hour)))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(TryzubColors.mutedText)
                        }
                    }
                }
            }
            .frame(height: height.tryzubFiniteNonNegativeLayoutValue)
        }
    }

    // Black/white/gray only: emphasis is conveyed by opacity of the brand dark
    // tone, never by hue (red stays reserved for warnings).
    private func barStyle(for slot: ServiceTimelineSlot) -> Color {
        if slot.guestCount == 0 { return TryzubColors.primaryControl.opacity(0.08) }
        if slot.hour == highlightHour { return TryzubColors.primaryControl }
        if slot.hour == peakHour { return TryzubColors.primaryControl.opacity(0.85) }
        return TryzubColors.primaryControl.opacity(0.32)
    }
}

/// Compact bar chart showing guests per service hour. Used on Home and Detail
/// to visualize service pressure without taking much vertical space.
struct ServiceTimelineGraph: View {
    let slots: [ServiceTimelineSlot]
    var highlightHour: Int?
    var barHeight: CGFloat = 64

    private var maxGuests: Int { max(slots.map(\.guestCount).max() ?? 0, 1) }
    private var peakHour: Int? { ServiceTimeline.peakHour(in: slots) }

    var body: some View {
        if slots.isEmpty {
            Text("No reservations to chart yet")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        } else {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(slots) { slot in
                    bar(for: slot)
                }
            }
        }
    }

    private func bar(for slot: ServiceTimelineSlot) -> some View {
        let safeBarHeight = barHeight.tryzubFiniteNonNegativeLayoutValue
        let fraction = CGFloat.tryzubSafeRatio(
            numerator: CGFloat(slot.guestCount),
            denominator: CGFloat(maxGuests)
        )
        let isPeak = slot.hour == peakHour && slot.guestCount > 0
        let isHighlight = highlightHour != nil && slot.hour == highlightHour

        return VStack(spacing: 4) {
            Text(slot.guestCount > 0 ? "\(slot.guestCount)" : " ")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isHighlight ? TryzubColors.info : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ZStack(alignment: .bottom) {
                Color.clear.frame(height: safeBarHeight)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(barFill(isPeak: isPeak, isHighlight: isHighlight, hasGuests: slot.guestCount > 0))
                    .frame(height: max(safeBarHeight * fraction, slot.guestCount > 0 ? 7 : 3))
            }

            Text(slot.hourLabel)
                .font(.system(size: 9, weight: isHighlight || isPeak ? .bold : .regular))
                .foregroundStyle(isHighlight ? TryzubColors.info : (isPeak ? .primary : .secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func barFill(isPeak: Bool, isHighlight: Bool, hasGuests: Bool) -> Color {
        if isHighlight { return TryzubColors.info }
        if !hasGuests { return Color.primary.opacity(0.06) }
        if isPeak { return TryzubColors.primaryControl }
        return TryzubColors.primaryControl.opacity(0.40)
    }
}

/// Compact metric tile for dense KPI strips (replaces stretched info pills).
struct ReservationMetricTile: View {
    let value: String
    let label: String
    var systemImage: String?
    var tint: Color = TryzubColors.primaryText
    var emphasize: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(emphasize ? tint : TryzubColors.mutedText)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(emphasize ? tint : TryzubColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(TryzubColors.secondaryCardBackground, in: RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TryzubSpacing.controlCornerRadius, style: .continuous)
                .stroke(emphasize ? tint.opacity(0.28) : TryzubColors.border, lineWidth: 1)
        }
    }
}

/// Bottom action container for pushed navigation destinations. Adds enough
/// bottom clearance so primary/destructive buttons always sit above the
/// floating tab bar instead of hiding behind it.
struct BottomSafeActionBar<Content: View>: View {
    var clearsTabBar: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, clearsTabBar ? ReservationLayout.floatingTabBarClearance : 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.5)
        }
    }
}

struct ReservationHeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary.opacity(0.78))
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
