//
//  HostReservationSlotContextBanner.swift
//  Tryzub Reservations
//
//  Compact arrival-window context for reservation create/edit forms.
//

import SwiftUI

struct HostReservationSlotContextBanner: View {
  let context: HostReservationSlotContext?

  var body: some View {
    if let context {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 10) {
          HostPulseIcon(
            isActive: context.severity == .busy || context.severity == .critical,
            size: 10
          )

          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(context.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TryzubColors.primaryText)

              Text(context.timeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TryzubColors.mutedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                  TryzubColors.border.opacity(0.45),
                  in: Capsule()
                )
            }

            Text(context.detail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)

            if !context.hints.isEmpty {
              VStack(alignment: .leading, spacing: 3) {
                ForEach(context.hints, id: \.self) { hint in
                  Text(hint)
                    .font(.caption2)
                    .foregroundStyle(hintColor(for: context.severity))
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
          }
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(severityBackground(context.severity), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(severityBorder(context.severity), lineWidth: 1)
      }
      .accessibilityElement(children: .combine)
      .transition(.opacity.combined(with: .move(edge: .top)))
    }
  }

  private func severityBackground(_ severity: HostPressureSeverity) -> Color {
    switch severity {
    case .critical:
      return TryzubColors.attentionBackground.opacity(0.55)
    case .busy:
      return TryzubColors.warning.opacity(0.08)
    case .watch:
      return Color(.tertiarySystemGroupedBackground)
    case .calm:
      return Color(.secondarySystemGroupedBackground)
    }
  }

  private func severityBorder(_ severity: HostPressureSeverity) -> Color {
    switch severity {
    case .critical:
      return TryzubColors.attentionBorder.opacity(0.65)
    case .busy:
      return TryzubColors.warning.opacity(0.28)
    case .watch, .calm:
      return TryzubColors.border
    }
  }

  private func hintColor(for severity: HostPressureSeverity) -> Color {
    switch severity {
    case .critical:
      return TryzubColors.danger
    case .busy:
      return TryzubColors.warning
    case .watch, .calm:
      return TryzubColors.mutedText
    }
  }
}
