//
//  HostIntelligenceReviewView.swift
//  Tryzub Reservations
//
//  Read-only expanded Host Intelligence review for staff.
//

import SwiftUI

struct HostIntelligenceReviewView: View {
  let snapshot: HostDecisionSnapshot
  let operationalPrompts: [HostOperationalBriefingPrompt]
  let briefingText: String
  let briefingSource: HostBriefingWriterSource?
  var onActionTapped: ((HostSuggestedAction) -> Void)? = nil

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        headerSection
        mainBriefingSection
        operationalPromptsSection
        topFactsSection
        suggestedActionsSection
        signalsSummarySection
      }
      .padding()
    }
    .navigationTitle("Review signals")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") {
          dismiss()
        }
      }
    }
  }

  // MARK: - Sections

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(serviceStateTitle)
        .font(.title3.weight(.semibold))
      Text("Pressure \(Int(snapshot.pressureScore.rounded()))/100")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text(generatedAtText)
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var mainBriefingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Main briefing")
        .font(.headline)

      Text(displayBriefingText)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)

      if let briefingSourceCaption {
        Text(briefingSourceCaption)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .reviewCardStyle()
  }

  @ViewBuilder
  private var operationalPromptsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Operational prompts")
        .font(.headline)

      if operationalPrompts.isEmpty {
        Text("No grouped operational prompts for this snapshot.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(operationalPrompts) { prompt in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(prompt.title)
                .font(.subheadline.weight(.semibold))
              Spacer(minLength: 8)
              Text(prompt.severity.rawValue.capitalized)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Text(prompt.body)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if !prompt.relatedReservationIDs.isEmpty {
              Text("\(prompt.relatedReservationIDs.count) related reservation\(prompt.relatedReservationIDs.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
          .reviewCardStyle()
        }
      }
    }
  }

  @ViewBuilder
  private var topFactsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Top facts")
        .font(.headline)

      if snapshot.briefingFacts.isEmpty {
        Text("No ranked briefing facts.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(snapshot.briefingFacts.prefix(5))) { fact in
          VStack(alignment: .leading, spacing: 4) {
            Text(fact.title)
              .font(.subheadline.weight(.semibold))
            Text(fact.detail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .reviewCardStyle()
        }
      }
    }
  }

  @ViewBuilder
  private var suggestedActionsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Suggested actions")
        .font(.headline)

      if snapshot.suggestedActions.isEmpty {
        Text("No suggested actions.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(snapshot.suggestedActions.prefix(8)) { action in
          if let onActionTapped {
            Button {
              onActionTapped(action)
              dismiss()
            } label: {
              actionRow(action, isTappable: true)
            }
            .buttonStyle(.plain)
          } else {
            actionRow(action, isTappable: false)
          }
        }
      }
    }
  }

  private var signalsSummarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Signals summary")
        .font(.headline)

      LabeledContent("Guest signals") {
        Text("\(snapshot.guestSignals.count)")
      }
      LabeledContent("Table signals") {
        Text("\(snapshot.tableSignals.count)")
      }
      LabeledContent("Booking decisions") {
        Text("\(snapshot.bookingDecisions.count)")
      }
      LabeledContent("Slot pressures") {
        Text("\(snapshot.slotPressures.count)")
      }
    }
    .reviewCardStyle()
  }

  // MARK: - Rows

  private func actionRow(_ action: HostSuggestedAction, isTappable: Bool) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text(action.title)
          .font(.subheadline.weight(.semibold))
          .multilineTextAlignment(.leading)
        Text(action.reason)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
        if isTappable {
          Text("Tap to review reservation")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      if isTappable {
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
    }
    .reviewCardStyle()
  }

  // MARK: - Helpers

  private var serviceStateTitle: String {
    switch snapshot.serviceState {
    case .calm: return "Calm service"
    case .building: return "Building service"
    case .busy: return "Busy service"
    case .critical: return "Critical service"
    }
  }

  private var generatedAtText: String {
    snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened)
  }

  private var displayBriefingText: String {
    let trimmed = briefingText.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? snapshot.templateBriefingText : trimmed
  }

  private var briefingSourceCaption: String? {
    nil
  }
}

private extension View {
  func reviewCardStyle() -> some View {
    padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
