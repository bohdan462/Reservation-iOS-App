//
//  GuestMessageDraftService.swift
//  Tryzub Reservations
//
//  UI integration boundary for guest message drafts (Phase 4B+).
//

import Foundation

enum GuestMessageDraftWriterHandle: Sendable {
    case template
    case localModel

    func draftMessage(from packet: GuestMessageDraftPacket) async -> GuestMessageDraft {
        switch self {
        case .template:
            return await TemplateGuestMessageDraftWriter().draftMessage(from: packet)
        case .localModel:
            return await LocalModelGuestMessageDraftWriter().draftMessage(from: packet)
        }
    }
}

@MainActor
final class GuestMessageDraftService: ObservableObject {

    @Published private(set) var isDrafting = false
    @Published private(set) var lastErrorMessage: String?

    private let writer: GuestMessageDraftWriterHandle
    private let wordingProfile: LocalWordingModelProfile

    init(writer: GuestMessageDraftWriterHandle, wordingProfile: LocalWordingModelProfile) {
        self.writer = writer
        self.wordingProfile = wordingProfile
    }

    func draft(
        kind: GuestMessageDraftKind,
        reservation: ReservationRecord,
        restaurantProfile: ReservationEmailRestaurantProfile = .workflowDefault,
        manageURL: String? = nil,
        tone: GuestMessageTone = .warmProfessional
    ) async -> GuestMessageDraft {
        isDrafting = true
        lastErrorMessage = nil
        defer { isDrafting = false }

        let packet = GuestMessageDraftPacketBuilder.build(
            kind: kind,
            reservation: reservation,
            restaurantProfile: restaurantProfile,
            manageURL: manageURL,
            tone: tone
        )

        let templateFallback = GuestMessageDraftTemplateWriter.draft(from: packet)
        if kind.usesDeterministicOperationalTemplate {
            HostProductionTrace.guestDraftContext(
                remoteID: reservation.remoteID,
                kind: kind,
                occasion: packet.occasion,
                source: "template"
            )
            return templateFallback
        }

        let draft = await writer.draftMessage(from: packet)

        switch GuestMessageDraftValidator.validate(draft, packet: packet) {
        case .valid:
            HostProductionTrace.guestDraftContext(
                remoteID: reservation.remoteID,
                kind: kind,
                occasion: packet.occasion,
                source: draft.source == .localModel ? wordingProfile.traceName : draft.source.rawValue
            )
            return draft
        case .blocked(let reason):
            HostProductionTrace.guestDraftContext(
                remoteID: reservation.remoteID,
                kind: kind,
                occasion: packet.occasion,
                source: "blocked"
            )
            return GuestMessageDraft(
                emailSubject: templateFallback.emailSubject,
                emailBody: templateFallback.emailBody,
                shortMessageBody: templateFallback.shortMessageBody,
                safetyNote: reason,
                blockedReason: nil,
                source: .template
            )
        }
    }
}

enum GuestMessageDraftServiceFactory {
    @MainActor
    static func make(useLocalModel: Bool) -> GuestMessageDraftService {
        make(profile: useLocalModel ? .smallFastLocal : .template)
    }

    @MainActor
    static func make(profile: LocalWordingModelProfile) -> GuestMessageDraftService {
        GuestMessageDraftService(
            writer: profile == .template ? .template : .localModel,
            wordingProfile: profile
        )
    }
}
