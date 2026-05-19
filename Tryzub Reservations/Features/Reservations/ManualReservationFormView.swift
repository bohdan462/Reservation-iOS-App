//
//  ManualReservationFormView.swift
//  Tryzub Reservations
//

import SwiftUI

struct ManualReservationFormView: View {
    let failure: ImportFailureDTO?
    let onCreateReservation: (ReservationCreateRequest) async throws -> ReservationDTO

    @Environment(\.dismiss) private var dismiss

    @State private var guestName: String
    @State private var email: String
    @State private var phone: String
    @State private var reservationDate: Date
    @State private var reservationTime: Date
    @State private var partySize: Int
    @State private var guestNotes: String
    @State private var staffNotes: String
    @State private var tableName: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        failure: ImportFailureDTO? = nil,
        onCreateReservation: @escaping (ReservationCreateRequest) async throws -> ReservationDTO
    ) {
        self.failure = failure
        self.onCreateReservation = onCreateReservation

        let snapshot = failure?.reservation
        _guestName = State(initialValue: snapshot?.guestName ?? "")
        _email = State(initialValue: snapshot?.email ?? "")
        _phone = State(initialValue: snapshot?.phone ?? "")
        _reservationDate = State(initialValue: Self.parseDate(snapshot?.reservationDate) ?? Date())
        _reservationTime = State(initialValue: Self.parseTime(snapshot?.reservationTime) ?? Date())
        _partySize = State(initialValue: max(snapshot?.partySize ?? 2, 1))
        _guestNotes = State(initialValue: snapshot?.notes ?? "")

        let defaultStaffNotes: String
        if let failure {
            defaultStaffNotes = "Created manually from failed Flamingo import \(failure.sourceSubmissionId.map(String.init) ?? "unknown")."
        } else {
            defaultStaffNotes = ""
        }

        _staffNotes = State(initialValue: defaultStaffNotes)
        _tableName = State(initialValue: "")
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

                if let failure {
                    Section("Failed Import Link") {
                        row("Source Submission", failure.sourceSubmissionId.map(String.init) ?? "Unknown")
                        row("Reason", failure.errorMessage)
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
                            Text("Party Size")
                            Spacer()
                            Text("\(partySize)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("Table", text: $tableName, prompt: Text("Optional"))
                }

                Section("Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Guest Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $guestNotes)
                            .frame(minHeight: 80)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Staff Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $staffNotes)
                            .frame(minHeight: 100)
                    }
                }
            }
            .navigationTitle(failure == nil ? "New Reservation" : "Fix Failed Import")
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
                            await createReservation()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func createReservation() async {
        let trimmedName = guestName.trimmed
        let trimmedEmail = email.trimmed
        let trimmedPhone = phone.trimmed

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

        isSaving = true
        errorMessage = nil

        defer {
            isSaving = false
        }

        let request = ReservationCreateRequest(
            sourceSubmissionId: failure?.sourceSubmissionId,
            guestName: trimmedName,
            email: trimmedEmail,
            phone: trimmedPhone,
            reservationDate: Self.formatDate(reservationDate),
            reservationTime: Self.formatTime(reservationTime),
            partySize: partySize,
            guestNotes: guestNotes.trimmed.nilIfBlank,
            staffNotes: staffNotes.trimmed.nilIfBlank,
            tableName: tableName.trimmed.nilIfBlank
        )

        do {
            _ = try await onCreateReservation(request)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
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
        isEmpty ? nil : self
    }
}

#if DEBUG
#Preview("Manual Reservation") {
    ManualReservationFormView { _ in
        ReservationPreviewData.sampleDTOs[0]
    }
}
#endif
