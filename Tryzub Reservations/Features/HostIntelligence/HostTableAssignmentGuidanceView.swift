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
    if let context {
      VStack(alignment: .leading, spacing: 12) {
        if let slotContext = context.slotContext {
          HostReservationSlotContextBanner(context: slotContext)
        }

        if !context.proposals.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Suggested seating")
              .font(.caption.weight(.semibold))
              .foregroundStyle(TryzubColors.mutedText)

            ForEach(context.proposals) { proposal in
              proposalRow(proposal)
            }
          }
        }
      }
      .animation(.snappy(duration: 0.28), value: context)
    }
  }

  @ViewBuilder
  private func proposalRow(_ proposal: HostTableAssignmentProposal) -> some View {
    Button {
      onSelectProposal(proposal.tableLabel)
      ReservationHaptics.selection()
    } label: {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(proposal.tableLabel)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(proposal.isAvailable ? TryzubColors.primaryText : TryzubColors.mutedText)

            if proposal.isRecommended, proposal.isAvailable {
              Text("Recommended")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TryzubColors.primaryControl)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                  TryzubColors.primaryControl.opacity(0.12),
                  in: Capsule()
                )
            }
          }

          Text(proposal.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)

          if let detail = proposal.detail {
            Text(detail)
              .font(.caption2)
              .foregroundStyle(TryzubColors.warning)
              .multilineTextAlignment(.leading)
          }
        }

        Spacer(minLength: 8)

        if proposal.isAvailable {
          Image(systemName: "checkmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(TryzubColors.success)
        } else {
          Image(systemName: "exclamationmark.triangle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(TryzubColors.warning)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        proposal.isAvailable
          ? Color(.secondarySystemGroupedBackground)
          : Color(.tertiarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(
            proposal.isRecommended && proposal.isAvailable
              ? TryzubColors.primaryControl.opacity(0.28)
              : TryzubColors.border,
            lineWidth: 1
          )
      }
    }
    .buttonStyle(.plain)
  }
}
