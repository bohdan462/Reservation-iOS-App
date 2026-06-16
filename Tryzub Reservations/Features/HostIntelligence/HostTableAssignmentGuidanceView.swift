//
//  HostTableAssignmentGuidanceView.swift
//  Tryzub Reservations
//
//  Slot summary + proposed seating for table assignment sheets.
//

import SwiftUI

struct HostTableAssignmentGuidanceView: View {
  let context: HostTableAssignmentContext?
  var onSelectProposal: (String) -> Void

  var body: some View {
    if let context, showsSuggestedSeating(context) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Suggested seating")
          .font(.caption.weight(.semibold))
          .foregroundStyle(TryzubColors.mutedText)

        if let slotContext = context.slotContext {
          HostReservationSlotContextBanner(context: slotContext)
        }

        if !context.proposals.isEmpty {
          LazyVGrid(
            columns: ReservationSlotGridStyle.fourColumns,
            alignment: .leading,
            spacing: ReservationSlotGridStyle.rowSpacing
          ) {
            ForEach(context.proposals) { proposal in
              HostAssignmentTableProposalCard(proposal: proposal) {
                onSelectProposal(proposal.tableLabel)
                ReservationHaptics.selection()
              }
            }
          }
        }
      }
      .animation(.snappy(duration: 0.28), value: context)
    }
  }

  private func showsSuggestedSeating(_ context: HostTableAssignmentContext) -> Bool {
    context.slotContext != nil || !context.proposals.isEmpty
  }
}

struct HostAssignmentTableProposalCard: View {
  let proposal: HostTableAssignmentProposal
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HostAssignmentCardSurface(isMuted: !proposal.isAvailable) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(proposal.tableLabel)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(proposal.isAvailable ? TryzubColors.primaryText : TryzubColors.mutedText)
              .lineLimit(1)

            Spacer(minLength: 0)

            if let seatCount = proposal.seatCount {
              Label {
                Text("\(seatCount)")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
              } icon: {
                Image(systemName: "person.2")
                  .font(.caption2.weight(.semibold))
              }
              .labelStyle(.titleAndIcon)
            }
          }

          Text(displayFitDescription)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)

          if let detail = proposal.detail {
            Text(detail)
              .font(.caption2)
              .foregroundStyle(TryzubColors.warning)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
      }
    }
    .buttonStyle(.plain)
  }

  private var displayFitDescription: String {
    if let fitDescription = proposal.fitDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
       !fitDescription.isEmpty {
      return fitDescription
    }
    return proposal.summary
  }
}
