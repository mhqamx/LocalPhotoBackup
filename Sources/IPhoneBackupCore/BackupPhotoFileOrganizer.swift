import Foundation

public struct BackupPhotoOrganizationSummary: Equatable {
    public var discovered: Int
    public var copied: Int
    public var skippedExistingFiles: Int
    public var failed: Int

    public init(discovered: Int, copied: Int, skippedExistingFiles: Int, failed: Int) {
        self.discovered = discovered
        self.copied = copied
        self.skippedExistingFiles = skippedExistingFiles
        self.failed = failed
    }
}

public struct BackupPhotoFileOrganizer {
    public typealias ProgressHandler = (_ copied: Int, _ total: Int, _ currentPath: String) -> Void

    private let datePolicy: BackupDateFolderPolicy
    private let mediaExtensions: Set<String>

    public init(
        datePolicy: BackupDateFolderPolicy = BackupDateFolderPolicy(),
        mediaExtensions: Set<String> = BackupPhotoFileOrganizer.defaultMediaExtensions
    ) {
        self.datePolicy = datePolicy
        self.mediaExtensions = mediaExtensions
    }

    public func organize(
        from sourceRoot: URL,
        to destinationRoot: URL,
        progress: ProgressHandler? = nil
    ) throws -> BackupPhotoOrganizationSummary {
        let files = try discoverMediaFiles(under: sourceRoot)
        let plannedItems = files.map { url in
            BackupSourcePhoto(
                sourceURL: url,
                mediaFolderName: mediaFolderName(forPathExtension: url.pathExtension),
                dateFolderName: dateFolderName(for: url),
                originalFilename: url.lastPathComponent
            )
        }
        var namersByDateFolder: [String: BackupFileNamer] = [:]
        let plannedDestinations = plannedItems.map { item in
            let relativeFolder = "\(item.mediaFolderName)/\(item.dateFolderName)"
            let namer = namersByDateFolder[relativeFolder] ?? BackupFileNamer()
            namersByDateFolder[relativeFolder] = namer
            return BackupPlannedPhotoDestination(
                item: item,
                relativeFolder: relativeFolder,
                filename: namer.filename(forOriginalName: item.originalFilename)
            )
        }
        let exportItems = plannedDestinations.filter {
            !FileManager.default.fileExists(atPath: destinationURL(for: $0, under: destinationRoot).path)
        }

        var summary = BackupPhotoOrganizationSummary(
            discovered: plannedItems.count,
            copied: 0,
            skippedExistingFiles: plannedDestinations.count - exportItems.count,
            failed: 0
        )

        for planned in exportItems {
            let item = planned.item
            let relativeFolder = planned.relativeFolder
            let dateFolderURL = destinationRoot
                .appendingPathComponent(item.mediaFolderName, isDirectory: true)
                .appendingPathComponent(item.dateFolderName, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dateFolderURL, withIntermediateDirectories: true)
                let filename = planned.filename
                let destinationURL = dateFolderURL.appendingPathComponent(filename)
                try FileManager.default.copyItem(at: item.sourceURL, to: destinationURL)
                summary.copied += 1
                progress?(summary.copied, exportItems.count, "\(relativeFolder)/\(filename)")
            } catch {
                summary.failed += 1
                progress?(summary.copied, exportItems.count, item.sourceURL.lastPathComponent)
            }
        }

        return summary
    }

    private func destinationURL(for planned: BackupPlannedPhotoDestination, under destinationRoot: URL) -> URL {
        destinationRoot
            .appendingPathComponent(planned.item.mediaFolderName, isDirectory: true)
            .appendingPathComponent(planned.item.dateFolderName, isDirectory: true)
            .appendingPathComponent(planned.filename)
    }

    public func discoverMediaFiles(under rootURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard mediaExtensions.contains(url.pathExtension.lowercased()) else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func dateFolderName(for url: URL) -> String {
        if let components = dateComponentsFromPrefixedFilename(url.lastPathComponent) {
            return datePolicy.folderName(
                year: components.year,
                month: components.month,
                day: components.day
            )
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let creationDate = attributes[.creationDate] as? Date ?? attributes[.modificationDate] as? Date {
            return datePolicy.folderName(for: creationDate)
        }

        return "未知日期"
    }

    private func mediaFolderName(forPathExtension pathExtension: String) -> String {
        if Self.videoExtensions.contains(pathExtension.lowercased()) {
            return "video"
        }
        return "pic"
    }

    private func dateComponentsFromPrefixedFilename(_ filename: String) -> BackupFilenameDateComponents? {
        let pattern = #"^(\d{4})_(\d{2})_(\d{2})(?:_(\d{2})_(\d{2})_(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range) else { return nil }

        func int(at index: Int, default defaultValue: Int = 0) -> Int {
            let matchRange = match.range(at: index)
            guard matchRange.location != NSNotFound, let range = Range(matchRange, in: filename) else {
                return defaultValue
            }
            return Int(filename[range]) ?? defaultValue
        }

        return BackupFilenameDateComponents(
            year: int(at: 1),
            month: int(at: 2),
            day: int(at: 3)
        )
    }

    public static let defaultMediaExtensions: Set<String> = [
        "aa", "aae", "arw", "avi", "bmp", "dng", "gif", "heic", "heif", "jpeg", "jpg",
        "m4v", "mov", "mp4", "png", "raw", "tif", "tiff", "xmp"
    ]

    public static let videoExtensions: Set<String> = [
        "avi", "m4v", "mov", "mp4"
    ]
}

private struct BackupSourcePhoto {
    let sourceURL: URL
    let mediaFolderName: String
    let dateFolderName: String
    let originalFilename: String
}

private struct BackupFilenameDateComponents {
    let year: Int
    let month: Int
    let day: Int
}

private struct BackupPlannedPhotoDestination {
    let item: BackupSourcePhoto
    let relativeFolder: String
    let filename: String
}
