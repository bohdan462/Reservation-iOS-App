//
//  GuestHistorySemantics.swift
//  Tryzub Reservations
//
//  Shared source-of-truth for guest history and reservation-note copy.
//

import Foundation

enum GuestHistorySemantics {

  // MARK: - Notes

  static func hasActualReservationNotes(_ reservation: ReservationRecord) -> Bool {
    reservation.hasGuestNotes || reservation.hasStaffNotes
  }

  static func combinedNoteText(for reservation: ReservationRecord) -> String {
    [reservation.guestNotes, reservation.staffNotes]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  static func hasOccasionNoteText(for reservation: ReservationRecord) -> Bool {
    let text = combinedNoteText(for: reservation)
    guard !text.isEmpty else { return false }
    if HostGuestNoteSnippetExtractor.specialOccasionSnippet(from: text) != nil {
      return true
    }
    let lower = text.lowercased()
    return specialOccasionKeywords.contains(where: { lower.contains($0) })
  }

  static func backendNoteFlagIsActionable(
    _ flag: Bool,
    reservation: ReservationRecord,
    requiresOccasionKeywords: Bool = false
  ) -> Bool {
    guard flag else { return false }
    guard hasActualReservationNotes(reservation) else { return false }
    if requiresOccasionKeywords {
      return hasOccasionNoteText(for: reservation)
    }
    return true
  }

  static func hasExplicitAllergyLanguage(in text: String) -> Bool {
    let lower = text.lowercased()
    return explicitAllergyKeywords.contains { keyword in
      lower.contains(keyword)
    }
  }

  static func hasDietaryPreferenceLanguage(in text: String) -> Bool {
    let lower = text.lowercased()
    return dietaryPreferenceKeywords.contains { keyword in
      lower.contains(keyword)
    }
  }

  static func backendAllergyFlagIsActionable(
    _ flag: Bool,
    reservation: ReservationRecord
  ) -> Bool {
    guard backendNoteFlagIsActionable(flag, reservation: reservation) else { return false }
    let text = combinedNoteText(for: reservation)
    guard !text.isEmpty else { return false }
    if hasDietaryPreferenceLanguage(in: text), !hasExplicitAllergyLanguage(in: text) {
      return false
    }
    return hasExplicitAllergyLanguage(in: text)
  }

  static func occasionNoteTitle(for reservation: ReservationRecord) -> String {
    let lower = combinedNoteText(for: reservation).lowercased()
    if lower.contains("birthday") { return "Birthday note" }
    if lower.contains("anniversary") { return "Anniversary note" }
    if lower.contains("bachelor party") || lower.contains("bachelorette") {
      return "Occasion note"
    }
    if lower.contains("graduation") || lower.contains("celebration") {
      return "Occasion note"
    }
    return "Guest note"
  }

  static func occasionNoteMessage(
    guestName: String,
    reservation: ReservationRecord
  ) -> String {
    let text = combinedNoteText(for: reservation)
    let lower = text.lowercased()
    if lower.contains("birthday") {
      return "\(guestName) mentioned a birthday."
    }
    if lower.contains("anniversary") {
      return "\(guestName) mentioned an anniversary."
    }
    if text.count <= 80, !text.isEmpty {
      return text
    }
    return "\(guestName) has a guest note attached."
  }

  struct DetailInsightLine: Equatable {
    let title: String
    let detail: String
  }

  struct DetailInsightPresentation: Equatable {
    let historyTitle: String
    let historyDetail: String
    let supplementalLines: [DetailInsightLine]
  }

  enum MergedHistorySource: String, Equatable {
    case localReliablePriorVisits = "local_reliable_prior"
    case backendSeenBefore = "backend_seen_before"
    case backendFirstTime = "backend_first_time"
    case unknownNotLoaded = "unknown_not_loaded"
    case unknownNoSummary = "unknown_no_summary"
    case localIncomplete = "local_incomplete"
  }

  enum GuestInsightsMetricsSource: String, Equatable {
    case backendSummary = "backend_summary"
    case localCache = "local_cache"
    case merged = "merged"
  }

  enum GuestInsightsBookingHistoryScope: String, Equatable {
    case localCacheOnly = "local_cache_only"
    case serverPreviewAvailable = "server_preview_available"
    case serverAndLocal = "server_and_local"
  }

  struct GuestInsightsMetricsPresentation: Equatable {
    let title: String
    let value: String
    let caption: String
    let source: GuestInsightsMetricsSource
  }

  struct GuestInsightsBookingHistoryPresentation: Equatable {
    let scope: GuestInsightsBookingHistoryScope
    let sectionTitle: String
    let scopeNote: String?
  }

  struct GuestInsightsMergedContext: Equatable {
    let historyTitle: String
    let historyDetail: String
    let mergedSource: MergedHistorySource
    let mergedRegularity: GuestRegularityLevel?
    let metrics: GuestInsightsMetricsPresentation
    let bookingHistory: GuestInsightsBookingHistoryPresentation
    let serverLastSeenDisplay: String?
    let traceKey: String
  }

  static func detailTraceSource(for source: MergedHistorySource) -> String {
    switch source {
    case .backendSeenBefore:
      return "server_guest_intelligence"
    case .localReliablePriorVisits:
      return "local_reliable_prior"
    default:
      return source.rawValue
    }
  }

  static func insightsMergedContext(
    guestName: String,
    localReport: GuestInsightReport,
    serverSummary: GuestIntelligenceSummaryDTO?,
    serverAnswered: Bool,
    profileStamp: String,
    profilePack: GuestIntelligenceProfilePackDTO? = nil,
    selectedReservation: ReservationRecord? = nil,
    reservationPool: [ReservationRecord]? = nil
  ) -> GuestInsightsMergedContext {
    let operationalTruth: GuestOperationalTruth.Evaluation? = {
      guard let selectedReservation else { return nil }
      if let reservationPool {
        return GuestOperationalTruth.evaluate(
          surface: "guest_insights",
          selected: selectedReservation,
          reservationPool: reservationPool,
          summary: serverSummary,
          profilePack: profilePack
        )
      }
      return GuestOperationalTruth.evaluate(
        surface: "guest_insights",
        selected: selectedReservation,
        localReport: nil,
        summary: serverSummary,
        profilePack: profilePack
      )
    }()
    let merged = mergedHistoryLine(
      guestName: guestName,
      localReport: localReport,
      serverSummary: serverSummary,
      serverAnswered: serverAnswered,
      profilePack: profilePack,
      selectedReservation: selectedReservation,
      reservationPool: reservationPool,
      truthSurface: "guest_insights",
      operationalTruth: operationalTruth
    )
    let backendSeenBefore = isBackendSeenBefore(
      serverSummary: serverSummary,
      profilePack: profilePack
    )
    return GuestInsightsMergedContext(
      historyTitle: merged.title,
      historyDetail: merged.detail,
      mergedSource: merged.source,
      mergedRegularity: mergedRegularityLevel(
        localReport: localReport,
        serverSummary: serverSummary,
        serverAnswered: serverAnswered,
        profilePack: profilePack,
        selectedReservation: selectedReservation,
        reservationPool: reservationPool,
        operationalTruth: operationalTruth
      ),
      metrics: insightsMetricsPresentation(
        localReport: localReport,
        serverSummary: serverSummary,
        serverAnswered: serverAnswered,
        mergedSource: merged.source,
        profilePack: profilePack
      ),
      bookingHistory: bookingHistoryPresentation(
        localReport: localReport,
        serverSummary: serverSummary,
        profilePack: profilePack
      ),
      serverLastSeenDisplay: serverLastSeenDisplay(
        serverSummary,
        mergedSource: merged.source,
        profilePack: profilePack,
        selectedReservation: selectedReservation
      ),
      traceKey: semanticMergeDedupeKey(
        surface: "insights",
        reservationID: localReport.selectedReservationID,
        mergedSource: merged.source,
        backendSeenBefore: backendSeenBefore,
        localPriorCount: localReport.priorReliableVisitCount,
        profilePack: profilePack
      )
    )
  }

  static func insightsMetricsPresentation(
    localReport: GuestInsightReport,
    serverSummary: GuestIntelligenceSummaryDTO?,
    serverAnswered: Bool,
    mergedSource: MergedHistorySource,
    profilePack: GuestIntelligenceProfilePackDTO? = nil
  ) -> GuestInsightsMetricsPresentation {
    if localReport.hasReliableRepeatGuestHistory {
      return GuestInsightsMetricsPresentation(
        title: "Clean visits",
        value: "\(localReport.visitOrdinal)",
        caption: "Local cached history only",
        source: .localCache
      )
    }

    if let packMetric = profilePackKnownVisitDisplay(profilePack) {
      return GuestInsightsMetricsPresentation(
        title: "Known visits",
        value: packMetric.value,
        caption: packMetric.caption,
        source: .backendSummary
      )
    }

    if let serverSummary, isServerReturning(serverSummary) {
      if let knownVisits = reliableKnownVisitDisplay(serverSummary) {
        return GuestInsightsMetricsPresentation(
          title: "Known visits",
          value: knownVisits.value,
          caption: knownVisits.caption,
          source: .backendSummary
        )
      }

      return GuestInsightsMetricsPresentation(
        title: "Known history",
        value: "Seen before",
        caption: "Count not confirmed",
        source: .backendSummary
      )
    }

    if mergedSource == .backendFirstTime {
      return GuestInsightsMetricsPresentation(
        title: "Clean visits",
        value: "1",
        caption: "First time",
        source: .backendSummary
      )
    }

    if mergedSource == .unknownNotLoaded {
      return GuestInsightsMetricsPresentation(
        title: "Known visits",
        value: "—",
        caption: "Guest history loading",
        source: .merged
      )
    }

    if mergedSource == .unknownNoSummary || mergedSource == .localIncomplete {
      return GuestInsightsMetricsPresentation(
        title: "Known visits",
        value: "-",
        caption: "History not confirmed",
        source: .merged
      )
    }

    return GuestInsightsMetricsPresentation(
      title: "Clean visits",
      value: "\(localReport.visitOrdinal)",
      caption: "Local cached history only",
      source: .localCache
    )
  }

  static func bookingHistoryPresentation(
    localReport: GuestInsightReport,
    serverSummary: GuestIntelligenceSummaryDTO?,
    profilePack: GuestIntelligenceProfilePackDTO? = nil
  ) -> GuestInsightsBookingHistoryPresentation {
    if let profilePack, !profilePack.matchedVisitPreview.isEmpty {
      return GuestInsightsBookingHistoryPresentation(
        scope: .serverPreviewAvailable,
        sectionTitle: "Past visits",
        scopeNote: "Earlier guest visits."
      )
    }

    let serverReturning = isBackendSeenBefore(
      serverSummary: serverSummary,
      profilePack: profilePack
    )
    let localShowsCurrentOnly = localReport.priorReliableVisitCount == 0

    if serverReturning, localShowsCurrentOnly {
      return GuestInsightsBookingHistoryPresentation(
        scope: .localCacheOnly,
        sectionTitle: "Cached Booking History",
        scopeNote: "Earlier visit found. Only bookings saved on this device are shown below."
      )
    }

    return GuestInsightsBookingHistoryPresentation(
      scope: .localCacheOnly,
      sectionTitle: "Booking History",
      scopeNote: nil
    )
  }

  static func localCachedHistoryPresentation(
    localReport: GuestInsightReport,
    profilePack: GuestIntelligenceProfilePackDTO?
  ) -> GuestInsightsBookingHistoryPresentation? {
    guard profilePack?.matchedVisitPreview.isEmpty == false else { return nil }
    guard !localReport.bookingHistory.isEmpty else { return nil }
    return GuestInsightsBookingHistoryPresentation(
      scope: .serverAndLocal,
      sectionTitle: "Local Cached History",
      scopeNote: "Only reservations stored on this device are shown here."
    )
  }

  static func serverLastSeenDisplay(
    _ summary: GuestIntelligenceSummaryDTO?,
    mergedSource: MergedHistorySource,
    profilePack: GuestIntelligenceProfilePackDTO? = nil,
    selectedReservation: ReservationRecord? = nil
  ) -> String? {
    guard mergedSource == .backendSeenBefore
      || mergedSource == .localReliablePriorVisits
      || isProfilePackReturning(profilePack) else {
      return nil
    }
    let raw = profilePack?.history?.lastSeenDate ?? summary?.lastVisitDate
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
      return nil
    }
    guard let selectedReservation else {
      #if DEBUG
      print("[INTEL_TRUTH_TRACE] surface=serverLastSeenDisplay missingSelectedReservation=true lastVisitSuppressed=true")
      #endif
      return nil
    }
    guard let date = GuestOperationalTruth.acceptedBackendLastVisit(
      raw,
      selectedDate: selectedReservation.reservationDate,
      selectedTime: selectedReservation.reservationTime
    ) else { return nil }
    return ReservationFormatters.mediumDate.string(from: date)
  }

