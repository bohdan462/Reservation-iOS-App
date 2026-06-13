//
//  ArrivalPressureBucketSheet.swift
//  Tryzub Reservations
//
//  Compact bucket detail sheet — who is arriving in a 15-minute window.
//  No phone, email, or raw notes.
//

import SwiftUI

struct ArrivalPressureBucketSheet: View {
  let bucket: ArrivalPressureBucket
  let onOpenReservation: (Int) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 16) {
            statPill(value: "\(bucket.reservationCount)", label: "Reservations")
            statPill(value: "\(bucket.guestCount)", label: "Guests")
            if bucket.noTableCount > 0 {
              statPill(value: "\(bucket.noTableCount)", label: "No table", tint: TryzubColors.warning)
            }
          }
          .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
        }

        Section("Arriving") {
          ForEach(bucket.items) { item in
            Button {
              dismiss()
              onOpenReservation(item.remoteID)
            } label: {
              reservationRow(item)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .navigationTitle(bucket.windowLabel)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func statPill(value: String, label: String, tint: Color = TryzubColors.primaryText) -> some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.headline.weight(.semibold))
        .foregroundStyle(tint)
        .monospacedDigit()
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private func reservationRow(_ item: ArrivalPressureReservationItem) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(item.guestName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)

          Text("·\(item.partySize)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 6) {
          Text(item.displayTime)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

          Text(item.status.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(statusTint(item.status))

          if let table = item.tableName {
            Text("T\(table)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }

      Spacer(minLength: 4)

      HStack(spacing: 4) {
        if item.hasNoTable {
          badgeDot(color: TryzubColors.warning, label: "No table")
        }
        if item.hasGuestNotes {
          badgeDot(color: TryzubColors.info, label: "Note")
        }
        if item.needsReview {
          badgeDot(color: TryzubColors.warning, label: "Review")
        }
        if item.isReturningGuest {
          badgeDot(color: TryzubColors.success, label: "Returning")
        }
        if item.isSeated {
          badgeDot(color: Color.accentColor, label: "Seated")
        }
      }

      Image(systemName: "chevron.right")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(voiceOverLabel(for: item))
    .accessibilityAddTraits(.isButton)
  }

  private func statusTint(_ status: ReservationStatus) -> Color {
    switch status {
    case .needsReview, .new: return TryzubColors.warning
    case .seated: return Color.accentColor
    case .confirmed: return TryzubColors.success
    default: return .secondary
    }
  }

  private func badgeDot(color: Color, label: String) -> some View {
    Circle()
      .fill(color.opacity(0.75))
      .frame(width: 6, height: 6)
      .accessibilityLabel(label)
  }

  private func voiceOverLabel(for item: ArrivalPressureReservationItem) -> String {
    var parts = [item.guestName, item.displayTime, "\(item.partySize) guests", item.status.displayName]
    if let table = item.tableName { parts.append("Table \(table)") }
    if item.hasNoTable { parts.append("no table") }
    return parts.joined(separator: ", ")
  }
}
