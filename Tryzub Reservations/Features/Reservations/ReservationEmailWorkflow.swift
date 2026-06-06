//
//  ReservationEmailWorkflow.swift
//  Tryzub Reservations
//

import Foundation

enum ReservationEmailWorkflow {
    /// Pilot uses staff Mail/Gmail with guest-manage links. POST `/confirm` stays off until backend email is re-enabled.
    static let isBackendConfirmEmailEnabled = false

    static let restaurantName = "Tryzub Ukrainian Kitchen"
    static let restaurantAddressLine = "2201 W Chicago Ave, Chicago, IL 60622"
    static let restaurantPhone = "(773) 698-8624"
    static let websiteURL = URL(string: "https://tryzubchicago.com")!
    static let reservationPoliciesURL = URL(string: "https://tryzubchicago.com/book-table/")!

    static let manualConfirmationStaffNoteMarker = "[iOS] Manual confirmation email sent"
}
