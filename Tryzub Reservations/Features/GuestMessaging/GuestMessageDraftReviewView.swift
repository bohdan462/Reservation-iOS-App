//
//  GuestMessageDraftReviewView.swift
//  Tryzub Reservations
//

import SwiftUI

// MARK: - Approved draft

struct ApprovedGuestMessageDraft: Equatable {
    let kind: GuestMessageDraftKind
    let emailSubject: String
    let emailBody: String
    let shortMessageBody: String
    let source: GuestMessageDraftSource
    let wasEdited: Bool
    let aiGenerated: Bool

    init(
        kind: GuestMessageDraftKind,
        draft: GuestMessageDraft,
        emailSubject: String,
        emailBody: String,
        shortMessageBody: String,
        wasEdited: Bool
    ) {
        self.kind = kind
        self.emailSubject = emailSubject
        self.emailBody = emailBody
        self.shortMessageBody = shortMessageBody
        self.source = draft.source
        self.wasEdited = wasEdited
        self.aiGenerated = draft.source == .localModel
    }
}

// MARK: - Detail actions

struct GuestMessageDraftActionsSection: View {
    let reservation: ReservationRecord
    let isDrafting: Bool
    let onDraft: (GuestMessageDraftKind) -> Void

    private var isLargeParty: Bool {
        reservation.partySize >= GuestMessageDraftPacketBuilder.largePartyMinimumPartySize
    }

    private var showsTableReadyDraft: Bool {
        guard !reservation.isHidden else { return false }
        switch reservation.statusValue {
        case .confirmed, .seated:
            return true
        case .cancelled, .completed, .noShow:
            return false
        default:
            return false
        }
    }

    var body: some View {
        DetailSectionCard(title: "Draft guest message", systemImage: "text.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Review before sending. Nothing is sent automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isDrafting {
                    TryzubLoadingRow(title: "Preparing draft...")
                }

                draftButton(.confirmation, systemImage: "checkmark.circle")
                draftButton(.reminder, systemImage: "bell")
                draftButton(.clarificationRequest, systemImage: "questionmark.circle")

                if isLargeParty {
                    draftButton(.largePartyConfirmation, systemImage: "person.3.fill", emphasized: true)
                }

                if showsTableReadyDraft {
                    draftButton(.tableReady, systemImage: "table.furniture", emphasized: true)
                }
            }
        }
    }

    @ViewBuilder
    private func draftButton(
        _ kind: GuestMessageDraftKind,
        systemImage: String,
        emphasized: Bool = false
    ) -> some View {
        Button {
            onDraft(kind)
        } label: {
            Label(kind.draftActionTitle, systemImage: systemImage)
                .font(.subheadline.weight(emphasized ? .semibold : .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isDrafting)
    }
}

// MARK: - Review sheet

struct GuestMessageDraftReviewView: View {
    let reservationID: Int
    let kind: GuestMessageDraftKind
    let draft: GuestMessageDraft
    let canSendEmail: Bool
    let canSendText: Bool
    let onSendEmail: (ApprovedGuestMessageDraft) -> Void
    let onSendText: (ApprovedGuestMessageDraft) -> Void
    let onCopyEmail: (ApprovedGuestMessageDraft) -> Void
    let onCopyText: (ApprovedGuestMessageDraft) -> Void
    let onDismiss: () -> Void

    @State private var editedSubject: String = ""
    @State private var editedEmailBody: String = ""
    @State private var editedTextBody: String = ""
    @State private var didEdit = false

    private var sendDisabled: Bool {
        draft.isBlocked
    }

    private var showsBetaWarning: Bool {
        draft.source == .localModel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection

                    if showsBetaWarning {
                        reviewBanner(
                            title: "AI draft is beta",
                            message: "AI draft is beta. Review and edit before sending.",
                            tint: TryzubColors.info
                        )
                    }

                    if draft.isBlocked, let reason = draft.blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                        reviewBanner(title: "Draft blocked", message: reason, tint: .orange)
                    } else if draft.hasSafetyNote, let note = draft.safetyNote, draft.source == .localModel {
                        reviewBanner(title: "Review note", message: note, tint: TryzubColors.info)
                    }

                    editableField(title: "Email subject", text: $editedSubject, axis: false)
                    editableField(title: "Email body", text: $editedEmailBody, axis: true)
                    editableField(title: "Text reminder", text: $editedTextBody, axis: true)

                    actionButtons
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(kind.staffLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
            .onAppear {
                editedSubject = draft.emailSubject
                editedEmailBody = draft.emailBody
                editedTextBody = draft.shortMessageBody
                GuestCommunicationTrace.messageReview(
                    reservationID: reservationID,
                    type: reviewTraceType,
                    phase: "presented",
                    aiDraft: draft.source == .localModel,
                    edited: false
                )
            }
        }
    }

    private var reviewTraceType: String {
        switch kind {
        case .confirmation: return "confirmation"
        case .reminder: return "reminder"
        case .clarificationRequest, .largePartyConfirmation, .tableReady: return "manualQuestion"
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.staffLabel)
                .font(.title3.weight(.semibold))
            Text(draft.source.staffLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Review before sending. Staff sends manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                onSendEmail(approvedDraft())
            } label: {
                Label("Send Email", systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sendDisabled || !canSendEmail)

            Button {
                onSendText(approvedDraft())
            } label: {
                Label("Send Text", systemImage: "message.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(sendDisabled || !canSendText)

            HStack(spacing: 10) {
                Button {
                    onCopyEmail(approvedDraft())
                } label: {
                    Label("Copy Email", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sendDisabled)

                Button {
                    onCopyText(approvedDraft())
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sendDisabled)
            }
        }
    }

    @ViewBuilder
    private func editableField(title: String, text: Binding<String>, axis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if axis {
                TextEditor(text: text)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
                    .onChange(of: text.wrappedValue) { _, _ in markEdited() }
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text.wrappedValue) { _, _ in markEdited() }
            }
        }
    }

    private func approvedDraft() -> ApprovedGuestMessageDraft {
        GuestCommunicationTrace.messageReview(
            reservationID: reservationID,
            type: reviewTraceType,
            phase: "approved_for_composer",
            aiDraft: draft.source == .localModel,
            edited: didEdit
        )
        return ApprovedGuestMessageDraft(
            kind: kind,
            draft: draft,
            emailSubject: editedSubject,
            emailBody: editedEmailBody,
            shortMessageBody: editedTextBody,
            wasEdited: didEdit
        )
    }

    private func markEdited() {
        didEdit = true
        GuestCommunicationTrace.messageReview(
            reservationID: reservationID,
            type: reviewTraceType,
            phase: "edited",
            aiDraft: draft.source == .localModel,
            edited: true
        )
    }

    private func reviewBanner(title: String, message: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// Shared with ReservationDetailView detail cards.
private struct DetailSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.medium))

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
