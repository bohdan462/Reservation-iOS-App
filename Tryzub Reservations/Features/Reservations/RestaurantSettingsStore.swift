//
//  RestaurantSettingsStore.swift
//  Tryzub Reservations
//

import SwiftUI

// MARK: - Local Restaurant Settings

enum ManualEmailPlaceholderPolicy: String, Codable, CaseIterable, Identifiable {
    case manualReservationDomain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualReservationDomain:
            return "Manual reservation email"
        }
    }
}

struct RestaurantBusinessHours: Codable, Equatable {
    var isClosed: Bool
    var opensAtMinutes: Int
    var closesAtMinutes: Int

    static let defaultService = RestaurantBusinessHours(
        isClosed: false,
        opensAtMinutes: 15 * 60,
        closesAtMinutes: 23 * 60
    )
}

struct RestaurantSettings: Codable, Equatable {
    var weekdayHours: [Int: RestaurantBusinessHours]
    var slotIntervalMinutes: Int
    var lastSeatingMinutes: Int
    var defaultPartySize: Int
    var callInEmailPlaceholderPolicy: ManualEmailPlaceholderPolicy

    static let `default` = RestaurantSettings(
        weekdayHours: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, .defaultService) }),
        slotIntervalMinutes: 30,
        lastSeatingMinutes: 22 * 60 + 30,
        defaultPartySize: 2,
        callInEmailPlaceholderPolicy: .manualReservationDomain
    )

    func availableServiceDates(
        starting startDate: Date = Date(),
        count: Int = 10,
        calendar: Calendar = .current
    ) -> [Date] {
        var dates: [Date] = []
        var offset = 0

        while dates.count < count && offset < 45 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                offset += 1
                continue
            }

            if !availableTimes(for: date, now: startDate, calendar: calendar).isEmpty {
                dates.append(calendar.startOfDay(for: date))
            }

            offset += 1
        }

        return dates
    }

    func defaultServiceSlot(now: Date = Date(), calendar: Calendar = .current) -> (date: Date, time: Date, partySize: Int) {
        let serviceDates = availableServiceDates(starting: now, count: 1, calendar: calendar)
        let serviceDate = serviceDates.first ?? calendar.startOfDay(for: now)
        let time = availableTimes(for: serviceDate, now: now, calendar: calendar).first
            ?? calendar.date(bySettingHour: 18, minute: 0, second: 0, of: serviceDate)
            ?? serviceDate

        return (serviceDate, time, defaultPartySize)
    }

    func availableTimes(
        for serviceDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let weekday = calendar.component(.weekday, from: serviceDate)
        let hours = weekdayHours[weekday] ?? .defaultService
        guard !hours.isClosed else { return [] }

        let startMinutes = hours.opensAtMinutes
        let endMinutes = min(hours.closesAtMinutes, lastSeatingMinutes)
        let interval = max(slotIntervalMinutes, 5)
        guard startMinutes <= endMinutes else { return [] }

        return stride(from: startMinutes, through: endMinutes, by: interval).compactMap { minutes in
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

    func placeholderEmail(for guestName: String, date: Date = Date()) -> String {
        let stamp = Int(date.timeIntervalSince1970)
        return "\(stamp)_manual_reservation@manualreservation.com"
    }
}

@MainActor
final class RestaurantSettingsStore: ObservableObject {
    private static let storageKey = "tryzub.restaurantSettings"

    @Published var settings: RestaurantSettings {
        didSet {
            persist()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(RestaurantSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    private let userDefaults: UserDefaults

    func resetToDefault() {
        settings = .default
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Settings Screen

struct RestaurantSettingsView: View {
    @EnvironmentObject private var settingsStore: RestaurantSettingsStore

    private let weekdays: [(id: Int, name: String)] = [
        (1, "Sunday"),
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday"),
        (7, "Saturday")
    ]

    var body: some View {
        Form {
            Section("Business Hours") {
                ForEach(weekdays, id: \.id) { weekday in
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(weekday.name, isOn: isOpenBinding(for: weekday.id))
                            .font(.headline.weight(.medium))

                        if !(settingsStore.settings.weekdayHours[weekday.id] ?? .defaultService).isClosed {
                            HStack {
                                DatePicker(
                                    "Opens",
                                    selection: timeBinding(for: weekday.id, keyPath: \.opensAtMinutes),
                                    displayedComponents: .hourAndMinute
                                )

                                DatePicker(
                                    "Closes",
                                    selection: timeBinding(for: weekday.id, keyPath: \.closesAtMinutes),
                                    displayedComponents: .hourAndMinute
                                )
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Reservation Slots") {
                Picker("Slot interval", selection: settingBinding(\.slotIntervalMinutes)) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                    Text("60 minutes").tag(60)
                }

                DatePicker(
                    "Last seating",
                    selection: lastSeatingBinding,
                    displayedComponents: .hourAndMinute
                )

                Stepper(value: settingBinding(\.defaultPartySize), in: 1...20) {
                    HStack {
                        Text("Default party size")
                        Spacer()
                        Text("\(settingsStore.settings.defaultPartySize)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Call-in Reservations") {
                Picker("Email placeholder", selection: settingBinding(\.callInEmailPlaceholderPolicy)) {
                    ForEach(ManualEmailPlaceholderPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                Text("If staff does not enter an email, the app sends a local manual-reservation placeholder so the current backend can create the record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Defaults") {
                    settingsStore.resetToDefault()
                    ReservationHaptics.warning()
                }
                .foregroundStyle(ReservationUIStyle.cancelColor)
            }
        }
        .navigationTitle("Restaurant Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isOpenBinding(for weekday: Int) -> Binding<Bool> {
        Binding {
            !(settingsStore.settings.weekdayHours[weekday] ?? .defaultService).isClosed
        } set: { isOpen in
            var settings = settingsStore.settings
            var hours = settings.weekdayHours[weekday] ?? .defaultService
            hours.isClosed = !isOpen
            settings.weekdayHours[weekday] = hours
            settingsStore.settings = settings
        }
    }

    private func timeBinding(
        for weekday: Int,
        keyPath: WritableKeyPath<RestaurantBusinessHours, Int>
    ) -> Binding<Date> {
        Binding {
            let minutes = (settingsStore.settings.weekdayHours[weekday] ?? .defaultService)[keyPath: keyPath]
            return date(fromMinutes: minutes)
        } set: { date in
            var settings = settingsStore.settings
            var hours = settings.weekdayHours[weekday] ?? .defaultService
            hours[keyPath: keyPath] = minutes(from: date)
            settings.weekdayHours[weekday] = hours
            settingsStore.settings = settings
        }
    }

    private var lastSeatingBinding: Binding<Date> {
        Binding {
            date(fromMinutes: settingsStore.settings.lastSeatingMinutes)
        } set: { date in
            var settings = settingsStore.settings
            settings.lastSeatingMinutes = minutes(from: date)
            settingsStore.settings = settings
        }
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<RestaurantSettings, Value>) -> Binding<Value> {
        Binding {
            settingsStore.settings[keyPath: keyPath]
        } set: { value in
            var settings = settingsStore.settings
            settings[keyPath: keyPath] = value
            settingsStore.settings = settings
        }
    }

    private func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
