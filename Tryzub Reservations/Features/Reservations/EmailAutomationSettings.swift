//
//  EmailAutomationSettings.swift
//  Tryzub Reservations
//
//  Device-local controls for backend email automation.
//

import Foundation

struct EmailAutomationSettings: Codable, Equatable {
    static let storageKey = "tryzub.emailAutomation.settings.v2"
    static let legacyStorageKey = "tryzub.emailAutomation.settings.v1"

    var backendConfirmationEnabled: Bool = true
    var automaticReminderProofEnabled: Bool = true
    var manualReminderSendEnabled: Bool = false
    var manualMailFallbackEnabled: Bool = true

    static let defaults = EmailAutomationSettings()
}

