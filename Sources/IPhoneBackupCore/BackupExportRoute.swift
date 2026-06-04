import Foundation

public enum BackupExportRoute: Equatable, Sendable {
    case imageCapture
    case fullBackup(useNetwork: Bool)
    case unavailable

    public static func route(for connection: DeviceConnection, fullBackupAvailable: Bool) -> BackupExportRoute {
        switch connection {
        case .usb:
            return .imageCapture
        case .wifi:
            return fullBackupAvailable ? .fullBackup(useNetwork: true) : .unavailable
        }
    }
}
