//
//  HostReservationOpenIntent.swift
//  Tryzub Reservations
//
//  Lightweight navigation context when staff opens a reservation from Host Intelligence.
//

import Foundation
import SwiftUI

struct HostReservationOpenIntent: Identifiable, Codable, Equatable {
  let id: String
  let reservationRemoteID: Int
  let actionKind: HostActionKind
  let title: String
  let reason: String
  let targetSlotTime: String?
  let targetTableName: String?
  let createdAt: Date
}

extension HostReservationOpenIntent {
  static func from(
    action: HostSuggestedAction,
    resolvedRemoteID: Int
  ) -> HostReservationOpenIntent {
    HostReservationOpenIntent(
      id: "host-intent-\(resolvedRemoteID)-\(action.kind.rawValue)-\(action.id)",
      reservationRemoteID: resolvedRemoteID,
      actionKind: action.kind,
      title: action.title,
      reason: action.reason,
      targetSlotTime: action.targetSlotTime,
      targetTableName: action.targetTableName,
      createdAt: Date()
    )
  }

  var actionHint: String? {
    switch actionKind {
    case .assignTable:
      return "Use the existing Assign Table action below."
    case .suggestAlternateTime:
      return "Use guest communication or the manual update flow."
    case .confirmReservation:
      return "Use Confirm after reviewing details."
    case .markNoShow:
      return "Use No-show only after confirming with staff policy."
    case .completeReservation:
      return "Use Complete only if the table is actually done."
    case .alertServer:
      return "Share this note with the server before seating."
    case .reviewReservation, .reviewCancellationOpportunity:
      return "Review the reservation details before taking action."
    case .seatReservation:
      return "Use Seat after confirming the table is ready."
    default:
      return nil
    }
  }

  var formattedTargetSlotTime: String? {
    guard let targetSlotTime else { return nil }
    let normalized = targetSlotTime.count >= 5
      ? String(targetSlotTime.prefix(5))
      : targetSlotTime
    if let date = ReservationFormatters.apiTime.date(from: normalized) {
      return ReservationFormatters.shortTime.string(from: date)
    }
    return normalized
  }
}

// MARK: - Banner

struct HostIntelligenceIntentBanner: View {
  let intent: HostReservationOpenIntent
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "sparkles")
          .font(.headline)
          .foregroundStyle(.secondary)
          .frame(width: 32, height: 32)
          .background(Color(.tertiarySystemGroupedBackground), in: Circle())

        VStack(alignment: .leading, spacing: 4) {
          Text("Host pulse")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          Text(intent.title)
            .font(.headline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)

          Text(intent.reason)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          if let time = intent.formattedTargetSlotTime {
            Text("Suggested time: \(time)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let table = intent.targetTableName?.trimmingCharacters(in: .whitespacesAndNewlines),
             !table.isEmpty {
            Text("Suggested table: \(table)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let hint = intent.actionHint {
            Text(hint)
              .font(.caption)
              .foregroundStyle(.tertiary)
          }

          Text("Review only — staff confirmation is still required.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }

        Spacer(minLength: 0)

        Button {
          onDismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
      }
    }
    .padding(14)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }
  }
}