  static func reliableBackendPriorCount(_ summary: GuestIntelligenceSummaryDTO?) -> Int? {
    guard let summary,
          hasReliableServerClassificationIdentity(summary.identityConfidence) else {
      return nil
    }
    let priorClean = summary.cleanVisitCount
    guard priorClean > 0 else { return nil }
    return priorClean
  }

  private static func reliableKnownVisitDisplay(
    _ summary: GuestIntelligenceSummaryDTO
  ) -> (value: String, caption: String)? {
    guard hasReliableServerClassificationIdentity(summary.identityConfidence) else {
      return nil
    }

    let priorClean = summary.cleanVisitCount
    if priorClean >= 2 {
      return ("\(priorClean + 1)", "Includes prior visits")
    }
    if priorClean == 1 {
      return ("2+", "Includes prior visit")
    }

    return nil
  }

  static func detailInsightPresentation(
    reservation: ReservationRecord,
    reservationPool: [ReservationRecord],
    localReport: GuestInsightReport,
    serverSummary: GuestIntelligenceSummaryDTO?,
    serverAnswered: Bool,
    profilePack: GuestIntelligenceProfilePackDTO? = nil
  ) -> DetailInsightPresentation {
    let merged = mergedHistoryLine(
      guestName: reservation.guestName,
      localReport: localReport,
      serverSummary: serverSummary,
      serverAnswered: serverAnswered,
      profilePack: profilePack,
      selectedReservation: reservation,
      reservationPool: reservationPool
    )
    var supplemental: [DetailInsightLine] = []

    if hasOccasionNoteText(for: reservation)
      || serverSummary?.hasSpecialOccasionNote == true {
      supplemental.append(
        DetailInsightLine(
          title: occasionNoteTitle(for: reservation),
          detail: occasionNoteMessage(guestName: reservation.guestName, reservation: reservation)
        )
      )
    }

    let noteText = combinedNoteText(for: reservation)
    if hasDietaryPreferenceLanguage(in: noteText),
       !hasExplicitAllergyLanguage(in: noteText),
       !supplemental.contains(where: { $0.title == occasionNoteTitle(for: reservation) }) {
      supplemental.append(
        DetailInsightLine(
          title: "Dietary note",
          detail: noteText.count <= 80
            ? noteText
            : "Guest note mentions a dietary preference."
        )
      )
    }

    if hasExplicitAllergyLanguage(in: noteText)
      || backendAllergyFlagIsActionable(serverSummary?.hasAllergyNote == true, reservation: reservation) {
      supplemental.append(
        DetailInsightLine(
          title: "Allergy note",
          detail: "Guest note mentions allergy language. Staff should review before seating."
        )
      )
    }

    return DetailInsightPresentation(
      historyTitle: merged.title,
      historyDetail: merged.detail,
      supplementalLines: supplemental
    )
  }

