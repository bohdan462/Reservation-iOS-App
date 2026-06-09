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
    .navigationTitle("Review details")
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
      Text("Updated \(generatedAtText)")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var mainBriefingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Right now")
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
      Text("What to check")
        .font(.headline)

      if operationalPrompts.isEmpty {
        Text("Nothing else grouped for this moment.")
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
      Text("Key details")
        .font(.headline)

      if snapshot.briefingFacts.isEmpty {
        Text("No extra details right now.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(dedupedReviewFacts.prefix(5))) { fact in
          VStack(alignment: .leading, spacing: 4) {
            Text(HostStaffLanguage.rewrite(fact.title))
              .font(.subheadline.weight(.semibold))
            Text(HostStaffLanguage.rewrite(fact.detail))
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
      Text("Check next")
        .font(.headline)

      if snapshot.suggestedActions.isEmpty {
        Text("No checks suggested right now.")
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

  @ViewBuilder
  private var signalsSummarySection: some View {
    let flaggedCount = snapshot.briefingFacts.count
      + snapshot.suggestedActions.count
    if flaggedCount > 0 {
      VStack(alignment: .leading, spacing: 8) {
        Text("Summary")
          .font(.headline)

        Text("\(flaggedCount) item\(flaggedCount == 1 ? "" : "s") flagged for staff review.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .reviewCardStyle()
    }
  }

  // MARK: - Rows

  private func actionRow(_ action: HostSuggestedAction, isTappable: Bool) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text(HostStaffLanguage.rewrite(action.title))
          .font(.subheadline.weight(.semibold))
          .multilineTextAlignment(.leading)
        Text(HostStaffLanguage.rewrite(action.reason))
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
        if isTappable {
          Text(ManagerAttentionItemBuilder.tapLabel(for: action))
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

  private var dedupedReviewFacts: [HostBriefingFact] {
    var seenKeys = Set<String>()
    var results: [HostBriefingFact] = []

    for fact in snapshot.briefingFacts {
      let title = HostStaffLanguage.rewrite(fact.title).lowercased()
      let detail = HostStaffLanguage.rewrite(fact.detail).lowercased()
      let key = "\(title)|\(detail)"
      guard !seenKeys.contains(key) else { continue }
      seenKeys.insert(key)
      results.append(fact)
    }

    return results
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
