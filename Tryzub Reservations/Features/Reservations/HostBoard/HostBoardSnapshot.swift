//
//  HostBoardSnapshot.swift
//  Tryzub Reservations
//

import Foundation

struct HostBoardSnapshot {
    let selectedDate: Date
    let now: Date
    let upcoming: [ReservationRecord]
    let seated: [ReservationRecord]
    let needsReview: [ReservationRecord]
    let newReservations: [ReservationRecord]
    let noTableCount: Int
    let expectedGuestCount: Int
    let peakTimeText: String
    let nextReservationText: String?
    let arrivalPressure: ArrivalPressureSummary

    // Active same-day reservations remain visible until staff changes status.
    // Time only chooses the "next" highlight; it does not auto-complete or hide rows.
    init(
        reservations: [ReservationRecord],
        selectedDate: Date,
        now: Date,
        serviceOpen: Date? = nil,
        serviceClose: Date? = nil,
        largePartyThreshold: Int = 7,
        effectiveTableAssignments: [EffectiveReservationTableAssignment] = []
    ) {
        self.selectedDate = selectedDate
        self.now = now
        let effectiveTablesByReservationID = ReservationTableTruth.assignmentsByReservationID(
            effectiveTableAssignments
        )
        upcoming = ReservationRecord.sortedForHostBoard(
            reservations.filter {
                $0.statusValue == .new || $0.statusValue == .needsReview || $0.statusValue == .confirmed
            },
            now: now
        )
        seated = ReservationRecord.sortedChronologically(
            reservations.filter { $0.statusValue == .seated }
        )
        needsReview = upcoming.filter { $0.statusValue == .needsReview }
        newReservations = upcoming.filter { $0.statusValue == .new }
        noTableCount = upcoming.filter {
            !ReservationTableTruth.hasEffectiveTableAssignment(
                for: $0,
                assignmentsByReservationID: effectiveTablesByReservationID
            )
        }.count
        expectedGuestCount = upcoming.reduce(0) { $0 + $1.partySize } + seated.reduce(0) { $0 + $1.partySize }

        let isToday = selectedDate.reservationDateString() == Date.reservationDateString()
        let nextReservation = ReservationRecord.nextExpectedArrivalReservation(
            from: reservations,
            selectedDate: selectedDate,
            now: now
        )
        let pressureReservations = upcoming + seated
        arrivalPressure = ArrivalPressureEngine.build(
            from: pressureReservations,
            selectedDate: selectedDate,
            serviceOpen: serviceOpen,
            serviceClose: serviceClose,
            now: now,
            largePartyThreshold: largePartyThreshold,
            effectiveTableAssignments: effectiveTableAssignments
        )
        peakTimeText = arrivalPressure.peakLegendText
        nextReservationText = arrivalPressure.nextLegendText
            ?? Self.nextReservationText(
                for: nextReservation,
                isToday: isToday,
                now: now
            )
    }

    private static func nextReservationText(
        for reservation: ReservationRecord?,
        isToday: Bool,
        now: Date
    ) -> String? {
        guard isToday, let reservation, let serviceDate = reservation.serviceDateTime else {
            return nil
        }

        let time = ReservationFormatters.shortTime.string(from: serviceDate)
        let minutes = Int(ceil(abs(serviceDate.timeIntervalSince(now)) / 60))

        if serviceDate < now {
            if minutes <= 10 {
                return "\(time) · now"
            }
            return "\(time) · \(durationText(minutes: minutes)) late"
        }
        if minutes <= 5 {
            return "\(time) · soon"
        }
        return "\(time) · in \(durationText(minutes: minutes))"
    }

    private static func durationText(minutes: Int) -> String {
        let minutes = max(minutes, 1)
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }
}
