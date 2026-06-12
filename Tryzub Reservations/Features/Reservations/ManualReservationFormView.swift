//
//  ManualReservationFormView.swift
//  Tryzub Reservations
//

import SwiftData
import SwiftUI
import UIKit

// MARK: - Manual Reservation Wrapper

struct ManualReservationFormView: View {
    let failure: ImportFailureDTO?
    let prefill: ManualReservationPrefill?
    let onCreateReservation: (ReservationCreateRequest) async throws -> ReservationDTO

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var controller: ReservationsController
    @State private var draft: ReservationFormDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showCreateConfirmation = false

    init(
        failure: ImportFailureDTO? = nil,
        prefill: ManualReservationPrefill? = nil,
        onCreateReservation: @escaping (ReservationCreateRequest) async throws -> ReservationDTO
    ) {
        self.failure = failure
        self.prefill = prefill
        self.onCreateReservation = onCreateReservation
        _draft = State(initialValue: ReservationFormDraft(failure: failure, prefill: prefill))
    }

    var body: some View {
        NavigationStack {
            ReservationFormContent(
                mode: failure == nil ? .manualCreate : .fixFailedImport,
                draft: $draft,
                originalDraft: nil,
                isSaving: isSaving,
                errorMessage: errorMessage,
                failure: failure,
                reservation: nil,
                showsGuestLookupDetailReminder: prefill?.source == .callInGuestLookup,
                onCancel: { dismiss() },
                onSubmit: { prepareCreateConfirmation() }
            )
        }
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showCreateConfirmation) {
            ReservationFormConfirmationSheet(
                title: "Add Reservation",
                subtitle: "Review the call-in details before accepting this reservation.",
                confirmTitle: "Add Reservation",
                isProcessing: isSaving,
                onConfirm: {
                    Task { await createReservation() }
                },
                onCancel: {
                    showCreateConfirmation = false
                }
            ) {
                ReservationFormChangeReview(createSummary: draft.createSummaryRows())
            }
            .interactiveDismissDisabled(isSaving)
        }
        .task {
            // Lazy form support load: setup provides manual-create defaults only.
            _ = try? await controller.loadRestaurantSetup()
        }
    }

    private func prepareCreateConfirmation() {
        guard validateRequiredFields() else { return }
        dismissKeyboard()
        // Defer one run loop so keyboard teardown finishes before the sheet presents.
        Task { @MainActor in
            await Task.yield()
            FormTrace.event(surface: "manual_add", name: "confirmation_sheet_presented", extra: "mode=create")
            showCreateConfirmation = true
        }
    }

    private func dismissKeyboard() {
        dismissReservationFormKeyboard(reason: "confirmation_sheet")
    }

    // Intent: Staff creates a fast call-in/manual reservation.
    // Network: Caller performs POST /managed-reservations.
    private func createReservation() async {
        guard validateRequiredFields() else { return }

        FormTrace.event(surface: "manual_add", name: "submit_started")
        isSaving = true
        errorMessage = nil
        let saveStarted = ContinuousClock.now

        defer {
            isSaving = false
            let saveMs = Int(saveStarted.duration(to: .now).pressureTraceTimeInterval * 1000)
            FormTrace.event(
                surface: "manual_add",
                name: "submit_completed",
                extra: "durationMs=\(saveMs)"
            )
        }

        do {
            _ = try await onCreateReservation(
                draft.createRequest(
                    sourceSubmissionId: failure?.sourceSubmissionId,
                    sourceType: failure == nil ? .manualCallIn : .importRepair,
                    setup: controller.restaurantSetup
                )
            )
            ReservationHaptics.success()
            showCreateConfirmation = false
            dismiss()
        } catch {
            ReservationHaptics.warning()
            errorMessage = error.isOfflineLike
                ? "Could not save. Check the connection and try again."
                : "Could not save. Check the details and try again."
        }
    }

    private func validateRequiredFields() -> Bool {
        do {
            _ = try ReservationFormValidator.validate(
                draft: draft,
                setup: controller.restaurantSetup,
                applyLeadTime: false
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
            return false
        }
    }
}

// MARK: - Edit Reservation Wrapper

struct ReservationEditFormView: View {
    let reservation: ReservationRecord
    let onSave: (ReservationUpdateRequest) async throws -> ReservationDTO

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var controller: ReservationsController
    @Environment(\.modelContext) private var modelContext
    @State private var draft: ReservationFormDraft
    @State private var originalDraft: ReservationFormDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSaveConfirmation = false
    @State private var isShowingHideConfirmation = false

    init(
        reservation: ReservationRecord,
        onSave: @escaping (ReservationUpdateRequest) async throws -> ReservationDTO
    ) {
        self.reservation = reservation
        self.onSave = onSave
        let initial = ReservationFormDraft(reservation: reservation)
        _draft = State(initialValue: initial)
        _originalDraft = State(initialValue: initial)
    }

    var body: some View {
        ReservationFormContent(
            mode: .edit,
            draft: $draft,
            originalDraft: originalDraft,
            isSaving: isSaving,
                errorMessage: errorMessage,
                failure: nil,
                reservation: reservation,
                showsGuestLookupDetailReminder: false,
                onCancel: { dismiss() },
                onSubmit: { prepareSaveConfirmation() },
                onHideReservation: reservation.canSoftHideAsWrongEntry && !reservation.isHidden
                ? { prepareHideConfirmation() }
                : nil
        )
        .sheet(isPresented: $showSaveConfirmation) {
            ReservationFormConfirmationSheet(
                title: "Save Changes",
                subtitle: "Review the reservation updates before saving.",
                confirmTitle: "Save Changes",
                isProcessing: isSaving,
                onConfirm: {
                    Task { await saveReservation() }
                },
                onCancel: {
                    showSaveConfirmation = false
                }
            ) {
                ReservationFormChangeReview(changes: draft.changes(from: originalDraft))
            }
        }
        .confirmationDialog(
            "Hide this reservation?",
            isPresented: $isShowingHideConfirmation,
            titleVisibility: .visible
        ) {
            Button("Hide reservation", role: .destructive) {
                Task { await hideReservation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the wrong entry from normal staff views. It does not permanently delete it.")
        }
    }

    private func prepareSaveConfirmation() {
        guard validateRequiredFields() else { return }
        if draft.changes(from: originalDraft).isEmpty {
            errorMessage = "No changes to save."
            return
        }
        dismissReservationFormKeyboard(reason: "confirmation_sheet")
        Task { @MainActor in
            await Task.yield()
            FormTrace.event(surface: "manual_add", name: "confirmation_sheet_presented", extra: "mode=edit")
            showSaveConfirmation = true
        }
    }

    private func prepareHideConfirmation() {
        dismissReservationFormKeyboard(reason: "hide_confirmation_dialog")
        Task { @MainActor in
            await Task.yield()
            FormTrace.event(surface: "manual_add", name: "confirmation_sheet_presented", extra: "mode=edit_hide")
            isShowingHideConfirmation = true
        }
    }

    // Intent: Staff edits an existing managed reservation.
    // Network: Caller performs PATCH /managed-reservations/{id}.
    private func saveReservation() async {
        guard validateRequiredFields() else { return }

        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        do {
            _ = try await onSave(draft.updateRequest())
            ReservationHaptics.success()
            showSaveConfirmation = false
            dismiss()
        } catch {
            ReservationHaptics.warning()
            errorMessage = error.isOfflineLike
                ? "Could not save. Check the connection and try again."
                : "Could not save. Check the details and try again."
        }
    }

    private func hideReservation() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await controller.hideWrongEntry(reservation: reservation, context: modelContext)
            ReservationHaptics.warning()
            dismiss()
        } catch {
            errorMessage = "Could not hide this reservation. Please try again."
            ReservationHaptics.warning()
        }
    }

