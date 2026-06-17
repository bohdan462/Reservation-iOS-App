//
//  EmailAutomationSettingsView.swift
//  Tryzub Reservations
//

import SwiftUI

struct EmailAutomationSettingsView: View {
    @ObservedObject var settingsStore: EmailAutomationSettingsStore
    @EnvironmentObject private var controller: ReservationsController

    private var backendManualBatchEnabled: Bool {
        controller.restaurantSetup.manualBatchRemindersEnabled
    }

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
                    "Allow batch reminder sending",
                    isOn: binding(\.manualReminderSendEnabled)
                )
                Toggle(
                    "Manual Mail fallback",
                    isOn: binding(\.manualMailFallbackEnabled)
                )
            } footer: {
                Text("Applies on this iPad only. Batch reminder sending also requires backend Restaurant Setup to allow manual batch reminders.")
            }

            if settingsStore.settings.manualReminderSendEnabled, !backendManualBatchEnabled {
                Section {
                    Label {
                        Text("Backend reminder sending is off. This iPad cannot send batch reminders until it is enabled in Restaurant Setup.")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
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
