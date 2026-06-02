import Foundation
import IPhoneBackupCore

/// 通过 libimobiledevice 轮询发现同一 Wi-Fi 网络下、已配对并开启 Wi-Fi 同步的 iOS 设备。
final class NetworkDeviceDiscovery {
    var onDevicesChanged: (([PhotoDevice]) -> Void)?
    var onLog: ((BackupLogEntry.Level, String) -> Void)?

    private let pollInterval: TimeInterval = 5
    private let queue = DispatchQueue(label: "com.local.IPhoneBackup.network-discovery")
    private var timer: DispatchSourceTimer?
    private var isPolling = false
    private var warnedMissingTool = false

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        guard let ideviceIDURL = toolURL(named: "idevice_id") else {
            if !warnedMissingTool {
                warnedMissingTool = true
                emitLog(.info, "未检测到 idevice_id，无法发现 Wi-Fi 设备；可执行 brew install libimobiledevice 启用无线导出")
            }
            emitDevices([])
            return
        }

        guard let output = runCapturing(ideviceIDURL, arguments: ["-n"]) else {
            emitDevices([])
            return
        }

        let udids = NetworkDeviceParsing.parseUDIDs(from: output)
        let devices = udids.map { udid -> PhotoDevice in
            let name = deviceValue(for: udid, key: "DeviceName") ?? "Wi-Fi iPhone"
            let product = deviceValue(for: udid, key: "ProductType") ?? "iPhone"
            return PhotoDevice(
                id: "wifi-\(udid)",
                name: name,
                productKind: product,
                transport: "Wi-Fi",
                itemCount: 0,
                isReady: true,
                isRestricted: false,
                connection: .wifi,
                udid: udid
            )
        }
        emitDevices(devices)
    }

    private func deviceValue(for udid: String, key: String) -> String? {
        guard let ideviceInfoURL = toolURL(named: "ideviceinfo") else { return nil }
        guard let output = runCapturing(ideviceInfoURL, arguments: ["-n", "-u", udid, "-k", key]) else {
            return nil
        }
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func runCapturing(_ url: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func toolURL(named name: String) -> URL? {
        ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"]
            .map { URL(fileURLWithPath: $0 + name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func emitDevices(_ devices: [PhotoDevice]) {
        DispatchQueue.main.async { [onDevicesChanged] in
            onDevicesChanged?(devices)
        }
    }

    private func emitLog(_ level: BackupLogEntry.Level, _ message: String) {
        DispatchQueue.main.async { [onLog] in
            onLog?(level, message)
        }
    }
}
