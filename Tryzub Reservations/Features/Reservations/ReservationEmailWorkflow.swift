//
//  ReservationEmailWorkflow.swift
//  Tryzub Reservations
//

import Foundation

enum ReservationEmailWorkflow {
    /// Staff-triggered only: when ON, an explicit Confirm & Send tap calls POST `/confirm`.
    /// Sync, startup, refresh, reminders, and background work must never confirm reservations.
    static var isBackendConfirmEmailEnabled: Bool {
        guard let data = UserDefaults.standard.data(forKey: "tryzub.emailAutomation.settings.v1"),
              let settings = try? JSONDecoder().decode(EmailAutomationSettings.self, from: data) else {
            return EmailAutomationSettings.defaults.backendConfirmationEnabled
        }
        return settings.backendConfirmationEnabled
    }

    static let restaurantName = "Tryzub Ukrainian Kitchen"
    static let restaurantAddressLine = "2201 W Chicago Ave, Chicago, IL 60622"
    static let restaurantPhone = "(773) 698-8624"
    static let websiteURL = URL(string: "https://tryzubchicago.com")!
    static let reservationPoliciesURL = URL(string: "https://tryzubchicago.com/home-page/privacy-policy-terms-and-conditions/")!
    static let bookTableURL = URL(string: "https://tryzubchicago.com/book-table/")!
    static let guestContactEmail = "info@tryzubchicago.com"

    static let manualConfirmationStaffNoteMarker = "[iOS] confirmation email sent"
}
