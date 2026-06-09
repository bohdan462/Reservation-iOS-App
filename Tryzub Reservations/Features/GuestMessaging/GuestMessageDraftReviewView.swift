//
//  GuestMessageDraftReviewView.swift
//  Tryzub Reservations
//

import SwiftUI

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
    let kind: GuestMessageDraftKind
    let draft: GuestMessageDraft
    let canSendEmail: Bool
    let canSendText: Bool
    let onSendEmail: () -> Void
    let onSendText: () -> Void
    let onCopyEmail: () -> Void
    let onCopyText: () -> Void
    let onDismiss: () -> Void

    private var sendDisabled: Bool {
        draft.isBlocked
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection

                    if draft.isBlocked, let reason = draft.blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                        reviewBanner(title: "Draft blocked", message: reason, tint: .orange)
                    } else if draft.hasSafetyNote, let note = draft.safetyNote {
                        reviewBanner(title: "Review note", message: note, tint: TryzubColors.info)
                    }

                    reviewField(title: "Email subject", value: draft.emailSubject)
                    reviewField(title: "Email body", value: draft.emailBody, allowsWrap: true)
                    reviewField(title: "Text message", value: draft.shortMessageBody, allowsWrap: true)

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
            Button(action: onSendEmail) {
                Label("Send Email", systemImage: "envelope.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sendDisabled || !canSendEmail)

            Button(action: onSendText) {
                Label("Send Text", systemImage: "message.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(sendDisabled || !canSendText)

            HStack(spacing: 10) {
                Button(action: onCopyEmail) {
                    Label("Copy Email", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sendDisabled)

                Button(action: onCopyText) {
                    Label("Copy Text", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sendDisabled)
            }
        }
    }

    @ViewBuilder
    private func reviewField(title: String, value: String, allowsWrap: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(allowsWrap ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ReservationUIStyle.cardCorner, style: .continuous))
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
