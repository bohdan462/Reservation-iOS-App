//
//  BookingSuggestionsView.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 4 (Booking Load Suggestions).
//
//  Shared, display-only building blocks for booking-load suggestions. These never
//  mutate anything: the action button (Global hub) routes staff to the existing
//  blocked-slots confirm screen, where staff confirm any real close.
//

import SwiftUI

/// Simple staff-language text block describing one busy window.
struct BookingSuggestionContent: View {
    let item: BookingSuggestionViewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(item.headline)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            Text(item.loadLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(item.closeLine)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Text(item.alternateLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        item.severity == .veryBusy ? .red : .orange
    }
}

/// Concise, read-only Host Board heads-up for the busiest window during/before service.
struct BookingLoadHostCard: View {
    let item: BookingSuggestionViewItem
    let knownOnlyNote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookingSuggestionContent(item: item)
            Text(knownOnlyNote)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
