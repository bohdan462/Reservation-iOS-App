//
//  RestaurantSettingsStore.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

// MARK: - Restaurant Setup UI Helpers

extension RestaurantSetup {
    func suggestedServiceDates(
        starting startDate: Date = Date(),
        count: Int = 10,
        calendar: Calendar = .current
    ) -> [Date] {
        (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate)
                .map { calendar.startOfDay(for: $0) }
        }
    }

    func defaultServiceSlot(now: Date = Date(), calendar: Calendar = .current) -> (date: Date, time: Date, partySize: Int) {
        let serviceDate = calendar.startOfDay(for: now)
        let time = suggestedTimes(for: serviceDate, now: now, calendar: calendar).first
            ?? calendar.date(bySettingHour: 18, minute: 0, second: 0, of: serviceDate)
            ?? serviceDate

        return (serviceDate, time, max(defaultPartySize, 1))
    }

    func suggestedTimes(
        for serviceDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        // UI convenience only. Real business hours and slot rules will come from backend later.
        let serviceMinutes = stride(from: 15 * 60, through: 22 * 60 + 30, by: 30)
        return serviceMinutes.compactMap { minutes in
            guard let slot = calendar.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: serviceDate
            ) else {
                return nil
            }

            if calendar.isDate(slot, inSameDayAs: now), slot <= now {
                return nil
            }

            return slot
        }
    }
}

// MARK: - Settings Screen

struct RestaurantSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    @State private var draft = RestaurantSetup.default
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoadInitialDraft = false

    var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Restaurant Setup") {
                TextField("Business name", text: $draft.businessName)
                    .textInputAutocapitalization(.words)

                TextField("Timezone", text: $draft.timezone)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Stepper(value: $draft.defaultPartySize, in: 1...20) {
                    HStack {
                        Text("Default party size")
                        Spacer()
                        Text("\(draft.defaultPartySize)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Email Identity") {
                TextField("Call-in placeholder email", text: $draft.callInPlaceholderEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("From email", text: $draft.fromEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Reply-to email", text: $draft.replyToEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Text("Business hours and reservation slots are coming later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task {
                        await save()
                    }
                } label: {
                    if isSaving || controller.isSavingRestaurantSetup {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving || controller.isSavingRestaurantSetup)
            }
        }
        .navigationTitle("Restaurant Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await load(forceDraftUpdate: true)
                    }
                } label: {
                    if controller.isLoadingRestaurantSetup {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(controller.isLoadingRestaurantSetup || isSaving)
            }
        }
        .task {
            await load(forceDraftUpdate: !didLoadInitialDraft)
        }
    }

    private func load(forceDraftUpdate: Bool) async {
        errorMessage = nil
        do {
            let setup = try await controller.loadRestaurantSetup(context: modelContext)
            if forceDraftUpdate || !didLoadInitialDraft {
                draft = setup
                didLoadInitialDraft = true
            }
        } catch {
            errorMessage = error.localizedDescription
            if !didLoadInitialDraft {
                draft = controller.restaurantSetup
                didLoadInitialDraft = true
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            let saved = try await controller.updateRestaurantSetup(
                request: RestaurantSetupUpdateRequest(
                    businessName: draft.businessName.trimmed,
                    timezone: draft.timezone.trimmed,
                    defaultPartySize: draft.defaultPartySize,
                    callInPlaceholderEmail: draft.callInPlaceholderEmail.trimmed,
                    fromEmail: draft.fromEmail.trimmed,
                    replyToEmail: draft.replyToEmail.trimmed
                )
            )
            draft = saved
            ReservationHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
