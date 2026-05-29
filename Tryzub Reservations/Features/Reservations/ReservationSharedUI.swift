//
//  ReservationSharedUI.swift
//  Tryzub Reservations
//

import SwiftUI

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
    static let dueSoonBackground = Color(.systemGray5)
    static let successBackground = Color(.systemGreen).opacity(0.10)
    static let primaryControl = Color(red: 0.02, green: 0.08, blue: 0.18)
    static let destructiveText = Color(red: 0.55, green: 0.16, blue: 0.13)
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
    static let chipSpacing: CGFloat = 8
    static let cornerRadius: CGFloat = 8
    static let controlCornerRadius: CGFloat = 8
}

enum ReservationUIStyle {
    static let cardCorner = TryzubSpacing.cornerRadius
    static let controlCorner = TryzubSpacing.controlCornerRadius
    static let selectedControlColor = TryzubColors.primaryControl
    static let serviceTitleColor = Color(red: 0.03, green: 0.10, blue: 0.22)
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

    var body: some View {
        Text(title)
            .font(TryzubTypography.badge)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
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
            .foregroundStyle(Color(.systemBackground))
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
                if isVertical {
                    path.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                } else {
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
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
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        TryzubSectionCard(title: title, systemImage: systemImage, spacing: spacing) {
            content
        }
    }
}

struct ReservationChoiceChip: View {
    let title: String
    var subtitle: String?
    var isSelected: Bool
    var minWidth: CGFloat = 78
    var minHeight: CGFloat = 38
    var fillsWidth = true
    var selectedColor: Color = ReservationUIStyle.selectedControlColor

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(isSelected ? Color(.systemBackground).opacity(0.82) : .secondary)
            }
        }
        .foregroundStyle(isSelected ? Color(.systemBackground) : .primary.opacity(0.82))
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight)
        .frame(minWidth: minWidth)
        .padding(.horizontal, 10)
        .background(isSelected ? selectedColor : Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
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

struct ReservationOpenCalendarButton: View {
    @Binding var selectedDate: Date
    var title = "Open Calendar"
    @State private var showsCalendarPicker = false

    var body: some View {
        Button {
            showsCalendarPicker = true
            ReservationHaptics.selection()
        } label: {
            Label(title, systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.78))
                .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsCalendarPicker) {
            DatePicker("Service date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .frame(minWidth: 320, minHeight: 360)
                .presentationCompactAdaptation(.popover)
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
