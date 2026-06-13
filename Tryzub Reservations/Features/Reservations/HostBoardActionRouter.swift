//
//  HostBoardActionRouter.swift
//  Tryzub Reservations
//
//  Small UI routing helpers for Host Intelligence cluster actions.
//

import SwiftUI

enum HostBoardActionRouter {
    static func reservation(
        for action: HostQuickAction,
        dayReservations: [ReservationRecord],
        knownReservations: [ReservationRecord]
    ) -> ReservationRecord? {
        HostSuggestedActionRouter.findReservation(
            remoteID: action.remoteID,
            dayReservations: dayReservations,
            knownReservations: knownReservations
        )
    }

    static func sanitizedGuestNote(from reservation: ReservationRecord) -> String {
        let raw = reservation.guestNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            return "No guest note is saved for this reservation."
        }

        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: "."))
        let safeLines = raw
            .components(separatedBy: separators)
            .compactMap { ManagerNarrativePacketSanitizer.staffSafeLine($0) }
            .filter { !$0.isEmpty }

        guard !safeLines.isEmpty else {
            return "This note contains details that should be checked in reservation detail."
        }
        return safeLines.prefix(3).joined(separator: ". ") + "."
    }
}

struct HostGuestNoteSheetContext: Identifiable {
    let reservation: ReservationRecord
    let noteText: String

    var id: Int { reservation.remoteID }
}

struct HostQuickActionDraftReviewContext: Identifiable {
    let id = UUID()
    let reservation: ReservationRecord
    let kind: GuestMessageDraftKind
    let draft: GuestMessageDraft
}

struct HostGuestNoteSheet: View {
    let context: HostGuestNoteSheetContext
    let onOpenDetail: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.reservation.guestName)
                        .font(.headline)
                    Text("\(context.reservation.displayTime) · \(context.reservation.partySize) guest\(context.reservation.partySize == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(context.noteText)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    dismiss()
                    onOpenDetail()
                } label: {
                    Label("Open detail", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Guest note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
