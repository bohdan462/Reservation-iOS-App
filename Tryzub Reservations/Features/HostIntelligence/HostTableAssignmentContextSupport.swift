//
//  HostTableAssignmentContextSupport.swift
//  Tryzub Reservations
//
//  Slot pressure + proposed seating for table assignment / seat flows.
//

import Foundation

struct HostTableAssignmentProposal: Identifiable, Equatable {
  let id: String
  let tableLabel: String
  let summary: String
  let detail: String?
  let isRecommended: Bool
  let isAvailable: Bool
  let seatCount: Int?
  let fitDescription: String?

  init(
    id: String,
    tableLabel: String,
    summary: String,
    detail: String?,
    isRecommended: Bool,
    isAvailable: Bool,
    seatCount: Int? = nil,
    fitDescription: String? = nil
  ) {
    self.id = id
    self.tableLabel = tableLabel
    self.summary = summary
    self.detail = detail
    self.isRecommended = isRecommended
    self.isAvailable = isAvailable
    self.seatCount = seatCount
    self.fitDescription = fitDescription
  }
}

struct HostTableAssignmentContext: Equatable {
  let slotContext: HostReservationSlotContext?
  let proposals: [HostTableAssignmentProposal]
}

enum HostTableAssignmentContextSupport {

  static func build(
    reservation: ReservationRecord,
    dayReservations: [ReservationRecord],
    blockedSlotValues: Set<String>,
    tableConfigs: [RestaurantTableConfig],
    settings: HostIntelligenceSettings,
    localSeatedAtByReservationID: [Int: Date],
    manualTableSuggestions: [String],
    now: Date = Date()
  ) -> HostTableAssignmentContext? {
    guard settings.isEnabled else { return nil }
    guard let serviceDateTime = reservation.serviceDateTime else { return nil }

    let serviceDate = ReservationFormatters.reservationDateKey.date(from: reservation.reservationDate)
      ?? serviceDateTime
    let serviceTime = serviceDateTime
    let bucketStart = ReservationDensityCalculator.bucketStart(for: serviceDateTime)

    let slotContext = HostReservationSlotContextSupport.build(
      serviceDate: serviceDate,
      serviceTime: serviceTime,
      partySize: reservation.partySize,
      excludingReservationID: reservation.remoteID,
      dayReservations: dayReservations,
      blockedSlotValues: blockedSlotValues,
      isServiceClosed: false,
      tableConfigs: tableConfigs,
      settings: settings
    )

    let proposals = buildProposals(
      reservation: reservation,
      bucketStart: bucketStart,
      dayReservations: dayReservations,
      tableConfigs: tableConfigs,
      settings: settings,
      localSeatedAtByReservationID: localSeatedAtByReservationID,
      manualTableSuggestions: manualTableSuggestions,
      now: now
    )

    guard slotContext != nil || !proposals.isEmpty else { return nil }

    return HostTableAssignmentContext(
      slotContext: slotContext,
      proposals: proposals
    )
  }

  // MARK: - Proposals

  private static func buildProposals(
    reservation: ReservationRecord,
    bucketStart: Date,
    dayReservations: [ReservationRecord],
    tableConfigs: [RestaurantTableConfig],
    settings: HostIntelligenceSettings,
    localSeatedAtByReservationID: [Int: Date],
    manualTableSuggestions: [String],
    now: Date
  ) -> [HostTableAssignmentProposal] {
    var proposals: [HostTableAssignmentProposal] = []
    var seenLabels = Set<String>()

    let activeTables = tableConfigs.filter(\.isActive)
    if !activeTables.isEmpty {
      let fits = HostTableIntelligenceSupport.bestTableFitOptions(
        for: reservation,
        tableConfigs: activeTables,
        limit: 4
      )

      for fit in fits {
        let label = HostTableIntelligenceSupport.displayTableNames(fit.tableNames)
        let key = normalizeLabel(label)
        guard seenLabels.insert(key).inserted else { continue }

        let conflict = tableConflict(
          tableNames: fit.tableNames,
          reservation: reservation,
          bucketStart: bucketStart,
          dayReservations: dayReservations,
          localSeatedAtByReservationID: localSeatedAtByReservationID,
          settings: settings,
          now: now
        )
        let display = proposalDisplay(for: fit)

        proposals.append(
          HostTableAssignmentProposal(
            id: fit.id,
            tableLabel: label,
            summary: display.summary,
            detail: conflict,
            isRecommended: conflict == nil,
            isAvailable: conflict == nil,
            seatCount: display.seatCount,
            fitDescription: display.fitDescription
          )
        )
      }
    }

    for suggestion in manualTableSuggestions {
      let names = HostTableIntelligenceSupport.parseAssignedTableNames(suggestion)
      let label = names.isEmpty ? suggestion : HostTableIntelligenceSupport.displayTableNames(names)
      let key = normalizeLabel(label)
      guard seenLabels.insert(key).inserted else { continue }

      let conflict = tableConflict(
        tableNames: names.isEmpty ? [suggestion] : names,
        reservation: reservation,
        bucketStart: bucketStart,
        dayReservations: dayReservations,
        localSeatedAtByReservationID: localSeatedAtByReservationID,
        settings: settings,
        now: now
      )
      let manualProposal = manualDisplay(
        tableNames: names.isEmpty ? [suggestion] : names,
        partySize: reservation.partySize,
        tableConfigs: activeTables
      )

      proposals.append(
        HostTableAssignmentProposal(
          id: "manual-\(key)",
          tableLabel: label,
          summary: manualProposal.summary,
          detail: conflict,
          isRecommended: false,
          isAvailable: conflict == nil,
          seatCount: manualProposal.seatCount,
          fitDescription: manualProposal.fitDescription
        )
      )
    }

    return proposals
      .sorted { lhs, rhs in
        if lhs.isAvailable != rhs.isAvailable { return lhs.isAvailable }
        if lhs.isRecommended != rhs.isRecommended { return lhs.isRecommended }
        return lhs.tableLabel.localizedCaseInsensitiveCompare(rhs.tableLabel) == .orderedAscending
      }
      .prefix(5)
      .map { $0 }
  }