  static func mergedHistoryLine(
    guestName: String,
    localReport: GuestInsightReport,
    serverSummary: GuestIntelligenceSummaryDTO?,
    serverAnswered: Bool,
    profilePack: GuestIntelligenceProfilePackDTO? = nil,
    selectedReservation: ReservationRecord? = nil,
    reservationPool: [ReservationRecord]? = nil,
    truthSurface: String = "guest_detail",
    operationalTruth: GuestOperationalTruth.Evaluation? = nil
  ) -> (title: String, detail: String, source: MergedHistorySource) {
    if let selectedReservation {
      let truth: GuestOperationalTruth.Evaluation
      if let operationalTruth {
        truth = operationalTruth
      } else if let reservationPool {
        truth = GuestOperationalTruth.evaluate(
          surface: truthSurface,
          selected: selectedReservation,
          reservationPool: reservationPool,
          summary: serverSummary,
          profilePack: profilePack
        )
      } else {
        #if DEBUG
        print("[INTEL_TRUTH_TRACE] surface=\(truthSurface) reservationID=\(selectedReservation.remoteID) missingReservationPool=true localTruthSuppressed=true")
        #endif
        truth = GuestOperationalTruth.evaluate(
          surface: truthSurface,
          selected: selectedReservation,
          localReport: nil,
          summary: serverSummary,
          profilePack: profilePack
        )
      }
      if truth.seenBefore {
        let detail = truth.lastVisitDisplay.map { "Last visit \($0)" } ?? "Seen before"
        let source: MergedHistorySource = truth.source == .local
          ? .localReliablePriorVisits
          : .backendSeenBefore
        return ("Seen before", detail, source)
      }
      if truth.finalLabel == "Guest history found" {
        return ("Guest history", "Guest history found", .localIncomplete)
      }
    } else {
      #if DEBUG
      print("[INTEL_TRUTH_TRACE] surface=\(truthSurface) reservationID=\(localReport.selectedReservationID) missingSelectedReservation=true confirmedTruthSuppressed=true")
      #endif
      let historyEvidence = isProfilePackReturning(profilePack)
        || serverSummary.map(isServerReturning) == true
        || (serverSummary?.matchedVisitCount ?? 0) > 0
      if historyEvidence {
        return ("Guest history", "Guest history found", .localIncomplete)
      }
    }

    if serverAnswered,
       let serverSummary,
       serverSummary.classification == .new,
       hasReliableServerClassificationIdentity(serverSummary.identityConfidence) {
      return ("First time", "No prior visits found.", .backendFirstTime)
    }

    if !serverAnswered {
      return ("Guest history", "Guest history not checked yet.", .unknownNotLoaded)
    }

    if serverAnswered, serverSummary == nil {
      return ("Guest history", "No guest history summary for this reservation.", .unknownNoSummary)
    }

    return ("Guest history", "No prior visit history on file.", .localIncomplete)
  }

