//
//  ReservationDetailView.swift
//  Tryzub Reservations
//

import SwiftUI
import SwiftData

struct ReservationDetailView: View {
    let reservation: ReservationRecord
    let environment: AppEnvironment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ReservationsController

    @State private var showEditSheet = false
    @State private var isSavingQuickAction = false
    @State private var errorMessage: String?
    @State private var pendingAction: ReservationHostAction?
    @State private var tableAssignmentReservation: ReservationRecord?
    @State private var showSeatWithoutTableDialog = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                detailContent(isWide: proxy.size.width >= 760)
                    .padding(.horizontal, proxy.size.width >= 760 ? 20 : 16)
                    .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(reservation.guestName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showEditSheet = true
                }
                .disabled(!controller.capabilities.canEditReservationDetails)
            }
        }
        .sheet(item: $tableAssignmentReservation) { reservation in
            TableAssignmentSheet(reservation: reservation) { tableName in
                _ = try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: ReservationUpdateRequest(tableName: tableName),
                    context: modelContext
                )
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ReservationEditView(reservation: reservation) { request in
                try await controller.updateReservation(
                    id: reservation.remoteID,
                    request: request,
                    context: modelContext
                )
            }
        }
        .confirmationDialog(
            pendingAction?.dialogTitle(for: reservation) ?? "Update Reservation?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.fullTitle, role: pendingAction.role) {
                    Task {
                        await perform(pendingAction)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            if let pendingAction {
                Text(pendingAction.dialogMessage(for: reservation))
            }
        }
        .confirmationDialog(
            "Seat without table assignment?",
            isPresented: $showSeatWithoutTableDialog,
            titleVisibility: .visible
        ) {
            Button("Assign Table") {
                tableAssignmentReservation = reservation
            }
            Button("Seat Anyway") {
                Task {
                    await perform(.seat, allowSeatWithoutTable: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(reservation.guestName) has no table assigned. Assign a table first, or seat the party anyway if the host stand already knows the table.")
        }
    }

    @ViewBuilder
    private func detailContent(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = errorMessage ?? controller.errorMessage {
                DetailWarningCard(
                    title: "Action did not finish",
                    message: message,
                    symbolName: "exclamationmark.triangle",
                    tint: .red
                )
            }

            if reservation.statusValue == .needsReview {
                DetailWarningCard(
                    title: "Needs review",
                    message: reservation.staffNotes?.nilIfBlank ?? "Check this reservation before confirming.",
                    symbolName: "exclamationmark.triangle",
                    tint: .orange
                )
            }

            if isWide {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        ReservationHeroCard(
                            reservation: reservation,
                            capabilities: controller.capabilities,
                            isBusy: isSavingQuickAction || controller.isActionInProgress(for: reservation),
                            onAction: handleAction,
                            onEdit: { showEditSheet = true }
                        )
                        ReservationNotesCard(reservation: reservation) {
                            showEditSheet = true
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(spacing: 14) {
                        ReservationContactCard(reservation: reservation)
                        ReservationFactsCard(reservation: reservation)
                        ReservationOperationalCard(reservation: reservation)
                    }
                    .frame(maxWidth: 420, alignment: .topLeading)
                }
            } else {
                ReservationHeroCard(
                    reservation: reservation,
                    capabilities: controller.capabilities,
                    isBusy: isSavingQuickAction || controller.isActionInProgress(for: reservation),
                    onAction: handleAction,
                    onEdit: { showEditSheet = true }
                )
                ReservationContactCard(reservation: reservation)
                ReservationFactsCard(reservation: reservation)
                ReservationNotesCard(reservation: reservation) {
                    showEditSheet = true
                }
                ReservationOperationalCard(reservation: reservation)
            }
        }
    }

    private func handleAction(_ action: ReservationHostAction) {
        if action == .assignTable {
            tableAssignmentReservation = reservation
        } else if action == .seat, !reservation.hasTableAssignment {
            showSeatWithoutTableDialog = true
        } else {
            pendingAction = action
        }
    }

    private func perform(_ action: ReservationHostAction, allowSeatWithoutTable: Bool = false) async {
        if action == .seat, !allowSeatWithoutTable, !reservation.hasTableAssignment {
            pendingAction = nil
            showSeatWithoutTableDialog = true
            return
        }

        pendingAction = nil
        isSavingQuickAction = true
        errorMessage = nil

        defer {
            isSavingQuickAction = false
        }

        switch action {
        case .confirm:
            await controller.confirmReservation(reservation: reservation, context: modelContext)
        case .seat:
            await controller.updateStatus(reservation: reservation, status: .seated, context: modelContext)
        case .complete:
            await controller.updateStatus(reservation: reservation, status: .completed, context: modelContext)
        case .cancel:
            await controller.updateStatus(reservation: reservation, status: .cancelled, context: modelContext)
        case .noShow:
            await controller.updateStatus(reservation: reservation, status: .noShow, context: modelContext)
        case .assignTable:
            tableAssignmentReservation = reservation
        }
    }
}

private struct ReservationHeroCard: View {
    let reservation: ReservationRecord
    let capabilities: AppCapabilities
    let isBusy: Bool
    let onAction: (ReservationHostAction) -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.displayTime)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(reservation.displayDate)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(2)

                Spacer()

                ReservationStatusBadge(status: reservation.statusValue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(reservation.guestName)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    DetailPill(label: "\(reservation.partySize)", systemImage: "person.2", tint: .green)
                    DetailPill(label: reservation.tableDisplay, systemImage: "table.furniture", tint: reservation.hasTableAssignment ? .secondary : .orange)
                    if reservation.confirmationEmailSentAt?.nilIfBlank != nil {
                        DetailPill(label: "Email sent", systemImage: "envelope.badge", tint: .blue)
                    }
                }
                .lineLimit(1)
            }

            ReservationActionButtons(
                reservation: reservation,
                capabilities: capabilities,
                compact: false,
                includeSecondary: true,
                isBusy: isBusy,
                onAction: onAction
            )

            Button {
                onEdit()
            } label: {
                Label("Edit Details", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .disabled(!capabilities.canEditReservationDetails)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ReservationContactCard: View {
    let reservation: ReservationRecord

    private var phoneURL: URL? {
        let digits = reservation.phone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }

    private var emailURL: URL? {
        URL(string: "mailto:\(reservation.email)")
    }

    var body: some View {
        DetailCard(title: "Contact", systemImage: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 12) {
                if let phoneURL {
                    Link(destination: phoneURL) {
                        DetailContactLine(title: "Phone", value: reservation.formattedPhone, systemImage: "phone")
                    }
                    .buttonStyle(.plain)
                } else {
                    DetailContactLine(title: "Phone", value: reservation.formattedPhone, systemImage: "phone")
                }

                if let emailURL {
                    Link(destination: emailURL) {
                        DetailContactLine(title: "Email", value: reservation.email, systemImage: "envelope")
                    }
                    .buttonStyle(.plain)
                } else {
                    DetailContactLine(title: "Email", value: reservation.email, systemImage: "envelope")
                }
            }
        }
    }
}

private struct ReservationFactsCard: View {
    let reservation: ReservationRecord

    var body: some View {
        DetailCard(title: "Reservation", systemImage: "calendar") {
            VStack(spacing: 10) {
                DetailInfoRow(title: "Date", value: reservation.displayDate)
                DetailInfoRow(title: "Time", value: reservation.displayTime, monospaced: true)
                DetailInfoRow(title: "Party", value: "\(reservation.partySize) guests", monospaced: true)
                DetailInfoRow(title: "Table", value: reservation.tableDisplay, valueTint: reservation.hasTableAssignment ? .secondary : .orange)
                DetailInfoRow(title: "Status", value: reservation.statusValue.displayName)
            }
        }
    }
}

private struct ReservationNotesCard: View {
    let reservation: ReservationRecord
    let onEdit: () -> Void

    var body: some View {
        DetailCard(title: "Notes", systemImage: "note.text") {
            VStack(alignment: .leading, spacing: 14) {
                DetailNoteBlock(title: "Guest", value: reservation.guestNotes)
                DetailNoteBlock(title: "Staff", value: reservation.staffNotes)

                Button {
                    onEdit()
                } label: {
                    Label("Edit Notes", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct ReservationOperationalCard: View {
    let reservation: ReservationRecord

    var body: some View {
        DetailCard(title: "Operations", systemImage: "server.rack") {
            VStack(spacing: 10) {
                DetailInfoRow(title: "Remote ID", value: "#\(reservation.remoteID)", monospaced: true)
                DetailInfoRow(title: "Source", value: reservation.sourceSubmissionID > 0 ? "#\(reservation.sourceSubmissionID)" : "Manual", monospaced: true)
                DetailInfoRow(title: "Superseded By", value: reservation.supersededById.map { "#\($0)" } ?? "-", monospaced: true)
                Divider()
                DetailInfoRow(title: "Created", value: DetailDateFormatting.server(reservation.createdAt))
                DetailInfoRow(title: "Updated", value: DetailDateFormatting.server(reservation.apiUpdatedAt))
                DetailInfoRow(title: "Confirmed", value: DetailDateFormatting.server(reservation.confirmedAt))
                DetailInfoRow(title: "Email", value: DetailDateFormatting.server(reservation.confirmationEmailSentAt))
                DetailInfoRow(title: "Reminder", value: DetailDateFormatting.server(reservation.reminderEmailSentAt))
                DetailInfoRow(title: "Last Synced", value: DetailDateFormatting.local(reservation.lastSyncedAt))
            }
        }
    }
}

private struct DetailWarningCard: View {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailContactLine: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct DetailInfoRow: View {
    let title: String
    let value: String
    var monospaced = false
    var valueTint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(monospaced ? .subheadline.monospacedDigit() : .subheadline)
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct DetailNoteBlock: View {
    let title: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value?.nilIfBlank ?? "-")
                .font(.subheadline)
                .foregroundStyle(value?.nilIfBlank == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DetailPill: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private enum DetailDateFormatting {
    static func server(_ dateString: String?) -> String {
        guard let dateString = dateString?.nilIfBlank else {
            return "-"
        }

        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"

        guard let date = parser.date(from: dateString) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func local(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ReservationEditView: View {
    let reservation: ReservationRecord
    let onSave: (ReservationUpdateRequest) async throws -> ReservationDTO

    @Environment(\.dismiss) private var dismiss

    @State private var guestName: String
    @State private var email: String
    @State private var phone: String
    @State private var reservationDate: Date
    @State private var reservationTime: Date
    @State private var partySize: Int
    @State private var selectedStatus: ReservationStatus
    @State private var tableName: String
    @State private var guestNotes: String
    @State private var staffNotes: String
    @State private var supersededById: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        reservation: ReservationRecord,
        onSave: @escaping (ReservationUpdateRequest) async throws -> ReservationDTO
    ) {
        self.reservation = reservation
        self.onSave = onSave

        _guestName = State(initialValue: reservation.guestName)
        _email = State(initialValue: reservation.email)
        _phone = State(initialValue: reservation.phone)
        _reservationDate = State(initialValue: Self.parseDate(reservation.reservationDate) ?? Date())
        _reservationTime = State(initialValue: Self.parseTime(reservation.reservationTime) ?? Date())
        _partySize = State(initialValue: reservation.partySize)
        _selectedStatus = State(initialValue: reservation.statusValue)
        _tableName = State(initialValue: reservation.tableName ?? "")
        _guestNotes = State(initialValue: reservation.guestNotes ?? "")
        _staffNotes = State(initialValue: reservation.staffNotes ?? "")
        _supersededById = State(initialValue: reservation.supersededById.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section("Guest") {
                    TextField("Name", text: $guestName)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section("Reservation") {
                    DatePicker("Date", selection: $reservationDate, displayedComponents: .date)
                    DatePicker("Time", selection: $reservationTime, displayedComponents: .hourAndMinute)

                    Stepper(value: $partySize, in: 1...60) {
                        HStack {
                            Text("Party")
                            Spacer()
                            Text("\(partySize)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Status", selection: $selectedStatus) {
                        ForEach(ReservationStatus.allCases) { status in
                            Text(status.displayName).tag(status)
                        }
                    }

                    TextField("Table", text: $tableName, prompt: Text("Unassigned"))
                }

                Section("Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Guest Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $guestNotes)
                            .frame(minHeight: 70)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Staff Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $staffNotes)
                            .frame(minHeight: 90)
                    }
                }

                Section("Duplicate Resolution") {
                    TextField("Superseded by reservation ID", text: $supersededById)
                        .keyboardType(.numberPad)
                    Text("Use this only on the duplicate/cancelled record. The ID should be the reservation you are keeping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Reservation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        let trimmedName = guestName.trimmed
        let trimmedEmail = email.trimmed
        let trimmedPhone = phone.trimmed
        let trimmedSupersededById = supersededById.trimmed

        guard !trimmedName.isEmpty else {
            errorMessage = "Guest name is required."
            return
        }

        guard !trimmedEmail.isEmpty else {
            errorMessage = "Email is required."
            return
        }

        guard !trimmedPhone.isEmpty else {
            errorMessage = "Phone is required."
            return
        }

        let supersededByReservationId: Int?
        if trimmedSupersededById.isEmpty {
            supersededByReservationId = nil
        } else if let id = Int(trimmedSupersededById), id > 0 {
            supersededByReservationId = id
        } else {
            errorMessage = "Superseded By must be a reservation ID."
            return
        }

        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        let request = ReservationUpdateRequest(
            guestName: trimmedName,
            email: trimmedEmail,
            phone: trimmedPhone,
            reservationDate: Self.formatDate(reservationDate),
            reservationTime: Self.formatTime(reservationTime),
            partySize: partySize,
            guestNotes: guestNotes.trimmed,
            staffNotes: staffNotes.trimmed,
            status: selectedStatus,
            tableName: tableName.trimmed,
            supersededById: supersededByReservationId
        )

        do {
            _ = try await onSave(request)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func parseTime(_ value: String) -> Date? {
        let formatter = DateFormatter()

        for format in ["HH:mm:ss", "HH:mm", "h:mm a"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let trimmed = trimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if DEBUG
#Preview("Reservation Detail") {
    NavigationStack {
        ReservationDetailView(
            reservation: ReservationPreviewData.sampleRecord,
            environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
        )
    }
    .modelContainer(ReservationPreviewData.previewContainer)
    .environmentObject(
        ReservationsController(
            environment: AppEnvironment(apiClient: ReservationsAPIClient.preview, role: .developer)
        )
    )
}
#endif
