//
//  ReservationAttachmentRecord.swift
//  Tryzub Reservations
//
//  Local-first SwiftData model for reservation photo attachments.
//
//  DESIGN:
//  • The backend DOES NOT store attachment data. All images live on device.
//  • The stable anchor is `reservationRemoteID` (the backend reservation ID).
//    If the backend re-fetches and recreates a ReservationRecord SwiftData row,
//    attachments are still found by querying `reservationRemoteID`.
//  • Each record's `id` encodes the reservation: "res-{reservationRemoteID}-{uuid}"
//    so ownership is readable at a glance and stays unique across all devices.
//  • The image file lives at:
//      <Application Support>/attachments/<filename>
//    where `filename` = "<uuid>.jpg"
//  • ReservationRecord does NOT carry an image-IDs array — attachment lookup is
//    always done via a @Query on ReservationAttachmentRecord.reservationRemoteID.
//    This means a backend refetch cannot accidentally clear local images.
//

import Foundation
import SwiftData

@Model
final class ReservationAttachmentRecord {

    /// "res-{reservationRemoteID}-{UUID}" — unique per attachment, encodes ownership.
    @Attribute(.unique) var id: String

    /// Backend reservation ID — the stable foreign key.
    /// Indexed so @Query(filter: reservationRemoteID == x) is fast.
    @Attribute var reservationRemoteID: Int

    /// `AttachmentLabel.rawValue` stored as plain String for schema stability.
    var labelRaw: String

    /// Just the filename within the attachments directory (not a full path, which
    /// can change if the app sandbox moves between OS updates).
    var filename: String

    /// Optional staff note about this attachment.
    var note: String?

    var createdAt: Date

    /// Text extracted from the image by Apple Vision OCR. Nil until OCR runs.
    var extractedText: String?

    /// When OCR last ran on this attachment. Used to avoid re-running unnecessarily.
    var ocrRanAt: Date?

    // MARK: - Init

    init(reservationRemoteID: Int, label: AttachmentLabel, note: String? = nil) {
        let uuid = UUID().uuidString
        self.id = "res-\(reservationRemoteID)-\(uuid)"
        self.reservationRemoteID = reservationRemoteID
        self.labelRaw = label.rawValue
        self.filename = "\(uuid).jpg"
        self.note = note
        self.createdAt = Date()
    }

    // MARK: - Derived

    var label: AttachmentLabel {
        AttachmentLabel(rawValue: labelRaw) ?? .other
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
