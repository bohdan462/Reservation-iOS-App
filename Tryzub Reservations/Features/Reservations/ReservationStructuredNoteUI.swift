//
//  ReservationStructuredNoteUI.swift
//  Tryzub Reservations
//
//  UI components for the structured staff notes feature:
//    - StructuredNoteEditorSheet  — full editor for all note fields
//    - StructuredNoteRow          — compact label + text row
//    - DepositStatusPill          — colored pill for DepositStatus
//    - PreorderStatusPill         — colored pill for PreorderStatus
//

import SwiftUI
import SwiftData

// MARK: - Editor sheet

/// Full editor for all structured note fields on a single reservation.
/// Creates a new ReservationStructuredNoteRecord if one doesn't exist yet.
struct StructuredNoteEditorSheet: View {

    let reservationID: Int
    let guestName: String
    let existingRecord: ReservationStructuredNoteRecord?
    var modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    // Local edit state — mirrored to SwiftData on save
    @State private var managerNote: String = ""
    @State private var kitchenNote: String = ""
    @State private var barNote: String = ""
    @State private var setupNote: String = ""
    @State private var depositStatus: DepositStatus = .none
    @State private var depositAmountText: String = ""
    @State private var depositNoteText: String = ""
    @State private var preorderStatus: PreorderStatus = .none
    @State private var preorderNoteText: String = ""
    @State private var banquetNoteText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(guestName)
                        .font(.subheadline.weight(.semibold))
                    Text("These notes are stored on this device only until backend fields are available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Staff notes") {
                    staffNoteField(title: "Manager note", icon: "person.badge.key", text: $managerNote,
                                   placeholder: "Payment decision, special arrangements…")
                    staffNoteField(title: "Kitchen note", icon: "fork.knife", text: $kitchenNote,
                                   placeholder: "Preorder, allergy detail, cake, specific dishes…")
                    staffNoteField(title: "Bar note", icon: "wineglass", text: $barNote,
                                   placeholder: "Champagne, bottle, cocktail preference…")
                    staffNoteField(title: "Setup note", icon: "chair", text: $setupNote,
                                   placeholder: "High chair, wheelchair, quiet table, decorations…")
                }

                Section {
                    Picker("Status", selection: $depositStatus) {
                        ForEach(DepositStatus.allCases, id: \.rawValue) { status in
                            Text(status.staffLabel).tag(status)
                        }
                    }
                    if depositStatus != .none {
                        TextField("Amount (e.g. $200)", text: $depositAmountText)
                            .font(.subheadline)
                        TextField("Deposit note", text: $depositNoteText, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(2...4)
                    }
                } header: {
                    Text("Deposit")
                } footer: {
                    if depositStatus == .mentioned || depositStatus == .needsReview {
                        Text("Manager should verify before service.")
                    }
                }

                Section {
                    Picker("Status", selection: $preorderStatus) {
                        ForEach(PreorderStatus.allCases, id: \.rawValue) { status in
                            Text(status.staffLabel).tag(status)
                        }
                    }
                    if preorderStatus != .none {
                        TextField("Preorder note", text: $preorderNoteText, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(2...4)
                        TextField("Banquet / package note", text: $banquetNoteText, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(2...4)
                    }
                } header: {
                    Text("Preorder / Banquet")
                } footer: {
                    if preorderStatus == .mentioned {
                        Text("Kitchen should review before service.")
                    }
                }
            }
            .navigationTitle("Staff Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                populateFromExisting()
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func staffNoteField(
        title: String,
        icon: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...4)
        }
        .padding(.vertical, 2)
    }

    private func populateFromExisting() {
        guard let r = existingRecord else { return }
        managerNote = r.managerNote ?? ""
        kitchenNote = r.kitchenNote ?? ""
        barNote = r.barNote ?? ""
        setupNote = r.setupNote ?? ""
        depositStatus = r.depositStatus
        depositAmountText = r.depositAmountText ?? ""
        depositNoteText = r.depositNoteText ?? ""
        preorderStatus = r.preorderStatus
        preorderNoteText = r.preorderNoteText ?? ""
        banquetNoteText = r.banquetNoteText ?? ""
    }

    private func saveAndDismiss() {
        let record: ReservationStructuredNoteRecord
        if let existing = existingRecord {
            record = existing
        } else {
            record = ReservationStructuredNoteRecord(reservationRemoteID: reservationID)
            modelContext.insert(record)
        }
        record.managerNote = managerNote.trimmedNilIfBlank
        record.kitchenNote = kitchenNote.trimmedNilIfBlank
        record.barNote = barNote.trimmedNilIfBlank
        record.setupNote = setupNote.trimmedNilIfBlank
        record.depositStatus = depositStatus
        record.depositAmountText = depositAmountText.trimmedNilIfBlank
        record.depositNoteText = depositNoteText.trimmedNilIfBlank
        record.preorderStatus = preorderStatus
        record.preorderNoteText = preorderNoteText.trimmedNilIfBlank
        record.banquetNoteText = banquetNoteText.trimmedNilIfBlank
        record.updatedAt = Date()
        dismiss()
    }
}

// MARK: - Row

/// A compact label + body-text row for structured note fields.
struct StructuredNoteRow: View {
    let label: String
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label(label, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Status pills

struct DepositStatusPill: View {
    let status: DepositStatus

    var body: some View {
        Text(status.staffLabel)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(pillBackground)
            .foregroundStyle(pillForeground)
            .clipShape(Capsule())
    }

    private var pillBackground: Color {
        switch status {
        case .none: return Color.secondary.opacity(0.1)
        case .mentioned: return Color.orange.opacity(0.15)
        case .needsReview: return Color.red.opacity(0.12)
        case .verified: return Color.green.opacity(0.12)
        }
    }

    private var pillForeground: Color {
        switch status {
        case .none: return .secondary
        case .mentioned: return .orange
        case .needsReview: return .red
        case .verified: return .green
        }
    }
}

struct PreorderStatusPill: View {
    let status: PreorderStatus

    var body: some View {
        Text(status.staffLabel)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(pillBackground)
            .foregroundStyle(pillForeground)
            .clipShape(Capsule())
    }

    private var pillBackground: Color {
        switch status {
        case .none: return Color.secondary.opacity(0.1)
        case .mentioned: return Color.orange.opacity(0.15)
        case .confirmed: return Color.green.opacity(0.12)
        }
    }

    private var pillForeground: Color {
        switch status {
        case .none: return .secondary
        case .mentioned: return .orange
        case .confirmed: return .green
        }
    }
}

// MARK: - String helper

private extension String {
    var trimmedNilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
