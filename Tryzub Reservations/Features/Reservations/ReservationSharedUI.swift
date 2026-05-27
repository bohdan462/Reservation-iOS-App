//
//  ReservationSharedUI.swift
//  Tryzub Reservations
//

import SwiftUI

enum ReservationUIStyle {
    static let cardCorner: CGFloat = 14
    static let controlCorner: CGFloat = 8
    static let selectedControlColor = Color(red: 0.02, green: 0.08, blue: 0.18)
    static let serviceTitleColor = Color(red: 0.03, green: 0.10, blue: 0.22)
    static let cancelColor = Color(red: 0.55, green: 0.16, blue: 0.13)
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
        VStack(alignment: .leading, spacing: spacing) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
        .padding(18)
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
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 15, height: 15)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let value {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.82))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
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
