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
    let source: String
    let draftID: String
    let onCreateReservation: (ReservationCreateRequest) async throws -> ReservationDTO

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var controller: ReservationsController
    @State private var draft: ReservationFormDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showCreateConfirmation = false
    @State private var pendingCreateSummary: [(String, String)] = []
    @State private var intentionalConfirmationDismissalReason: String?
    @State private var didFinishIntentionally = false
    @State private var intakeMode: ManualReservationIntakeMode = .callIn

    init(
        failure: ImportFailureDTO? = nil,
        prefill: ManualReservationPrefill? = nil,
        source: String = "manual",
        draftID: String = UUID().uuidString,
        onCreateReservation: @escaping (ReservationCreateRequest) async throws -> ReservationDTO
    ) {
        self.failure = failure
        self.prefill = prefill
        self.source = source
        self.draftID = draftID
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
                intakeMode: $intakeMode,
                showsGuestLookupDetailReminder: prefill?.source == .callInGuestLookup,
                onCancel: {
                    didFinishIntentionally = true
                    if showCreateConfirmation {
                        logManualAdd(event: "confirm_dismissed", fields: ["reason": "user_cancelled"])
                    }
                    dismiss()
                },
                onSubmit: { prepareCreateConfirmation() }
            )
        }
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showCreateConfirmation) {
            ReservationFormConfirmationSheet(
                title: "Add Reservation",
                subtitle: "Review the details before accepting this reservation.",
                confirmTitle: "Add Reservation",
                isProcessing: isSaving,
                onConfirm: {
                    Task { await createReservation() }
                },
                onCancel: {
                    intentionalConfirmationDismissalReason = "user_cancelled"
                    logManualAdd(event: "confirm_dismissed", fields: ["reason": "user_cancelled"])
                    pendingCreateSummary = []
                    showCreateConfirmation = false
                }
            ) {
                ReservationFormChangeReview(createSummary: pendingCreateSummary)
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                logManualAdd(event: "confirm_presented")
            }
        }
        .task {
            // Lazy form support load: setup provides manual-create defaults only.
            _ = try? await controller.loadRestaurantSetup()
        }
        .onChange(of: showCreateConfirmation) { oldValue, newValue in
            guard oldValue, !newValue else { return }
            if let reason = intentionalConfirmationDismissalReason {
                intentionalConfirmationDismissalReason = nil
                pendingCreateSummary = []
                if reason == "create_success" {
                    return
                }
                return
            }
            pendingCreateSummary = []
            logManualAdd(event: "parent_reload_ignored", fields: ["reason": "confirmation_presented"])
            Task { @MainActor in
                await Task.yield()
                guard !didFinishIntentionally, !isSaving else { return }
                pendingCreateSummary = draft.createSummaryRows(intakeMode: intakeMode)
                showCreateConfirmation = true
            }
        }
        .onDisappear {
            guard !didFinishIntentionally, showCreateConfirmation else { return }
            logManualAdd(event: "parent_reload_ignored", fields: ["reason": "confirmation_presented"])
        }
    }

    private func prepareCreateConfirmation() {
        guard validateRequiredFields() else { return }
        pendingCreateSummary = draft.createSummaryRows(intakeMode: intakeMode)
        dismissKeyboard()
        logManualAdd(event: "show_confirm")
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
        logManualAdd(event: "create_started")
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
            let createdReservation = try await onCreateReservation(
                draft.createRequest(
                    sourceSubmissionId: failure?.sourceSubmissionId,
                    sourceType: createSourceType,
                    setup: controller.restaurantSetup
                )
            )
            ReservationHaptics.success()
            intentionalConfirmationDismissalReason = "create_success"
            didFinishIntentionally = true
            logManualAdd(event: "create_success", fields: ["reservationID": "\(createdReservation.id)"])
            pendingCreateSummary = []
            showCreateConfirmation = false
            logManualAdd(event: "confirm_dismissed", fields: ["reason": "create_success"])
            dismiss()
        } catch {
            ReservationHaptics.warning()
            errorMessage = error.isOfflineLike
                ? "Could not save. Check the connection and try again."
                : "Could not save. Check the details and try again."
            logManualAdd(
                event: "create_failed",
                fields: [
                    "preservingDraft": "true",
                    "error": "redacted"
                ]
            )
        }
    }

    private func logManualAdd(event: String, fields: [String: String] = [:]) {
        var output = fields
        output["source"] = source
        output["event"] = event
        output["draftID"] = draftID
        WorkflowCleanupTrace.log("MANUAL_ADD_TRACE", fields: output)
    }

    private func validateRequiredFields() -> Bool {
        do {
            _ = try ReservationFormValidator.validate(
                draft: draft,
                setup: controller.restaurantSetup,
                intakeMode: intakeMode,
                applyLeadTime: false
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            ReservationHaptics.warning()
            return false
        }
    }

    private var createSourceType: ReservationSourceType {
        guard failure == nil else { return .importRepair }
        if intakeMode == .walkIn {
            return .manualWalkIn
        }
        return draft.usedKnownGuest ? .knownGuestManual : .manualCallIn
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
    @State private var pendingChanges: [ReservationFormChange] = []
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
                intakeMode: .constant(reservation.sourceTypeValue == .manualWalkIn ? .walkIn : .callIn),
                showsGuestLookupDetailReminder: false,
                onCancel: { dismiss() },
                onSubmit: { prepareSaveConfirmation() },
                onHideReservation: reservation.canSoftHideAsWrongEntry && !reservation.isHidden
                ? { prepareHideConfirmation() }
                : nil
        )
        .sheet(
            isPresented: saveConfirmationBinding,
            onDismiss: {
                pendingChanges = []
            }
        ) {
            if pendingChanges.isEmpty {
                Text("No changes to save.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
                    .padding()
                    .onAppear {
                        showSaveConfirmation = false
                    }
            } else {
                ReservationFormConfirmationSheet(
                    title: "Save Changes",
                    subtitle: "Review the reservation updates before saving.",
                    confirmTitle: "Save Changes",
                    isProcessing: isSaving,
                    onConfirm: {
                        Task { await saveReservation() }
                    },
                    onCancel: {
                        pendingChanges = []
                        showSaveConfirmation = false
                    }
                ) {
                    ReservationFormChangeReview(changes: pendingChanges)
                }
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
        dismissReservationFormKeyboard(reason: "confirmation_sheet")
        guard validateRequiredFields() else { return }
        let changes = draft.changes(from: originalDraft)
        if changes.isEmpty {
            pendingChanges = []
            showSaveConfirmation = false
            errorMessage = "No changes to save."
            return
        }
        errorMessage = nil
        pendingChanges = changes
        FormTrace.event(surface: "manual_add", name: "confirmation_sheet_presented", extra: "mode=edit changes=\(changes.count)")
        showSaveConfirmation = true
    }

    private var saveConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                showSaveConfirmation && !pendingChanges.isEmpty
            },
            set: { isPresented in
                if !isPresented {
                    showSaveConfirmation = false
                } else if !pendingChanges.isEmpty {
                    showSaveConfirmation = true
                }
            }
        )
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
            _ = try await onSave(draft.updateRequest(intakeMode: reservation.sourceTypeValue == .manualWalkIn ? .walkIn : .callIn))
            ReservationHaptics.success()
            pendingChanges = []
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
                intakeMode: reservation.sourceTypeValue == .manualWalkIn ? .walkIn : .callIn,
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

    var toolbarSubmitTitle: String {
        switch self {
        case .manualCreate, .fixFailedImport:
            return "Add"
        case .edit:
            return "Save"
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
}

private enum ManualReservationIntakeMode: String, CaseIterable, Identifiable {
    case callIn
    case walkIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .callIn:
            return "Call-in"
        case .walkIn:
            return "Walk-in"
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

    var isGuestLookupField: Bool {
        switch self {
        case .guestName, .phone, .email:
            return true
        case .guestNotes, .staffNotes, .tableName, .supersededById:
            return false
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
    @Binding var intakeMode: ManualReservationIntakeMode
    var showsGuestLookupDetailReminder = false
    let onCancel: () -> Void
    let onSubmit: () -> Void
    var onHideReservation: (() -> Void)?

    @EnvironmentObject private var controller: ReservationsController
    @EnvironmentObject private var guestProfileStore: GuestProfileStore
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
    @Query(
        sort: [
            SortDescriptor(\GuestProfileCacheRecord.cleanVisitCount, order: .reverse),
            SortDescriptor(\GuestProfileCacheRecord.totalReservations, order: .reverse),
            SortDescriptor(\GuestProfileCacheRecord.fetchedAt, order: .reverse)
        ]
    )
    private var cachedGuestProfiles: [GuestProfileCacheRecord]
    @StateObject private var guestLookupStore = GuestLookupStore()
    @EnvironmentObject private var hostTableConfigStore: HostTableConfigStore
    @StateObject private var hostIntelligenceSettingsStore = HostIntelligenceSettingsStore()
    @StateObject private var manualReservationFacade = ManualReservationFacade()
    @State private var allGuestRecordCandidates: [GuestProfileLookupCandidate] = []
    @State private var isSearchingAllGuestRecords = false
    @State private var guestRecordSearchMessage: String?
    @State private var lastSubmittedGuestSearch = ""
    @State private var activeGuestRecordLookupKey: String?
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
                .padding(.bottom, ReservationLayout.scrollBottomInset + 96)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinsGuestCandidateSectionAboveKeyboard {
                keyboardPinnedGuestCandidateSection
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ManualGuestProfileRoute.self) { route in
            GuestProfileDetailView(guestKey: route.guestKey, environment: controller.environment)
        }
        .toolbar {
            if mode.showsNavigationCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(ReservationUIStyle.cancelColor)
                        .tint(ReservationUIStyle.cancelColor)
                        .disabled(isSaving)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Button(mode.toolbarSubmitTitle, action: submitIfValid)
                        .fontWeight(.semibold)
                        .disabled(isPrimaryActionDisabled)
                }
            }
        }
        .onAppear {
            applyInitialSettingsIfNeeded()
            prepareAvailabilityState()
            refreshSlotContext()
            refreshGuestLookup()
            WorkflowCleanupTrace.log(
                "NEW_RESERVATION_UX_TRACE",
                fields: [
                    "phase": "render",
                    "date": draft.reservationDate.reservationDateString(),
                    "party": "\(draft.partySize)",
                    "timeMode": timeChoices.contains(where: { isSameTime($0, draft.reservationTime) }) ? "preset" : "custom",
                    "serviceTimes": "\(timeChoices.count)"
                ]
            )
        }
        .task(id: guestLookupCacheKey) {
            guestLookupStore.updateCache(
                records: guestLookupRecords,
                cacheKey: guestLookupCacheKey,
                context: modelContext
            )
            guestLookupStore.scheduleSearch(currentGuestLookupText)
        }
        .onChange(of: draft.guestName) { _, _ in
            clearAllGuestRecordSearchIfNeeded()
            guestLookupStore.scheduleSearch(currentGuestLookupText)
        }
        .onChange(of: draft.phone) { _, _ in
            clearAllGuestRecordSearchIfNeeded()
            guestLookupStore.scheduleSearch(currentGuestLookupText)
        }
        .onChange(of: draft.email) { _, _ in
            clearAllGuestRecordSearchIfNeeded()
            guestLookupStore.scheduleSearch(currentGuestLookupText)
        }
        .onChange(of: intakeMode) { _, newMode in
            applyIntakeModeDefaults(newMode)
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
            #if DEBUG
            FormTrace.event(
                surface: "manual_add",
                name: "focus_changed",
                extra: "field=\(newValue.traceName)"
            )
            #endif
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

            if mode == .manualCreate {
                intakeModeControl
            }

            if isWideForm {
                formColumnPair {
                    contactCard
                } right: {
                    dateCard
                }
                guestCandidateSection

                serviceChoicesGrid
                slotContextBanner

                if showsWalkInDetailsCard {
                    walkInDetailsCard
                }

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
                if !pinsGuestCandidateSectionAboveKeyboard {
                    guestCandidateSection
                }
                dateCard
                serviceChoicesGrid
                slotContextBanner

                if mode.showsEditControls {
                    editDetailsCard
                } else if showsWalkInDetailsCard {
                    walkInDetailsCard
                }

                notesSection
            }
        }
    }

    private var intakeModeControl: some View {
        Picker("Intake mode", selection: $intakeMode) {
            ForEach(ManualReservationIntakeMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
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
            refreshGuestLookup()
        }
    }

    @ViewBuilder
    private var guestCandidateSection: some View {
        if mode.usesManualGuestInput {
            ManualGuestCandidateSection(
                localResults: localGuestCandidates,
                allRecordResults: cappedAllGuestRecordResults,
                isSearchingAllGuestRecords: isSearchingAllGuestRecords,
                message: guestCandidateMessage,
                canSearchAllRecords: !isSearchingAllGuestRecords && isEligibleForAllGuestRecordSearch(currentGuestLookupText),
                onSearchAllRecords: {
                    Task { await searchAllGuestRecords() }
                },
                onUse: { result in
                    applyGuestCandidate(result)
                },
                profileRoute: { result in
                    manualGuestProfileRoute(for: result)
                },
            )
        }
    }

    private var guestLookupCacheKey: GuestLookupCacheKey {
        GuestLookupCacheKey(records: guestLookupRecords, cachedProfiles: cachedGuestProfiles)
    }

    private var focusFieldOrder: [ReservationFormField] {
        var order: [ReservationFormField] = [.guestName, .phone, .email, .guestNotes, .staffNotes]
        if showsWalkInDetailsCard {
            order.append(.tableName)
        }
        if mode.showsEditControls {
            order.append(contentsOf: [.tableName, .supersededById])
        }
        return order
    }

    private func moveFocusAfterSubmit(from field: ReservationFormField) {
        if let next = field.next(in: focusFieldOrder) {
            focusedField = next
        } else {
            focusedField = nil
        }
    }

    private var currentGuestLookupText: String {
        switch focusedField {
        case .phone:
            return draft.phone
        case .email:
            return draft.email
        case .guestName:
            return draft.guestName
        default:
            if !draft.phone.trimmed.isEmpty { return draft.phone }
            if !draft.email.trimmed.isEmpty { return draft.email }
            return draft.guestName
        }
    }

    private var allGuestRecordResults: [GuestLookupResult] {
        allGuestRecordCandidates.map(\.lookupResult)
    }

    private var pinsGuestCandidateSectionAboveKeyboard: Bool {
        guard !isWideForm, mode.usesManualGuestInput else { return false }
        guard focusedField?.isGuestLookupField == true else { return false }
        return hasGuestCandidateContent
    }

    private var hasGuestCandidateContent: Bool {
        !localGuestCandidates.isEmpty
            || !cappedAllGuestRecordResults.isEmpty
            || guestCandidateMessage != nil
            || isSearchingAllGuestRecords
    }

    private var keyboardPinnedGuestCandidateSection: some View {
        ScrollView {
            guestCandidateSection
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(maxHeight: 280)
        .scrollIndicators(.visible)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }

    private var localGuestCandidates: [GuestLookupResult] {
        let allRecordKeys = Set(allGuestRecordResults.compactMap(guestCandidateIdentityKey(for:)))
        let results = guestLookupStore.results.filter { !draftAlreadyMatchesGuest($0) }
        let filtered: [GuestLookupResult]
        if allRecordKeys.isEmpty {
            filtered = results
        } else {
            filtered = results.filter { result in
                guard let key = guestCandidateIdentityKey(for: result) else { return true }
                return !allRecordKeys.contains(key)
            }
        }
        return Array(filtered.prefix(6))
    }

    private var cappedAllGuestRecordResults: [GuestLookupResult] {
        Array(allGuestRecordResults.prefix(6))
    }

    private var guestCandidateMessage: String? {
        if let guestRecordSearchMessage {
            return guestRecordSearchMessage
        }
        return nil
    }

    private func isEligibleForAllGuestRecordSearch(_ text: String) -> Bool {
        ManualGuestServerLookupRequest(text: text) != nil
    }

    private var allGuestRecordSearchRequest: ManualGuestServerLookupRequest? {
        ManualGuestServerLookupRequest(text: currentGuestLookupText)
    }

    private func refreshGuestLookup() {
        guard mode.usesManualGuestInput else { return }
        guestLookupStore.updateCache(
            records: guestLookupRecords,
            cacheKey: guestLookupCacheKey,
            context: modelContext
        )
        guestLookupStore.scheduleSearch(currentGuestLookupText)
    }

    private func clearAllGuestRecordSearchIfNeeded() {
        guard lastSubmittedGuestSearch != currentGuestLookupText.trimmed else { return }
        guard !allGuestRecordCandidates.isEmpty || guestRecordSearchMessage != nil else { return }
        allGuestRecordCandidates = []
        guestRecordSearchMessage = nil
    }

    private func draftAlreadyMatchesGuest(_ result: GuestLookupResult) -> Bool {
        let trimmedName = draft.guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameMatches = !trimmedName.isEmpty
            && trimmedName.localizedCaseInsensitiveCompare(result.displayName) == .orderedSame

        let draftDigits = GuestLookupPhoneNormalizer.digits(draft.phone)
        guard let resultDigits = result.phoneDigits, !draftDigits.isEmpty else {
            return nameMatches
        }

        let phoneMatches = draftDigits == resultDigits
            || resultDigits.hasPrefix(draftDigits)
            || (draftDigits.count == ManualPhoneSuggestTrace.threshold && resultDigits.hasSuffix(draftDigits))
            || (draftDigits.count >= 10 && resultDigits.hasSuffix(String(draftDigits.suffix(10))))

        if let email = result.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            let draftEmail = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
            return nameMatches && phoneMatches && draftEmail.localizedCaseInsensitiveCompare(email) == .orderedSame
        }

        return nameMatches && phoneMatches
    }

    private func searchAllGuestRecords() async {
        guard let request = allGuestRecordSearchRequest else {
            allGuestRecordCandidates = []
            guestRecordSearchMessage = nil
            lastSubmittedGuestSearch = currentGuestLookupText.trimmed
            return
        }

        guard !(isSearchingAllGuestRecords && activeGuestRecordLookupKey == request.key) else { return }

        isSearchingAllGuestRecords = true
        activeGuestRecordLookupKey = request.key
        lastSubmittedGuestSearch = request.submittedText
        guestRecordSearchMessage = nil

        defer {
            if activeGuestRecordLookupKey == request.key {
                isSearchingAllGuestRecords = false
                activeGuestRecordLookupKey = nil
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
            guard activeGuestRecordLookupKey == request.key else { return }
            allGuestRecordCandidates = result.candidates
            guestRecordSearchMessage = result.candidates.isEmpty ? "No matching guest found." : nil
        } catch {
            guard activeGuestRecordLookupKey == request.key else { return }
            guestRecordSearchMessage = "Couldn't search guest records. Try again."
        }
    }

    private func applyGuestCandidate(_ result: GuestLookupResult) {
        if shouldReplaceGuestName {
            draft.guestName = result.displayName
        }
        if let phoneDigits = result.phoneDigits {
            draft.phone = ReservationInputNormalizer.sanitizedUSPhoneInput(phoneDigits)
        }
        if let email = result.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            if draft.email.trimmed.isEmpty {
                draft.email = email
            }
        }
        draft.usedKnownGuest = true
        ReservationHaptics.selection()
    }

    private var shouldReplaceGuestName: Bool {
        let name = draft.guestName.trimmed.lowercased()
        return name.isEmpty || ["guest", "unknown", "walk-in", "walk in"].contains(name)
    }

    private func manualGuestProfileRoute(for result: GuestLookupResult) -> ManualGuestProfileRoute? {
        guard let guestKey = result.guestKey?.trimmed.nilIfBlank else { return nil }
        return ManualGuestProfileRoute(guestKey: guestKey)
    }

    private func guestCandidateIdentityKey(for result: GuestLookupResult) -> String? {
        if let guestKey = result.guestKey?.trimmed.nilIfBlank {
            return "guest:\(guestKey.lowercased())"
        }
        if let phoneDigits = result.phoneDigits.map(GuestLookupPhoneNormalizer.digits)?.nilIfBlank {
            return "phone:\(phoneDigits)"
        }
        if let email = result.email?.trimmed.nilIfBlank {
            return "email:\(email.lowercased())"
        }
        let name = result.displayName.trimmed.lowercased()
        return name.isEmpty ? nil : "name:\(name)"
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
            error: guestNameFieldError,
            onSubmit: { moveFocusAfterSubmit(from: .guestName) }
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
            error: phoneFieldError,
            onSubmit: { moveFocusAfterSubmit(from: .phone) }
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
            error: emailFieldError,
            onSubmit: { moveFocusAfterSubmit(from: .email) }
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
                Text("No preset service times for this date. Use Custom.")
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.partySize >= 9 ? "Large party · \(draft.partySize) guests" : "Party of \(draft.partySize)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    if draft.partySize >= 9 {
                        Text("Review table plan / banquet note recommended")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var showsWalkInDetailsCard: Bool {
        mode == .manualCreate && intakeMode == .walkIn
    }

    private var walkInDetailsCard: some View {
        ReservationFormSection(title: "Walk-in", systemImage: "figure.walk.arrival") {
            ReservationFormTextField(
                title: "Table optional",
                text: $draft.tableName,
                prompt: "Unassigned",
                inputKind: .tableName,
                field: .tableName,
                focusedField: $focusedField
            )
        }
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

    private var isPrimaryActionDisabled: Bool {
        controller.isNetworkDegraded || availabilityBlockingMessage != nil || isSaving
    }

    private func submitIfValid() {
        hasAttemptedSave = true
        dismissReservationFormKeyboard(reason: "submit")
        focusedField = nil
        let isValid = !controller.isNetworkDegraded
            && availabilityBlockingMessage == nil
            && validationErrorMessage == nil
            && !isSaving
        WorkflowCleanupTrace.log(
            "NEW_RESERVATION_UX_TRACE",
            fields: [
                "phase": "create_tapped",
                "valid": "\(isValid)"
            ]
        )
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
        guard mode != .manualCreate || intakeMode == .callIn else { return nil }
        let guestName = ReservationInputNormalizer.collapsedWhitespace(draft.guestName)
        guard guestName.count < 2 else { return nil }
        return "Add the guest name before saving."
    }

    private var phoneFieldError: String? {
        guard hasAttemptedSave else { return nil }
        guard mode != .manualCreate || intakeMode == .callIn else { return nil }
        let phoneDigits = ReservationInputNormalizer.phoneDigits(draft.phone)
        guard !ReservationFormValidator.isPlausibleUSPhone(phoneDigits) else { return nil }
        return "Add a valid phone number before saving this call-in."
    }

    private var emailFieldError: String? {
        guard hasAttemptedSave else { return nil }
        guard mode != .manualCreate || intakeMode == .callIn else { return nil }
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
                intakeMode: intakeMode,
                applyLeadTime: appliesStaffLeadTime
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var availabilityValidationMessage: String? {
        if isLoadingPublicSlots
            && activeSuggestedSlots == nil
            && activeDayAvailability == nil {
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
            applyIntakeModeDefaults(intakeMode)
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

    private func applyIntakeModeDefaults(_ mode: ManualReservationIntakeMode) {
        guard self.mode == .manualCreate else { return }
        switch mode {
        case .callIn:
            draft.status = .confirmed
        case .walkIn:
            draft.status = .seated
            draft.applyDefaultStaffServiceSlot(
                setup: controller.restaurantSetup,
                keepGuestFields: true,
                availability: controller.cachedRestaurantDayAvailability(
                    date: Date().reservationDateString()
                ),
                publicSlots: controller.cachedReservationSlots(
                    date: Date().reservationDateString()
                )
            )
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

private struct ManualGuestProfileRoute: Hashable {
    let guestKey: String
}

private struct ManualGuestServerLookupRequest: Hashable {
    let phone: String?
    let email: String?
    let query: String?
    let limit: Int
    let submittedText: String

    init?(text: String) {
        let submitted = text.trimmed
        guard !submitted.isEmpty else { return nil }

        let phoneDigits = GuestLookupPhoneNormalizer.digits(submitted)
        if ManualGuestServerLookupRequest.isLikelyEmail(submitted) {
            phone = nil
            email = submitted
            query = nil
        } else if phoneDigits.count >= 7 {
            phone = phoneDigits
            email = nil
            query = nil
        } else if ManualGuestServerLookupRequest.normalizedTextKey(submitted).count >= 2 {
            phone = nil
            email = nil
            query = submitted
        } else {
            return nil
        }

        limit = 5
        submittedText = submitted
    }

    var key: String {
        [
            phone ?? "",
            email?.lowercased() ?? "",
            query?.lowercased() ?? "",
            "\(limit)"
        ].joined(separator: "|")
    }

    private static func isLikelyEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].isEmpty == false,
              parts[1].contains(".") else {
            return false
        }
        return true
    }

    private static func normalizedTextKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
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
        GuestLookupPhoneNormalizer.digits(value)
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
        intakeMode: ManualReservationIntakeMode = .callIn,
        applyLeadTime: Bool = true
    ) throws -> ReservationFormState {
        let guestName = ReservationInputNormalizer.collapsedWhitespace(draft.guestName)
        if intakeMode == .callIn, guestName.count < 2 {
            throw ReservationFormValidationError(message: "Add the guest name before saving.")
        }

        let phoneDigits = ReservationInputNormalizer.phoneDigits(draft.phone)
        let normalizedPhoneDigits: String
        if intakeMode == .callIn {
            guard isPlausibleUSPhone(phoneDigits) else {
                throw ReservationFormValidationError(message: "Add a valid phone number before saving this call-in.")
            }
            normalizedPhoneDigits = phoneDigits
        } else {
            normalizedPhoneDigits = isPlausibleUSPhone(phoneDigits) ? phoneDigits : ""
        }

        let email = ReservationInputNormalizer.normalizedEmail(draft.email)
        if intakeMode == .callIn, !email.isEmpty, !isPlausibleEmail(email) {
            throw ReservationFormValidationError(message: "Enter a valid email address or leave email blank.")
        }
        let normalizedEmail = isPlausibleEmail(email) ? email : ""

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
            email: normalizedEmail,
            phoneDigits: normalizedPhoneDigits,
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
    var usedKnownGuest: Bool

    var traceKey: String {
        [
            ReservationInputNormalizer.collapsedWhitespace(guestName),
            ReservationInputNormalizer.phoneDigits(phone),
            ReservationInputNormalizer.normalizedEmail(email),
            reservationDate.reservationDateString(),
            ReservationFormatters.apiTime.string(from: reservationTime),
            "\(partySize)",
            "\(guestNotes.count)",
            "\(staffNotes.count)",
            "\(usedKnownGuest)"
        ].joined(separator: "|")
    }

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
        usedKnownGuest = false

        if let failure {
            staffNotes = "Created manually from failed Flamingo import \(failure.sourceSubmissionId.map(String.init) ?? "unknown")."
        } else {
            staffNotes = ""
        }

        if failure == nil, let prefill {
            guestName = prefill.guestName
            phone = prefill.phoneDigits.map(ReservationInputNormalizer.sanitizedUSPhoneInput) ?? ""
            email = prefill.email ?? ""
            usedKnownGuest = prefill.source == .callInGuestLookup
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
        usedKnownGuest = false
    }

    func createRequest(
        sourceSubmissionId: Int?,
        sourceType: ReservationSourceType,
        setup: RestaurantSetup
    ) -> ReservationCreateRequest {
        let intakeMode: ManualReservationIntakeMode = sourceType == .manualWalkIn ? .walkIn : .callIn
        let state = (try? ReservationFormValidator.validate(draft: self, setup: setup, intakeMode: intakeMode)) ?? fallbackState(intakeMode: intakeMode)
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

    func updateRequest(intakeMode: ManualReservationIntakeMode = .callIn) -> ReservationUpdateRequest {
        let state = (try? ReservationFormValidator.validate(draft: self, setup: .default, intakeMode: intakeMode)) ?? fallbackState(intakeMode: intakeMode)
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

    private func fallbackState(intakeMode: ManualReservationIntakeMode) -> ReservationFormState {
        let phoneDigits = ReservationInputNormalizer.phoneDigits(phone)
        let email = ReservationInputNormalizer.normalizedEmail(email)
        return ReservationFormState(
            guestName: ReservationInputNormalizer.collapsedWhitespace(guestName),
            email: ReservationFormValidator.isPlausibleEmail(email) ? email : "",
            phoneDigits: intakeMode == .walkIn && !ReservationFormValidator.isPlausibleUSPhone(phoneDigits) ? "" : phoneDigits,
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

    private static func canonicalTime(_ date: Date) -> String {
        ReservationFormatters.apiTime.string(from: date)
    }

    private static func normalizedPartySize(_ value: Int) -> Int {
        min(max(value, 1), 60)
    }

    private static func displayDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    func createSummaryRows(intakeMode: ManualReservationIntakeMode) -> [(String, String)] {
        var rows = [
            ("Intake", intakeMode.title),
            ("Name", guestName.trimmed.isEmpty ? "Walk-in guest" : guestName.trimmed),
            ("Phone", phone.trimmed.isEmpty ? "No phone" : phone.trimmed),
            ("Email", email.trimmed.isEmpty ? "No email" : email.trimmed),
            ("Date", Self.displayDate(reservationDate)),
            ("Time", Self.displayTime(reservationTime)),
            ("Party", "\(partySize)")
        ]

        if let table = tableName.trimmed.nilIfBlank {
            rows.append(("Table", table))
        }
        if let guestNotes = guestNotes.trimmed.nilIfBlank {
            rows.append(("Guest notes", guestNotes))
        }
        if let staffNotes = staffNotes.trimmed.nilIfBlank {
            rows.append(("Staff notes", staffNotes))
        }

        return rows
    }

    func changes(from original: ReservationFormDraft) -> [ReservationFormChange] {
        var result: [ReservationFormChange] = []

        func append(_ field: String, old: String, new: String, oldDisplay: String? = nil, newDisplay: String? = nil) {
            guard old != new else { return }
            result.append(
                ReservationFormChange(
                    field: field,
                    oldValue: oldDisplay ?? old,
                    newValue: newDisplay ?? new
                )
            )
        }

        append("Name", old: original.guestName.trimmed, new: guestName.trimmed)
        append("Phone", old: original.phone.trimmed, new: phone.trimmed)
        append("Email", old: original.email.trimmed.nilIfBlank ?? "No email", new: email.trimmed.nilIfBlank ?? "No email")
        append("Date", old: Self.displayDate(original.reservationDate), new: Self.displayDate(reservationDate))
        append(
            "Time",
            old: Self.canonicalTime(original.reservationTime),
            new: Self.canonicalTime(reservationTime),
            oldDisplay: Self.displayTime(original.reservationTime),
            newDisplay: Self.displayTime(reservationTime)
        )
        append(
            "Party",
            old: "\(Self.normalizedPartySize(original.partySize))",
            new: "\(Self.normalizedPartySize(partySize))"
        )
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
    var onSubmit: (() -> Void)?

    private var isFocused: Bool {
        guard let field, let focusedField else { return false }
        return focusedField.wrappedValue == field
    }

    private var displayBinding: Binding<String> {
        switch inputKind {
        case .plain, .guestName, .guestPhone, .guestEmail, .tableName, .numericID:
            return $text
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
        .id(field)
    }

    private var styledTextField: some View {
        TextField(prompt, text: displayBinding)
            .staffFormFieldChrome(isFocused: isFocused)
            .modifier(ReservationFormTextFieldModifiers(inputKind: inputKind))
            .submitLabel(submitLabel)
            .onSubmit {
                onSubmit?()
            }
    }

    private var submitLabel: SubmitLabel {
        switch field {
        case .guestName, .phone, .email, .tableName, .supersededById:
            return .next
        case .guestNotes, .staffNotes:
            return .done
        case nil:
            return .done
        }
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
                .textContentType(.none)
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
        .id(field)
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

private struct ManualGuestCandidateSection: View {
    let localResults: [GuestLookupResult]
    let allRecordResults: [GuestLookupResult]
    let isSearchingAllGuestRecords: Bool
    let message: String?
    let canSearchAllRecords: Bool
    let onSearchAllRecords: () -> Void
    let onUse: (GuestLookupResult) -> Void
    let profileRoute: (GuestLookupResult) -> ManualGuestProfileRoute?

    var body: some View {
        ReservationFormSection(title: "Saved guests", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: ReservationFormLayout.fieldSpacing) {
                if let message {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TryzubColors.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !localResults.isEmpty {
                    candidateGroup(results: localResults)
                }

                if !allRecordResults.isEmpty {
                    candidateGroup(results: allRecordResults)
                }

                Button(action: onSearchAllRecords) {
                    HStack(spacing: 8) {
                        Label("Search all guest records", systemImage: "magnifyingglass.circle")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        if isSearchingAllGuestRecords {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canSearchAllRecords)
                .accessibilityLabel("Search all guest records")
            }
        }
    }

    private func candidateGroup(results: [GuestLookupResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(results) { result in
                ManualGuestCandidateCard(
                    result: result,
                    profileRoute: profileRoute(result),
                    onUse: {
                        onUse(result)
                    }
                )
            }
        }
    }
}

private struct ManualGuestCandidateCard: View {
    let result: GuestLookupResult
    let profileRoute: ManualGuestProfileRoute?
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(result.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(matchBadgeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(result.isStrongBackendMatch ? TryzubColors.success : TryzubColors.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (result.isStrongBackendMatch ? TryzubColors.success : TryzubColors.warning).opacity(0.12),
                        in: Capsule()
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                if let phoneDigits = result.phoneDigits {
                    Label(GuestLookupFormatting.phoneDisplay(phoneDigits), systemImage: "phone")
                }
                if let email = result.email {
                    Label(email, systemImage: "envelope")
                }
                if result.totalReservations > 0 {
                    Label("\(result.totalReservations) \(result.totalReservations == 1 ? "reservation" : "reservations")", systemImage: "clock.arrow.circlepath")
                }
                if let lastReservationDate = result.lastReservationDate {
                    Label("Last seen \(ManualGuestCandidateDateFormatter.display(lastReservationDate))", systemImage: "calendar")
                }
                if let nextLine {
                    Label(nextLine, systemImage: "calendar.badge.clock")
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

            HStack(spacing: 8) {
                Button(action: onUse) {
                    Label("Use guest", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .accessibilityLabel("Use guest")

                if let profileRoute {
                    NavigationLink(value: profileRoute) {
                        Label("View history", systemImage: "person.text.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ReservationUIStyle.selectedControlColor)
                    .background(
                        ReservationUIStyle.selectedControlColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    )
                    .accessibilityLabel("View history")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var matchBadgeText: String {
        result.isStrongBackendMatch ? "Likely guest" : "Possible match"
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

    private var nextLine: String? {
        guard let next = result.nextReservation, next.hasDisplayValue else { return nil }
        let date = next.date.map(ManualGuestCandidateDateFormatter.display)
        let time = next.time.map(ManualGuestCandidateDateFormatter.displayTime)
        let party = next.partySize.map { "\($0) \($0 == 1 ? "guest" : "guests")" }
        return [date, time, party, next.tableName?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfBlank
    }
}

private enum ManualGuestCandidateDateFormatter {
    static func display(_ value: String) -> String {
        guard let date = ReservationFormatters.reservationDateKey.date(from: value) else {
            return value
        }

        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func displayTime(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = ReservationFormatters.apiTime.date(from: trimmed) {
            return ReservationFormatters.shortTime.string(from: date)
        }
        return String(trimmed.prefix(5))
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
