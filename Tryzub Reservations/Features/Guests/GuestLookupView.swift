//
//  GuestLookupView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

// MARK: - Guest Lookup View

struct GuestLookupView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController
    @Query
    private var reservations: [ReservationRecord]

    @StateObject private var store = GuestLookupStore()
    @State private var searchText = ""
    @State private var activeSheet: GuestLookupSheet?

    let environment: AppEnvironment
    let isActive: Bool

    init(environment: AppEnvironment, isActive: Bool) {
        self.environment = environment
        self.isActive = isActive
        _reservations = Query(
            filter: #Predicate<ReservationRecord> { record in
                !record.isHidden
            },
            sort: [
                SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
                SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
            ]
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if controller.isNetworkDegraded {
                    Section {
                        Label(
                            "Offline — showing saved guests. Create requires internet.",
                            systemImage: "wifi.slash"
                        )
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TryzubColors.warning)
                    }
                }

                Section {
                    Button {
                        activeSheet = GuestLookupSheet(prefill: .blankCallIn)
                    } label: {
                        Label("Create", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(isBookingDisabled)
                } footer: {
                    Text("Search cached reservations by phone or name. No backend guest profile is created.")
                }

                if !store.isSearchActive {
                    Section {
                        ContentUnavailableView(
                            "Search Guests",
                            systemImage: "person.text.rectangle",
                            description: Text("Enter at least 4 phone digits or 2 name characters.")
                        )
                    }
                } else if store.results.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Guest Found",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("Try a different phone number or name.")
                        )
                    }
                } else {
                    Section("Cached guests") {
                        ForEach(store.results) { result in
                            GuestLookupResultCard(
                                result: result,
                                isBookingDisabled: isBookingDisabled,
                                onBook: {
                                    activeSheet = GuestLookupSheet(prefill: result.prefill)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("Guests")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search phone or name")
            .listStyle(.plain)
            .contentMargins(.bottom, ReservationLayout.scrollBottomInset, for: .scrollContent)
            .fullScreenCover(item: $activeSheet) { sheet in
                ManualReservationFormView(prefill: sheet.prefill) { request in
                    try await controller.createAcceptedManualReservation(request, context: modelContext)
                }
            }
            .task(id: cacheKey) {
                refreshCacheIfVisible()
            }
            .task(id: isActive) {
                refreshCacheIfVisible()
            }
            .onChange(of: searchText) { _, value in
                guard isActive else { return }
                store.scheduleSearch(value)
            }
            .onAppear {
                guard isActive else { return }
                store.scheduleSearch(searchText)
            }
        }
    }

    private var cacheKey: GuestLookupCacheKey {
        GuestLookupCacheKey(records: reservations)
    }

    private var isBookingDisabled: Bool {
        controller.isNetworkDegraded || !controller.capabilities.canCreateManualReservations
    }

    private func refreshCacheIfVisible() {
        guard isActive else { return }
        store.updateCache(records: reservations, cacheKey: cacheKey)
        store.scheduleSearch(searchText)
    }
}

// MARK: - Guest Result Card

private struct GuestLookupResultCard: View {
    let result: GuestLookupResult
    let isBookingDisabled: Bool
    let onBook: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text("\(result.totalReservations) \(result.totalReservations == 1 ? "visit" : "visits")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TryzubColors.mutedText)
            }

            VStack(alignment: .leading, spacing: 5) {
                if let phoneDigits = result.phoneDigits {
                    Label(GuestLookupPhoneFormatter.display(phoneDigits), systemImage: "phone")
                }

                if let email = result.email {
                    Label(email, systemImage: "envelope")
                }

                if let lastReservationDate = result.lastReservationDate {
                    Label("Last reservation \(GuestLookupDateFormatter.display(lastReservationDate))", systemImage: "calendar")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(TryzubColors.mutedText)
            .lineLimit(1)

            if result.latestGuestNotes != nil || result.latestStaffNotes != nil {
                HStack(spacing: 8) {
                    if result.latestGuestNotes != nil {
                        Label("Guest Notes", systemImage: "note.text")
                    }
                    if result.latestStaffNotes != nil {
                        Label("Staff Notes", systemImage: "note.text.badge.plus")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TryzubColors.mutedText)
            }

            Button(action: onBook) {
                Label("Book New Reservation", systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .disabled(isBookingDisabled)
            .opacity(isBookingDisabled ? 0.45 : 1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }
}

private struct GuestLookupSheet: Identifiable {
    let id = UUID()
    let prefill: ManualReservationPrefill
}

private enum GuestLookupPhoneFormatter {
    static func display(_ digits: String) -> String {
        let cleaned = digits.filter(\.isNumber)
        let local = cleaned.count == 11 && cleaned.first == "1"
            ? String(cleaned.dropFirst())
            : cleaned

        guard local.count == 10 else { return cleaned }

        let area = local.prefix(3)
        let middle = local.dropFirst(3).prefix(3)
        let last = local.suffix(4)
        return "(\(area)) \(middle)-\(last)"
    }
}

private enum GuestLookupDateFormatter {
    static func display(_ value: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: value) else {
            return value
        }

        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
