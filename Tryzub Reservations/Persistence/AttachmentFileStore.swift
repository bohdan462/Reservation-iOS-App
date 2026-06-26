//
//  AttachmentFileStore.swift
//  Tryzub Reservations
//
//  Handles disk I/O for reservation attachment images.
//
//  Images are stored as JPEG files in:
//    <Application Support>/attachments/<filename>
//
//  Rules:
//  • `filename` matches `ReservationAttachmentRecord.filename` — it is the only index.
//  • Files are written atomically to avoid partial writes.
//  • Thumbnails are generated lazily at load time (no separate thumbnail file needed
//    for the number of attachments expected in a staff app).
//  • This store is pure static helpers — no state of its own.
//

import UIKit

enum AttachmentFileStore {

    /// Maximum JPEG quality for stored originals. 0.85 gives ≈ 200–600 KB for a
    /// typical phone photo, which is reasonable for staff reference images.
    static let jpegQuality: CGFloat = 0.85

    /// Maximum edge length for stored originals (staff reference, not full-res needed).
    static let maxEdge: CGFloat = 1920

    // MARK: - Directory

    static var attachmentsDirectory: URL {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("[ATTACHMENTS] Application Support URL unavailable")
        }
        return support.appendingPathComponent("attachments", isDirectory: true)
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: attachmentsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Write

    /// Compresses and saves image data to disk.
    /// Returns the filename that was written (same as the `filename` passed in).
    @discardableResult
    static func save(image: UIImage, filename: String) throws -> String {
        ensureDirectory()
        let resized = image.tryzubResized(maxEdge: maxEdge)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else {
            throw AttachmentFileStoreError.compressionFailed
        }
        let url = attachmentsDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    @discardableResult
    static func saveDownloadedAttachmentData(
        _ data: Data,
        reservationID: Int,
        attachmentID: Int,
        preferredExtension: String
    ) throws -> String {
        ensureDirectory()
        let filename = downloadedAttachmentFilename(
            reservationID: reservationID,
            attachmentID: attachmentID,
            preferredExtension: preferredExtension
        )
        let url = attachmentsDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    // MARK: - Read

    static func load(filename: String) -> UIImage? {
        let url = attachmentsDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func loadDownloadedAttachmentData(filename: String) throws -> Data? {
        let url = attachmentsDirectory.appendingPathComponent(safeStoredFilename(filename))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Loads and downsamples to a thumbnail for list display without loading the full image.
    @MainActor
    static func thumbnail(filename: String, size: CGSize = CGSize(width: 120, height: 120)) -> UIImage? {
        let url = attachmentsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * UIScreen.main.scale,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return load(filename: filename)
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Delete

    static func delete(filename: String) {
        let url = attachmentsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    static func removeDownloadedAttachment(filename: String) throws {
        let url = attachmentsDirectory.appendingPathComponent(safeStoredFilename(filename))
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Existence check

    static func exists(filename: String) -> Bool {
        FileManager.default.fileExists(
            atPath: attachmentsDirectory.appendingPathComponent(filename).path
        )
    }

    static func downloadedAttachmentFilename(
        reservationID: Int,
        attachmentID: Int,
        preferredExtension: String
    ) -> String {
        let ext = normalizedImageExtension(preferredExtension)
        return "remote-\(max(reservationID, 0))-\(max(attachmentID, 0)).\(ext)"
    }

    static func preferredExtension(forMimeType mimeType: String?) -> String {
        switch mimeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/jpeg", "image/jpg": return "jpg"
        default: return "jpg"
        }
    }

    private static func normalizedImageExtension(_ preferredExtension: String) -> String {
        let ext = preferredExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t\r"))
            .lowercased()
        switch ext {
        case "jpeg", "jpg": return "jpg"
        case "png": return "png"
        case "heic": return "heic"
        case "heif": return "heif"
        default: return "jpg"
        }
    }

    private static func safeStoredFilename(_ filename: String) -> String {
        filename.split(separator: "/").last.map(String.init) ?? filename
    }
}

enum AttachmentFileStoreError: LocalizedError {
    case compressionFailed
    case missingFile

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
        "Could not compress the photo."
        case .missingFile:
            "Could not find the saved photo."
        }
    }
}

// MARK: - UIImage resize helper

private extension UIImage {
    func tryzubResized(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return self }
        let scale = maxEdge / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