  /// Server/profile merge source without local cache — used for stable pre-analysis stamps.
  static func serverBackedMergeSource(
    serverSummary: GuestIntelligenceSummaryDTO?,
    serverAnswered: Bool,
    profilePack: GuestIntelligenceProfilePackDTO?
  ) -> MergedHistorySource {
    if isProfilePackReturning(profilePack) {
      return .backendSeenBefore
    }
    if let serverSummary, isServerReturning(serverSummary) {
      return .backendSeenBefore
    }
    if serverAnswered,
       let serverSummary,
       serverSummary.classification == .new,
       hasReliableServerClassificationIdentity(serverSummary.identityConfidence) {
      return .backendFirstTime
    }
    if !serverAnswered {
      return .unknownNotLoaded
    }
    if serverAnswered, serverSummary == nil {
      return .unknownNoSummary
    }
    return .localIncomplete
  }

  /// Stable merge trace/dedupe key — excludes load timestamps and transient flags.
  static func semanticMergeDedupeKey(
    surface: String,
    reservationID: Int,
    mergedSource: MergedHistorySource,
    backendSeenBefore: Bool,
    localPriorCount: Int,
    profilePack: GuestIntelligenceProfilePackDTO?
  ) -> String {
    let previewRows = profilePack?.matchedVisitPreview.count ?? 0
    let knownVisits = profilePack?.visitAnalytics?.knownVisitCount ?? -1
    let packSeenBefore = profilePack?.history?.seenBefore == true
      || profilePack?.hostProfilePacket?.seenBefore == true
    let packVersion = profilePack?.profilePackVersion ?? "none"
    let normalizedLocalPrior = mergedSource == .localReliablePriorVisits
      ? localPriorCount
      : -1
    return [
      surface,
      "\(reservationID)",
      mergedSource.rawValue,
      "\(backendSeenBefore)",
      "\(normalizedLocalPrior)",
      "\(previewRows)",
      "\(knownVisits)",
      "\(packSeenBefore)",
      packVersion
    ].joined(separator: "-")
  }

