//
//  HostIntelligenceCard.swift
//  Tryzub Reservations
//
//  Read-only Host Intelligence briefing card for the Host board.
//

import SwiftUI

enum HostIntelligencePresentationStyle {
  case fullCard
  case compactStrip
}

struct HostIntelligenceCard: View {
  let snapshot: HostDecisionSnapshot
  var presentation: HostIntelligenceCardPresentation = .empty
  var presentationStyle: HostIntelligencePresentationStyle = .fullCard
  var attentionPresentation: HostAttentionPresentation = .empty
  var briefingTextOverride: String? = nil
  var managerNarrative: ManagerNarrative? = nil
  var briefingSource: HostBriefingWriterSource? = nil
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
    switch presentationStyle {
    case .fullCard:
      if isCalmPresentation {
        calmCard
      } else {
        activeCard
      }
    case .compactStrip:
      compactStrip
    }
  }

  // MARK: - Layout

  private var compactStrip: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .center, spacing: 9) {
        HostIntelligenceStaticMark(isActive: pulseIsActive, size: 26)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 2) {
          Text(compactOperationalSentence)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.90)
            .fixedSize(horizontal: false, vertical: true)

          if isRefreshingAttentionCard {
            Text("Refreshing")
              .font(.caption2)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: 6) {
          compactStateChip
          compactPrimaryActionChip
          if !staffFacingPresentation {
            compactReviewButton
          }
        }
        .fixedSize(horizontal: true, vertical: false)
      }

      compactInlineLane
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .hostIntelligenceCompactPanel(cornerRadius: 16)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(compactStateTitle). \(compactOperationalSentence)")
    .background(renderTraceView)
  }

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

      if !presentation.attentionItems.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(presentation.attentionItems) { item in
            attentionRow(item)
          }
        }
      }

      if presentation.attentionItems.isEmpty, !attentionPresentation.secondaryContext.isEmpty {
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

  private var compactStateTitle: String {
    if snapshot.briefingFacts.contains(where: {
      $0.severity == .critical || $0.category == .overdue
    }) {
      return "Attention"
    }

    if !snapshot.briefingFacts.isEmpty || !snapshot.suggestedActions.isEmpty {
      switch snapshot.serviceState {
      case .critical: return "Very busy"
      case .busy: return "Busy"
      case .building, .calm: return "Attention"
      }
    }

    switch snapshot.serviceState {
    case .calm: return "Quiet"
    case .building: return "Picking up"
    case .busy: return "Busy"
    case .critical: return "Very busy"
    }
  }

  private var compactOperationalSentence: String {
    if let deterministicHeadline = presentation.headline {
      return compactSentence(from: deterministicHeadline)
    }

    if let headline = staffFacingNarrative?.headline.trimmingCharacters(in: .whitespacesAndNewlines),
       !headline.isEmpty {
      return compactSentence(from: headline)
    }

    let override = briefingTextOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty, !isDefaultQuietLine(override) {
      return compactSentence(from: override)
    }

    let template = snapshot.templateBriefingText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !template.isEmpty, !isDefaultQuietLine(template) {
      return compactSentence(from: template)
    }

    return "Service is quiet right now."
  }

  private func compactSentence(from text: String) -> String {
    let singleLine = text
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !singleLine.isEmpty else { return "Service is quiet right now." }

    let terminalCharacters = CharacterSet(charactersIn: ".!?")
    if let end = singleLine.rangeOfCharacter(from: terminalCharacters) {
      return String(singleLine[...end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return singleLine
  }

  private func isDefaultQuietLine(_ text: String) -> Bool {
    HostStaffLanguage.areSameStaffMeaning(text, HostDecisionSnapshot.empty.templateBriefingText)
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

        if presentation.attentionItems.isEmpty,
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
      return nil
    }
    if renderState != .ready,
       managerNarrative.headline == ManagerNarrative.empty.headline {
      return nil
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
      EmptyView()
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

  private var signalCount: Int {
    snapshot.briefingFacts.count
      + snapshot.guestSignals.count
      + snapshot.tableSignals.count
      + snapshot.seatedTimingSignals.count
  }

  private var animatedPrimaryInlineItemID: String? {
    presentation.primaryActionID
  }

  private var compactPrimaryAction: HostSuggestedAction? {
    guard let action = HostIntelligenceActionLabelPolicy.primaryAction(
      from: attentionPresentation,
      snapshot: snapshot
    ) else {
      return nil
    }

    if action.kind == .closeSlot {
      return onReviewTapped == nil ? nil : action
    }

    return onActionTapped == nil ? nil : action
  }

  private var renderTraceKey: String {
    [
      cardRenderSource,
      "\(presentation.attentionItems.count)",
      "\(presentation.visibleItems.count)",
      "\(attentionPresentation.secondaryContext.count)",
      attentionPresentation.presentationFingerprint,
      displayBriefingText
    ].joined(separator: "|")
  }

  private var cardRenderSource: String {
    switch briefingSource {
    case .localModel, .repairedLocalModel:
      return "model"
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
      "[HOST_CARD_RENDER_TRACE] source=\(cardRenderSource) rows=\(presentation.attentionItems.count) context=\(attentionPresentation.secondaryContext.count) presentation=\(presentation.key)"
    )
    #endif
  }

  @ViewBuilder
  private var compactPromptLines: some View {
    if showOperationalReview, !presentation.visibleCompactPrompts.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(presentation.visibleCompactPrompts) { prompt in
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

  private var hasCompactReviewContent: Bool {
    onReviewTapped != nil
      && (showOperationalReview
        || !presentation.attentionItems.isEmpty
        || !attentionPresentation.secondaryContext.isEmpty
        || !snapshot.suggestedActions.isEmpty
        || staffFacingNarrative?.hasStructuredDetail == true
        || presentation.hasCompactPrompts)
  }

  private var compactStateChip: some View {
    Text(compactStateTitle)
      .font(.caption2.weight(.medium))
      .foregroundStyle(.primary.opacity(0.76))
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .hostIntelligenceCompactCapsule(strokeOpacity: 0.08)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var compactInlineLane: some View {
    if !presentation.visibleItems.isEmpty {
      ScrollView(.horizontal) {
        HStack(spacing: 7) {
          ForEach(presentation.visibleItems) { item in
            compactInlineItem(item)
          }
        }
      }
      .scrollIndicators(.hidden)
      .padding(.top, 1)
      .accessibilityElement(children: .contain)
    }
  }

  @ViewBuilder
  private func compactInlineItem(_ item: HostIntelligenceInlineItem) -> some View {
    let role = inlineVisualRole(for: item)
    let animateBorder = item.id == animatedPrimaryInlineItemID
    if item.opensReview, onReviewTapped != nil {
      Button {
        onReviewTapped?()
      } label: {
        compactInlineItemContent(item, role: role, animateBorder: animateBorder)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(item.title). \(item.detail)")
    } else if let action = item.action, onActionTapped != nil {
      Button {
        if action.kind == .closeSlot {
          onReviewTapped?()
        } else {
          onActionTapped?(action)
        }
      } label: {
        compactInlineItemContent(item, role: role, animateBorder: animateBorder)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(item.title). \(item.detail)")
    } else {
      compactInlineItemContent(item, role: role, animateBorder: animateBorder)
    }
  }

  private func compactInlineItemContent(
    _ item: HostIntelligenceInlineItem,
    role: HostIntelligenceInlineVisualRole,
    animateBorder: Bool
  ) -> some View {
    let tint = inlineTint(for: item)
    return HStack(spacing: 5) {
      Image(systemName: inlineIconName(for: item))
        .font(.caption2.weight(role == .primaryAction ? .bold : .semibold))
        .foregroundStyle(tint.opacity(role == .info ? 0.66 : 0.86))
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
      Text(item.title)
        .font(.caption2.weight(role == .info ? .medium : .semibold))
        .foregroundStyle(role == .info ? .secondary : .primary)
        .lineLimit(1)
      if !item.detail.isEmpty {
        Text(item.detail)
          .font(.caption2.weight(.medium))
          .foregroundStyle(role == .primaryAction ? Color.primary.opacity(0.74) : Color.secondary)
          .lineLimit(1)
      }
    }
    .hostIntelligenceInlineChipChrome(
      role: role,
      tint: tint,
      animateBorder: animateBorder
    )
  }

  private func inlineVisualRole(for item: HostIntelligenceInlineItem) -> HostIntelligenceInlineVisualRole {
    if item.id == animatedPrimaryInlineItemID {
      return .primaryAction
    }
    if item.action != nil || item.opensReview {
      switch item.kind {
      case .nextGuest, .returningGuest, .calm:
        return .info
      default:
        return .secondaryAction
      }
    }
    return .info
  }

  private func inlineIconName(for item: HostIntelligenceInlineItem) -> String {
    switch item.kind {
    case .allergy:
      return "exclamationmark.triangle.fill"
    case .accessibility:
      return "figure.roll"
    case .guestNote:
      return "note.text"
    case .occasion:
      return "sparkles"
    case .noTable:
      return "tablecells"
    case .busyTime:
      return "clock"
    case .possibleCorrection:
      return "arrow.triangle.2.circlepath"
    case .reminder:
      return "bell"
    case .seatedTooLong:
      return "timer"
    case .serviceSummary:
      return "doc.text"
    case .returningGuest:
      return "person.crop.circle.badge.checkmark"
    case .nextGuest:
      return "person.fill"
    case .tableSuggestion:
      return "rectangle.split.2x1"
    case .cleanup:
      return "checklist"
    case .calm:
      return "ellipsis"
    }
  }

  private func inlineTint(for item: HostIntelligenceInlineItem) -> Color {
    switch item.kind {
    case .allergy, .accessibility:
      return .red
    case .guestNote, .occasion, .possibleCorrection, .reminder:
      return TryzubColors.warning
    case .noTable, .seatedTooLong, .cleanup:
      return TryzubColors.info
    case .busyTime:
      return TryzubColors.warning
    case .returningGuest, .nextGuest, .serviceSummary, .tableSuggestion, .calm:
      return TryzubColors.mutedText
    }
  }

  @ViewBuilder
  private var compactPrimaryActionChip: some View {
    if let action = compactPrimaryAction {
      Button {
        if action.kind == .closeSlot {
          onReviewTapped?()
        } else {
          onActionTapped?(action)
        }
      } label: {
        Text(HostIntelligenceActionLabelPolicy.label(for: action))
          .font(.caption2.weight(.semibold))
          .lineLimit(1)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .hostIntelligenceCompactCapsule(strokeOpacity: 0.10)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .accessibilityLabel(HostIntelligenceActionLabelPolicy.label(for: action))
    }
  }

  @ViewBuilder
  private var compactReviewButton: some View {
    if hasCompactReviewContent {
      Button {
        onReviewTapped?()
      } label: {
        Text("Review")
          .font(.caption2.weight(.medium))
          .lineLimit(1)
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .hostIntelligenceCompactCapsule(strokeOpacity: 0.09)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .accessibilityLabel("Review Host Intelligence details")
    }
  }
}

private struct HostIntelligenceStaticMark: View {
  let isActive: Bool
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(Color(.secondarySystemGroupedBackground))
      Circle()
        .strokeBorder(Color.accentColor.opacity(isActive ? 0.34 : 0.18), lineWidth: 1)
      Image(systemName: isActive ? "sparkles" : "circle.dotted")
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(Color.accentColor.opacity(isActive ? 0.82 : 0.56))
    }
    .frame(width: size, height: size)
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
