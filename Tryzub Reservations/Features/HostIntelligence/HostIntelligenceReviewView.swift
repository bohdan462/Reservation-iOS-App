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
        checkNowSection
        keyDetailsSection
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

      Text(staffFacingNarrative.headline)
        .font(.body.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)

      if let why = staffFacingNarrative.whyItMatters?.trimmingCharacters(in: .whitespacesAndNewlines),
         !why.isEmpty {
        Text(why)
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let briefingSourceCaption {
        Text(briefingSourceCaption)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .reviewCardStyle()
  }

  /// Unified "Check now" section: operational prompts first (grouped, with related counts),
  /// then any suggested actions whose title/body have not already appeared in the prompts.
  /// This replaces the old "What to check" + "Check next" pair that could repeat the same
  /// reservation in both lists with near-identical wording.
  @ViewBuilder
  private var checkNowSection: some View {
    let actions = dedupedActions
    VStack(alignment: .leading, spacing: 10) {
      Text("Check now")
        .font(.headline)

      if operationalPrompts.isEmpty && actions.isEmpty {
        Text("Nothing to check right now.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .reviewCardStyle()
      } else {
        ForEach(operationalPrompts) { prompt in
          VStack(alignment: .leading, spacing: 6) {
            Text(prompt.title)
              .font(.subheadline.weight(.semibold))
            Text(prompt.body)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if !prompt.relatedReservationIDs.isEmpty {
              Text("\(prompt.relatedReservationIDs.count) \(prompt.relatedReservationIDs.count == 1 ? "reservation" : "reservations")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
          .reviewCardStyle()
        }

        ForEach(actions) { action in
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

  /// Key details: facts from the snapshot that are not already captured in the headline
  /// or the operational prompts. Capped at 4 to avoid padding noise.
  @ViewBuilder
  private var keyDetailsSection: some View {
    let facts = dedupedReviewFacts
    if !facts.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Text("Key details")
          .font(.headline)

        ForEach(Array(facts.prefix(4))) { fact in
          VStack(alignment: .leading, spacing: 4) {
            Text(HostStaffLanguage.rewrite(fact.title))
              .font(.subheadline.weight(.semibold))
            let detail = HostStaffLanguage.rewrite(fact.detail)
            if !detail.isEmpty {
              Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .reviewCardStyle()
        }
      }
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

  private var staffFacingNarrative: ManagerNarrative {
    let template = ManagerNarrativeTemplateBuilder.build(from: snapshot)
    let trimmed = briefingText.trimmingCharacters(in: .whitespacesAndNewlines)
    if briefingSource != .template, !trimmed.isEmpty {
      return ManagerNarrative(
        headline: trimmed,
        whyItMatters: nil,
        checkNext: nil,
        source: template.source,
        failedReason: nil
      )
    }
    return template
  }

  /// Suggested actions whose title+reason are not already covered by an operational prompt.
  /// This prevents the same reservation appearing in both "What to check" and "Check next"
  /// with identical wording.
  private var dedupedActions: [HostSuggestedAction] {
    let promptTitles = Set(operationalPrompts.map { $0.title.lowercased() })
    let promptBodies = Set(operationalPrompts.map { $0.body.lowercased() })
    var seen = Set<String>()
    var results: [HostSuggestedAction] = []
    for action in snapshot.suggestedActions.prefix(8) {
      let titleKey = HostStaffLanguage.rewrite(action.title).lowercased()
      let reasonKey = HostStaffLanguage.rewrite(action.reason).lowercased()
      if promptTitles.contains(titleKey) || promptBodies.contains(titleKey) { continue }
      if promptBodies.contains(reasonKey) || promptTitles.contains(reasonKey) { continue }
      let dedupKey = "\(titleKey)|\(reasonKey)"
      guard !seen.contains(dedupKey) else { continue }
      seen.insert(dedupKey)
      results.append(action)
    }
    return results
  }

  private var dedupedReviewFacts: [HostBriefingFact] {
    let narrative = staffFacingNarrative
    var seenKeys = Set<String>()
    var results: [HostBriefingFact] = []

    for fact in snapshot.briefingFacts {
      let title = HostStaffLanguage.rewrite(fact.title)
      let detail = HostStaffLanguage.rewrite(fact.detail)
      if HostStaffLanguage.areSameStaffMeaning(title, narrative.headline) {
        continue
      }
      if HostStaffLanguage.isGenericCheckLine(detail),
         HostStaffLanguage.areSameStaffMeaning(detail, narrative.whyItMatters ?? "") {
        continue
      }
      let key = "\(title.lowercased())|\(detail.lowercased())"
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