    private func validateRequiredFields() -> Bool {
        do {
            _ = try ReservationFormValidator.validate(
                draft: draft,
                setup: controller.restaurantSetup,
                originalDraft: originalDraft,
                applyLeadTime: false
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
            return false
        }
    }
}

// MARK: - Shared Reservation Form

private enum ReservationFormLayout {
    static let sectionSpacing: CGFloat = 12
    static let columnSpacing: CGFloat = 12
    static let fieldSpacing: CGFloat = 10
    static let chipSpacing: CGFloat = 8
}

private enum ReservationFormMode {
    case manualCreate
    case fixFailedImport
    case edit

    var title: String {
        switch self {
        case .manualCreate:
            return "New Reservation"
        case .fixFailedImport:
            return "Fix Failed Import"
        case .edit:
            return "Edit Reservation"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .manualCreate, .fixFailedImport:
            return "Add Reservation"
        case .edit:
            return "Save Changes"
        }
    }

    var showsEditControls: Bool {
        if case .edit = self {
            return true
        }
        return false
    }

    var usesManualGuestInput: Bool {
        switch self {
        case .manualCreate, .fixFailedImport:
            return true
        case .edit:
            return false
        }
    }

    /// Edit is pushed inside a NavigationStack — back chevron is enough; no Cancel.
    var showsNavigationCancel: Bool {
        switch self {
        case .edit:
            return false
        case .manualCreate, .fixFailedImport:
            return true
        }
    }

    // Edit is pushed inside the tab shell, so its primary button must clear the
    // floating tab bar. Create/fix-import are full-screen covers without it.
    var primaryButtonBottomInset: CGFloat {
        switch self {
        case .edit:
            return ReservationLayout.floatingTabBarClearance
        case .manualCreate, .fixFailedImport:
            return 16
        }
    }
}

private enum ReservationFormField: Hashable, CaseIterable {
    case guestName
    case phone
    case email
    case guestNotes
    case staffNotes
    case tableName
    case supersededById

    var traceName: String {
        switch self {
        case .guestName: return "guest_name"
        case .phone: return "phone"
        case .email: return "email"
        case .guestNotes: return "guest_notes"
        case .staffNotes: return "staff_notes"
        case .tableName: return "table_name"
        case .supersededById: return "superseded_by_id"
        }
    }

    func next(in order: [ReservationFormField]) -> ReservationFormField? {
        guard let index = order.firstIndex(of: self), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    func previous(in order: [ReservationFormField]) -> ReservationFormField? {
        guard let index = order.firstIndex(of: self), index > 0 else { return nil }
        return order[index - 1]
    }
}

private struct ReservationFormContent: View {
    let mode: ReservationFormMode
    @Binding var draft: ReservationFormDraft
    let originalDraft: ReservationFormDraft?
    let isSaving: Bool
    let errorMessage: String?
    let failure: ImportFailureDTO?
    var reservation: ReservationRecord?
    var showsGuestLookupDetailReminder = false
    let onCancel: () -> Void
    let onSubmit: () -> Void
    var onHideReservation: (() -> Void)?

    @EnvironmentObject private var controller: ReservationsController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(
        filter: #Predicate<ReservationRecord> { record in
            !record.isHidden
        },
        sort: [
            SortDescriptor(\ReservationRecord.reservationDate, order: .reverse),
            SortDescriptor(\ReservationRecord.reservationTime, order: .reverse)
        ]
    )
    private var guestLookupRecords: [ReservationRecord]
    @StateObject private var guestPhoneLookupStore = GuestLookupStore()
    @EnvironmentObject private var hostTableConfigStore: HostTableConfigStore
    @StateObject private var hostIntelligenceSettingsStore = HostIntelligenceSettingsStore()
    @StateObject private var manualReservationFacade = ManualReservationFacade()
    @State private var suppressedGuestPhoneSuggestionID: String?
    @State private var slotContext: HostReservationSlotContext?
    @State private var isCustomTimePresented = false
    @State private var didApplyInitialSettings = false
    @State private var hasAttemptedSave = false
    @State private var cachedDayReservationsDateKey: String?
    @State private var cachedDayReservations: [ReservationRecord] = []
    @State private var slotContextRefreshTask: Task<Void, Never>?
    @FocusState private var focusedField: ReservationFormField?

    private var dayAvailability: RestaurantDayAvailabilityDTO? {
        manualReservationFacade.dayAvailability
    }

    private var suggestedSlots: ReservationSlotsResponseDTO? {
        manualReservationFacade.suggestedSlots
    }

    private var blockedSlotValues: Set<String> {
        manualReservationFacade.blockedSlotValues
    }

    private var isLoadingPublicSlots: Bool {
        manualReservationFacade.isLoadingPublicSlots
    }

    private var publicSlotsError: String? {
        manualReservationFacade.publicSlotsError
    }

    private var loadedSlotsDateKey: String? {
        manualReservationFacade.viewState?.selectedDateKey
    }

    private var loadedAvailabilityDateKey: String? {
        manualReservationFacade.viewState?.selectedDateKey
    }

