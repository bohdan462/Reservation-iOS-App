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

    private var emailUsage: ResolvedEmailUsage {
        ResolvedEmailUsage.resolving(
            setup: controller.restaurantSetup,
            status: controller.lastReminderStatusByDate[Date.reservationDateString()]
        )
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

            Section("Resend usage") {
                EmailUsageDisplayLines(usage: emailUsage)
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

            if settingsStore.settings.manualReminderSendEnabled,
               emailUsage.hasUsageData,
               emailUsage.isDailyLimitReached {
                Section {
                    Label {
                        Text("Daily Resend limit reached. Batch reminders stay disabled until tomorrow.")
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

struct EmailUsageDisplayLines: View {
    let usage: ResolvedEmailUsage

    var body: some View {
        if let dailyText = usage.dailyDisplayText {
            Text(dailyText)
        }
        if let monthlyText = usage.monthlyDisplayText {
            Text(monthlyText)
        }
        if !usage.hasUsageData {
            Text("Usage unavailable")
                .foregroundStyle(.secondary)
        }
    }
}
