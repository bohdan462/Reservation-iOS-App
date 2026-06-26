//
//  EmailAutomationSettingsView.swift
//  Tryzub Reservations
//

import SwiftUI

struct EmailAutomationSettingsView: View {
    @ObservedObject var settingsStore: EmailAutomationSettingsStore
    @EnvironmentObject private var controller: ReservationsController
    @Environment(\.dismiss) private var dismiss

    private var setup: RestaurantSetup {
        controller.restaurantSetup
    }

    private var backendManualBatchEnabled: Bool {
        setup.manualBatchRemindersEnabled
    }

    private var emailUsage: ResolvedEmailUsage {
        ResolvedEmailUsage.resolving(
            setup: setup,
            status: controller.lastReminderStatusByDate[Date.reservationDateString()]
        )
    }

    var body: some View {
        Form {

            Section {
                Toggle(
                    "Use backend confirmation on this device",
                    isOn: binding(\.backendConfirmationEnabled)
                )
                Toggle(
                    "Show automatic reminder proof on this device",
                    isOn: binding(\.automaticReminderProofEnabled)
                )
                Toggle(
                    "Allow reminder batch send on this device",
                    isOn: binding(\.manualReminderSendEnabled)
                )
                .disabled(!backendManualBatchEnabled)

                if !backendManualBatchEnabled {
                    Text("Backend manual batch reminders are off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Allow Manual Mail fallback on this device",
                    isOn: binding(\.manualMailFallbackEnabled)
                )
            } header: {
                Text("This device")
            } footer: {
                Text("These switches are stored on this device. Restaurant Settings owns backend reminders and auto-confirm rules.")
            }

            Section {
                LabeledContent("Automatic reminders", value: setup.automaticRemindersEnabled ? "On" : "Off")
                LabeledContent("Manual batch reminders", value: setup.manualBatchRemindersEnabled ? "On" : "Off")
                LabeledContent("Reminder lead time", value: reminderLeadHoursLabel(setup.reminderLeadHours))
                LabeledContent("Morning reminder time", value: setup.morningReminderTime)

                if !backendManualBatchEnabled {
                    Label {
                        Text("Backend manual batch reminders are off. Cannot send reminder batches until enabled in Backend Reminders.")
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Label("Back to Restaurant Settings", systemImage: "arrow.uturn.backward.circle")
                        .font(.subheadline.weight(.semibold))
                }
            } header: {
                Text("Backend reminders")
            } footer: {
                Text("Backend reminders are global server settings and affect all devices.")
            }

            Section("Resend usage") {
                EmailUsageDisplayLines(usage: emailUsage)
            }

            if settingsStore.settings.manualReminderSendEnabled,
               backendManualBatchEnabled,
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
        .navigationTitle("This Device Email")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reminderLeadHoursLabel(_ hours: Int) -> String {
        let unit = hours == 1 ? "hour" : "hours"
        return "\(hours) \(unit)"
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
            Text("Usage unavailable from backend.")
                .foregroundStyle(.secondary)
        }
    }
}
