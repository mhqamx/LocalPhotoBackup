import Foundation

public struct BackupCameraFailurePolicy: Sendable {
    public let maxConsecutiveFailures: Int
    public let maxAttemptsPerFile: Int

    public init(maxConsecutiveFailures: Int = 10, maxAttemptsPerFile: Int = 2) {
        self.maxConsecutiveFailures = max(1, maxConsecutiveFailures)
        self.maxAttemptsPerFile = max(1, maxAttemptsPerFile)
    }

    public func shouldStop(consecutiveFailures: Int) -> Bool {
        consecutiveFailures >= maxConsecutiveFailures
    }

    public func shouldRetry(attempts: Int) -> Bool {
        attempts < maxAttemptsPerFile
    }
}
