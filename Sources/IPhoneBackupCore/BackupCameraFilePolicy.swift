import Foundation

public struct BackupCameraFilePolicy: Sendable {
    private let mediaExtensions: Set<String>

    public init(mediaExtensions: Set<String> = BackupCameraFilePolicy.primaryMediaExtensions) {
        self.mediaExtensions = mediaExtensions
    }

    public func shouldQueueDownload(originalFilename: String?, fallbackName: String?) -> Bool {
        guard let filename = firstUsableFilename(originalFilename, fallbackName) else {
            return false
        }

        let pathExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard !pathExtension.isEmpty else { return false }
        return mediaExtensions.contains(pathExtension)
    }

    private func firstUsableFilename(_ candidates: String?...) -> String? {
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    public static let primaryMediaExtensions: Set<String> = [
        "arw", "avi", "bmp", "dng", "gif", "heic", "heif", "jpeg", "jpg",
        "m4v", "mov", "mp4", "png", "raw", "tif", "tiff"
    ]
}
