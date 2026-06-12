//
//  BookingLoadActionBuilder.swift
//  Tryzub Reservations
//
//  Service Intelligence — Phase 4 (Booking Load Suggestions).
//
//  Turns a deterministic BookingLoadReport into simple staff-language items + manual
//  StaffActionIntents. Everything here is decision-support: canAutoComplete is always
//  false and nothing is mutated. Staff confirm any real close-slot action elsewhere.
//

import Foundation

/// Display + action bundle for one busy booking window.
struct BookingSuggestionViewItem: Identifiable, Equatable {
    let id: Int                 // window start minutes-of-day
    let slotValue: String       // "HH:mm" for blocked-slot targeting
    let headline: String        // "6:00 PM looks full"
    let loadLine: String        // "5 reservations · 22 known guests"
    let closeLine: String       // "Suggest closing this time for new bookings"
    let alternateLine: String   // "Next better time: 6:30 PM" / "No better nearby time found."
    let severity: BookingLoadSeverity
    let closeAction: StaffActionIntent
    let alternateAction: StaffActionIntent?
}

enum BookingLoadActionBuilder {

    static func items(from report: BookingLoadReport) -> [BookingSuggestionViewItem] {
        report.suggestions.map { suggestion in
            let item = makeItem(suggestion)
            BookingLoadTrace.action(
                type: .suggestCloseBookingSlot,
                slot: item.slotValue,
                priority: item.closeAction.priority,
                canAutoComplete: false
            )
            if let alternate = item.alternateAction {
                BookingLoadTrace.action(
                    type: .suggestAlternateBookingTime,
                    slot: suggestion.alternateSlotValue ?? item.slotValue,
                    priority: alternate.priority,
                    canAutoComplete: false
                )
            }
            return item
        }
    }

    /// The single most important busy window, for a concise Host Board heads-up.
    static func topItem(from report: BookingLoadReport) -> BookingSuggestionViewItem? {
        guard let suggestion = report.suggestions.max(by: { lhs, rhs in
            if lhs.window.knownGuestCount != rhs.window.knownGuestCount {
                return lhs.window.knownGuestCount < rhs.window.knownGuestCount
            }
            return lhs.window.reservationCount < rhs.window.reservationCount
        }) else { return nil }
        return makeItem(suggestion)
    }

    // MARK: - Mapping

    private static func makeItem(_ suggestion: BookingLoadSuggestion) -> BookingSuggestionViewItem {
        let w = suggestion.window
        let fullWord = w.severity == .veryBusy ? "very full" : "full"
        let headline = "\(w.label) looks \(fullWord)"
        let loadLine = "\(w.reservationCount) \(reservationWord(w.reservationCount)) · \(w.knownGuestCount) known \(guestWord(w.knownGuestCount))"
        let closeLine = "Suggest closing this time for new bookings"
        let alternateLine = suggestion.alternateLabel.map { "Next better time: \($0)" }
            ?? "No better nearby time found."

        let closeAction = StaffActionIntent(
            id: "booking-close-\(w.slotValue)",
            type: .suggestCloseBookingSlot,
            reservationID: nil,
            title: "Suggest closing \(w.label) for new bookings",
            detail: "\(w.reservationCount) \(reservationWord(w.reservationCount)) are already around this time, about \(w.knownGuestCount) known \(guestWord(w.knownGuestCount)) before walk-ins.",
            priority: w.severity == .veryBusy ? .high : .medium,
            timing: .now,
            canAutoComplete: false
        )

        var alternateAction: StaffActionIntent?
        if let altLabel = suggestion.alternateLabel {
            alternateAction = StaffActionIntent(
                id: "booking-alt-\(suggestion.alternateSlotValue ?? altLabel)",
                type: .suggestAlternateBookingTime,
                reservationID: nil,
                title: "Suggest \(altLabel) instead",
                detail: "\(altLabel) has fewer known guests.",
                priority: .medium,
                timing: .now,
                canAutoComplete: false
            )
        }

        return BookingSuggestionViewItem(
            id: w.startMinutes,
            slotValue: w.slotValue,
            headline: headline,
            loadLine: loadLine,
            closeLine: closeLine,
            alternateLine: alternateLine,
            severity: w.severity,
            closeAction: closeAction,
            alternateAction: alternateAction
        )
    }

    private static func reservationWord(_ count: Int) -> String {
        count == 1 ? "reservation" : "reservations"
    }

    private static func guestWord(_ count: Int) -> String {
        count == 1 ? "guest" : "guests"
    }
}
