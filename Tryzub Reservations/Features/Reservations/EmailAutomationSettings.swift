//
//  EmailAutomationSettings.swift
//  Tryzub Reservations
//
//  Device-local controls for backend email automation.
//

import Foundation

struct EmailAutomationSettings: Codable, Equatable {
    var backendConfirmationEnabled: Bool = true
    var automaticReminderProofEnabled: Bool = true
    var manualReminderSendEnabled: Bool = true
    var manualMailFallbackEnabled: Bool = true

    static let defaults = EmailAutomationSettings()
}

