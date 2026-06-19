//
//  HostIntelligenceReviewView.swift
//  Tryzub Reservations
//
//  Read-only expanded Host Intelligence review for staff.
//

import SwiftUI

struct HostIntelligenceReviewView: View {
  let snapshot: HostDecisionSnapshot
  var reservations: [ReservationRecord] = []
  let operationalPrompts: [HostOperationalBriefingPrompt]
  let briefingText: String
  let briefingSource: HostBriefingWriterSource?
  var onActionTapped: ((HostSuggestedAction) -> Void)? = nil

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        nowSection
        needsActionSection
        guestsToKnowSection
        notesAndWarningsSection
        busyTimesSection
        floorTableIssuesSection
        whyThisMattersSection
        afterServiceSummarySection
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Host review")
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

  private var nowSection: some View {
    reviewSection("Now") {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(serviceStateTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(serviceStateColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .hostBoardGlassCapsule(strokeOpacity: 0.10)

          Text("Updated \(generatedAtText)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }

        Text(staffFacingNarrative.headline)
          .font(.body.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)

        if let why = staffFacingNarrative.whyItMatters?.trimmingCharacters(in: .whitespacesAndNewlines),
           !why.isEmpty {
          Text(why)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .reviewCardStyle()
    }
  }

  @ViewBuilder
  private var needsActionSection: some View {
    let actions = actionableReviewActions
    reviewSection("Needs action") {
      if operationalPrompts.isEmpty && actions.isEmpty {
        Text("Nothing needs action right now.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .reviewCardStyle()
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(operationalPrompts.prefix(5))) { prompt in
            promptRow(prompt)
          }

          ForEach(actions.prefix(5)) { action in
            actionButton(action)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var guestsToKnowSection: some View {
    reviewSection("Guests to know") {
      if groupedGuestSignals.isEmpty {
        Text("No guest notes need special attention.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .reviewCardStyle()
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(groupedGuestSignals.prefix(6)) { group in
            guestSignalRow(group)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var notesAndWarningsSection: some View {
    let facts = noteAndWarningFacts
    reviewSection("Notes and warnings") {
      if facts.isEmpty {
        Text("No extra notes or warnings are active.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .reviewCardStyle()
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(facts.prefix(6)) { fact in
            factRow(fact)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var busyTimesSection: some View {
    let pressures = busySlotPressures
    reviewSection("Busy times") {
      if pressures.isEmpty {
        Text("No busy arrival windows stand out.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .reviewCardStyle()
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(pressures.prefix(6)) { pressure in
            busyTimeRow(pressure)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var floorTableIssuesSection: some View {
    let tableRows = floorTableRows
    reviewSection("Floor/table issues") {
      if tableRows.isEmpty {
        Text("No floor or table issues are active.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .reviewCardStyle()
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(tableRows.prefix(6)) { row in
            floorTableRow(row)
          }
        }
      }
    }
  }

  private var whyThisMattersSection: some View {
    reviewSection("Why this matters") {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(whyEvidenceLines, id: \.self) { line in
          HStack(alignment: .top, spacing: 8) {
            Circle()
              .fill(TryzubColors.mutedText.opacity(0.55))
              .frame(width: 5, height: 5)
              .padding(.top, 7)
            Text(line)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .reviewCardStyle()
    }
  }

  @ViewBuilder
  private var afterServiceSummarySection: some View {
    if let summary = afterServiceSummary {
      reviewSection("After-service summary") {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(summary, id: \.self) { line in
            Text(line)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .reviewCardStyle()
      }
    }
  }

  // MARK: - Rows

  private func promptRow(_ prompt: HostOperationalBriefingPrompt) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(prompt.title)
        .font(.subheadline.weight(.semibold))
      Text(prompt.body)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if !prompt.relatedReservationIDs.isEmpty {
        Text("\(prompt.relatedReservationIDs.count) \(prompt.relatedReservationIDs.count == 1 ? "reservation" : "reservations")")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.tertiary)
      }
    }
    .reviewCardStyle()
  }

  @ViewBuilder
  private func actionButton(_ action: HostSuggestedAction) -> some View {
    if action.kind == .closeSlot {
      actionRow(action, isTappable: false)
    } else if let onActionTapped {
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

  private func actionRow(_ action: HostSuggestedAction, isTappable: Bool) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 5) {
        Text(HostIntelligenceActionLabelPolicy.reviewTitle(for: action))
          .font(.subheadline.weight(.semibold))
          .multilineTextAlignment(.leading)
        let reason = HostStaffLanguage.rewrite(action.reason)
        if !reason.isEmpty {
          Text(reason)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(HostIntelligenceActionLabelPolicy.label(for: action))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.tertiary)
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

  @ViewBuilder
  private func guestSignalRow(_ group: GuestSignalGroup) -> some View {
    let action = actionForReservation(group.reservationID)
    if let action, let onActionTapped {
      Button {
        onActionTapped(action)
        dismiss()
      } label: {
        guestSignalContent(group, isTappable: true)
      }
      .buttonStyle(.plain)
    } else {
      guestSignalContent(group, isTappable: false)
    }
  }

  private func guestSignalContent(_ group: GuestSignalGroup, isTappable: Bool) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 7) {
        Text(group.guestName)
          .font(.subheadline.weight(.semibold))
        Text(group.reason)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        badgeWrap(group.badges)
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

  private func factRow(_ fact: HostBriefingFact) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      badgeWrap([badgeLabel(for: fact.category)])
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

  private func busyTimeRow(_ pressure: HostSlotPressure) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(displaySlotTime(pressure.slotTime))
          .font(.subheadline.weight(.semibold))
          .monospacedDigit()
        Text(pressureSeverityLabel(pressure.severity))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(pressureSeverityColor(pressure.severity))
      }

      Text(busyTimeSummary(pressure))
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if pressure.suggestedActions.contains(where: { $0.kind == .closeSlot }) {
        badgeWrap(["Review busy time"])
      }
    }
    .reviewCardStyle()
  }

  @ViewBuilder
  private func floorTableRow(_ row: FloorTableReviewRow) -> some View {
    if let action = row.action, let onActionTapped {
      Button {
        onActionTapped(action)
        dismiss()
      } label: {
        floorTableContent(row, isTappable: true)
      }
      .buttonStyle(.plain)
    } else {
      floorTableContent(row, isTappable: false)
    }
  }

  private func floorTableContent(_ row: FloorTableReviewRow, isTappable: Bool) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 5) {
        Text(row.title)
          .font(.subheadline.weight(.semibold))
        if let detail = row.detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        badgeWrap([row.badge])
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

  private func badgeWrap(_ badges: [String]) -> some View {
    FlowLayout(spacing: 6) {
      ForEach(badges.stableUnique(), id: \.self) { badge in
        Text(badge)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .hostBoardGlassCapsule(strokeOpacity: 0.10)
      }
    }
  }

  private func reviewSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Derived Content

  private var actionableReviewActions: [HostSuggestedAction] {
    dedupedActions.filter { action in
      action.kind != .noAction
        && !isCoveredByPrompts(action)
    }
  }

  private var dedupedActions: [HostSuggestedAction] {
    var seen = Set<String>()
    var results: [HostSuggestedAction] = []
    for action in snapshot.suggestedActions {
      let titleKey = HostIntelligenceActionLabelPolicy.reviewTitle(for: action).lowercased()
      let reasonKey = HostStaffLanguage.rewrite(action.reason).lowercased()
      let key = "\(action.kind.rawValue)|\(titleKey)|\(reasonKey)|\(action.relatedReservationIDs.map(String.init).joined(separator: ","))|\(action.targetSlotTime ?? "")"
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      results.append(action)
    }
    return results
  }

  private var groupedGuestSignals: [GuestSignalGroup] {
    let grouped = Dictionary(grouping: snapshot.guestSignals, by: \.reservationID)
    return grouped.values.compactMap { signals in
      guard let first = signals.sorted(by: signalSort).first else { return nil }
      let sorted = signals.sorted(by: signalSort)
      return GuestSignalGroup(
        reservationID: first.reservationID,
        guestName: first.guestName,
        reason: HostStaffLanguage.rewrite(sorted.first?.message ?? first.message),
        badges: sorted.map { badgeLabel(for: $0.kind) }.stableUnique(),
        priority: sorted.map(\.severity.rank).min() ?? HostSeverity.info.rank
      )
    }
    .sorted {
      if $0.priority != $1.priority { return $0.priority < $1.priority }
      return $0.guestName.localizedCaseInsensitiveCompare($1.guestName) == .orderedAscending
    }
  }

  private var noteAndWarningFacts: [HostBriefingFact] {
    dedupedReviewFacts.filter { fact in
      switch fact.category {
      case .note, .preference, .duplicate, .sync, .cancellation, .bookingDecision, .guest, .allergy:
        return true
      default:
        return fact.severity == .warning || fact.severity == .critical
    }
    }
  }

  private var busySlotPressures: [HostSlotPressure] {
    snapshot.slotPressures
      .filter { $0.reservationCount > 0 || $0.guestCount > 0 || $0.severity != .calm }
      .sorted {
        if pressureRank($0.severity) != pressureRank($1.severity) {
          return pressureRank($0.severity) < pressureRank($1.severity)
        }
        return $0.slotTime < $1.slotTime
      }
  }

  private var floorTableRows: [FloorTableReviewRow] {
    var rows: [FloorTableReviewRow] = []

    for signal in snapshot.tableSignals {
      rows.append(
        FloorTableReviewRow(
          id: signal.id,
          title: HostStaffLanguage.rewrite(signal.title),
          detail: HostStaffLanguage.rewrite(signal.detail),
          badge: tableBadgeLabel(for: signal.kind),
          reservationID: signal.relatedReservationIDs.first,
          action: actionForReservation(signal.relatedReservationIDs.first)
        )
      )
    }

    for signal in snapshot.seatedTimingSignals {
      rows.append(
        FloorTableReviewRow(
          id: signal.id,
          title: signal.guestName,
          detail: HostStaffLanguage.rewrite(signal.message),
          badge: "Seated timing",
          reservationID: signal.reservationID,
          action: actionForReservation(signal.reservationID)
        )
      )
    }

    for action in dedupedActions where action.kind == .assignTable {
      rows.append(
        FloorTableReviewRow(
          id: "action-\(action.id)",
          title: HostIntelligenceActionLabelPolicy.reviewTitle(for: action),
          detail: HostStaffLanguage.rewrite(action.reason),
          badge: HostIntelligenceActionLabelPolicy.label(for: action),
          reservationID: action.relatedReservationIDs.first,
          action: action
        )
      )
    }

    return rows.stableDedupe()
  }

  private var whyEvidenceLines: [String] {
    var lines: [String] = []
    let grounding = snapshot.serviceGrounding
    if grounding.activeReservationCount > 0 || grounding.expectedGuestCount > 0 {
      lines.append("\(grounding.activeReservationCount) active reservations and \(grounding.expectedGuestCount) expected guests are in the current service picture.")
    }
    if !groupedGuestSignals.isEmpty {
      lines.append("\(groupedGuestSignals.count) guest \(groupedGuestSignals.count == 1 ? "signal needs" : "signals need") staff awareness before service moves.")
    }
    if let busiest = busySlotPressures.first {
      lines.append("\(displaySlotTime(busiest.slotTime)) has \(busiest.reservationCount) reservations and \(busiest.guestCount) guests.")
    }
    let noTableCount = snapshot.tableSignals.filter { $0.kind == .noTableAssigned }.count
    if noTableCount > 0 {
      lines.append("\(noTableCount) \(noTableCount == 1 ? "reservation still needs" : "reservations still need") a table.")
    }
    if lines.isEmpty {
      lines.append("Current reservations do not show a staff action that needs attention.")
    }
    return lines.stableUnique()
  }

  private var afterServiceSummary: [String]? {
    let visible = reservations.filter { !$0.isHidden }
    guard !visible.isEmpty, visible.allSatisfy({ !$0.isExpectedGuest }) else { return nil }
    let completed = visible.filter { $0.statusValue == .completed }.count
    let cancelled = visible.filter { $0.statusValue == .cancelled }.count
    let noShows = visible.filter { $0.statusValue == .noShow }.count
    let guests = visible
      .filter { $0.statusValue != .cancelled && $0.statusValue != .noShow }
      .reduce(0) { $0 + max(0, $1.partySize) }
    let noteCount = visible.filter { $0.hasGuestNotes || $0.hasStaffNotes }.count
    let noTableCompleted = visible.filter { $0.statusValue == .completed && !$0.hasTableAssignment }.count
    var lines = [
      "\(visible.count) reservations · \(guests) expected guests.",
      "\(completed) completed · \(cancelled) cancelled · \(noShows) no-show."
    ]
    if noteCount > 0 {
      lines.append("\(noteCount) \(noteCount == 1 ? "reservation had" : "reservations had") guest or staff notes.")
    }
    if noTableCompleted > 0 {
      lines.append("\(noTableCompleted) completed \(noTableCompleted == 1 ? "reservation never had" : "reservations never had") a table picked.")
    }
    if let busiest = busySlotPressures.first {
      lines.append("Busiest window: \(displaySlotTime(busiest.slotTime)) · \(busiest.guestCount) guests.")
    }
    return lines
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

  // MARK: - Helpers

  private var serviceStateTitle: String {
    switch snapshot.serviceState {
    case .calm: return "Calm service"
    case .building: return "Picking up"
    case .busy: return "Busy service"
    case .critical: return "Very busy service"
    }
  }

  private var serviceStateColor: Color {
    switch snapshot.serviceState {
    case .calm: return .secondary
    case .building: return TryzubColors.mutedText
    case .busy: return TryzubColors.warning
    case .critical: return .red
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
        whyItMatters: template.whyItMatters,
        checkNext: template.checkNext,
        source: template.source,
        failedReason: nil
      )
    }
    return template
  }

  private func isCoveredByPrompts(_ action: HostSuggestedAction) -> Bool {
    let title = HostIntelligenceActionLabelPolicy.reviewTitle(for: action).lowercased()
    let reason = HostStaffLanguage.rewrite(action.reason).lowercased()
    return operationalPrompts.contains { prompt in
      let promptText = "\(prompt.title) \(prompt.body)".lowercased()
      return promptText.contains(title) || (!reason.isEmpty && promptText.contains(reason))
    }
  }

  private func actionForReservation(_ reservationID: Int?) -> HostSuggestedAction? {
    guard let reservationID else { return nil }
    return dedupedActions.first { action in
      action.kind != .closeSlot
        && action.kind != .noAction
        && action.relatedReservationIDs.contains(reservationID)
    }
  }

  private func signalSort(_ lhs: HostGuestSignal, _ rhs: HostGuestSignal) -> Bool {
    if lhs.severity.rank != rhs.severity.rank {
      return lhs.severity.rank < rhs.severity.rank
    }
    return badgeLabel(for: lhs.kind) < badgeLabel(for: rhs.kind)
  }

  private func displaySlotTime(_ value: String) -> String {
    if let date = ReservationFormatters.apiTime.date(from: value) {
      return ReservationFormatters.shortTime.string(from: date)
    }
    return String(value.prefix(5))
  }

  private func busyTimeSummary(_ pressure: HostSlotPressure) -> String {
    var parts = [
      "\(pressure.reservationCount) \(pressure.reservationCount == 1 ? "reservation" : "reservations")",
      "\(pressure.guestCount) \(pressure.guestCount == 1 ? "guest" : "guests")"
    ]
    if pressure.largePartyCount > 0 {
      parts.append("\(pressure.largePartyCount) large \(pressure.largePartyCount == 1 ? "party" : "parties")")
    }
    if pressure.noTableCount > 0 {
      parts.append("\(pressure.noTableCount) \(pressure.noTableCount == 1 ? "still needs" : "still need") tables")
    }
    return parts.joined(separator: " · ")
  }

  private func pressureSeverityLabel(_ severity: HostPressureSeverity) -> String {
    switch severity {
    case .critical: return "Very busy"
    case .busy: return "Busy"
    case .watch: return "Watch"
    case .calm: return "Quiet"
    }
  }

  private func pressureSeverityColor(_ severity: HostPressureSeverity) -> Color {
    switch severity {
    case .critical: return .red
    case .busy: return TryzubColors.warning
    case .watch: return TryzubColors.mutedText
    case .calm: return .secondary
    }
  }

  private func pressureRank(_ severity: HostPressureSeverity) -> Int {
    switch severity {
    case .critical: return 0
    case .busy: return 1
    case .watch: return 2
    case .calm: return 3
    }
  }

  private func badgeLabel(for kind: HostGuestSignalKind) -> String {
    switch kind {
    case .allergy: return "Allergy"
    case .possibleDuplicate: return "Possible correction"
    case .regularGuest, .importantGuest, .vip: return "Returning"
    case .accessibility: return "Accessibility"
    case .specialOccasion: return "Occasion"
    case .seatingPreference: return "Guest note"
    case .noteReminder: return "Staff note"
    case .previousServiceIssue: return "Service issue"
    case .cancellationRisk: return "Cancellation risk"
    case .noShowRisk: return "No-show risk"
    case .manualCallIn: return "Staff note"
    case .unknown: return "Note"
    }
  }

  private func badgeLabel(for category: HostFactCategory) -> String {
    switch category {
    case .allergy: return "Allergy"
    case .duplicate: return "Possible correction"
    case .guest: return "Guest note"
    case .note: return "Staff note"
    case .preference: return "Guest note"
    case .sync: return "System notice"
    case .cancellation: return "Cancellation"
    case .bookingDecision: return "Booking review"
    case .table: return "Table"
    case .capacity: return "Capacity"
    case .largeParty: return "Large party"
    case .arrivalWave: return "Busy time"
    case .overdue: return "Needs action"
    case .opportunity: return "Opportunity"
    case .timing: return "Timing"
    case .analytics: return "Service pattern"
    case .unknown: return "Note"
    }
  }

  private func tableBadgeLabel(for kind: HostTableSignalKind) -> String {
    switch kind {
    case .noTableAssigned: return "No table"
    case .tableTurnRisk: return "Table timing"
    case .doubleBookedTable: return "Double booked"
    case .tableFreed: return "Table opened"
    case .tableCapacityMismatch: return "Capacity"
    case .longSeated: return "Seated long"
    case .cancellationFreedTable: return "Table opened"
    case .unknown: return "Floor note"
    }
  }
}

private struct GuestSignalGroup: Identifiable {
  let reservationID: Int
  let guestName: String
  let reason: String
  let badges: [String]
  let priority: Int

  var id: Int { reservationID }
}

private struct FloorTableReviewRow: Identifiable {
  let id: String
  let title: String
  let detail: String?
  let badge: String
  let reservationID: Int?
  let action: HostSuggestedAction?
}

private extension View {
  func reviewCardStyle() -> some View {
    padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      }
  }
}

private extension Array where Element == String {
  func stableUnique() -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in self {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
      seen.insert(trimmed)
      result.append(trimmed)
    }
    return result
  }
}

private extension Array where Element == FloorTableReviewRow {
  func stableDedupe() -> [FloorTableReviewRow] {
    var seen = Set<String>()
    var result: [FloorTableReviewRow] = []
    for row in self {
      let key = "\(row.reservationID.map(String.init) ?? row.id)|\(row.badge)|\(row.title.lowercased())"
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append(row)
    }
    return result
  }
}
