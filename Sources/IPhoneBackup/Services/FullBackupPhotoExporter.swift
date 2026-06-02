import Foundation
import IPhoneBackupCore

final class FullBackupPhotoExporter {
    var onProgressChanged: ((BackupProgressState) -> Void)?
    var onLog: ((BackupLogEntry.Level, String) -> Void)?
    var onExportFinished: ((Result<Int, Error>) -> Void)?

    private var runningProcess: Process?
    private let organizer = BackupPhotoFileOrganizer()
    private var lastProcessOutput: [String] = []

    var isAvailable: Bool {
        toolURL != nil
    }

    private var toolURL: URL? {
        let candidates = [
            "/opt/homebrew/bin/idevicebackup2",
            "/usr/local/bin/idevicebackup2",
            "/usr/bin/idevicebackup2"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func export(to destinationURL: URL) {
        guard runningProcess == nil else {
            onLog?(.warning, "完整备份任务正在进行")
            return
        }
        guard let toolURL else {
            onLog?(.warning, "未安装 idevicebackup2，改用系统相机接口导出")
            onExportFinished?(.failure(FullBackupError.toolMissing))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runExport(toolURL: toolURL, destinationURL: destinationURL)
        }
    }

    func cancel() {
        runningProcess?.terminate()
        runningProcess = nil
        onLog?(.warning, "已取消完整备份任务")
    }

    private func runExport(toolURL: URL, destinationURL: URL) {
        let workURL = destinationURL.appendingPathComponent(".iphonebackup-mobilebackup", isDirectory: true)

        do {
            try removeIncompleteBackupIfNeeded(at: workURL)
            try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
            emitProgress(BackupProgressState(isRunning: true, completed: 0, total: 3, currentFilename: "准备完整备份"))

            emitLog(.info, "使用完整备份协议读取照片，工作目录：\(workURL.path)")
            emitLog(.info, "如果 iPhone 弹出提示，请解锁并信任此电脑")
            try run(toolURL, arguments: ["backup", "--full", workURL.path], phase: "完整备份")

            emitProgress(BackupProgressState(isRunning: true, completed: 1, total: 3, currentFilename: "解包备份文件"))
            try run(toolURL, arguments: ["unback", workURL.path], phase: "解包备份")

            emitProgress(BackupProgressState(isRunning: true, completed: 2, total: 3, currentFilename: "整理照片和视频"))
            let sourceRoots = try photoSourceRoots(in: workURL)
            guard !sourceRoots.isEmpty else {
                throw FullBackupError.noUnpackedPhotos
            }

            var totalSummary = BackupPhotoOrganizationSummary(discovered: 0, copied: 0, skippedExistingDate: 0, failed: 0)
            for sourceRoot in sourceRoots {
                let summary = try organizer.organize(from: sourceRoot, to: destinationURL) { [weak self] copied, total, currentPath in
                    self?.emitProgress(BackupProgressState(isRunning: true, completed: copied, total: total, currentFilename: currentPath))
                }
                totalSummary.discovered += summary.discovered
                totalSummary.copied += summary.copied
                totalSummary.skippedExistingDate += summary.skippedExistingDate
                totalSummary.failed += summary.failed
            }

            emitProgress(BackupProgressState(isRunning: false, completed: totalSummary.copied, total: totalSummary.discovered))
            emitLog(
                .success,
                "完整备份整理完成：发现 \(totalSummary.discovered) 个媒体文件，复制 \(totalSummary.copied) 个，跳过已存在日期 \(totalSummary.skippedExistingDate) 个，失败 \(totalSummary.failed) 个"
            )
            emitFinished(.success(totalSummary.copied))
        } catch {
            emitProgress(BackupProgressState())
            emitLog(.error, "完整备份失败：\(error.localizedDescription)")
            emitFinished(.failure(error))
        }
    }

    private func run(_ executableURL: URL, arguments: [String], phase: String) throws {
        lastProcessOutput = []
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        runningProcess = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            self?.emitProcessOutput(output, phase: phase)
        }

        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        runningProcess = nil

        guard process.terminationStatus == 0 else {
            throw FullBackupError.processFailed(
                phase: phase,
                status: process.terminationStatus,
                output: lastProcessOutput.suffix(10).joined(separator: "\n")
            )
        }
    }

    private func emitProcessOutput(_ output: String, phase: String) {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for line in lines.suffix(5) {
            lastProcessOutput.append(line)
            if lastProcessOutput.count > 80 {
                lastProcessOutput.removeFirst(lastProcessOutput.count - 80)
            }
            emitLog(.info, "\(phase)：\(line)")
        }
    }

    private func removeIncompleteBackupIfNeeded(at workURL: URL) throws {
        guard directoryExists(workURL) else { return }
        let statusFiles = try files(named: "Status.plist", under: workURL)
        guard statusFiles.isEmpty else { return }
        emitLog(.warning, "发现上次未完成的完整备份工作区，先清理后重新开始")
        try FileManager.default.removeItem(at: workURL)
    }

    private func files(named name: String, under rootURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true, url.lastPathComponent == name {
                matches.append(url)
            }
        }
        return matches
    }

