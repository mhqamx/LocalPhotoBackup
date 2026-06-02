import Foundation

public final class BackupFileNamer {
    private var usedNames: [String: Int] = [:]
    private let fallbackBaseName: String

    public init(fallbackBaseName: String = "iPhone Photo") {
        self.fallbackBaseName = fallbackBaseName
    }

    public func filename(forOriginalName originalName: String) -> String {
        let sanitized = sanitizedFilename(from: originalName)
        let baseName = sanitized.isEmpty ? fallbackBaseName : sanitized
        let nextIndex = (usedNames[baseName] ?? 0) + 1
        usedNames[baseName] = nextIndex

        guard nextIndex > 1 else {
            return baseName
        }

        let url = URL(fileURLWithPath: baseName)
        let fileExtension = url.pathExtension
        let stem = fileExtension.isEmpty ? baseName : url.deletingPathExtension().lastPathComponent

        if fileExtension.isEmpty {
            return "\(stem) \(nextIndex)"
        }

        return "\(stem) \(nextIndex).\(fileExtension)"
    }

    private func sanitizedFilename(from originalName: String) -> String {
        let normalized = originalName
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.hasSuffix("/") else {
            return ""
        }

        let components = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." && $0 != ".." }

        let joined = components.joined(separator: " ")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbiddenCharacters = CharacterSet(charactersIn: ":")

        return trimmed
            .components(separatedBy: forbiddenCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }
}