  /// Task/onChange key aligned with `recordMergePresentation` dedupe for a surface.
  static func mergePresentationTaskKey(
    surface: String,
    guestName: String,
    localReport: GuestInsightReport,
    serverSummary: GuestIntelligenceSummaryDTO?,
    serverAnswered: Bool,
    profilePack: GuestIntelligenceProfilePackDTO?,
    selectedReservation: ReservationRecord?,
    reservationPool: [ReservationRecord]?
  ) -> String {
    let merged = mergedHistoryLine(
      guestName: guestName,
      localReport: localReport,
      serverSummary: serverSummary,
      serverAnswered: serverAnswered,
      profilePack: profilePack,
      selectedReservation: selectedReservation,
      reservationPool: reservationPool,
      truthSurface: surface
    )
    let backendSeenBefore = isBackendSeenBefore(
      serverSummary: serverSummary,
      profilePack: profilePack
    )
    return semanticMergeDedupeKey(
      surface: surface,
      reservationID: localReport.selectedReservationID,
      mergedSource: merged.source,
      backendSeenBefore: backendSeenBefore,
      localPriorCount: localReport.priorReliableVisitCount,
      profilePack: profilePack
    )
  }

  static func mergedRegularityLevel(
    localReport: GuestInsightReport,
    serverSummary: GuestIntelligenceSummaryDTO?,
    serverAnswered: Bool,
    profilePack: GuestIntelligenceProfilePackDTO? = nil,
    selectedReservation: ReservationRecord? = nil,
    reservationPool: [ReservationRecord]? = nil,
    operationalTruth: GuestOperationalTruth.Evaluation? = nil
  ) -> GuestRegularityLevel? {
    if let selectedReservation {
      let truth: GuestOperationalTruth.Evaluation
      if let operationalTruth {
        truth = operationalTruth
      } else if let reservationPool {
        truth = GuestOperationalTruth.evaluate(
          surface: "regularity",
          selected: selectedReservation,
          reservationPool: reservationPool,
          summary: serverSummary,
          profilePack: profilePack
        )
      } else {
        truth = GuestOperationalTruth.evaluate(
          surface: "regularity",
          selected: selectedReservation,
          localReport: nil,
          summary: serverSummary,
          profilePack: profilePack
        )
      }
      if truth.finalLabel == "Guest history found" { return nil }
      return truth.regularity.guestLevel
    }
    #if DEBUG
    print("[INTEL_TRUTH_TRACE] surface=regularity reservationID=\(localReport.selectedReservationID) missingSelectedReservation=true regularitySuppressed=true")
    #endif
    return serverAnswered && serverSummary?.classification == .new ? .firstTime : nil
  }

