//
//  HostIntelligenceCard.swift
//  Tryzub Reservations
//
//  Read-only Host Intelligence briefing card for the Host board.
//

import SwiftUI

struct HostIntelligenceCard: View {
  let snapshot: HostDecisionSnapshot
  var attentionPresentation: HostAttentionPresentation = .empty
  var briefingTextOverride: String? = nil
  var managerNarrative: ManagerNarrative? = nil
  var briefingSource: HostBriefingWriterSource? = nil
  var compactOperationalPrompts: [HostOperationalBriefingPrompt] = []
  var showOperationalReview: Bool = false
  /// When true, hides technical briefing captions and uses staff-facing labels.
  var staffFacingPresentation: Bool = true
  /// Pulses the awareness icon during on-device support preparation, etc.
  var externalPulseActive: Bool = false
  var renderState: HostIntelligenceRenderState = .ready
  var isRefreshingAttentionCard: Bool = false
  var onReviewTapped: (() -> Void)? = nil
  var onActionTapped: ((HostSuggestedAction) -> Void)? = nil

  var body: some View {
    if isCalmPresentation {
      calmCard
    } else {
      activeCard
    }
  }

  // MARK: - Layout

  private var calmCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      cardTitleRow
      refreshingCaption

      narrativeBody

      compactPromptLines

