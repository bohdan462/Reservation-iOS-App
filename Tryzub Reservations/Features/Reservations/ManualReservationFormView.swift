//
//  ManualReservationFormView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

// MARK: - Manual Reservation Wrapper

struct ManualReservationFormView: View {
    let failure: ImportFailureDTO?
    let prefill: ManualReservationPrefill?
    let onCreateReservation: (ReservationCreateRequest) async throws -> ReservationDTO

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var controller: ReservationsController
    @State private var draft: ReservationFormDraft
    @State private var isPhoneConfirmedForLookup: Bool
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
        _isPhoneConfirmedForLookup = State(initialValue: prefill?.source != .callInGuestLookup)
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
                requiresPhoneConfirmation: prefill?.source == .callInGuestLookup,
                isPhoneConfirmedForLookup: $isPhoneConfirmedForLookup,
                onCancel: { dismiss() },
                onSubmit: { prepareCreateConfirmation() }
            )
        }
        .interactiveDismissDisabled(true)
        .confirmationDialog(
            "Add this reservation?",
            isPresented: $showCreateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Add Reservation") {
                Task { await createReservation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(draft.createReviewMessage())
        }
        .task {
            // Lazy form support load: setup provides manual-create defaults only.
            _ = try? await controller.loadRestaurantSetup()
        }
    }

    private func prepareCreateConfirmation() {
        guard validateRequiredFields() else { return }
        showCreateConfirmation = true
    }

    // Intent: Staff creates a fast call-in/manual reservation.
    // Network: Caller performs POST /managed-reservations.
    private func createReservation() async {
        guard validateRequiredFields() else { return }

        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
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
            dismiss()
        } catch {
            ReservationHaptics.warning()
            errorMessage = error.isOfflineLike
                ? "Offline. Showing saved reservations. Edits require internet."
                : "Could not create reservation. Please try again."
        }
    }

    private func validateRequiredFields() -> Bool {
        do {
            _ = try ReservationFormValidator.validate(
                draft: draft,
                setup: controller.restaurantSetup,
                applyLeadTime: controller.hasLoadedRestaurantSetup
            )
            if prefill?.source == .callInGuestLookup, !isPhoneConfirmedForLookup {
                throw ReservationFormValidationError(message: "Confirm the caller's phone number before creating this call-in reservation.")
            }
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
                requiresPhoneConfirmation: false,
                isPhoneConfirmedForLookup: .constant(false),
                onCancel: { dismiss() },
                onSubmit: { prepareSaveConfirmation() },
                onHideReservation: reservation.canSoftHideAsWrongEntry && !reservation.isHidden
                ? { isShowingHideConfirmation = true }
                : nil
        )
        .confirmationDialog(
            "Save changes?",
            isPresented: $showSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save Changes") {
                Task { await saveReservation() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if pendingChanges.isEmpty {
                Text("No field changes detected.")
            } else {
                Text(pendingChanges.map { "\($0.field): \($0.oldValue) → \($0.newValue)" }.joined(separator: "\n"))
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
            Text("Hide the reservation while keeping it in backend history.")
        }
    }

    private func prepareSaveConfirmation() {
        guard validateRequiredFields() else { return }
        pendingChanges = draft.changes(from: originalDraft)
        if pendingChanges.isEmpty {
            errorMessage = "No changes to save."
            return
        }
        showSaveConfirmation = true
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
            dismiss()
        } catch {
            ReservationHaptics.warning()
            errorMessage = error.isOfflineLike
                ? "Offline. Showing saved reservations. Edits require internet."
                : "Could not save changes. Please try again."
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
            errorMessage = "Could not hide this reservation. Please retry."
            ReservationHaptics.warning()
        }
    }

    private func validateRequiredFields() -> Bool {
        do {
            _ = try ReservationFormValidator.validate(
                draft: draft,
                setup: controller.restaurantSetup,
                originalDraft: originalDraft,
                applyLeadTime: controller.hasLoadedRestaurantSetup
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

private struct ReservationFormContent: View {
    let mode: ReservationFormMode
    @Binding var draft: ReservationFormDraft
    let originalDraft: ReservationFormDraft?
    let isSaving: Bool
    let errorMessage: String?
    let failure: ImportFailureDTO?
    var reservation: ReservationRecord?
    let requiresPhoneConfirmation: Bool
    @Binding var isPhoneConfirmedForLookup: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    var onHideReservation: (() -> Void)?

    @EnvironmentObject private var controller: ReservationsController
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isCustomTimePresented = false
    @State private var didApplyInitialSettings = false
    @State private var dayAvailability: RestaurantDayAvailabilityDTO?
    @State private var loadedAvailabilityDateKey: String?
    @State private var suggestedSlots: ReservationSlotsResponseDTO?
    @State private var blockedSlotValues: Set<String> = []
    @State private var isLoadingPublicSlots = false
    @State private var publicSlotsError: String?
    @State private var loadedSlotsDateKey: String?
    @State private var slotLoadTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            formShell
                .padding(.bottom, 108)
        }
        .background(TryzubColors.screenBackground)
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
            ensureSlotLoad()
        }
        .onChange(of: draft.reservationDate.reservationDateString()) { _, _ in
            ensureSlotLoad()
        }
        .onDisappear {
            slotLoadTask?.cancel()
            slotLoadTask = nil
        }
        .safeAreaInset(edge: .bottom) {
            primaryActionButton
        }
    }

    private var formShell: some View {
        formFields
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                ReservationFormWarningCard(message: errorMessage)
            }

            if controller.isNetworkDegraded {
                ReservationFormWarningCard(message: "Offline. Showing saved reservations. Edits require internet.")
            }

            if let formBlockingMessage {
                ReservationFormWarningCard(message: formBlockingMessage)
            }

            if let failure {
                ReservationFormImportCard(failure: failure)
            }

            contactCard
            dateCard
            serviceChoicesGrid

            if mode.showsEditControls {
                editDetailsCard
            }

            notesSection
        }
    }

    private var contactCard: some View {
        ReservationServiceCard(title: "Guest", systemImage: "person", spacing: 8) {
            HStack(spacing: 8) {
                if mode.usesManualGuestInput {
                    ReservationFormTextField(
                        title: "Name",
                        text: $draft.guestName,
                        prompt: "Guest name",
                        inputKind: .guestName
                    )
                    ReservationFormTextField(
                        title: "Phone",
                        text: $draft.phone,
                        prompt: "(312) 345-5674",
                        inputKind: .guestPhone
                    )
                } else {
                    ReservationFormTextField(title: "Name", text: $draft.guestName, prompt: "Guest name")
                        .textContentType(.name)
                    ReservationFormTextField(title: "Phone", text: $draft.phone, prompt: "Phone")
                        .keyboardType(.phonePad)
                }
            }

            if mode.usesManualGuestInput {
                ReservationFormTextField(
                    title: "Email optional",
                    text: $draft.email,
                    prompt: "Leave blank if none",
                    inputKind: .guestEmail
                )
            } else {
                ReservationFormTextField(title: "Email optional", text: $draft.email, prompt: "Leave blank if none")
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if requiresPhoneConfirmation {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $isPhoneConfirmedForLookup) {
                        Label("Phone confirmed with caller", systemImage: "checkmark.shield")
                            .font(.subheadline.weight(.semibold))
                    }

                    Text("Required for call-in bookings started from Guest Lookup.")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(TryzubColors.mutedText)
                }
                .padding(.top, 2)
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
        }
    }

    private var dateCard: some View {
        ReservationServiceCard(title: "Date", systemImage: "calendar", spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ReservationSlotGridStyle.columnSpacing) {
                    ForEach(quickDates, id: \.timeIntervalSinceReferenceDate) { date in
                        dateChoiceButton(date)
                    }
                }
            }

            HStack {
                ReservationOpenCalendarButton(selectedDate: $draft.reservationDate)
                Spacer()
                Text(draft.reservationDate.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TryzubColors.mutedText)
            }
        }
    }

    private var serviceChoicesGrid: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 8) {
                    timeCard
                    partyCard
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    timeCard
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    partyCard
                        .frame(width: 240)
                }
            }
        }
    }

    private var timeCard: some View {
        ReservationServiceCard(title: "Time", systemImage: "clock", spacing: 8) {
            if isLoadingPublicSlots && activeSuggestedSlots == nil {
                ProgressView("Checking available times...")
                    .font(.caption2)
                    .frame(minHeight: 28, alignment: .leading)
            } else if shouldBlockClosedDate {
                Text("This date is closed. Choose another date.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TryzubColors.danger)
            } else if timeChoices.isEmpty {
                Text("No public slots. Use Custom Time.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
            } else {
                LazyVGrid(
                    columns: timeColumns,
                    spacing: ReservationSlotGridStyle.rowSpacing
                ) {
                    ForEach(timeChoices, id: \.self) { time in
                        Button {
                            draft.reservationTime = time
                            ReservationHaptics.selection()
                        } label: {
                            ReservationChoiceChip(
                                title: timeLabel(time),
                                isSelected: isSameTime(draft.reservationTime, time),
                                minWidth: 62,
                                minHeight: 30
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let publicSlotsError {
                Text(publicSlotsError)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
            }

            if let blockedWarningText {
                Label(blockedWarningText, systemImage: "exclamationmark.triangle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TryzubColors.danger)
            }

            if let timeValidationMessage {
                Label(timeValidationMessage, systemImage: "clock.badge.exclamationmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TryzubColors.danger)
            }

            if !shouldBlockClosedDate {
                HStack(spacing: 8) {
                    Button {
                        isCustomTimePresented = true
                        ReservationHaptics.selection()
                    } label: {
                        Label("Custom", systemImage: "plus")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TryzubColors.primaryText)
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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
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
                            minWidth: 62,
                            minHeight: 30,
                            fillsWidth: false
                        )
                    }
                }
            }
        }
    }

    private var partyCard: some View {
        ReservationServiceCard(title: "Party", systemImage: "person.2", spacing: 8) {
            LazyVGrid(
                columns: partyColumns,
                spacing: ReservationSlotGridStyle.rowSpacing
            ) {
                ForEach(1...8, id: \.self) { size in
                    Button {
                        draft.partySize = size
                        ReservationHaptics.selection()
                    } label: {
                        ReservationChoiceChip(
                            title: "\(size)",
                            isSelected: draft.partySize == size,
                            minWidth: 44,
                            minHeight: 36
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Text("Party of \(draft.partySize)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Stepper("Party of \(draft.partySize)", value: $draft.partySize, in: 1...60)
                    .labelsHidden()
            }
        }
    }

    private var partyColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 4 : 4
        return Array(repeating: GridItem(.flexible(), spacing: ReservationSlotGridStyle.columnSpacing), count: count)
    }

    private var timeColumns: [GridItem] {
        if horizontalSizeClass == .compact {
            return Array(repeating: GridItem(.flexible(), spacing: ReservationSlotGridStyle.columnSpacing), count: 2)
        }
        return ReservationSlotGridStyle.columns
    }

    private var statusColumns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .compact ? 96 : 112), spacing: ReservationSlotGridStyle.columnSpacing)]
    }

    private var editDetailsCard: some View {
        ReservationServiceCard(title: "Service Details", systemImage: "slider.horizontal.3", spacing: 8) {
            LazyVGrid(
                columns: statusColumns,
                spacing: ReservationSlotGridStyle.rowSpacing
            ) {
                ForEach(ReservationStatus.allCases) { status in
                    Button {
                        draft.status = status
                        ReservationHaptics.selection()
                    } label: {
                        ReservationChoiceChip(
                            title: status.shortDisplayName,
                            isSelected: draft.status == status,
                            minWidth: 86,
                            minHeight: 36
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                ReservationFormTextField(title: "Table", text: $draft.tableName, prompt: "Unassigned")
                    .textInputAutocapitalization(.characters)
                ReservationFormTextField(title: "Superseded by", text: $draft.supersededById, prompt: "ID")
                    .keyboardType(.numberPad)
            }

            if let onHideReservation {
                HStack {
                    Button(role: .destructive, action: onHideReservation) {
                        Label("Hide", systemImage: "archivebox")
                            .font(.caption2.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TryzubColors.danger)
                    .background(TryzubColors.attentionBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                            .stroke(TryzubColors.attentionBorder, lineWidth: 1)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        ReservationServiceCard(title: "Notes", systemImage: "note.text", spacing: 8) {
            ReservationFormTextEditor(title: "Guest notes", text: $draft.guestNotes, minHeight: 96)
            ReservationFormTextEditor(title: "Staff notes", text: $draft.staffNotes, minHeight: 112)
        }
    }

    private var primaryActionButton: some View {
        Button(action: submitIfValid) {
            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                        .tint(Color(.systemBackground))
                } else {
                    Text(mode.primaryActionTitle)
                        .font(.headline.weight(.semibold))
                }
                Spacer()
            }
            .frame(maxWidth: 150)
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color(.systemBackground))
            .padding(.vertical, 14)
            .background(ReservationUIStyle.selectedControlColor, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .frame(maxWidth: 680)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, mode.primaryButtonBottomInset)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .buttonStyle(.plain)
        .disabled(isSaving || controller.isNetworkDegraded || formBlockingMessage != nil)
    }

    private func submitIfValid() {
        guard formBlockingMessage == nil,
              !controller.isNetworkDegraded,
              !isSaving else {
            ReservationHaptics.warning()
            return
        }
        onSubmit()
    }

    private var formBlockingMessage: String? {
        if requiresPhoneConfirmation, !isPhoneConfirmedForLookup {
            return "Confirm the caller's phone number before creating this call-in reservation."
        }

        if let availabilityValidationMessage {
            return availabilityValidationMessage
        }

        do {
            _ = try ReservationFormValidator.validate(
                draft: draft,
                setup: controller.restaurantSetup,
                originalDraft: originalDraft,
                applyLeadTime: controller.hasLoadedRestaurantSetup
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
            return "Checking available times for this date."
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
            applyLeadTime: controller.hasLoadedRestaurantSetup
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
        let rawChoices: [Date]
        if let suggestedSlots = activeSuggestedSlots,
           suggestedSlots.isOpen,
           !suggestedSlots.slots.isEmpty {
            rawChoices = suggestedSlots.slots.compactMap { ManualReservationFormPresenter.dateForSlotValue($0.value) }
        } else {
            rawChoices = controller.restaurantSetup.suggestedTimes(for: draft.reservationDate)
        }

        return rawChoices.filter(isTimeChoiceAllowed)
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
            applyLeadTime: controller.hasLoadedRestaurantSetup
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
            if let firstTime = controller.restaurantSetup
                .suggestedTimes(for: date)
                .first(where: isTimeChoiceAllowed) {
                draft.reservationTime = firstTime
            }
            ReservationHaptics.selection()
        } label: {
            ReservationChoiceChip(
                title: dateTitle(date),
                subtitle: date.formatted(.dateTime.weekday(.abbreviated)),
                isSelected: Calendar.current.isDate(draft.reservationDate, inSameDayAs: date),
                minWidth: 68,
                minHeight: 32,
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
            draft.applyDefaultServiceSlot(setup: controller.restaurantSetup)
        case .fixFailedImport:
            draft.status = .confirmed
            if controller.restaurantSetup.suggestedTimes(for: draft.reservationDate).isEmpty {
                draft.applyDefaultServiceSlot(setup: controller.restaurantSetup, keepGuestFields: true)
            }
        case .edit:
            break
        }
    }

    private var blockedWarningText: String? {
        ManualReservationFormPresenter.blockedWarningText(
            selectedTime: draft.reservationTime,
            blockedSlotValues: blockedSlotValues
        )
    }

    // Loads slots in an unstructured Task so SwiftUI view churn (navigation
    // updates, controller refreshes) cannot cancel an in-flight request and leave
    // the spinner stuck. Skips reloading once a date has loaded successfully.
    private func ensureSlotLoad() {
        let dateKey = draft.reservationDate.reservationDateString()
        if let cachedSlots = controller.cachedReservationSlots(date: dateKey) {
            suggestedSlots = cachedSlots
            loadedSlotsDateKey = dateKey
        }
        if let cachedAvailability = controller.cachedRestaurantDayAvailability(date: dateKey) {
            dayAvailability = cachedAvailability
            loadedAvailabilityDateKey = dateKey
        }
        if loadedSlotsDateKey == dateKey || loadedAvailabilityDateKey == dateKey {
            if let cachedBlocked = controller.cachedRestaurantBlockedSlots(date: dateKey) {
                blockedSlotValues = Set(cachedBlocked.data.map { ManualReservationFormPresenter.shortSlotValue($0.slotTime) })
            }
        }

        if loadedSlotsDateKey == dateKey && loadedAvailabilityDateKey == dateKey { return }
        slotLoadTask?.cancel()
        slotLoadTask = Task {
            await loadPublicSlotSuggestions(dateKey: dateKey)
            slotLoadTask = nil
        }
    }

    private func loadPublicSlotSuggestions(dateKey: String) async {
        isLoadingPublicSlots = true
        publicSlotsError = nil
        defer { isLoadingPublicSlots = false }

        do {
            let availability = try await controller.loadRestaurantDayAvailability(date: dateKey)
            guard draft.reservationDate.reservationDateString() == dateKey else { return }
            dayAvailability = availability
            loadedAvailabilityDateKey = dateKey

            guard availability.isOpen else {
                suggestedSlots = nil
                loadedSlotsDateKey = dateKey
                blockedSlotValues = []
                return
            }

            do {
                // Public slots are suggestions. If backend availability says the
                // date is open but slot suggestions fail, staff can still use a
                // custom manual time after local validation.
                let slots = try await controller.loadReservationSlots(date: dateKey)
                guard draft.reservationDate.reservationDateString() == dateKey else { return }
                suggestedSlots = slots
                loadedSlotsDateKey = dateKey
            } catch {
                guard draft.reservationDate.reservationDateString() == dateKey else { return }
                if error.isCancellationLike {
                    return
                }
                suggestedSlots = nil
                loadedSlotsDateKey = dateKey
                publicSlotsError = "Public slot suggestions are unavailable. Custom time is still allowed."
            }

            if let blocked = try? await controller.loadRestaurantBlockedSlots(date: dateKey),
               draft.reservationDate.reservationDateString() == dateKey {
                blockedSlotValues = Set(blocked.data.map { ManualReservationFormPresenter.shortSlotValue($0.slotTime) })
            }
        } catch {
            guard draft.reservationDate.reservationDateString() == dateKey else { return }
            // Cancellation (date change / dismiss) is not a real failure; leave the
            // loaded-date guard unset so the next appear retries.
            if !error.isCancellationLike {
                publicSlotsError = "Could not verify public availability for this date."
                blockedSlotValues = []
            }
        }
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
            throw ReservationFormValidationError(message: "Guest name is required.")
        }

        let phoneDigits = ReservationInputNormalizer.phoneDigits(draft.phone)
        guard isPlausibleUSPhone(phoneDigits) else {
            throw ReservationFormValidationError(message: "Enter a valid 10 digit phone number.")
        }

        let email = ReservationInputNormalizer.normalizedEmail(draft.email)
        if !email.isEmpty, !isPlausibleEmail(email) {
            throw ReservationFormValidationError(message: "Enter a valid email address or leave email blank.")
        }

        guard (1...60).contains(draft.partySize) else {
            throw ReservationFormValidationError(message: "Party size must be between 1 and 60.")
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

    private static func isPlausibleUSPhone(_ digits: String) -> Bool {
        digits.count == 10 || (digits.count == 11 && digits.first == "1")
    }

    private static func isPlausibleEmail(_ email: String) -> Bool {
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
        let slot = setup.defaultServiceSlot()
        reservationDate = slot.date
        reservationTime = slot.time

        if !keepGuestFields {
            partySize = max(slot.partySize, 1)
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

private struct ReservationFormCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.medium))
                .foregroundStyle(.secondary)

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

private struct ReservationFormTextField: View {
    enum InputKind {
        case plain
        case guestName
        case guestPhone
        case guestEmail
    }

    let title: String
    @Binding var text: String
    let prompt: String
    var inputKind: InputKind = .plain

    private var displayBinding: Binding<String> {
        switch inputKind {
        case .plain, .guestEmail:
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
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(prompt, text: displayBinding)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .modifier(ReservationFormTextFieldModifiers(inputKind: inputKind))
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
                .textContentType(.none)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        case .guestPhone:
            content
                .textContentType(.none)
                .keyboardType(.phonePad)
        case .guestEmail:
            content
                .textContentType(.none)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

private struct ReservationFormTextEditor: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
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
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

// MARK: - Previews

#if DEBUG
#Preview("Manual Reservation") {
    let environment = AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
    ManualReservationFormView { _ in
        ReservationPreviewData.sampleDTOs[0]
    }
    .environmentObject(ReservationsController(environment: environment))
}

#Preview("Edit Reservation") {
    let environment = AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
    ReservationEditFormView(reservation: ReservationPreviewData.sampleRecord) { _ in
        ReservationPreviewData.sampleDTOs[0]
    }
    .environmentObject(ReservationsController(environment: environment))
}
#endif