  static func isServerReturning(_ summary: GuestIntelligenceSummaryDTO) -> Bool {
    guard hasReliableServerClassificationIdentity(summary.identityConfidence) else {
      return false
    }
    if summary.cleanVisitCount > 0 { return true }
    guard summary.possibleDuplicate == false else { return false }
    return summary.classification == .regular || summary.classification == .frequentRegular
  }

  static func isBackendSeenBefore(
    serverSummary: GuestIntelligenceSummaryDTO?,
    profilePack: GuestIntelligenceProfilePackDTO?
  ) -> Bool {
    if isProfilePackReturning(profilePack) {
      return true
    }
    if let serverSummary, isServerReturning(serverSummary) {
      return true
    }
    return false
  }

  static func isProfilePackReturning(_ profilePack: GuestIntelligenceProfilePackDTO?) -> Bool {
    guard let profilePack else { return false }
    let confidence = profilePack.resolvedSummary?.identityConfidence
    let hostConfidence = profilePack.hostProfilePacket?.identityConfidence?.lowercased()
    let reliableIdentity = confidence == .exact || confidence == .strong
      || hostConfidence == "exact" || hostConfidence == "strong"
    guard reliableIdentity else { return false }
    if let prior = profilePack.history?.priorVisitCount, prior > 0 { return true }
    if let prior = profilePack.visitAnalytics?.priorVisitCount, prior > 0 { return true }
    if let clean = profilePack.resolvedSummary?.cleanVisitCount, clean > 0 { return true }
    if let summary = profilePack.resolvedSummary, isServerReturning(summary) {
      return true
    }
    return false
  }

  private static func profilePackKnownVisitDisplay(
    _ profilePack: GuestIntelligenceProfilePackDTO?
  ) -> (value: String, caption: String)? {
    guard isProfilePackReturning(profilePack) else { return nil }

    let prior = profilePack?.history?.priorVisitCount
      ?? profilePack?.visitAnalytics?.priorVisitCount
      ?? profilePack?.resolvedSummary?.cleanVisitCount
      ?? 0

    if prior >= 2 {
      return ("\(prior + 1)", "Includes prior visits")
    }
    if prior == 1 {
      return ("2+", "Includes prior visit")
    }
    return ("Seen before", "Count not confirmed")
  }

  private static func hasReliableServerClassificationIdentity(
    _ confidence: GuestIdentityConfidenceDTO
  ) -> Bool {
    switch confidence {
    case .exact, .strong:
      return true
    case .possible, .weak, .unknown:
      return false
    }
  }