      reviewIntelligenceButton
    }
    .cardStyle()
  }

  private var activeCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        cardTitleRow

        Spacer(minLength: 8)

        if staffFacingPresentation {
          Text(stateTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        } else {
          Text(stateTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          Text("\(Int(snapshot.pressureScore.rounded()))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }

      if !staffFacingPresentation {
        Text(stateLine)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      refreshingCaption
      narrativeBody

      if let briefingSourceCaption {
        Text(briefingSourceCaption)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      compactPromptLines

      reviewIntelligenceButton

      if !attentionItems.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(attentionItems) { item in
            attentionRow(item)
          }
        }
      }

      if attentionItems.isEmpty, !attentionPresentation.secondaryContext.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(attentionPresentation.secondaryContext) { item in
            contextRow(item)
          }
        }
      }

      if !staffFacingPresentation, signalCount > 0 {
        Text("Based on \(signalCount) live signal\(signalCount == 1 ? "" : "s")")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .cardStyle()
    .background(renderTraceView)
  }

  private var cardTitleRow: some View {
    HStack(spacing: 8) {
      if staffFacingPresentation {
        HostPulseIcon(isActive: pulseIsActive, size: 11)
      } else {
        Text("Host Intelligence")
          .font(.headline)
      }
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private func attentionRow(_ item: ManagerAttentionItem) -> some View {
    if let onActionTapped, let action = item.sourceAction {
      Button {
        onActionTapped(action)
      } label: {
        attentionRowContent(item, isTappable: true)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens reservation for staff to check.")
    } else {
      attentionRowContent(item, isTappable: false)
    }
  }

  private func contextRow(_ item: HostAttentionContextItem) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.caption.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        if let detail = item.detail {
          Text(detail)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func attentionRowContent(_ item: ManagerAttentionItem, isTappable: Bool) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.caption.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        if let detail = item.detail {
          Text(detail)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if isTappable {
          Text(item.actionTitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
      }

      if isTappable {
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  // MARK: - Helpers

  private var isCalmPresentation: Bool {
    guard renderState == .ready else { return false }
    guard !isLoadingPresentation else { return false }
    return snapshot.briefingFacts.isEmpty
      && snapshot.suggestedActions.isEmpty
      && snapshot.slotPressures.allSatisfy { $0.severity == .calm && $0.reservationCount == 0 }
  }

  private var isLoadingPresentation: Bool {
    renderState == .evaluating
      && !snapshot.hasAttentionContent
      && !isRefreshingAttentionCard
  }

  private var stateTitle: String {
    if snapshot.briefingFacts.contains(where: { $0.id.hasPrefix("future-no-table-planning-") }) {
      return "Planning"
    }

    if snapshot.briefingFacts.contains(where: {
      $0.severity == .critical || $0.category == .overdue
    }) {
      return "Attention"
    }

    if !snapshot.briefingFacts.isEmpty || !snapshot.suggestedActions.isEmpty {
      switch snapshot.serviceState {
      case .critical: return "Very busy"
      case .busy: return "Busy"
      case .building: return "Check"
      case .calm: return "Check"
      }
    }

    switch snapshot.serviceState {
    case .calm: return "Quiet"
    case .building: return "Picking up"
    case .busy: return "Busy"
    case .critical: return "Very busy"
    }
  }

  private var stateLine: String {
    "Service state · pressure \(Int(snapshot.pressureScore.rounded()))/100"
  }

  @ViewBuilder
  private var narrativeBody: some View {
    if let narrative = staffFacingNarrative {
      VStack(alignment: .leading, spacing: 4) {
        Text(narrative.headline)
          .font(.subheadline.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)

        if let why = narrative.whyItMatters?.trimmingCharacters(in: .whitespacesAndNewlines),
           !why.isEmpty {
          Text(why)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if attentionItems.isEmpty,
           let check = narrative.checkNext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !check.isEmpty {
          Text(check)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    } else {
      Text(displayBriefingText)
        .font(.subheadline)
        .foregroundStyle(isCalmPresentation ? .secondary : .primary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var staffFacingNarrative: ManagerNarrative? {
    guard staffFacingPresentation, let managerNarrative else { return nil }
    if isLoadingPresentation {
      return .loading
    }
    if renderState != .ready,
       managerNarrative.headline == ManagerNarrative.empty.headline {
      return .loading
    }
    guard managerNarrative.source != .localModel
        || !ManagerNarrativeValidator.containsLeakedModelLabels(in: managerNarrative) else {
      return nil
    }
    let headline = managerNarrative.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !headline.isEmpty else { return nil }
    return managerNarrative
  }

  @ViewBuilder
  private var refreshingCaption: some View {
    if isRefreshingAttentionCard {
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.mini)
        Text("Refreshing…")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    } else if isLoadingPresentation {
      HStack(spacing: 6) {
        TryzubSubtleLoadingDot(diameter: 6)
        Text("Checking service status…")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
  }

  private var displayBriefingText: String {
    if let narrative = staffFacingNarrative {
      return narrative.headline
    }
    let override = briefingTextOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty {
      return override
    }
    return snapshot.templateBriefingText
  }

  private var pulseIsActive: Bool {
    externalPulseActive
      || signalCount > 0
      || !snapshot.briefingFacts.isEmpty
      || !snapshot.suggestedActions.isEmpty
      || snapshot.serviceState != .calm
  }

  private var briefingSourceCaption: String? {
    if staffFacingPresentation { return nil }
    guard let briefingSource else { return nil }
    switch briefingSource {
    case .template:
      return nil
    case .localPlaceholder:
      return "Enhanced briefing"
    case .localModel, .repairedLocalModel:
      return "Local model briefing"
    case .failedFallback:
      return "Using template fallback"
    }
  }

  private var attentionItems: [ManagerAttentionItem] {
    ManagerAttentionItemBuilder.build(
      from: snapshot,
      presentation: attentionPresentation,
      maxItems: 3,
      compactPresentation: staffFacingPresentation,
      briefingText: displayBriefingText
    )
  }

  private var visibleCompactPrompts: [HostOperationalBriefingPrompt] {
    guard attentionItems.isEmpty else { return [] }
    return ManagerAttentionItemBuilder.nonRedundantPrompts(
      briefingText: displayBriefingText,
      prompts: compactOperationalPrompts
    )
  }

  private var signalCount: Int {
    snapshot.briefingFacts.count
      + snapshot.guestSignals.count
      + snapshot.tableSignals.count
      + snapshot.seatedTimingSignals.count
  }

  private var renderTraceKey: String {
    [
      cardRenderSource,
      "\(attentionItems.count)",
      "\(attentionPresentation.secondaryContext.count)",
      attentionPresentation.presentationFingerprint,
      displayBriefingText
    ].joined(separator: "|")
  }

  private var cardRenderSource: String {
    switch briefingSource {
    case .localModel, .repairedLocalModel:
      return "localModel3B"
    case .failedFallback:
      return "fallbackTemplate"
    case .template, .localPlaceholder, nil:
      return attentionPresentation.hasVisibleContent ? "groupedTemplate" : "fallbackTemplate"
    }
  }

  private var renderTraceView: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .onAppear {
        logRenderTrace()
      }
      .onChange(of: renderTraceKey) { _, _ in
        logRenderTrace()
      }
  }

  private func logRenderTrace() {
    #if DEBUG
    print(
      "[HOST_CARD_RENDER_TRACE] source=\(cardRenderSource) rows=\(attentionItems.count) context=\(attentionPresentation.secondaryContext.count)"
    )
    #endif
  }

  @ViewBuilder
  private var compactPromptLines: some View {
    if showOperationalReview, !visibleCompactPrompts.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(visibleCompactPrompts) { prompt in
          Text(prompt.body)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  @ViewBuilder
  private var reviewIntelligenceButton: some View {
    if showOperationalReview, onReviewTapped != nil {
      Button(staffFacingPresentation ? "Review details" : "Review Intelligence") {
        onReviewTapped?()
      }
      .font(.caption.weight(.semibold))
    }
  }
}

// MARK: - Card Style

private extension View {
  func cardStyle() -> some View {
    padding(.horizontal, 10)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
