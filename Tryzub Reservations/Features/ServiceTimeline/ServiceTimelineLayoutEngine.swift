//
//  ServiceTimelineLayoutEngine.swift
//  Tryzub Reservations
//
//  Stateless layout computer: turns reservations + a service window into
//  precomputed block frames and time-tick descriptors. No LLM, no network.
//

import SwiftUI

// MARK: - Layout Engine

enum ServiceTimelineLayoutEngine {

    // MARK: - Geometry Constants

    /// Points per minute on the horizontal axis. 4 pt/min → 15 min = 60 pts, 1 hr = 240 pts.
    static let pointsPerMinute: CGFloat = 4.0
    static let laneHeight: CGFloat = 54
    static let laneSpacing: CGFloat = 4
    static let headerHeight: CGFloat = 40
    /// Padding added before the first tick and after the last tick.
    static let timelineHorizontalPadding: CGFloat = 20
    static let blockMinWidth: CGFloat = 64
    static let blockVerticalInset: CGFloat = 7

    // MARK: - Service Window

    /// Returns the fallback service window for a given date when no restaurant hours are available.
    static func defaultServiceWindow(for date: Date) -> ServiceTimelineWindow {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)  // 1=Sun … 7=Sat
        let (openH, closeH): (Int, Int) = {
            switch weekday {
            case 2: return (17, 21)       // Mon
            case 3, 4, 5: return (17, 21) // Tue–Thu
            case 6: return (17, 22)       // Fri
            case 7: return (11, 22)       // Sat
            case 1: return (11, 21)       // Sun
            default: return (17, 22)
            }
        }()
        let open  = cal.date(bySettingHour: openH,  minute: 0, second: 0, of: date) ?? date
        let close = cal.date(bySettingHour: closeH, minute: 0, second: 0, of: date) ?? date
        return ServiceTimelineWindow(open: open, close: close)
    }

    // MARK: - Duration Estimation

    /// Fallback dining duration when no server-side duration is provided.
    static func estimatedDurationMinutes(partySize: Int) -> Int {
        switch partySize {
        case 1...2: return 80
        case 3...4: return 90
        case 5...6: return 105
        default:    return 120
        }
    }

    // MARK: - Block Computation

    /// Precompute one `ServiceTimelineBlock` per visible reservation.
    /// Returns an empty array when the window is invalid.
    static func computeBlocks(
        from reservations: [ReservationRecord],
        window: ServiceTimelineWindow,
        pointsPerMinute ppm: CGFloat = Self.pointsPerMinute
    ) -> [ServiceTimelineBlock] {
        guard window.isValid else { return [] }

        let sorted = ReservationRecord.sortedChronologically(reservations)
        var results: [ServiceTimelineBlock] = []
        results.reserveCapacity(sorted.count)

        let startTime = ContinuousClock.now
        for (index, reservation) in sorted.enumerated() {
            guard let serviceDate = reservation.serviceDateTime else { continue }

            let startMinutes = window.minutesFromOpen(for: serviceDate)
            let durationMinutes = Double(estimatedDurationMinutes(partySize: reservation.partySize))

            let xOffset = CGFloat(startMinutes) * ppm + timelineHorizontalPadding
            let rawWidth = CGFloat(durationMinutes) * ppm
            let width = max(blockMinWidth, rawWidth)

            results.append(ServiceTimelineBlock(
                id: reservation.remoteID,
                guestName: reservation.guestName,
                displayTime: reservation.displayTime,
                partySize: reservation.partySize,
                status: reservation.statusValue,
                assignedTableName: reservation.assignedTableName,
                hasGuestNotes: reservation.hasGuestNotes,
                confirmedAt: reservation.confirmedAt,
                laneIndex: index,
                xOffset: xOffset,
                width: width
            ))
        }

        #if DEBUG
        let elapsed = ContinuousClock.now - startTime
        let elapsedMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
        print("""
            [SERVICE_TIMELINE_LAYOUT_TRACE] \
            reservations=\(reservations.count) \
            visibleBlocks=\(results.count) \
            pointsPerMinute=\(ppm) \
            lanes=\(results.count) \
            durationMs=~\(elapsedMs)
            """)
        #endif

        return results
    }

    // MARK: - Content Dimensions

    static func totalContentWidth(
        window: ServiceTimelineWindow,
        pointsPerMinute ppm: CGFloat = Self.pointsPerMinute
    ) -> CGFloat {
        CGFloat(window.durationMinutes) * ppm + timelineHorizontalPadding * 2
    }

    static func totalContentHeight(laneCount: Int) -> CGFloat {
        headerHeight + CGFloat(laneCount) * (laneHeight + laneSpacing)
    }

    // MARK: - Now Position

    static func nowXOffset(
        window: ServiceTimelineWindow,
        now: Date,
        pointsPerMinute ppm: CGFloat = Self.pointsPerMinute
    ) -> CGFloat {
        let minutes = window.minutesFromOpen(for: now)
        return CGFloat(minutes) * ppm + timelineHorizontalPadding
    }

    // MARK: - Time Ticks

    struct TimeTick: Identifiable {
        let id: Int            // minutes from service open
        let xOffset: CGFloat
        let label: String      // non-empty only for major ticks
        let isMajor: Bool
    }

    static func timeTicks(
        window: ServiceTimelineWindow,
        majorIntervalMinutes: Int = 30,
        minorIntervalMinutes: Int = 15,
        pointsPerMinute ppm: CGFloat = Self.pointsPerMinute
    ) -> [TimeTick] {
        guard window.isValid else { return [] }

        var ticks: [TimeTick] = []
        let total = window.durationMinutes
        var m = 0

        while m <= total {
            let isMajor = m % majorIntervalMinutes == 0
            let date = window.open.addingTimeInterval(TimeInterval(m * 60))
            let label = isMajor ? ReservationFormatters.shortTime.string(from: date) : ""
            let x = CGFloat(m) * ppm + timelineHorizontalPadding
            ticks.append(TimeTick(id: m, xOffset: x, label: label, isMajor: isMajor))
            m += minorIntervalMinutes
        }
        return ticks
    }
}
