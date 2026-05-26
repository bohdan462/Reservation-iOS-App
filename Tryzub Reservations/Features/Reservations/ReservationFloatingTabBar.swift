//
//  ReservationFloatingTabBar.swift
//  Tryzub Reservations
//

import SwiftUI

enum ReservationsAppTab: Hashable, CaseIterable, Identifiable {
    case today
    case schedule
    case review
    case more

    var id: Self { self }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .schedule:
            return "Schedule"
        case .review:
            return "Pending"
        case .more:
            return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            return "calendar"
        case .schedule:
            return "list.bullet.rectangle"
        case .review:
            return "tray.full"
        case .more:
            return "ellipsis"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .today:
            return "calendar"
        case .schedule:
            return "list.bullet.rectangle.fill"
        case .review:
            return "tray.full.fill"
        case .more:
            return "ellipsis"
        }
    }
}

struct ReservationFloatingTabBar: View {
    @Binding var selection: ReservationsAppTab

    var body: some View {
        HStack(spacing: 7) {
            ForEach(ReservationsAppTab.allCases) { tab in
                ReservationFloatingTabButton(
                    tab: tab,
                    isSelected: selection == tab
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selection = tab
                    }
                }
            }
        }
        .padding(7)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
    }
}

private struct ReservationFloatingTabButton: View {
    let tab: ReservationsAppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: isSelected ? 7 : 0) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(isSelected ? Color(.systemBackground) : .secondary)
                    .background(iconBackground, in: Circle())

                if isSelected {
                    Text(tab.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.86))
                }
            }
            .frame(height: 44)
            .padding(.trailing, isSelected ? 12 : 0)
            .background(selectedBackground, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var iconBackground: Color {
        isSelected ? Color.primary.opacity(0.82) : Color(.systemBackground)
    }

    private var selectedBackground: Color {
        isSelected ? Color(.systemBackground) : .clear
    }
}
