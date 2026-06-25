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
    @EnvironmentObject private var guestProfileStore: GuestProfileStore
    @Query
    private var reservations: [ReservationRecord]
    @Query(
        sort: [
            SortDescriptor(\GuestProfileCacheRecord.cleanVisitCount, order: .reverse),
            SortDescriptor(\GuestProfileCacheRecord.totalReservations, order: .reverse),
            SortDescriptor(\GuestProfileCacheRecord.fetchedAt, order: .reverse)
        ]
    )
    private var cachedGuestProfiles: [GuestProfileCacheRecord]

    @StateObject private var store = GuestLookupStore()
    @State private var searchText = ""
    @State private var activeSheet: GuestLookupSheet?
    @State private var serverCandidates: [GuestProfileLookupCandidate] = []
    @State private var isSearchingAllGuests = false
    @State private var serverLookupMessage: String?
    @State private var lastSubmittedSearch = ""
    @State private var activeLookupKey: String?

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

                    Button {
                        Task {
                            await submitServerLookup()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Label("Search all guest records", systemImage: "magnifyingglass.circle")
                                .font(.subheadline.weight(.semibold))

                            Spacer(minLength: 8)

                            if isSearchingAllGuests {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Searching")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(TryzubColors.mutedText)
                            }
                        }
                    }
                    .disabled(isSearchingAllGuests)
                    .accessibilityLabel("Search all guest records")

                    if let serverLookupMessage {
                        Text(serverLookupMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TryzubColors.mutedText)
                    }
                } footer: {
                    Text("Matches saved on this iPad appear as you type. Search all guest records to check older visits too.")
                }

                let localResults = localResultsForDisplay
                let serverResults = serverResultsForDisplay

                if !store.isSearchActive && serverResults.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Find a guest by name, phone, or email.",
                            systemImage: "person.text.rectangle",
                            description: Text("Start typing to check saved guests, or search all guest records.")
                        )
                    }
                } else if localResults.isEmpty && serverResults.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No saved guest found",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("Try a different name, phone, or email, or search all guest records.")
                        )
                    }
                } else {
                    if !localResults.isEmpty {
                        Section("Saved on this iPad") {
                            ForEach(localResults) { result in
                                GuestLookupResultCard(
                                    result: result,
                                    profileRoute: profileRoute(for: result),
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

                    if !serverResults.isEmpty {
                        Section("All guest records") {
                            ForEach(serverResults) { result in
                                GuestLookupResultCard(
                                    result: result,
                                    profileRoute: profileRoute(for: result),
                                    matchBadgeText: result.isStrongBackendMatch ? "Likely guest" : "Possible match",
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
            }
            .navigationTitle("Guests")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: GuestProfileRoute.self) { route in
                GuestProfileDetailView(guestKey: route.guestKey, environment: environment)
            }
            .searchable(text: $searchText, prompt: "Name, phone, or email")
            .onSubmit(of: .search) {
                Task {
                    await submitServerLookup()
                }
            }
            .listStyle(.plain)
            .contentMargins(.bottom, ReservationLayout.scrollBottomInset, for: .scrollContent)
            .fullScreenCover(item: $activeSheet) { sheet in
                ManualReservationFormView(prefill: sheet.prefill, source: "guests") { request in
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

    private var serverResultsForDisplay: [GuestLookupResult] {
        serverCandidates.map(\.lookupResult)
    }

    private var localResultsForDisplay: [GuestLookupResult] {
        let serverKeys = Set(serverResultsForDisplay.compactMap(identityKey(for:)))
        guard !serverKeys.isEmpty else { return store.results }
        return store.results.filter { result in
            guard let key = identityKey(for: result) else { return true }
            return !serverKeys.contains(key)
        }
    }

    private var cacheKey: GuestLookupCacheKey {
        GuestLookupCacheKey(records: reservations, cachedProfiles: cachedGuestProfiles)
    }

    private var isBookingDisabled: Bool {
        controller.isNetworkDegraded || !controller.capabilities.canCreateManualReservations
    }

    private func refreshCacheIfVisible() {
        guard isActive else { return }
        store.updateCache(records: reservations, cacheKey: cacheKey, context: modelContext)
        store.scheduleSearch(searchText)
    }

    private func submitServerLookup() async {
        let request = serverLookupRequest(for: searchText)
        guard let request else {
            serverCandidates = []
            serverLookupMessage = "Enter a name, email, or at least 7 phone digits."
            lastSubmittedSearch = searchText.trimmedForGuestLookup
            return
        }

        guard !(isSearchingAllGuests && activeLookupKey == request.key) else { return }

        if lastSubmittedSearch != request.submittedText {
            serverCandidates = []
            serverLookupMessage = nil
        }

        isSearchingAllGuests = true
        activeLookupKey = request.key
        lastSubmittedSearch = request.submittedText
        defer {
            if activeLookupKey == request.key {
                isSearchingAllGuests = false
                activeLookupKey = nil
            }
        }

        do {
            let result = try await guestProfileStore.lookupProfiles(
                phone: request.phone,
                email: request.email,
                query: request.query,
                limit: request.limit,
                context: modelContext
            )
            guard activeLookupKey == request.key else { return }
            serverCandidates = result.candidates
            serverLookupMessage = result.candidates.isEmpty ? "No other guest records found." : nil
        } catch {
            guard activeLookupKey == request.key else { return }
            serverLookupMessage = "Couldn't search guest records. Try again."
        }
    }

    private func serverLookupRequest(for text: String) -> GuestServerLookupRequest? {
        let submitted = text.trimmedForGuestLookup
        guard !submitted.isEmpty else { return nil }

        let phoneDigits = GuestLookupPhoneNormalizer.digits(submitted)
        if isLikelyEmail(submitted) {
            return GuestServerLookupRequest(
                phone: nil,
                email: submitted,
                query: nil,
                limit: 5,
                submittedText: submitted
            )
        }

        if phoneDigits.count >= 7 {
            return GuestServerLookupRequest(
                phone: phoneDigits,
                email: nil,
                query: nil,
                limit: 5,
                submittedText: submitted
            )
        }

        let normalizedName = normalizedTextKey(submitted)
        guard normalizedName.count >= 2 else { return nil }
        return GuestServerLookupRequest(
            phone: nil,
            email: nil,
            query: submitted,
            limit: 5,
            submittedText: submitted
        )
    }

    private func profileRoute(for result: GuestLookupResult) -> GuestProfileRoute? {
        guard let guestKey = result.guestKey?.nilIfBlank else { return nil }
        return GuestProfileRoute(guestKey: guestKey)
    }

    private func identityKey(for result: GuestLookupResult) -> String? {
        if let guestKey = result.guestKey?.nilIfBlank {
            return "guest:\(guestKey.lowercased())"
        }
        if let phoneDigits = result.phoneDigits.map(GuestLookupPhoneNormalizer.digits)?.nilIfBlank {
            return "phone:\(phoneDigits)"
        }
        if let email = result.email?.nilIfBlank {
            return "email:\(email.lowercased())"
        }
        let name = normalizedTextKey(result.displayName)
        return name.isEmpty ? nil : "name:\(name)"
    }

    private func isLikelyEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].isEmpty == false,
              parts[1].contains(".") else {
            return false
        }
        return true
    }

    private func normalizedTextKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private struct GuestServerLookupRequest: Hashable {
    let phone: String?
    let email: String?
    let query: String?
    let limit: Int
    let submittedText: String

    var key: String {
        [
            phone ?? "",
            email?.lowercased() ?? "",
            query?.lowercased() ?? "",
            "\(limit)"
        ].joined(separator: "|")
    }
}

private struct GuestProfileRoute: Hashable {
    let guestKey: String
}

// MARK: - Guest Result Card

private struct GuestLookupResultCard: View {
    let result: GuestLookupResult
    let profileRoute: GuestProfileRoute?
    let matchBadgeText: String?
    let isBookingDisabled: Bool
    let onBook: () -> Void

    init(
        result: GuestLookupResult,
        profileRoute: GuestProfileRoute?,
        matchBadgeText: String? = nil,
        isBookingDisabled: Bool,
        onBook: @escaping () -> Void
    ) {
        self.result = result
        self.profileRoute = profileRoute
        self.matchBadgeText = matchBadgeText
        self.isBookingDisabled = isBookingDisabled
        self.onBook = onBook
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if let matchBadgeText {
                    Text(matchBadgeText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(matchBadgeText == "Likely guest" ? TryzubColors.success : TryzubColors.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (matchBadgeText == "Likely guest" ? TryzubColors.success : TryzubColors.warning)
                                .opacity(0.12),
                            in: Capsule()
                        )
                }

                Text("\(result.totalReservations) \(result.totalReservations == 1 ? "reservation" : "reservations")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TryzubColors.mutedText)
            }

            VStack(alignment: .leading, spacing: 5) {
                if let phoneDigits = result.phoneDigits {
                    Label(GuestLookupFormatting.phoneDisplay(phoneDigits), systemImage: "phone")
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

            if let memoryLine {
                Text(memoryLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TryzubColors.mutedText)
                    .lineLimit(2)
            }

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

            HStack(spacing: 8) {
                if let profileRoute {
                    NavigationLink(value: profileRoute) {
                        Label("View history", systemImage: "person.text.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ReservationUIStyle.selectedControlColor)
                    .background(
                        ReservationUIStyle.selectedControlColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    )
                    .accessibilityLabel("View history")
                }

                Button(action: onBook) {
                    Label("Book reservation", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .disabled(isBookingDisabled)
                .opacity(isBookingDisabled ? 0.45 : 1)
                .accessibilityLabel("Book reservation")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(TryzubColors.border, lineWidth: 1)
        }
    }

    private var memoryLine: String? {
        var parts: [String] = []
        if result.isRegularGuest {
            parts.append("Regular guest")
        }
        if result.hasDietaryNote {
            parts.append("Dietary note")
        }
        if let labelSummary = result.labelSummary?.nilIfBlank {
            parts.append(labelSummary)
        }
        if let summaryLine = result.summaryLine?.nilIfBlank {
            parts.append(summaryLine)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct GuestLookupSheet: Identifiable {
    let id = UUID()
    let prefill: ManualReservationPrefill
}

private enum GuestLookupDateFormatter {
    static func display(_ value: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: value) else {
            return value
        }

        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedForGuestLookup: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
