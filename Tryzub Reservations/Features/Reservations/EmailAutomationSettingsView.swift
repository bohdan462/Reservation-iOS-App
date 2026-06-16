//
//  EmailAutomationSettingsView.swift
//  Tryzub Reservations
//

import SwiftUI

struct EmailAutomationSettingsView: View {
    @ObservedObject var settingsStore: EmailAutomationSettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Use backend email for Confirm & Send",
                    isOn: binding(\.backendConfirmationEnabled)
                )
                Toggle(
                    "Automatic reminder proof",
                    isOn: binding(\.automaticReminderProofEnabled)
                )
                Toggle(
                    "Manual reminder send",
                    isOn: binding(\.manualReminderSendEnabled)
                )
                Toggle(
                    "Manual Mail fallback",
                    isOn: binding(\.manualMailFallbackEnabled)
                )
            } footer: {
                Text("Applies on this iPad only. It does not change WordPress, Resend, or other devices yet.")
            }
        }
        .navigationTitle("Email Automation")
    }

    private func binding(_ keyPath: WritableKeyPath<EmailAutomationSettings, Bool>) -> Binding<Bool> {
        Binding {
            settingsStore.settings[keyPath: keyPath]
        } set: { newValue in
            settingsStore.update { settings in
                settings[keyPath: keyPath] = newValue
            }
        }
    }
}
