//
//  HostAssignmentChoiceRow.swift
//  Tryzub Reservations
//
//  Shared card row for table and reservation assignment pickers.
//

import SwiftUI

struct HostAssignmentCardSurface<Content: View>: View {
  var isMuted: Bool = false
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isMuted
          ? Color(.tertiarySystemGroupedBackground)
          : Color(.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(TryzubColors.border, lineWidth: 1)
      }
  }
}

struct HostAssignmentChoiceRow: View {
  let title: String
  let summary: String
  let detail: String?
  let isAvailable: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HostAssignmentCardSurface(isMuted: !isAvailable) {
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text(title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(isAvailable ? TryzubColors.primaryText : TryzubColors.mutedText)

            Text(summary)
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.leading)

            if let detail {
              Text(detail)
                .font(.caption2)
                .foregroundStyle(TryzubColors.warning)
                .multilineTextAlignment(.leading)
            }
          }

          Spacer(minLength: 8)

          if isAvailable {
            Image(systemName: "checkmark.circle")
              .font(.caption.weight(.semibold))
              .foregroundStyle(TryzubColors.success)
          } else {
            Image(systemName: "exclamationmark.triangle")
              .font(.caption.weight(.semibold))
              .foregroundStyle(TryzubColors.warning)
          }
        }
      }
    }
    .buttonStyle(.plain)
  }
}

struct HostAssignmentChoiceList: View {
  let sectionTitle: String
  let proposals: [HostTableAssignmentProposal]
  let onSelect: (HostTableAssignmentProposal) -> Void

  var body: some View {
    if !proposals.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(sectionTitle)
          .font(.caption.weight(.semibold))
          .foregroundStyle(TryzubColors.mutedText)

        ForEach(proposals) { proposal in
          HostAssignmentChoiceRow(
            title: proposal.tableLabel,
            summary: proposal.summary,
            detail: proposal.detail,
            isAvailable: proposal.isAvailable
          ) {
            onSelect(proposal)
            ReservationHaptics.selection()
          }
        }
      }
    }
  }
}
