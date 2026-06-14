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
        DetailSectionCard(title: "Guest message", systemImage: "text.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Review before sending. Nothing is sent automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isDrafting {
                    TryzubLoadingRow(title: "Preparing draft...")
                }

                draftButton(.reminder, systemImage: "bell")

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

    private var screenTitle: String {
        kind == .reminder ? "Review reminder" : "Review message"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerSection

                    if showsBetaWarning {
                        inlineAINote
                    }

                    if draft.isBlocked, let reason = draft.blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                        reviewBanner(title: "Draft blocked", message: reason, tint: .orange)
                    }

                    editableField(title: "Subject", text: $editedSubject, axis: false)
                    editableField(title: "Email message", text: $editedEmailBody, axis: true)
                    editableField(title: "Text message", text: $editedTextBody, axis: true)

                    actionButtons
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(screenTitle)
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
                GuestCommunicationTrace.messageReviewPolish(
                    reservationID: reservationID,
                    type: reviewTraceType
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
            Text(screenTitle)
                .font(.title3.weight(.semibold))
            Text("Nothing is sent automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inlineAINote: some View {
        Label("AI draft — review before sending.", systemImage: "sparkles")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                onSendEmail(approvedDraft())
            } label: {
                Label("Open Email", systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sendDisabled || !canSendEmail)

            Button {
                onSendText(approvedDraft())
            } label: {
                Label("Open Text", systemImage: "message.fill")
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
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: title == "Text message" ? 86 : 108)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .onChange(of: text.wrappedValue) { _, _ in markEdited() }
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
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