  private struct ProposalDisplay {
    let summary: String
    let seatCount: Int?
    let fitDescription: String?
  }

  private static func proposalDisplay(for fit: HostTableFitOption) -> ProposalDisplay {
    let fitLabel = fitLabel(for: fit.fitQuality).lowercased()
    let summary = proposalSummary(for: fit, fitLabel: fitLabel)

    return ProposalDisplay(
      summary: summary,
      seatCount: fit.totalCapacity,
      fitDescription: fitLabel
    )
  }

  private static func proposalSummary(for fit: HostTableFitOption, fitLabel: String) -> String {
    if fit.isCombination {
      return "Combined · seats \(fit.totalCapacity) · \(fitLabel)"
    }
    if let section = fit.section?.nilIfBlank {
      return "Seats \(fit.totalCapacity) · \(section) · \(fitLabel)"
    }
    return "Seats \(fit.totalCapacity) · \(fitLabel)"
  }

  private static func fitLabel(for quality: HostTableFitQuality) -> String {
    switch quality {
    case .exact: return "Exact fit"
    case .tight: return "Tight fit"
    case .comfortable: return "Comfortable fit"
    case .oversized: return "Roomy fit"
    case .unavailable: return "Check capacity"
    }
  }

  private static func manualDisplay(
    tableNames: [String],
    partySize: Int,
    tableConfigs: [RestaurantTableConfig]
  ) -> ProposalDisplay {
    if let matched = HostTableIntelligenceSupport.matchingTables(for: tableNames, in: tableConfigs) {
      let capacity = matched.reduce(0) { $0 + $1.capacity }
      if capacity >= partySize {
        return ProposalDisplay(
          summary: "Seats \(capacity) · matches party",
          seatCount: capacity,
          fitDescription: "matches party"
        )
      }
      return ProposalDisplay(
        summary: "Seats \(capacity) · may be tight for \(partySize)",
        seatCount: capacity,
        fitDescription: "may be tight"
      )
    }
    let summary = tableNames.count > 1 ? "Combined table" : "Saved table option"
    return ProposalDisplay(summary: summary, seatCount: nil, fitDescription: nil)
  }

  // MARK: - Conflicts

  private static func tableConflict(
    tableNames: [String],
    reservation: ReservationRecord,
    bucketStart: Date,
    dayReservations: [ReservationRecord],
    localSeatedAtByReservationID: [Int: Date],
    settings: HostIntelligenceSettings,
    now: Date
  ) -> String? {
    let normalizedTargets = Set(tableNames.map { HostTableIntelligenceSupport.normalizeTableName($0) })
    guard !normalizedTargets.isEmpty else { return nil }
    guard let serviceDate = reservation.serviceDateTime else { return nil }

    for seated in dayReservations where seated.remoteID != reservation.remoteID {
      guard seated.statusValue == .seated,
            let assigned = seated.assignedTableName else { continue }

      let seatedTables = HostTableIntelligenceSupport
        .parseAssignedTableNames(assigned)
        .map { HostTableIntelligenceSupport.normalizeTableName($0) }
      guard !Set(seatedTables).isDisjoint(with: normalizedTargets) else { continue }

      if let seatedAt = localSeatedAtByReservationID[seated.remoteID] {
        let turnMinutes = estimatedTurnMinutes(partySize: seated.partySize, settings: settings)
        let release = seatedAt.addingTimeInterval(TimeInterval(turnMinutes * 60))
        if release <= serviceDate {
          continue
        }
        let releaseLabel = ReservationFormatters.shortTime.string(from: release)
        return "\(assigned) in use until about \(releaseLabel) (\(seated.guestName))"
      }

      return "\(assigned) in use now (\(seated.guestName))"
    }

    let peers = matchingReservations(
      in: dayReservations,
      bucketStart: bucketStart,
      excludingReservationID: reservation.remoteID
    )

    for peer in peers {
      guard let assigned = peer.assignedTableName else { continue }
      let peerTables = HostTableIntelligenceSupport
        .parseAssignedTableNames(assigned)
        .map { HostTableIntelligenceSupport.normalizeTableName($0) }
      guard !Set(peerTables).isDisjoint(with: normalizedTargets) else { continue }
      return "\(assigned) booked for \(peer.guestName) at this time"
    }

    return nil
  }

  private static func matchingReservations(
    in reservations: [ReservationRecord],
    bucketStart: Date,
    excludingReservationID: Int
  ) -> [ReservationRecord] {
    reservations.filter { reservation in
      guard reservation.isExpectedGuest else { return false }
      guard reservation.remoteID != excludingReservationID else { return false }
      guard let peerBucket = ReservationDensityCalculator.bucketStart(for: reservation) else {
        return false
      }
      return peerBucket == bucketStart
    }
  }

  private static func estimatedTurnMinutes(
    partySize: Int,
    settings: HostIntelligenceSettings
  ) -> Int {
    if partySize <= 2 { return 75 }
    if partySize >= settings.largePartyThreshold { return 120 }
    return 90
  }

  private static func normalizeLabel(_ value: String) -> String {
    HostTableIntelligenceSupport.normalizeTableName(value)
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
