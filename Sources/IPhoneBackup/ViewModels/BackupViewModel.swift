import AppKit
import Foundation
import IPhoneBackupCore

@MainActor
final class BackupViewModel: ObservableObject {
    @Published var devices: [PhotoDevice] = []
    @Published var selectedDeviceID: PhotoDevice.ID?
    @Published var destinationURL: URL?
    @Published var progress = BackupProgressState()
    @Published var logs: [BackupLogEntry] = []

    private let importer = ImageCapturePhotoImporter()
    private let fullBackupExporter = FullBackupPhotoExporter()
    private let networkDiscovery = NetworkDeviceDiscovery()

    private var usbDevices: [PhotoDevice] = []
    private var wifiDevices: [PhotoDevice] = []

    private func rebuildDevices() {
        devices = BackupDeviceMerger.merge(usb: usbDevices, wifi: wifiDevices)
        if selectedDeviceID == nil {
            selectedDeviceID = devices.first?.id
        } else if let selected = selectedDeviceID, !devices.contains(where: { $0.id == selected }) {
            selectedDeviceID = devices.first?.id
        }
    }

    var selectedDevice: PhotoDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    var canExport: Bool {
        selectedDevice?.isReady == true && destinationURL != nil && !progress.isRunning
    }

    var usesFullBackupMode: Bool {
        fullBackupExporter.isAvailable
    }

    var selectedDeviceDetail: String {
        guard let selectedDevice else {
            return "连接设备后即可导出相册。"
        }
        return detailText(for: selectedDevice)
    }

    var selectedDeviceReferenceCount: String? {
        guard let selectedDevice,
              BackupExportRoute.route(for: selectedDevice.connection, fullBackupAvailable: fullBackupExporter.isAvailable) == .fullBackup(useNetwork: true),
              selectedDevice.itemCount > 0 else {
            return nil
        }
        return "相机接口参考：\(selectedDevice.itemCount) 项；完整备份数量会在导出时统计。"
    }

    init() {
        importer.onDevicesChanged = { [weak self] devices in
            Task { @MainActor in
                self?.usbDevices = devices
                self?.rebuildDevices()
            }
        }
        importer.onProgressChanged = { [weak self] progress in
            Task { @MainActor in
                self?.progress = progress
            }
        }
        importer.onLog = { [weak self] level, message in
            Task { @MainActor in
                self?.appendLog(level: level, message)
            }
        }
        importer.onExportFinished = { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    NSSound(named: "Glass")?.play()
                case .failure(let error):
                    self?.appendLog(level: .error, error.localizedDescription)
                }
            }
        }
        fullBackupExporter.onProgressChanged = { [weak self] progress in
            Task { @MainActor in
                self?.progress = progress
            }
        }
        fullBackupExporter.onLog = { [weak self] level, message in
            Task { @MainActor in
                self?.appendLog(level: level, message)
            }
        }
        fullBackupExporter.onExportFinished = { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    NSSound(named: "Glass")?.play()
                case .failure(let error):
                    self?.appendLog(level: .error, "完整备份未完成：\(error.localizedDescription)")
                    self?.appendLog(level: .warning, "没有自动退回相机接口；相机接口会漏数据，并可能对 iCloud 占位资源产生大量 -9934 失败")
                }
            }
        }
        networkDiscovery.onDevicesChanged = { [weak self] devices in
            Task { @MainActor in
                self?.wifiDevices = devices
                self?.rebuildDevices()
            }
        }
        networkDiscovery.onLog = { [weak self] level, message in
            Task { @MainActor in
                self?.appendLog(level: level, message)
            }
        }
        networkDiscovery.start()
        importer.startScanning()
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "选择相册导出位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            destinationURL = panel.url
            if let path = panel.url?.path {
                appendLog(level: .info, "导出位置：\(path)")
            }
        }
    }

    func startExport() {
        guard let selectedDeviceID, let destinationURL, let device = selectedDevice else { return }

        switch BackupExportRoute.route(for: device.connection, fullBackupAvailable: fullBackupExporter.isAvailable) {
        case .imageCapture:
            if !fullBackupExporter.isAvailable {
                appendLog(level: .warning, "未检测到完整备份工具，只能使用 macOS 相机接口，可能漏掉 iCloud/备份协议中的资源")
            }
            importer.exportDevice(id: selectedDeviceID, to: destinationURL)
        case .fullBackup(let useNetwork):
            appendLog(level: .info, "通过 Wi-Fi 导出 \(device.name) 的完整备份")
            fullBackupExporter.export(to: destinationURL, udid: device.udid, useNetwork: useNetwork)
        case .unavailable:
            if device.connection == .wifi {
                appendLog(level: .error, "无线导出需要 idevicebackup2；请执行 brew install libimobiledevice 后重试")
                return
            }
        }
    }

    func cancelExport() {
        fullBackupExporter.cancel()
        importer.cancelExport()
    }

    func refreshSelectedDevice() {
        guard let selectedDeviceID, let device = selectedDevice else { return }
        switch device.connection {
        case .wifi:
            networkDiscovery.refresh()
        case .usb:
            importer.refreshDevice(id: selectedDeviceID)
        }
    }

    func detailText(for device: PhotoDevice) -> String {
        if BackupExportRoute.route(for: device.connection, fullBackupAvailable: fullBackupExporter.isAvailable) == .fullBackup(useNetwork: true) {
            var parts: [String] = [device.connection.label]
            if !device.productKind.isEmpty {
                parts.append(device.productKind)
            }
            parts.append("完整备份模式可用")
            if device.isRestricted {
                parts.append("需要解锁并信任")
            }
            return parts.joined(separator: " · ")
        }

        return device.detail
    }

    private func appendLog(level: BackupLogEntry.Level, _ message: String) {
        logs.insert(BackupLogEntry(level: level, message: message), at: 0)
        if logs.count > 300 {
            logs.removeLast(logs.count - 300)
        }
    }
}
