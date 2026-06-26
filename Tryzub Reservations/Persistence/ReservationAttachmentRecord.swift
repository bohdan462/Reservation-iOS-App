//
//  ReservationAttachmentRecord.swift
//  Tryzub Reservations
//
//  Local-first SwiftData model for reservation photo attachments, with optional
//  backend metadata for private staff-authenticated attachment sync.
//
//  DESIGN:
//  • Local-only images still live on device.
//  • Remote images are represented by metadata first; bytes are cached on demand.
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

enum ReservationAttachmentSyncState: String, Codable, CaseIterable {
    case localOnly
    case remoteOnly
    case synced
    case uploading
    case uploadFailed
    case downloaded
    case deletedRemote
}

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

    /// Backend attachment id for records synced from private attachment routes.
    var remoteID: Int?

    /// Backend reservation id echoed by the attachment endpoint.
    var remoteReservationID: Int?

    var remoteCreatedAtRaw: String?
    var remoteUpdatedAtRaw: String?
    var remoteDeletedAtRaw: String?
    var contentPath: String?
    var originalFilename: String?
    var mimeType: String?
    var fileSizeBytes: Int?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var uploadedByUserID: Int?
    var syncStateRaw: String = ReservationAttachmentSyncState.localOnly.rawValue
    var lastRemoteSyncAt: Date?
    var lastDownloadAt: Date?
    var localFullImageCacheFilename: String?
    var localThumbnailCacheFilename: String?
    var remoteCaption: String?

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

    convenience init(remote dto: ReservationAttachmentDTO, reservationRemoteID: Int, syncedAt: Date = Date()) {
        let label = AttachmentLabel(backendValue: dto.label)
        self.init(reservationRemoteID: reservationRemoteID, label: label, note: dto.caption)
        let attachmentID = dto.id
        self.id = "res-\(reservationRemoteID)-remote-\(attachmentID)"
        self.filename = AttachmentFileStore.downloadedAttachmentFilename(
            reservationID: reservationRemoteID,
            attachmentID: attachmentID,
            preferredExtension: AttachmentFileStore.preferredExtension(forMimeType: dto.mimeType)
        )
        applyRemoteMetadata(dto, syncedAt: syncedAt)
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

    var syncState: ReservationAttachmentSyncState {
        get { ReservationAttachmentSyncState(rawValue: syncStateRaw) ?? .localOnly }
        set { syncStateRaw = newValue.rawValue }
    }

    var hasRemoteIdentity: Bool {
        remoteID != nil
    }

    var isLocalOnly: Bool {
        remoteID == nil && syncState == .localOnly
    }

    var cachedImageFilename: String? {
        localFullImageCacheFilename ?? (AttachmentFileStore.exists(filename: filename) ? filename : nil)
    }

    // MARK: - Remote Metadata

    func applyRemoteMetadata(_ dto: ReservationAttachmentDTO, syncedAt: Date = Date()) {
        remoteID = dto.id
        remoteReservationID = dto.reservationID == 0 ? reservationRemoteID : dto.reservationID
        labelRaw = AttachmentLabel(backendValue: dto.label).rawValue
        remoteCaption = dto.caption
        if note == nil || syncState != .localOnly {
            note = dto.caption
        }
        originalFilename = dto.originalFilename
        mimeType = dto.mimeType
        fileSizeBytes = dto.fileSizeBytes
        pixelWidth = dto.width
        pixelHeight = dto.height
        remoteCreatedAtRaw = dto.createdAt
        remoteUpdatedAtRaw = dto.updatedAt
        remoteDeletedAtRaw = nil
        uploadedByUserID = dto.uploadedByUserID
        contentPath = dto.contentPath
        lastRemoteSyncAt = syncedAt
        if localFullImageCacheFilename != nil {
            syncState = .downloaded
        } else if AttachmentFileStore.exists(filename: filename) {
            syncState = .synced
        } else {
            syncState = .remoteOnly
        }
    }

    func markDownloaded(filename: String, thumbnailFilename: String? = nil, at date: Date = Date()) {
        localFullImageCacheFilename = filename
        localThumbnailCacheFilename = thumbnailFilename
        lastDownloadAt = date
        syncState = .downloaded
    }

    func markRemoteDeleted(rawDeletedAt: String? = nil, at date: Date = Date()) {
        remoteDeletedAtRaw = rawDeletedAt
        lastRemoteSyncAt = date
        syncState = .deletedRemote
    }

    @discardableResult
    static func upsertRemoteMetadata(
        _ attachments: [ReservationAttachmentDTO],
        reservationID: Int,
        in context: ModelContext,
        syncedAt: Date = Date()
    ) throws -> [ReservationAttachmentRecord] {
        let descriptor = FetchDescriptor<ReservationAttachmentRecord>(
            predicate: #Predicate { record in
                record.reservationRemoteID == reservationID
            }
        )
        let existingRecords = try context.fetch(descriptor)
        var existingByRemoteID: [Int: ReservationAttachmentRecord] = [:]
        for record in existingRecords {
            if let remoteID = record.remoteID {
                existingByRemoteID[remoteID] = record
            }
        }

        var merged: [ReservationAttachmentRecord] = []
        for dto in attachments {
            if let existing = existingByRemoteID[dto.id] {
                existing.applyRemoteMetadata(dto, syncedAt: syncedAt)
                merged.append(existing)
            } else {
                let record = ReservationAttachmentRecord(
                    remote: dto,
                    reservationRemoteID: dto.reservationID == 0 ? reservationID : dto.reservationID,
                    syncedAt: syncedAt
                )
                context.insert(record)
                merged.append(record)
            }
        }
        return merged
    }
}