    private func photoSourceRoots(in workURL: URL) throws -> [URL] {
        let unpackedRoots = try directories(named: "_unback_", under: workURL)
        let roots = unpackedRoots.flatMap { root -> [URL] in
            let candidates = [
                root.appendingPathComponent("CameraRollDomain", isDirectory: true),
                root.appendingPathComponent("CameraRollDomain/Media", isDirectory: true),
                root.appendingPathComponent("HomeDomain/Media/DCIM", isDirectory: true),
                root.appendingPathComponent("HomeDomain/Media/PhotoData", isDirectory: true),
                root.appendingPathComponent("MediaDomain/Media/DCIM", isDirectory: true),
                root.appendingPathComponent("MediaDomain/Media/PhotoData", isDirectory: true),
                root.appendingPathComponent("Media/DCIM", isDirectory: true),
                root.appendingPathComponent("Photos", isDirectory: true)
            ]
            let recursiveCandidates = ((try? directories(named: "CameraRollDomain", under: root)) ?? [])
                + ((try? directories(named: "DCIM", under: root)) ?? []).filter { $0.path.contains("/Media/") }
                + ((try? directories(named: "PhotoData", under: root)) ?? []).filter { $0.path.contains("/Media/") }
            let existing = uniqueDirectories(candidates.filter { directoryExists($0) } + recursiveCandidates)
            return existing.isEmpty ? [root] : existing
        }
        return roots
    }

    private func directories(named name: String, under rootURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return []
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true, url.lastPathComponent == name {
                matches.append(url)
            }
        }
        return matches
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func uniqueDirectories(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private func emitProgress(_ progress: BackupProgressState) {
        DispatchQueue.main.async { [onProgressChanged] in
            onProgressChanged?(progress)
        }
    }

    private func emitLog(_ level: BackupLogEntry.Level, _ message: String) {
        DispatchQueue.main.async { [onLog] in
            onLog?(level, message)
        }
    }

    private func emitFinished(_ result: Result<Int, Error>) {
        DispatchQueue.main.async { [onExportFinished] in
            onExportFinished?(result)
        }
    }
}

enum FullBackupError: LocalizedError {
    case toolMissing
    case noUnpackedPhotos
    case processFailed(phase: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .toolMissing:
            return "未找到 idevicebackup2"
        case .noUnpackedPhotos:
            return "完整备份已完成，但没有找到解包后的照片目录"
        case .processFailed(let phase, let status, let output):
            if output.isEmpty {
                return "\(phase) 命令退出码 \(status)"
            }
            return "\(phase) 命令退出码 \(status)：\(output)"
        }
    }
}