    private var isWideForm: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ScrollView {
            formShell
                .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode.showsNavigationCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(ReservationUIStyle.cancelColor)
                        .tint(ReservationUIStyle.cancelColor)
                        .disabled(isSaving)
                }
            }
        }
        .onAppear {
            applyInitialSettingsIfNeeded()
            prepareAvailabilityState()
            refreshSlotContext()
            refreshGuestPhoneLookup()
        }
        .task(id: guestLookupCacheKey) {
            guestPhoneLookupStore.updateCache(
                records: guestLookupRecords,
                cacheKey: guestLookupCacheKey
            )
            guestPhoneLookupStore.schedulePhoneLookup(draft.phone)
        }
        .onChange(of: draft.phone) { _, _ in
            suppressedGuestPhoneSuggestionID = nil
            guestPhoneLookupStore.schedulePhoneLookup(draft.phone)
        }
        .onChange(of: guestPhoneLookupStore.phoneMatch?.id) { _, _ in
            guard let match = guestPhoneLookupStore.phoneMatch else { return }
            guard shouldAutoApplyGuestPhoneSuggestion(match) else { return }
            applyGuestPhoneSuggestion(match)
        }
        .onChange(of: draft.reservationDate.reservationDateString()) { _, newDateKey in
            cachedDayReservationsDateKey = nil
            cachedDayReservations = []
            prepareAvailabilityState()
            FormTrace.event(
                surface: "manual_add",
                name: "date_changed",
                extra: "date=\(newDateKey)"
            )
        }
        .onChange(of: loadedSlotsDateKey) { _, _ in
            syncSelectedTimeToAvailableChoicesIfNeeded()
            refreshSlotContext()
        }
        .onChange(of: loadedAvailabilityDateKey) { _, _ in
            syncSelectedTimeToAvailableChoicesIfNeeded()
            refreshSlotContext()
        }
        .onChange(of: slotContextRefreshKey) { _, _ in
            refreshSlotContext()
        }
        .onChange(of: focusedField) { _, newValue in
            guard let newValue else { return }
            FormTrace.event(
                surface: "manual_add",
                name: "focus_changed",
                extra: "field=\(newValue.traceName)"
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let focusedField, let previous = focusedField.previous(in: focusFieldOrder) {
                    Button("Previous") {
                        self.focusedField = previous
                    }
                }
                if let focusedField, let next = focusedField.next(in: focusFieldOrder) {
                    Button("Next") {
                        self.focusedField = next
                    }
                }
                Spacer()
                Button("Done") {
                    dismissReservationFormKeyboard(reason: "keyboard_done")
                    self.focusedField = nil
                }
            }
        }
        .onDisappear {
            slotContextRefreshTask?.cancel()
            slotContextRefreshTask = nil
            manualReservationFacade.cancelLoads()
        }
        .safeAreaInset(edge: .bottom) {
            primaryActionButton
        }
    }

    private var formShell: some View {
        formFields
            .frame(maxWidth: isWideForm ? 920 : 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, isWideForm ? 20 : 16)
            .padding(.top, 8)
    }

    private func formColumnPair<Left: View, Right: View>(
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .top, spacing: ReservationFormLayout.columnSpacing) {
            left()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            right()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: ReservationFormLayout.sectionSpacing) {
            formBanners

            if isWideForm {
                formColumnPair {
                    contactCard
                } right: {
                    dateCard
                }

                serviceChoicesGrid
                slotContextBanner

                if mode.showsEditControls {
                    formColumnPair {
                        editDetailsCard
                    } right: {
                        notesSection
                    }
                } else {
                    notesSection
                }
            } else {
                contactCard
                dateCard
                serviceChoicesGrid
                slotContextBanner

                if mode.showsEditControls {
                    editDetailsCard
                }

                notesSection
            }
        }
    }

    @ViewBuilder
    private var formBanners: some View {
        VStack(alignment: .leading, spacing: ReservationFormLayout.sectionSpacing) {
            if let errorMessage {
                ReservationFormWarningCard(message: errorMessage)
            }

            if controller.isNetworkDegraded {
                ReservationFormWarningCard(message: "Connection is weak. You can view saved reservations, but saving needs internet.")
            }

            if showsGuestLookupDetailReminder {
                ReservationFormInfoCard(message: "Confirm details before submitting.")
            }

            if let formBlockingMessage {
                ReservationFormWarningCard(message: formBlockingMessage)
            }

            if let failure {
                ReservationFormImportCard(failure: failure)
            }
        }
    }

    private var contactCard: some View {
        ReservationFormSection(title: "Guest", systemImage: "person") {
            VStack(spacing: ReservationFormLayout.fieldSpacing) {
                if isWideForm {
                    guestInputFields
                } else {
                    HStack(spacing: ReservationFormLayout.fieldSpacing) {
                        guestNameField
                        guestPhoneField
                    }
                    guestEmailField
                }

                if let suggestion = visibleGuestPhoneSuggestion {
                    GuestPhoneLookupSuggestionRow(
                        result: suggestion,
                        onUse: {
                            applyGuestPhoneSuggestion(suggestion)
                        },
                        onDismiss: {
                            suppressedGuestPhoneSuggestionID = suggestion.id
                        }
                    )
                }

                if mode.usesManualGuestInput {
                    GuestTextMessageActionButtons(
                        phone: draft.phone,
                        confirmationBody: manualTextConfirmationBody,
                        tableDueBody: manualTextTableDueBody,
                        isCompact: !isWideForm
                    )
                }
            }
        }
        .onAppear {
            guard mode.usesManualGuestInput else { return }
            if draft.guestName.contains(where: \.isNumber) {
                draft.guestName = ReservationInputNormalizer.sanitizedGuestName(draft.guestName)
            }
            if draft.phone.allSatisfy(\.isNumber), !draft.phone.isEmpty {
                draft.phone = ReservationInputNormalizer.sanitizedUSPhoneInput(draft.phone)
            }
            refreshGuestPhoneLookup()
        }
    }

    private var guestLookupCacheKey: GuestLookupCacheKey {
        GuestLookupCacheKey(records: guestLookupRecords)
    }

    private var focusFieldOrder: [ReservationFormField] {
        var order: [ReservationFormField] = [.guestName, .phone, .email, .guestNotes, .staffNotes]
        if mode.showsEditControls {
            order.append(contentsOf: [.tableName, .supersededById])
        }
        return order
    }

    private var visibleGuestPhoneSuggestion: GuestLookupResult? {
        guard mode.usesManualGuestInput else { return nil }
        guard draft.phone.filter(\.isNumber).count >= 10 else { return nil }
        guard let match = guestPhoneLookupStore.phoneMatch else { return nil }
        guard suppressedGuestPhoneSuggestionID != match.id else { return nil }
        guard !draftAlreadyMatchesGuest(match) else { return nil }
        return match
    }

    private func refreshGuestPhoneLookup() {
        guard mode.usesManualGuestInput else { return }
        guestPhoneLookupStore.updateCache(
            records: guestLookupRecords,
            cacheKey: guestLookupCacheKey
        )
        guestPhoneLookupStore.schedulePhoneLookup(draft.phone)
    }

    private func shouldAutoApplyGuestPhoneSuggestion(_ result: GuestLookupResult) -> Bool {
        let draftDigits = draft.phone.filter(\.isNumber)
        guard draftDigits.count >= 10,
              let phoneDigits = result.phoneDigits else {
            return false
        }
        guard phoneDigits == draftDigits || phoneDigits.hasSuffix(draftDigits) else {
            return false
        }
        return draft.guestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func draftAlreadyMatchesGuest(_ result: GuestLookupResult) -> Bool {
        let trimmedName = draft.guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameMatches = !trimmedName.isEmpty
            && trimmedName.localizedCaseInsensitiveCompare(result.displayName) == .orderedSame

        let draftDigits = draft.phone.filter(\.isNumber)
        guard let resultDigits = result.phoneDigits, !draftDigits.isEmpty else {
            return nameMatches
        }

        let phoneMatches = draftDigits == resultDigits
            || (draftDigits.count >= 10 && resultDigits.hasSuffix(String(draftDigits.suffix(10))))

        if let email = result.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            let draftEmail = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
            return nameMatches && phoneMatches && draftEmail.localizedCaseInsensitiveCompare(email) == .orderedSame
        }

        return nameMatches && phoneMatches
    }

    private func applyGuestPhoneSuggestion(_ result: GuestLookupResult) {
        draft.guestName = result.displayName
        if let phoneDigits = result.phoneDigits {
            draft.phone = ReservationInputNormalizer.sanitizedUSPhoneInput(phoneDigits)
        }
        if let email = result.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            draft.email = email
        }
        suppressedGuestPhoneSuggestionID = nil
        ReservationHaptics.selection()
    }

    private var manualTextConfirmationBody: String {
        ManualTextMessageService.confirmationBody(
            guestName: draft.guestName,
            reservationDate: draft.reservationDate,
            reservationTime: draft.reservationTime,
            partySize: draft.partySize,
            tableName: draft.tableName.nilIfBlank
        )
    }

    private var manualTextTableDueBody: String {
        ManualTextMessageService.tableDueBody(
            guestName: draft.guestName,
            tableName: draft.tableName.nilIfBlank
        )
    }

    @ViewBuilder
    private var guestInputFields: some View {
        guestNameField
        guestPhoneField
        guestEmailField
    }

    @ViewBuilder
    private var guestNameField: some View {
        ReservationFormTextField(
            title: "Name",
            text: $draft.guestName,
            prompt: "Guest name",
            inputKind: .guestName,
            field: .guestName,
            focusedField: $focusedField,
            error: guestNameFieldError
        )
    }

    @ViewBuilder
    private var guestPhoneField: some View {
        ReservationFormTextField(
            title: "Phone",
            text: $draft.phone,
            prompt: mode.usesManualGuestInput ? "(312) 345-5674" : "Phone",
            inputKind: .guestPhone,
            field: .phone,
            focusedField: $focusedField,
            error: phoneFieldError
        )
    }

    @ViewBuilder
    private var guestEmailField: some View {
        ReservationFormTextField(
            title: "Email optional",
            text: $draft.email,
            prompt: "Leave blank if none",
            inputKind: .guestEmail,
            field: .email,
            focusedField: $focusedField,
            error: emailFieldError
        )
    }

    private var dateCard: some View {
        ReservationFormSection(title: "Date", systemImage: "calendar") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ReservationFormLayout.chipSpacing) {
                    ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                        dateChoiceButton(date)
                    }
                }
            }

            HStack {
                ReservationOpenCalendarButton(selectedDate: $draft.reservationDate)
                Spacer()
                Text(draft.reservationDate.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var serviceChoicesGrid: some View {
        Group {
            if isWideForm {
                formColumnPair {
                    timeCard
                } right: {
                    partyCard
                }
            } else {
                VStack(alignment: .leading, spacing: ReservationFormLayout.sectionSpacing) {
                    timeCard
                    partyCard
                }
            }
        }
    }

    private var timeCard: some View {
        ReservationFormSection(title: "Time", systemImage: "clock") {
            if isLoadingPublicSlots && timeChoices.isEmpty {
                ProgressView("Checking available times...")
                    .font(.subheadline)
                    .frame(minHeight: 32, alignment: .leading)
            } else if shouldBlockClosedDate {
                Text("This date is closed. Choose another date.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TryzubColors.danger)
            } else if timeChoices.isEmpty {
                Text("No service times for this date. Use Custom.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: timeColumns,
                    spacing: ReservationFormLayout.chipSpacing
                ) {
                    ForEach(timeChoices, id: \.self) { time in
                        Button {
                            draft.reservationTime = time
                            ReservationHaptics.selection()
                        } label: {
                            ReservationChoiceChip(
                                title: timeLabel(time),
                                isSelected: isSameTime(draft.reservationTime, time),
                                minWidth: 58,
                                minHeight: 36
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let statusLine = manualReservationFacade.viewState?.statusLine {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let publicSlotsError {
                Text(publicSlotsError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let blockedWarningText {
                Label(blockedWarningText, systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TryzubColors.danger)
            }

            if hasAttemptedSave, let timeValidationMessage {
                Label(timeValidationMessage, systemImage: "clock.badge.exclamationmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TryzubColors.danger)
            }

            if !shouldBlockClosedDate {
                HStack(spacing: 10) {
                    Button {
                        isCustomTimePresented = true
                        ReservationHaptics.selection()
                    } label: {
                        Label("Custom", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: $isCustomTimePresented) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Custom Time")
                                .font(.headline.weight(.semibold))
                            DatePicker("Time", selection: $draft.reservationTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                            Button("Done") {
                                isCustomTimePresented = false
                                ReservationHaptics.selection()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .frame(minWidth: 260, minHeight: 240)
                        .presentationCompactAdaptation(.popover)
                    }

                    Spacer()

                    if !timeChoices.contains(where: { isSameTime($0, draft.reservationTime) }) {
                        ReservationChoiceChip(
                            title: timeLabel(draft.reservationTime),
                            subtitle: "Custom",
                            isSelected: true,
                            minWidth: 58,
                            minHeight: 36,
                            fillsWidth: false
                        )
                    }
                }
            }
        }
    }

    private var partyCard: some View {
        ReservationFormSection(title: "Party", systemImage: "person.2") {
            LazyVGrid(
                columns: partyColumns,
                spacing: ReservationFormLayout.chipSpacing
            ) {
                ForEach(1...8, id: \.self) { size in
                    Button {
                        draft.partySize = size
                        ReservationHaptics.selection()
                    } label: {
                        ReservationChoiceChip(
                            title: "\(size)",
                            isSelected: draft.partySize == size,
                            minWidth: 40,
                            minHeight: 36
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: ReservationFormLayout.fieldSpacing) {
                Text("Party of \(draft.partySize)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("Party of \(draft.partySize)", value: $draft.partySize, in: 1...60)
                    .labelsHidden()
            }
        }
    }

    private var partyColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: ReservationFormLayout.chipSpacing),
            count: 4
        )
    }

    private var timeColumns: [GridItem] {
        let count = isWideForm ? 4 : 3
        return Array(
            repeating: GridItem(.flexible(), spacing: ReservationFormLayout.chipSpacing),
            count: count
        )
    }

    private var slotContextRefreshKey: String {
        let dateKey = draft.reservationDate.reservationDateString()
        let timeKey = ReservationFormatters.apiTime.string(from: draft.reservationTime)
        let excludeID = reservation?.remoteID ?? 0
        return "\(dateKey)|\(timeKey)|\(draft.partySize)|\(excludeID)|\(loadedSlotsDateKey ?? "")|\(blockedSlotValues.sorted().joined(separator: ","))"
    }

    private var slotContextBanner: some View {
        HostReservationSlotContextBanner(context: slotContext)
    }

    private func refreshSlotContext() {
        slotContextRefreshTask?.cancel()
        let dateKey = draft.reservationDate.reservationDateString()
        let serviceTime = draft.reservationTime
        let partySize = draft.partySize
        let excludeID = reservation?.remoteID
        let blocked = blockedSlotValues
        let isClosed = activeSuggestedSlots?.isOpen == false || activeDayAvailability?.isOpen == false
        let tables = hostTableConfigStore.tables
        let settings = hostIntelligenceSettingsStore.settings
        let nearbyChoices = timeChoices

        slotContextRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(75))
            guard !Task.isCancelled else { return }

            let dayReservations: [ReservationRecord]
            if cachedDayReservationsDateKey == dateKey {
                dayReservations = cachedDayReservations
            } else {
                let fetched = fetchDayReservations(dateKey: dateKey)
                cachedDayReservationsDateKey = dateKey
                cachedDayReservations = fetched
                dayReservations = fetched
            }

            slotContext = HostReservationSlotContextSupport.build(
                serviceDate: draft.reservationDate,
                serviceTime: serviceTime,
                partySize: partySize,
                excludingReservationID: excludeID,
                dayReservations: dayReservations,
                blockedSlotValues: blocked,
                isServiceClosed: isClosed,
                tableConfigs: tables,
                settings: settings,
                nearbyTimeChoices: nearbyChoices
            )
        }
    }

    private func fetchDayReservations(dateKey: String) -> [ReservationRecord] {
        let predicate = #Predicate<ReservationRecord> { record in
            record.reservationDate == dateKey && record.isHidden == false
        }
        let descriptor = FetchDescriptor<ReservationRecord>(predicate: predicate)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var editDetailsCard: some View {
        ReservationFormSection(title: "Service Details", systemImage: "slider.horizontal.3") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ReservationFormLayout.chipSpacing) {
                    ForEach(ReservationStatus.allCases) { status in
                        Button {
                            draft.status = status
                            ReservationHaptics.selection()
                        } label: {
                            ReservationChoiceChip(
                                title: status.shortDisplayName,
                                isSelected: draft.status == status,
                                minWidth: 88,
                                minHeight: 36,
                                fillsWidth: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: ReservationFormLayout.fieldSpacing) {
                ReservationFormTextField(
                    title: "Table",
                    text: $draft.tableName,
                    prompt: "Unassigned",
                    inputKind: .tableName,
                    field: .tableName,
                    focusedField: $focusedField
                )
                ReservationFormTextField(
                    title: "Superseded by",
                    text: $draft.supersededById,
                    prompt: "ID",
                    inputKind: .numericID,
                    field: .supersededById,
                    focusedField: $focusedField
                )
            }

            if let onHideReservation {
                Button(role: .destructive, action: onHideReservation) {
                    Label("Hide reservation", systemImage: "archivebox")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(TryzubColors.danger)
            }
        }
    }

    private var notesSection: some View {
        ReservationFormSection(title: "Notes", systemImage: "note.text") {
            if isWideForm && !mode.showsEditControls {
                HStack(alignment: .top, spacing: ReservationFormLayout.fieldSpacing) {
                    ReservationFormTextEditor(
                        title: "Guest notes",
                        text: $draft.guestNotes,
                        minHeight: 108,
                        field: .guestNotes,
                        focusedField: $focusedField
                    )
                    ReservationFormTextEditor(
                        title: "Staff notes",
                        text: $draft.staffNotes,
                        minHeight: 108,
                        field: .staffNotes,
                        focusedField: $focusedField
                    )
                }
            } else if isWideForm && mode.showsEditControls {
                VStack(spacing: ReservationFormLayout.fieldSpacing) {
                    ReservationFormTextEditor(
                        title: "Guest notes",
                        text: $draft.guestNotes,
                        minHeight: 88,
                        field: .guestNotes,
                        focusedField: $focusedField
                    )
                    ReservationFormTextEditor(
                        title: "Staff notes",
                        text: $draft.staffNotes,
                        minHeight: 88,
                        field: .staffNotes,
                        focusedField: $focusedField
                    )
                }
            } else {
                VStack(spacing: ReservationFormLayout.fieldSpacing) {
                    ReservationFormTextEditor(
                        title: "Guest notes",
                        text: $draft.guestNotes,
                        minHeight: 88,
                        field: .guestNotes,
                        focusedField: $focusedField
                    )
                    ReservationFormTextEditor(
                        title: "Staff notes",
                        text: $draft.staffNotes,
                        minHeight: 88,
                        field: .staffNotes,
                        focusedField: $focusedField
                    )
                }
            }
        }
    }

    private var primaryActionButton: some View {
        let isSubmitDisabled = controller.isNetworkDegraded || availabilityBlockingMessage != nil

        return VStack(spacing: 0) {
            Divider()

            Group {
                if isSaving {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    Button(mode.primaryActionTitle, action: submitIfValid)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(isSubmitDisabled)
                }
            }
            .frame(maxWidth: isWideForm ? 680 : .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, mode.primaryButtonBottomInset)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }

    private func submitIfValid() {
        hasAttemptedSave = true
        dismissReservationFormKeyboard(reason: "submit")
        focusedField = nil
        guard !controller.isNetworkDegraded,
              availabilityBlockingMessage == nil,
              validationErrorMessage == nil,
              !isSaving else {
            ReservationHaptics.warning()
            return
        }
        onSubmit()
    }

    /// Staff intake forms share the same service-time grid as call-in create — no guest lead time.
    private var appliesStaffLeadTime: Bool { false }

    private var formBlockingMessage: String? {
        availabilityBlockingMessage
    }

    private var guestNameFieldError: String? {
        guard hasAttemptedSave else { return nil }
        let guestName = ReservationInputNormalizer.collapsedWhitespace(draft.guestName)
        guard guestName.count < 2 else { return nil }
        return "Add the guest name before saving."
    }

    private var phoneFieldError: String? {
        guard hasAttemptedSave else { return nil }
        let phoneDigits = ReservationInputNormalizer.phoneDigits(draft.phone)
        guard !ReservationFormValidator.isPlausibleUSPhone(phoneDigits) else { return nil }
        return "Add a valid 10-digit phone number before saving."
    }

    private var emailFieldError: String? {
        guard hasAttemptedSave else { return nil }
        let email = ReservationInputNormalizer.normalizedEmail(draft.email)
        guard !email.isEmpty, !ReservationFormValidator.isPlausibleEmail(email) else { return nil }
        return "Enter a valid email address or leave email blank."
    }

    private var availabilityBlockingMessage: String? {
        availabilityValidationMessage
    }

    private var validationErrorMessage: String? {
        do {
            _ = try ReservationFormValidator.validate(
                draft: draft,
                setup: controller.restaurantSetup,
                originalDraft: originalDraft,
                applyLeadTime: appliesStaffLeadTime
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var availabilityValidationMessage: String? {
        let dateKey = draft.reservationDate.reservationDateString()
        if isLoadingPublicSlots
            && loadedSlotsDateKey != dateKey
            && loadedAvailabilityDateKey != dateKey
            && activeSuggestedSlots == nil {
            return "Loading open times for this date."
        }

        if shouldBlockClosedDate {
            return "This date is closed. Choose another date."
        }

        if shouldBlockUnverifiedDate {
            return "Could not verify this date is open. Try again before saving."
        }

        return nil
    }

    private var shouldBlockClosedDate: Bool {
        let isClosed = activeSuggestedSlots?.isOpen == false || activeDayAvailability?.isOpen == false
        guard isClosed else { return false }
        return !isOriginalDateTimeUnchanged
    }

    private var shouldBlockUnverifiedDate: Bool {
        guard publicSlotsError != nil,
              activeSuggestedSlots == nil,
              activeDayAvailability == nil else {
            return false
        }
        return !isOriginalDateTimeUnchanged
    }

    private var isOriginalDateTimeUnchanged: Bool {
        guard let originalDraft else { return false }
        return Calendar.current.isDate(originalDraft.reservationDate, inSameDayAs: draft.reservationDate)
            && isSameTime(originalDraft.reservationTime, draft.reservationTime)
    }

    private var timeValidationMessage: String? {
        ReservationFormValidator.timeValidationMessage(
            draft: draft,
            setup: controller.restaurantSetup,
            originalDraft: originalDraft,
            applyLeadTime: appliesStaffLeadTime
        )
    }

    private var quickDates: [Date] {
        controller.restaurantSetup.suggestedServiceDates(count: 10)
    }

    private func dateTitle(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var timeChoices: [Date] {
        staffTimeChoices(for: draft.reservationDate).filter(isTimeChoiceAllowed)
    }

    private func staffTimeChoices(for serviceDate: Date) -> [Date] {
        let setup = controller.restaurantSetup
        let calendar = Calendar.current
        let dateKey = serviceDate.reservationDateString()

        if let slots = resolvedPublicSlots(for: dateKey), !slots.slots.isEmpty {
            let parsed = slots.slots.compactMap { slot in
                ManualReservationFormPresenter.serviceDateTime(
                    for: slot.value,
                    on: serviceDate,
                    calendar: calendar
                )
            }
            if !parsed.isEmpty {
                return parsed.sorted()
            }
        }

        let availability = resolvedDayAvailability(for: dateKey)
        return setup.suggestedTimes(
            for: serviceDate,
            applyLeadTime: false,
            openTime: availability?.openTime,
            closeTime: availability?.closeTime,
            slotIntervalMinutes: availability?.slotIntervalMinutes
        )
    }

    private func resolvedPublicSlots(for dateKey: String) -> ReservationSlotsResponseDTO? {
        if loadedSlotsDateKey == dateKey {
            return suggestedSlots
        }
        return controller.cachedReservationSlots(date: dateKey)
    }

    private func resolvedDayAvailability(for dateKey: String) -> RestaurantDayAvailabilityDTO? {
        if loadedAvailabilityDateKey == dateKey {
            return dayAvailability
        }
        return controller.cachedRestaurantDayAvailability(date: dateKey)
    }

    private var activeSuggestedSlots: ReservationSlotsResponseDTO? {
        loadedSlotsDateKey == draft.reservationDate.reservationDateString() ? suggestedSlots : nil
    }

    private var activeDayAvailability: RestaurantDayAvailabilityDTO? {
        loadedAvailabilityDateKey == draft.reservationDate.reservationDateString() ? dayAvailability : nil
    }

    private func timeLabel(_ date: Date) -> String {
        ReservationFormatters.shortTime.string(from: date)
    }

    private func isTimeChoiceAllowed(_ time: Date) -> Bool {
        var testDraft = draft
        testDraft.reservationTime = time
        return ReservationFormValidator.timeValidationMessage(
            draft: testDraft,
            setup: controller.restaurantSetup,
            originalDraft: nil,
            applyLeadTime: appliesStaffLeadTime
        ) == nil
    }

    private func isSameTime(_ lhs: Date, _ rhs: Date) -> Bool {
        let lhsParts = Calendar.current.dateComponents([.hour, .minute], from: lhs)
        let rhsParts = Calendar.current.dateComponents([.hour, .minute], from: rhs)
        return lhsParts.hour == rhsParts.hour && lhsParts.minute == rhsParts.minute
    }

    private func dateChoiceButton(_ date: Date) -> some View {
        Button {
            draft.reservationDate = date
            if let firstTime = staffTimeChoices(for: date).first(where: isTimeChoiceAllowed) {
                draft.reservationTime = firstTime
            }
            ReservationHaptics.selection()
        } label: {
            ReservationChoiceChip(
                title: dateTitle(date),
                subtitle: date.formatted(.dateTime.weekday(.abbreviated)),
                isSelected: Calendar.current.isDate(draft.reservationDate, inSameDayAs: date),
                minWidth: 68,
                minHeight: 36,
                fillsWidth: false
            )
        }
        .buttonStyle(.plain)
    }

    private func applyInitialSettingsIfNeeded() {
        guard !didApplyInitialSettings else { return }
        didApplyInitialSettings = true

        switch mode {
        case .manualCreate:
            draft.applyDefaultStaffServiceSlot(
                setup: controller.restaurantSetup,
                availability: controller.cachedRestaurantDayAvailability(
                    date: draft.reservationDate.reservationDateString()
                ),
                publicSlots: controller.cachedReservationSlots(
                    date: draft.reservationDate.reservationDateString()
                )
            )
        case .fixFailedImport:
            draft.status = .confirmed
            if staffTimeChoices(for: draft.reservationDate).isEmpty {
                draft.applyDefaultStaffServiceSlot(
                    setup: controller.restaurantSetup,
                    keepGuestFields: true,
                    availability: controller.cachedRestaurantDayAvailability(
                        date: draft.reservationDate.reservationDateString()
                    ),
                    publicSlots: controller.cachedReservationSlots(
                        date: draft.reservationDate.reservationDateString()
                    )
                )
            }
        case .edit:
            break
        }
    }

    private func syncSelectedTimeToAvailableChoicesIfNeeded() {
        guard mode == .manualCreate || mode == .fixFailedImport else { return }
        let choices = staffTimeChoices(for: draft.reservationDate).filter(isTimeChoiceAllowed)
        guard let first = choices.first else { return }
        if !choices.contains(where: { isSameTime($0, draft.reservationTime) }) {
            draft.reservationTime = first
        }
    }

    private var blockedWarningText: String? {
        ManualReservationFormPresenter.blockedWarningText(
            selectedTime: draft.reservationTime,
            blockedSlotValues: blockedSlotValues
        )
    }

    private func prepareAvailabilityState() {
        manualReservationFacade.prepare(
            date: draft.reservationDate,
            controller: controller,
            canSubmit: availabilityBlockingMessage == nil,
            blockingWarning: availabilityBlockingMessage
        )
    }
}

// MARK: - Manual Form Presentation

private enum ManualReservationFormPresenter {
    private static let timeWithSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let timeWithoutSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func dateForSlotValue(_ value: String) -> Date? {
        timeWithSeconds.date(from: value) ?? timeWithoutSeconds.date(from: value)
    }

    static func serviceDateTime(
        for slotValue: String,
        on serviceDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let parsed = dateForSlotValue(slotValue) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: parsed)
        return calendar.date(
            bySettingHour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: 0,
            of: serviceDate
        )
    }

    static func blockedWarningText(
        selectedTime: Date,
        blockedSlotValues: Set<String>
    ) -> String? {
        let selectedValue = shortSlotValue(ReservationFormatters.apiTime.string(from: selectedTime))
        return blockedSlotValues.contains(selectedValue)
            ? "This time is blocked from the public form."
            : nil
    }

    static func shortSlotValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return trimmed }
        return String(trimmed.prefix(5))
    }
}

// MARK: - Draft Model

private struct ReservationFormState {
    let guestName: String
    let email: String
    let phoneDigits: String
    let partySize: Int
    let guestNotes: String?
    let staffNotes: String?
    let tableName: String?
}

private enum ReservationInputNormalizer {
    static func collapsedWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func phoneDigits(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedOptionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func sanitizedGuestName(_ value: String) -> String {
        let withoutDigits = value.filter { !$0.isNumber }
        return withoutDigits
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                guard let first = word.first else { return String(word) }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    static func sanitizedUSPhoneInput(_ value: String) -> String {
        var digits = value.filter(\.isNumber)
        while digits.first == "1" {
            digits.removeFirst()
        }
        return formatUSPhoneDisplay(String(digits.prefix(10)))
    }

    static func formatUSPhoneDisplay(_ digits: String) -> String {
        guard !digits.isEmpty else { return "" }

        var formatted = ""
        for (index, character) in digits.enumerated() {
            switch index {
            case 0:
                formatted += "("
            case 3:
                formatted += ") "
            case 6:
                formatted += "-"
            default:
                break
            }
            formatted.append(character)
        }
        return formatted
    }
}

private enum ReservationFormValidator {
    static func validate(
        draft: ReservationFormDraft,
        setup: RestaurantSetup,
        originalDraft: ReservationFormDraft? = nil,
        applyLeadTime: Bool = true
    ) throws -> ReservationFormState {
        let guestName = ReservationInputNormalizer.collapsedWhitespace(draft.guestName)
        guard guestName.count >= 2 else {
            throw ReservationFormValidationError(message: "Add the guest name before saving.")
        }

        let phoneDigits = ReservationInputNormalizer.phoneDigits(draft.phone)
        guard isPlausibleUSPhone(phoneDigits) else {
            throw ReservationFormValidationError(message: "Add a valid 10-digit phone number before saving.")
        }

        let email = ReservationInputNormalizer.normalizedEmail(draft.email)
        if !email.isEmpty, !isPlausibleEmail(email) {
            throw ReservationFormValidationError(message: "Enter a valid email address or leave email blank.")
        }

        guard (1...60).contains(draft.partySize) else {
            throw ReservationFormValidationError(message: "Party size must be at least 1.")
        }

        if let message = timeValidationMessage(
            draft: draft,
            setup: setup,
            originalDraft: originalDraft,
            applyLeadTime: applyLeadTime
        ) {
            throw ReservationFormValidationError(message: message)
        }

        return ReservationFormState(
            guestName: guestName,
            email: email,
            phoneDigits: phoneDigits,
            partySize: draft.partySize,
            guestNotes: ReservationInputNormalizer.normalizedOptionalText(draft.guestNotes),
            staffNotes: ReservationInputNormalizer.normalizedOptionalText(draft.staffNotes),
            tableName: ReservationInputNormalizer.normalizedOptionalText(draft.tableName)
        )
    }

    static func timeValidationMessage(
        draft: ReservationFormDraft,
        setup: RestaurantSetup,
        originalDraft: ReservationFormDraft? = nil,
        applyLeadTime: Bool = true,
        now: Date = Date()
    ) -> String? {
        if let originalDraft,
           Calendar.current.isDate(originalDraft.reservationDate, inSameDayAs: draft.reservationDate),
           isSameClockTime(originalDraft.reservationTime, draft.reservationTime) {
            return nil
        }

        let timeZone = TimeZone(identifier: setup.timezone) ?? TimeZone(identifier: "America/Chicago") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        guard calendar.isDate(draft.reservationDate, inSameDayAs: now),
              let selectedServiceTime = serviceDateTime(for: draft, calendar: calendar) else {
            return nil
        }

        let leadMinutes = applyLeadTime ? max(setup.minimumLeadTimeMinutes, 0) : 0
        let earliestAllowed = calendar.date(byAdding: .minute, value: leadMinutes, to: now) ?? now
        if selectedServiceTime <= now {
            return "This time has already passed. Choose a later time."
        }
        if leadMinutes > 0, selectedServiceTime < earliestAllowed {
            return "Choose a time at least \(leadMinutes) minutes from now."
        }
        return nil
    }

    private static func serviceDateTime(for draft: ReservationFormDraft, calendar: Calendar) -> Date? {
        let dateParts = calendar.dateComponents([.year, .month, .day], from: draft.reservationDate)
        let timeParts = Calendar.current.dateComponents([.hour, .minute], from: draft.reservationTime)
        var components = DateComponents()
        components.timeZone = calendar.timeZone
        components.year = dateParts.year
        components.month = dateParts.month
        components.day = dateParts.day
        components.hour = timeParts.hour
        components.minute = timeParts.minute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func isSameClockTime(_ lhs: Date, _ rhs: Date) -> Bool {
        let lhsParts = Calendar.current.dateComponents([.hour, .minute], from: lhs)
        let rhsParts = Calendar.current.dateComponents([.hour, .minute], from: rhs)
        return lhsParts.hour == rhsParts.hour && lhsParts.minute == rhsParts.minute
    }

    static func isPlausibleUSPhone(_ digits: String) -> Bool {
        digits.count == 10 || (digits.count == 11 && digits.first == "1")
    }

    static func isPlausibleEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@")
        guard parts.count == 2,
              parts[0].isEmpty == false,
              parts[1].contains("."),
              parts[1].hasSuffix(".") == false else {
            return false
        }
        return true
    }
}

private struct ReservationFormValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct ReservationFormDraft {
    var guestName: String
    var email: String
    var phone: String
    var reservationDate: Date
    var reservationTime: Date
    var partySize: Int
    var guestNotes: String
    var staffNotes: String
    var tableName: String
    var status: ReservationStatus
    var supersededById: String

    init(failure: ImportFailureDTO?, prefill: ManualReservationPrefill? = nil) {
        let snapshot = failure?.reservation
        guestName = snapshot?.guestName ?? ""
        email = snapshot?.email ?? ""
        phone = snapshot?.phone ?? ""
        reservationDate = Self.parseDate(snapshot?.reservationDate) ?? Date()
        reservationTime = Self.parseTime(snapshot?.reservationTime) ?? Self.defaultTime()
        partySize = max(snapshot?.partySize ?? 2, 1)
        guestNotes = snapshot?.notes ?? ""
        tableName = ""
        status = .confirmed
        supersededById = ""

        if let failure {
            staffNotes = "Created manually from failed Flamingo import \(failure.sourceSubmissionId.map(String.init) ?? "unknown")."
        } else {
            staffNotes = ""
        }

        if failure == nil, let prefill {
            guestName = prefill.guestName
            phone = prefill.phoneDigits.map(ReservationInputNormalizer.sanitizedUSPhoneInput) ?? ""
            email = prefill.email ?? ""
        }
    }

    init(reservation: ReservationRecord) {
        guestName = reservation.guestName
        email = reservation.email
        phone = reservation.phone
        reservationDate = Self.parseDate(reservation.reservationDate) ?? Date()
        reservationTime = Self.parseTime(reservation.reservationTime) ?? Self.defaultTime()
        partySize = reservation.partySize
        guestNotes = reservation.guestNotes ?? ""
        staffNotes = reservation.staffNotes ?? ""
        tableName = reservation.tableName ?? ""
        status = reservation.statusValue
        supersededById = reservation.supersededById.map(String.init) ?? ""
    }

    func createRequest(
        sourceSubmissionId: Int?,
        sourceType: ReservationSourceType,
        setup: RestaurantSetup
    ) -> ReservationCreateRequest {
        let state = (try? ReservationFormValidator.validate(draft: self, setup: setup)) ?? fallbackState()
        return ReservationCreateRequest(
            sourceSubmissionId: sourceSubmissionId,
            guestName: state.guestName,
            email: state.email,
            phone: state.phoneDigits,
            reservationDate: Self.formatDate(reservationDate),
            reservationTime: Self.formatTime(reservationTime),
            partySize: state.partySize,
            guestNotes: state.guestNotes,
            staffNotes: state.staffNotes,
            tableName: state.tableName,
            sourceType: sourceType,
            createdByDevice: "ios",
            status: status
        )
    }

    func updateRequest() -> ReservationUpdateRequest {
        let state = (try? ReservationFormValidator.validate(draft: self, setup: .default)) ?? fallbackState()
        return ReservationUpdateRequest(
            guestName: state.guestName,
            email: state.email,
            phone: state.phoneDigits,
            reservationDate: Self.formatDate(reservationDate),
            reservationTime: Self.formatTime(reservationTime),
            partySize: state.partySize,
            guestNotes: state.guestNotes ?? "",
            staffNotes: state.staffNotes ?? "",
            status: status,
            tableName: state.tableName ?? "",
            supersededById: Int(supersededById.trimmed)
        )
    }

    private func fallbackState() -> ReservationFormState {
        ReservationFormState(
            guestName: ReservationInputNormalizer.collapsedWhitespace(guestName),
            email: ReservationInputNormalizer.normalizedEmail(email),
            phoneDigits: ReservationInputNormalizer.phoneDigits(phone),
            partySize: max(partySize, 1),
            guestNotes: ReservationInputNormalizer.normalizedOptionalText(guestNotes),
            staffNotes: ReservationInputNormalizer.normalizedOptionalText(staffNotes),
            tableName: ReservationInputNormalizer.normalizedOptionalText(tableName)
        )
    }

    mutating func applyDefaultServiceSlot(setup: RestaurantSetup, keepGuestFields: Bool = false) {
        applyDefaultStaffServiceSlot(setup: setup, keepGuestFields: keepGuestFields)
    }

    mutating func applyDefaultStaffServiceSlot(
        setup: RestaurantSetup,
        keepGuestFields: Bool = false,
        availability: RestaurantDayAvailabilityDTO? = nil,
        publicSlots: ReservationSlotsResponseDTO? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let serviceDate = calendar.startOfDay(for: now)
        let times: [Date]

        if let publicSlots, !publicSlots.slots.isEmpty {
            times = publicSlots.slots.compactMap { slot in
                ManualReservationFormPresenter.serviceDateTime(
                    for: slot.value,
                    on: serviceDate,
                    calendar: calendar
                )
            }
            .sorted()
        } else {
            times = setup.suggestedTimes(
                for: serviceDate,
                now: now,
                calendar: calendar,
                applyLeadTime: false,
                openTime: availability?.openTime,
                closeTime: availability?.closeTime,
                slotIntervalMinutes: availability?.slotIntervalMinutes
            )
        }

        let time = times.first(where: { calendar.isDate(serviceDate, inSameDayAs: now) ? $0 > now : true })
            ?? times.first
            ?? calendar.date(bySettingHour: 18, minute: 0, second: 0, of: serviceDate)
            ?? serviceDate

        reservationDate = serviceDate
        reservationTime = time

        if !keepGuestFields {
            partySize = max(setup.defaultPartySize, 1)
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ReservationFormatters.reservationDateKey.date(from: value)
    }

    private static func parseTime(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()

        for format in ["HH:mm:ss", "HH:mm", "h:mm a"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static func defaultTime() -> Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func formatDate(_ date: Date) -> String {
        ReservationFormatters.reservationDateKey.string(from: date)
    }

    private static func formatTime(_ date: Date) -> String {
        ReservationFormatters.apiTime.string(from: date)
    }

    private static func displayTime(_ date: Date) -> String {
        ReservationFormatters.shortTime.string(from: date)
    }

    private static func displayDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    func createSummaryRows() -> [(String, String)] {
        [
            ("Name", guestName.trimmed),
            ("Phone", phone.trimmed),
            ("Email", email.trimmed.isEmpty ? "No email" : email.trimmed),
            ("Date", Self.displayDate(reservationDate)),
            ("Time", Self.displayTime(reservationTime)),
            ("Party", "\(partySize)")
        ]
    }

    func createReviewMessage() -> String {
        let emailLine = email.trimmed.isEmpty ? "No email" : email.trimmed
        return """
        Name: \(guestName.trimmed)
        Phone: \(phone.trimmed)
        Email: \(emailLine)
        Date: \(Self.displayDate(reservationDate))
        Time: \(Self.displayTime(reservationTime))
        Party: \(partySize)
        """
    }

    func changes(from original: ReservationFormDraft) -> [ReservationFormChange] {
        var result: [ReservationFormChange] = []

        func append(_ field: String, old: String, new: String) {
            guard old != new else { return }
            result.append(ReservationFormChange(field: field, oldValue: old, newValue: new))
        }

        append("Name", old: original.guestName.trimmed, new: guestName.trimmed)
        append("Phone", old: original.phone.trimmed, new: phone.trimmed)
        append("Email", old: original.email.trimmed.nilIfBlank ?? "No email", new: email.trimmed.nilIfBlank ?? "No email")
        append("Date", old: Self.displayDate(original.reservationDate), new: Self.displayDate(reservationDate))
        append("Time", old: Self.displayTime(original.reservationTime), new: Self.displayTime(reservationTime))
        append("Party", old: "\(original.partySize)", new: "\(partySize)")
        append("Status", old: original.status.displayName, new: status.displayName)
        append("Table", old: original.tableName.trimmed.nilIfBlank ?? "No table", new: tableName.trimmed.nilIfBlank ?? "No table")
        append("Guest notes", old: original.guestNotes.trimmed.nilIfBlank ?? "None", new: guestNotes.trimmed.nilIfBlank ?? "None")
        append("Staff notes", old: original.staffNotes.trimmed.nilIfBlank ?? "None", new: staffNotes.trimmed.nilIfBlank ?? "None")

        let oldSuperseded = original.supersededById.trimmed
        let newSuperseded = supersededById.trimmed
        if oldSuperseded != newSuperseded {
            append(
                "Superseded by",
                old: oldSuperseded.isEmpty ? "None" : oldSuperseded,
                new: newSuperseded.isEmpty ? "None" : newSuperseded
            )
        }

        return result
    }
}

// MARK: - Form Pieces

private struct ReservationFormSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ReservationFormLayout.fieldSpacing) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ReservationFormCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        ReservationFormSection(title: title, systemImage: systemImage) {
            content
        }
    }
}

private struct ReservationFormTextField: View {
    enum InputKind {
        case plain
        case guestName
        case guestPhone
        case guestEmail
        case tableName
        case numericID
    }

    let title: String
    @Binding var text: String
    let prompt: String
    var inputKind: InputKind = .plain
    var field: ReservationFormField?
    var focusedField: FocusState<ReservationFormField?>.Binding?
    var error: String?

    private var isFocused: Bool {
        guard let field, let focusedField else { return false }
        return focusedField.wrappedValue == field
    }

    private var displayBinding: Binding<String> {
        switch inputKind {
        case .plain, .guestEmail, .tableName, .numericID:
            return $text
        case .guestName:
            return Binding(
                get: { text },
                set: { text = ReservationInputNormalizer.sanitizedGuestName($0) }
            )
        case .guestPhone:
            return Binding(
                get: { text },
                set: { text = ReservationInputNormalizer.sanitizedUSPhoneInput($0) }
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StaffFormFieldLabel(title: title)

            Group {
                if let focusedField, let field {
                    styledTextField.focused(focusedField, equals: field)
                } else {
                    styledTextField
                }
            }

            if let error {
                StaffFormErrorCaption(message: error)
            }
        }
    }

    private var styledTextField: some View {
        TextField(prompt, text: displayBinding)
            .staffFormFieldChrome(isFocused: isFocused)
            .modifier(ReservationFormTextFieldModifiers(inputKind: inputKind))
    }
}

private struct ReservationFormTextFieldModifiers: ViewModifier {
    let inputKind: ReservationFormTextField.InputKind

    func body(content: Content) -> some View {
        switch inputKind {
        case .plain:
            content
        case .guestName:
            content
                .textContentType(.name)
                .textInputAutocapitalization(.words)
        case .guestPhone:
            content
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
        case .guestEmail:
            content
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .tableName:
            content
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        case .numericID:
            content
                .keyboardType(.numberPad)
        }
    }
}

private struct ReservationFormTextEditor: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat
    var field: ReservationFormField?
    var focusedField: FocusState<ReservationFormField?>.Binding?

    private var isFocused: Bool {
        guard let field, let focusedField else { return false }
        return focusedField.wrappedValue == field
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StaffFormFieldLabel(title: title)

            Group {
                if let focusedField, let field {
                    styledEditor.focused(focusedField, equals: field)
                } else {
                    styledEditor
                }
            }
        }
    }

    private var styledEditor: some View {
        TextEditor(text: $text)
            .font(.body)
            .textInputAutocapitalization(.sentences)
            .frame(minHeight: minHeight)
            .scrollContentBackground(.hidden)
            .padding(8)
            .staffFormFieldChrome(isFocused: isFocused)
    }
}

private struct ReservationFormWarningCard: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                    .stroke(Color.red.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct GuestPhoneLookupSuggestionRow: View {
    let result: GuestLookupResult
    let onUse: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title3)
                .foregroundStyle(ReservationUIStyle.selectedControlColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let phoneDigits = result.phoneDigits {
                        Text(GuestLookupFormatting.phoneDisplay(phoneDigits))
                    }
                    if let email = result.email {
                        Text(email)
                    }
                    if result.totalReservations > 0 {
                        Text("\(result.totalReservations) visits")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button("Use", action: onUse)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ReservationUIStyle.selectedControlColor)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss guest suggestion")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(ReservationUIStyle.selectedControlColor.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Known guest \(result.displayName)")
        .accessibilityHint("Double tap Use to fill guest details")
    }
}

private struct ReservationFormInfoCard: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct ReservationFormImportCard: View {
    let failure: ImportFailureDTO

    var body: some View {
        ReservationFormCard(title: "Failed Import Link", systemImage: "link") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Source \(failure.sourceSubmissionId.map(String.init) ?? "Unknown")")
                    .font(.subheadline.weight(.medium))
                Text(failure.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - String Helpers

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Keyboard

@MainActor
private func dismissReservationFormKeyboard(reason: String) {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
    FormTrace.event(surface: "manual_add", name: "keyboard_dismissed", extra: "reason=\(reason)")
}

// MARK: - Previews

#if DEBUG
#Preview("Manual Reservation") {
    let environment = AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
    ManualReservationFormView { _ in
        ReservationPreviewData.sampleDTOs[0]
    }
    .environmentObject(ReservationsController.preview(environment: environment))
    .environmentObject(HostTableConfigStore())
}

#Preview("Edit Reservation") {
    let environment = AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
    ReservationEditFormView(reservation: ReservationPreviewData.sampleRecord) { _ in
        ReservationPreviewData.sampleDTOs[0]
    }
    .environmentObject(ReservationsController.preview(environment: environment))
}
#endif
