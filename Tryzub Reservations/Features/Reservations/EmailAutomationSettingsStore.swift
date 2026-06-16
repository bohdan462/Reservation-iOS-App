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

    static let defaultsKey = "tryzub.emailAutomation.settings.v1"

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
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            settings = .defaults
            return
        }

        do {
            settings = try JSONDecoder().decode(EmailAutomationSettings.self, from: data)
        } catch {
            settings = .defaults
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
