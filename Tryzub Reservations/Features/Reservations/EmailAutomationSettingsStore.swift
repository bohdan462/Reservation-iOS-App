//
//  EmailAutomationSettingsStore.swift
//  Tryzub Reservations
//
//  UserDefaults-backed email automation settings for this iPad.
//

import Foundation

@MainActor
final class EmailAutomationSettingsStore: ObservableObject {
    static let shared = EmailAutomationSettingsStore()

    @Published private(set) var settings: EmailAutomationSettings

    static let defaultsKey = EmailAutomationSettings.storageKey
    private static let legacyDefaultsKey = EmailAutomationSettings.legacyStorageKey

    init() {
        settings = .defaults
        load()
    }

    func update(transform: (inout EmailAutomationSettings) -> Void) {
        var copy = settings
        transform(&copy)
        settings = copy
        persist()
    }

    func resetToDefaults() {
        settings = .defaults
        persist()
    }

    func reload() {
        load()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(EmailAutomationSettings.self, from: data) {
            settings = decoded
            return
        }

        if let data = UserDefaults.standard.data(forKey: Self.legacyDefaultsKey),
           var decoded = try? JSONDecoder().decode(EmailAutomationSettings.self, from: data) {
            decoded.manualReminderSendEnabled = false
            settings = decoded
            persist()
            UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
            return
        }

        settings = .defaults
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
