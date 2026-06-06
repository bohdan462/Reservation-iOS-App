//
//  ReservationFloatingTabBar.swift
//  Tryzub Reservations
//

import SwiftUI

enum ReservationsAppTab: Hashable, CaseIterable, Identifiable {
    case home
    case schedule
    case guests
    case review
    case more

    var id: Self { self }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .schedule:
            return "List"
        case .guests:
            return "Guests"
        case .review:
            return "Review"
        case .more:
            return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .schedule:
            return "calendar"
        case .guests:
            return "person.2"
        case .review:
            return "exclamationmark.triangle"
        case .more:
            return "ellipsis"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home:
            return "house.fill"
        case .schedule:
            return "calendar"
        case .guests:
            return "person.2.fill"
        case .review:
            return "exclamationmark.triangle.fill"
        case .more:
            return "ellipsis"
        }
    }
}

struct ReservationFloatingTabBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selection: ReservationsAppTab
    var reviewAttentionCount = 0

    var body: some View {
        let isCompact = horizontalSizeClass == .compact

        HStack(spacing: isCompact ? 2 : 8) {
            ForEach(ReservationsAppTab.allCases) { tab in
                ReservationFloatingTabButton(
                    tab: tab,
                    isSelected: selection == tab,
                    attentionCount: tab == .review ? reviewAttentionCount : 0,
                    isCompact: isCompact
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = tab
                    }
                    ReservationHaptics.selection()
                }
            }
        }
        .padding(.horizontal, isCompact ? 6 : 14)
        .padding(.vertical, isCompact ? 6 : 8)
//        .frame(maxWidth: .infinity)
        .frame(maxWidth: isCompact ? .infinity : 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
    }
}

private struct ReservationFloatingTabButton: View {
    let tab: ReservationsAppTab
    let isSelected: Bool
    let attentionCount: Int
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 5 : 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(isSelected ? ReservationUIStyle.selectedControlColor : .secondary)

                    if attentionCount > 0 {
                        Text("\(min(attentionCount, 99))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(minWidth: 15, minHeight: 15)
                            .padding(.horizontal, attentionCount > 9 ? 3 : 0)
                            .background(ReservationUIStyle.selectedControlColor, in: Capsule())
                            .offset(x: 6, y: -5)
                            .accessibilityHidden(true)
                    }
                }

                Text(tab.title)
                    .font((isCompact ? Font.caption : Font.subheadline).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(isSelected ? ReservationUIStyle.selectedControlColor : .primary.opacity(0.78))
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 38 : 42)
            .padding(.horizontal, isCompact ? 2 : 6)
            .background(selectedBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
//        .frame(maxWidth: isCompact ? .infinity : 38)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var selectedBackground: Color {
        isSelected ? Color(.systemBackground) : .clear
    }
}