  private static func hasReliableServerReturningIdentity(
    _ confidence: GuestIdentityConfidenceDTO
  ) -> Bool {
    hasReliableServerClassificationIdentity(confidence)
  }

  static func guestNoteAlertTitle(for reservation: ReservationRecord) -> String {
    "Check guest note"
  }

  static func containsInventedOccasionNoteLanguage(title: String, detail: String?) -> Bool {
    let titleLower = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if titleLower == "occasion note" || titleLower == "special occasion note" {
      return true
    }

    let detailLower = detail?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    if detailLower.contains("has a special occasion note") {
      return true
    }
    if detailLower.contains("share this note with the server") {
      return true
    }
    return false
  }

  static func guestNoteAlertReason(for reservation: ReservationRecord) -> String {
    let text = combinedNoteText(for: reservation)
    if text.count <= 80 {
      return text
    }
    return "Guest note attached."
  }

  // MARK: - Visit History

  static func visitOrdinal(priorReliableVisitCount: Int) -> Int {
    priorReliableVisitCount + 1
  }

  static func hasReliableRepeatHistory(priorReliableVisitCount: Int) -> Bool {
    priorReliableVisitCount >= 1
  }

  static func ordinalVisitText(for visitOrdinal: Int) -> String? {
    guard visitOrdinal >= 2 else { return nil }
    switch visitOrdinal {
    case 2: return "2nd visit"
    case 3: return "3rd visit"
    default: return "\(visitOrdinal)th visit"
    }
  }

  static func compactHistoryLine(
    priorReliableVisitCount: Int,
    lastPriorVisitDisplayDate: String?
  ) -> (title: String, detail: String) {
    guard hasReliableRepeatHistory(priorReliableVisitCount: priorReliableVisitCount) else {
      return ("First time", "No prior visits found.")
    }

    let ordinal = visitOrdinal(priorReliableVisitCount: priorReliableVisitCount)
    var detailParts: [String] = []
    if let ordinalText = ordinalVisitText(for: ordinal) {
      detailParts.append(ordinalText)
    }
    if let lastPriorVisitDisplayDate {
      detailParts.append("last \(lastPriorVisitDisplayDate)")
    }

    let detail = detailParts.isEmpty
      ? "Guest has prior reservation history."
      : detailParts.joined(separator: " · ")
    return ("Seen before", detail)
  }

  static func seenBeforeRowLine(
    priorReliableVisitCount: Int,
    lastPriorVisitDisplayDate: String?
  ) -> String {
    let line = compactHistoryLine(
      priorReliableVisitCount: priorReliableVisitCount,
      lastPriorVisitDisplayDate: lastPriorVisitDisplayDate
    )
    if line.detail == "Guest has prior reservation history." {
      return line.title
    }
    return "\(line.title) · \(line.detail)"
  }

  static func returningGuestMessage(
    guestName: String,
    visitOrdinal: Int,
    lastPriorVisitDisplayDate: String?,
    frequent: Bool = false
  ) -> String {
    if visitOrdinal >= 2, let ordinal = ordinalVisitText(for: visitOrdinal) {
      if frequent {
        if let lastPriorVisitDisplayDate {
          return "\(guestName) is a frequent returning guest for their \(ordinal); last visit \(lastPriorVisitDisplayDate)."
        }
        return "\(guestName) is a frequent returning guest for their \(ordinal)."
      }

      if let lastPriorVisitDisplayDate {
        return "\(guestName) is returning for \(ordinal); last visit \(lastPriorVisitDisplayDate)."
      }
      return "\(guestName) is returning for \(ordinal)."
    }

    if frequent {
      return "\(guestName) is a frequent returning guest."
    }
    if let lastPriorVisitDisplayDate {
      return "\(guestName) has been seen before. Last visit \(lastPriorVisitDisplayDate)."
    }
    return "\(guestName) has been seen before."
  }

  // MARK: - Private

  private static let specialOccasionKeywords = [
    "birthday", "anniversary", "engagement", "graduation", "celebration", "special occasion",
    "bachelor party", "bachelorette", "bachelorette party"
  ]

  private static let explicitAllergyKeywords = [
    "allergy", "allergic", "anaphylaxis", "peanut allergy", "shellfish allergy", "severe allergy"
  ]

  private static let dietaryPreferenceKeywords = [
    "vegetarian", "vegan", "pescatarian", "dairy-free", "dairy free", "gluten-free", "gluten free",
    "celiac"
  ]
}
