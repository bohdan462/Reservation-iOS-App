//
//  ManualReservationFormView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

// MARK: - Manual Reservation Wrapper

struct ManualReservationFormView: View {
    let failure: ImportFailureDTO?
    let onCreateReservation: (ReservationCreateRequest) async throws -> ReservationDTO

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var controller: ReservationsController
    @State private var draft: ReservationFormDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showCreateConfirmation = false

    init(
        failure: ImportFailureDTO? = nil,
        onCreateReservation: @escaping (ReservationCreateRequest) async throws -> ReservationDTO
    ) {
        self.failure = failure
        self.onCreateReservation = onCreateReservation
        _draft = State(initialValue: ReservationFormDraft(failure: failure))
    }

    var body: some View {
        NavigationStack {
            ReservationFormContent(
                mode: failure == nil ? .manualCreate : .fixFailedImport,
                draft: $draft,
                isSaving: isSaving,
                errorMessage: errorMessage,
                failure: failure,
                reservation: nil,
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
            errorMessage = error.localizedDescription
        }
    }

    private func validateRequiredFields() -> Bool {
        if draft.guestName.trimmed.isEmpty {
            errorMessage = "Guest name is required."
            ReservationHaptics.warning()
            return false
        }

        if draft.phone.trimmed.isEmpty {
            errorMessage = "Phone number is required for call-in reservations."
            ReservationHaptics.warning()
            return false
        }

        return true
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
            isSaving: isSaving,
            errorMessage: errorMessage,
            failure: nil,
            reservation: reservation,
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
            Text("This hides the reservation from normal lists while keeping it in backend history.")
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
            errorMessage = error.localizedDescription
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
        if draft.guestName.trimmed.isEmpty {
            errorMessage = "Guest name is required."
            ReservationHaptics.warning()
            return false
        }

        if draft.phone.trimmed.isEmpty {
            errorMessage = "Phone is required."
            ReservationHaptics.warning()
            return false
        }

        return true
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
    let isSaving: Bool
    let errorMessage: String?
    let failure: ImportFailureDTO?
    var reservation: ReservationRecord?
    let onCancel: () -> Void
    let onSubmit: () -> Void
    var onHideReservation: (() -> Void)?

    @EnvironmentObject private var controller: ReservationsController
    @State private var isEmailExpanded = false
    @State private var isNotesPresented = false
    @State private var isCustomTimePresented = false
    @State private var didApplyInitialSettings = false
    @State private var suggestedSlots: ReservationSlotsResponseDTO?
    @State private var blockedSlotValues: Set<String> = []
    @State private var isLoadingPublicSlots = false
    @State private var publicSlotsError: String?
    @State private var loadedSlotsDateKey: String?
    @State private var slotLoadTask: Task<Void, Never>?

    var body: some View {
        ViewThatFits(in: .vertical) {
            formShell
            ScrollView {
                formShell
            }
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
        .sheet(isPresented: $isNotesPresented) {
            ReservationNotesSheet(
                guestNotes: $draft.guestNotes,
                staffNotes: $draft.staffNotes
            )
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
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                ReservationFormWarningCard(message: errorMessage)
            }

            if let failure {
                ReservationFormImportCard(failure: failure)
            }

            contactCard
            dateCard
            serviceChoicesGrid

            if mode.showsEditControls {
                editDetailsCard
            } else {
                secondaryActions
            }
        }
    }

    private var contactCard: some View {
        ReservationServiceCard(title: "Guest", systemImage: "person", spacing: 8) {
            HStack(spacing: 8) {
                ReservationFormTextField(title: "Name", text: $draft.guestName, prompt: "Guest name")
                    .textContentType(.name)
                ReservationFormTextField(title: "Phone", text: $draft.phone, prompt: "Phone")
                    .keyboardType(.phonePad)
            }

            if isEmailExpanded || !draft.email.trimmed.isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                    ReservationFormTextField(title: "Email optional", text: $draft.email, prompt: "Leave blank if none")
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        draft.email = ""
                        isEmailExpanded = false
                        ReservationHaptics.selection()
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 32, height: 34)
                    }
                    .buttonStyle(ReservationHeaderIconButtonStyle())
                }
            } else {
                Button {
                    isEmailExpanded = true
                    ReservationHaptics.selection()
                } label: {
                    Label("Add email (optional)", systemImage: "envelope")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TryzubColors.mutedText)
                }
                .buttonStyle(.plain)
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
        HStack(alignment: .top, spacing: 8) {
            timeCard
                .frame(maxWidth: .infinity, alignment: .topLeading)
            partyCard
                .frame(width: 200)
        }
    }

    private var timeCard: some View {
        ReservationServiceCard(title: "Time", systemImage: "clock", spacing: 8) {
            if isLoadingPublicSlots && suggestedSlots == nil {
                ProgressView("Loading slots...")
                    .font(.caption2)
                    .frame(minHeight: 28, alignment: .leading)
            } else if timeChoices.isEmpty {
                Text("No public slots. Use Custom Time.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TryzubColors.mutedText)
            } else {
                LazyVGrid(
                    columns: ReservationSlotGridStyle.columns,
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

    private var partyCard: some View {
        ReservationServiceCard(title: "Party", systemImage: "person.2", spacing: 8) {
            LazyVGrid(
                columns: ReservationSlotGridStyle.fourColumns,
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
                            minWidth: 36,
                            minHeight: 30
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Stepper(value: $draft.partySize, in: 1...60) {
                Text("Party of \(draft.partySize)")
                    .font(.caption2.weight(.semibold))
            }
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 10) {
            Button {
                isNotesPresented = true
                ReservationHaptics.selection()
            } label: {
                Label(notesButtonTitle, systemImage: "note.text")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.plain)
            
            .foregroundStyle(.primary.opacity(0.78))
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
     
            if !mode.showsEditControls {
                ReservationChoiceChip(
                    title: reliableEmailHint,
                    subtitle: "Email",
                    isSelected: false,
                    minWidth: 100,
                    minHeight: 36
                )
            }
        }
       
    }

    private var notesButtonTitle: String {
        draft.guestNotes.trimmed.isEmpty && draft.staffNotes.trimmed.isEmpty
            ? "Add Notes"
            : "Notes Added"
    }

    private var reliableEmailHint: String {
        draft.email.trimmed.isEmpty ? "-" : "Provided"
    }

    private var editDetailsCard: some View {
        ReservationServiceCard(title: "Service Details", systemImage: "slider.horizontal.3", spacing: 8) {
            LazyVGrid(
                columns: ReservationSlotGridStyle.columns,
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
                            minWidth: 72,
                            minHeight: 30
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

            HStack(spacing: 8) {
                Button {
                    isNotesPresented = true
                    ReservationHaptics.selection()
                } label: {
                    Label(notesButtonTitle, systemImage: "note.text")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TryzubColors.primaryText)
                .background(TryzubColors.cardBackground, in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(TryzubColors.border, lineWidth: 1)
                }

                if let onHideReservation {
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

    private var primaryActionButton: some View {
        Button(action: onSubmit) {
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, mode.primaryButtonBottomInset)
            .background(.regularMaterial)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
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
        if let suggestedSlots, suggestedSlots.isOpen, !suggestedSlots.slots.isEmpty {
            return suggestedSlots.slots.compactMap { ManualReservationFormPresenter.dateForSlotValue($0.value) }
        }

        return controller.restaurantSetup.suggestedTimes(for: draft.reservationDate)
    }

    private func timeLabel(_ date: Date) -> String {
        ReservationFormatters.shortTime.string(from: date)
    }

    private func isSameTime(_ lhs: Date, _ rhs: Date) -> Bool {
        let lhsParts = Calendar.current.dateComponents([.hour, .minute], from: lhs)
        let rhsParts = Calendar.current.dateComponents([.hour, .minute], from: rhs)
        return lhsParts.hour == rhsParts.hour && lhsParts.minute == rhsParts.minute
    }

    private func dateChoiceButton(_ date: Date) -> some View {
        Button {
            draft.reservationDate = date
            if let firstTime = controller.restaurantSetup.suggestedTimes(for: date).first {
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
        if loadedSlotsDateKey == dateKey { return }
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
            // Public slots are the primary signal; a blocked-slots failure must not
            // discard otherwise-valid suggestions.
            let slots = try await controller.loadReservationSlots(date: dateKey)
            guard draft.reservationDate.reservationDateString() == dateKey else { return }
            suggestedSlots = slots
            loadedSlotsDateKey = dateKey

            if let blocked = try? await controller.loadRestaurantBlockedSlots(date: dateKey),
               draft.reservationDate.reservationDateString() == dateKey {
                blockedSlotValues = Set(blocked.data.map { ManualReservationFormPresenter.shortSlotValue($0.slotTime) })
            }
        } catch {
            guard draft.reservationDate.reservationDateString() == dateKey else { return }
            // Cancellation (date change / dismiss) is not a real failure; leave the
            // loaded-date guard unset so the next appear retries.
            if !error.isCancellationLike {
                publicSlotsError = "Public slot suggestions are unavailable. Custom time is still allowed."
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

    init(failure: ImportFailureDTO?) {
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
        ReservationCreateRequest(
            sourceSubmissionId: sourceSubmissionId,
            guestName: guestName.trimmed,
            email: email.trimmed,
            phone: phone.trimmed,
            reservationDate: Self.formatDate(reservationDate),
            reservationTime: Self.formatTime(reservationTime),
            partySize: partySize,
            guestNotes: guestNotes.trimmed.nilIfBlank,
            staffNotes: staffNotes.trimmed.nilIfBlank,
            tableName: tableName.trimmed.nilIfBlank,
            sourceType: sourceType,
            createdByDevice: "ios",
            status: status
        )
    }

    func updateRequest() -> ReservationUpdateRequest {
        ReservationUpdateRequest(
            guestName: guestName.trimmed,
            email: email.trimmed,
            phone: phone.trimmed,
            reservationDate: Self.formatDate(reservationDate),
            reservationTime: Self.formatTime(reservationTime),
            partySize: partySize,
            guestNotes: guestNotes.trimmed,
            staffNotes: staffNotes.trimmed,
            status: status,
            tableName: tableName.trimmed,
            supersededById: Int(supersededById.trimmed)
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

private struct ReservationNotesSheet: View {
    @Binding var guestNotes: String
    @Binding var staffNotes: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ReservationFormTextEditor(title: "Guest notes", text: $guestNotes, minHeight: 120)
                ReservationFormTextEditor(title: "Staff notes", text: $staffNotes, minHeight: 150)
                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reservation Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        ReservationHaptics.selection()
                        dismiss()
                    }
                }
            }
        }
    }
}

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
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ReservationUIStyle.controlCorner, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
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
