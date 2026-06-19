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
  var reservations: [ReservationRecord] = []
  var knownReservations: [ReservationRecord] = []
  var reminderInlineContext: HostIntelligenceReminderInlineContext? = nil
  var presentationStyle: HostIntelligencePresentationStyle = .fullCard
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
        HostIntelligenceMark(isActive: pulseIsActive, size: 26)
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
          compactReviewButton
        }
        .fixedSize(horizontal: true, vertical: false)
      }

      compactInlineLane
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .hostBoardGlassPanel(cornerRadius: 16, strokeOpacity: 0.12)
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
    if let deterministicHeadline = HostIntelligenceInlineItemBuilder.headline(
      snapshot: snapshot,
      reservations: reservations,
      items: inlineItems
    ) {
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

  private var inlineItems: [HostIntelligenceInlineItem] {
    HostIntelligenceInlineItemBuilder.build(
      snapshot: snapshot,
      reservations: reservations,
      knownReservations: knownReservations,
      reminderContext: reminderInlineContext
    )
  }

  private var visibleInlineItems: [HostIntelligenceInlineItem] {
    HostIntelligenceInlineItemBuilder.visibleItems(
      from: inlineItems,
      maxVisible: 4,
      includeMoreItem: onReviewTapped != nil
    )
  }

  private var animatedPrimaryInlineItemID: String? {
    visibleInlineItems.first(where: isPrimaryInlineCandidate)?.id
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
      "\(attentionItems.count)",
      "\(visibleInlineItems.count)",
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

  private var hasCompactReviewContent: Bool {
    onReviewTapped != nil
      && (showOperationalReview
        || !attentionItems.isEmpty
        || !attentionPresentation.secondaryContext.isEmpty
        || !snapshot.suggestedActions.isEmpty
        || staffFacingNarrative?.hasStructuredDetail == true
        || !compactOperationalPrompts.isEmpty)
  }

  private var compactStateChip: some View {
    Text(compactStateTitle)
      .font(.caption2.weight(.medium))
      .foregroundStyle(.primary.opacity(0.76))
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .hostBoardGlassCapsule(strokeOpacity: 0.10)
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var compactInlineLane: some View {
    if !visibleInlineItems.isEmpty {
      FlowLayout(spacing: 7) {
        ForEach(visibleInlineItems) { item in
          compactInlineItem(item)
        }
      }
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

  private func isPrimaryInlineCandidate(_ item: HostIntelligenceInlineItem) -> Bool {
    switch item.kind {
    case .allergy, .accessibility, .guestNote, .noTable, .possibleCorrection, .serviceSummary, .cleanup:
      return true
    case .reminder:
      return item.priority <= 26
    case .seatedTooLong:
      return true
    case .busyTime:
      return item.priority <= 30
    case .nextGuest, .returningGuest, .occasion, .tableSuggestion, .calm:
      return false
    }
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
          .hostBoardGlassCapsule(strokeOpacity: 0.14)
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
          .hostBoardGlassCapsule(strokeOpacity: 0.12)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .accessibilityLabel("Review Host Intelligence details")
    }
  }
}

private struct HostIntelligenceMark: View {
  let isActive: Bool
  let size: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var breatheExpanded = false
  @State private var glowLifted = false

  private var breatheMin: CGFloat { isActive ? 0.94 : 0.97 }
  private var breatheMax: CGFloat { isActive ? 1.06 : 1.03 }
  private var breatheDuration: Double { isActive ? 1.6 : 2.2 }
  private var ringSpeed: Double { isActive ? 32 : 16 }
  private var glowOpacityLow: Double { isActive ? 0.22 : 0.14 }
  private var glowOpacityHigh: Double { isActive ? 0.40 : 0.26 }

  var body: some View {
    ZStack {
      glowLayer
        .scaleEffect(breatheScale)
        .opacity(glowOpacity)

      HostIntelligenceMarkRing(
        size: size,
        isActive: isActive,
        ringSpeed: ringSpeed,
        reduceMotion: reduceMotion
      )
      .scaleEffect(breatheScale)

      centerLayer
        .scaleEffect(centerBreathScale)
    }
    .frame(width: size, height: size)
    .onAppear { syncAnimations() }
    .onChange(of: isActive) { _, _ in syncAnimations() }
    .onChange(of: reduceMotion) { _, _ in syncAnimations() }
  }

  private var breatheScale: CGFloat {
    reduceMotion ? 1 : (breatheExpanded ? breatheMax : breatheMin)
  }

  private var centerBreathScale: CGFloat {
    guard !reduceMotion else { return 1 }
    return breatheExpanded ? (isActive ? 1.04 : 1.02) : (isActive ? 0.97 : 0.99)
  }

  private var glowOpacity: Double {
    reduceMotion ? glowOpacityLow : (glowLifted ? glowOpacityHigh : glowOpacityLow)
  }

  private var glowLayer: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [
            Color.white.opacity(0.88),
            Color.cyan.opacity(isActive ? 0.44 : 0.28),
            Color.pink.opacity(isActive ? 0.18 : 0.10),
            Color.clear
          ],
          center: .center,
          startRadius: 1,
          endRadius: size * 0.58
        )
      )
      .blur(radius: 2.5)
  }

  private var centerLayer: some View {
    Circle()
      .fill(.ultraThinMaterial)
      .overlay {
        Circle()
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.74),
                Color.cyan.opacity(isActive ? 0.28 : 0.18),
                Color.pink.opacity(isActive ? 0.18 : 0.10)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .blendMode(.plusLighter)
      }
      .frame(width: size * 0.42, height: size * 0.42)
      .shadow(color: Color.cyan.opacity(isActive ? 0.18 : 0.08), radius: 3)
  }

  private func syncAnimations() {
    breatheExpanded = false
    glowLifted = false
    guard !reduceMotion else { return }

    withAnimation(.easeInOut(duration: breatheDuration).repeatForever(autoreverses: true)) {
      breatheExpanded = true
    }
    withAnimation(.easeInOut(duration: breatheDuration * 0.9).repeatForever(autoreverses: true)) {
      glowLifted = true
    }
  }
}

/// Rotates a fixed gradient ring via `rotationEffect` only — avoids rebuilding gradients every frame.
private struct HostIntelligenceMarkRing: View {
  let size: CGFloat
  let isActive: Bool
  let ringSpeed: Double
  let reduceMotion: Bool

  var body: some View {
    Group {
      if reduceMotion {
        ring
      } else {
        TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { context in
          ring
            .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * ringSpeed))
        }
      }
    }
  }

  private var ring: some View {
    Circle()
      .stroke(
        AngularGradient(
          colors: [
            Color.white.opacity(0.70),
            Color.cyan.opacity(isActive ? 0.58 : 0.38),
            Color.indigo.opacity(isActive ? 0.48 : 0.30),
            Color.pink.opacity(isActive ? 0.42 : 0.22),
            Color.white.opacity(0.70)
          ],
          center: .center
        ),
        lineWidth: 1.1
      )
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
