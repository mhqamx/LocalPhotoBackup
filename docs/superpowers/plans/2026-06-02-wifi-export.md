# Wi-Fi 无线导出相册 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保持现有 USB 导出不变的前提下，新增 Wi-Fi 无线导出能力，复用 `idevicebackup2` 网络模式。

**Architecture:** 增量扩展现有双子系统。ImageCaptureCore 继续负责 USB 发现；新增 `NetworkDeviceDiscovery` 用 libimobiledevice (`idevice_id -n` / `ideviceinfo`) 发现无线设备。ViewModel 将两个来源按设备名去重（USB 优先）合并成统一设备栏。导出时对 Wi-Fi 设备使用 `idevicebackup2 -n -u <UDID> backup --full`。可测试的纯逻辑（合并、解析、参数拼装）下沉到 `IPhoneBackupCore`。

**Tech Stack:** Swift 6 / SwiftUI / ImageCaptureCore / libimobiledevice (`idevice_id`, `ideviceinfo`, `idevicebackup2`)。测试用 `IPhoneBackupCoreChecks` 自定义断言可执行目标。

---

## File Structure

- `Sources/IPhoneBackupCore/PhotoDevice.swift` — **新建**。从 app 目标迁入 `PhotoDevice`，新增 `DeviceConnection` 枚举与 `udid` 字段（Core 公共类型，供测试引用）。
- `Sources/IPhoneBackupCore/BackupDeviceMerger.swift` — **新建**。`merge(usb:wifi:)` 纯函数。
- `Sources/IPhoneBackupCore/NetworkDeviceParsing.swift` — **新建**。解析 `idevice_id -n` 输出为 UDID 列表。
- `Sources/IPhoneBackupCore/BackupCommandArguments.swift` — **新建**。拼装 `idevicebackup2` 的 backup/unback 参数。
- `Sources/IPhoneBackup/Models/BackupModels.swift` — **修改**。移除 `PhotoDevice`（已迁入 Core），保留 `BackupProgressState`、`BackupLogEntry`。
- `Sources/IPhoneBackup/Services/NetworkDeviceDiscovery.swift` — **新建**。无线设备轮询发现服务。
- `Sources/IPhoneBackup/Services/FullBackupPhotoExporter.swift` — **修改**。`export` 增加 `udid` / `useNetwork` 参数。
- `Sources/IPhoneBackup/Services/ImageCapturePhotoImporter.swift` — **修改**。构造 `PhotoDevice` 时显式传 `connection: .usb`（依赖默认值，无需改动调用，仅确认编译）。
- `Sources/IPhoneBackup/ViewModels/BackupViewModel.swift` — **修改**。合并双来源、接入无线发现、改写 `startExport`。
- `Sources/IPhoneBackup/Views/ContentView.swift` — **修改**。设备行加连接方式徽章。
- `Tests/IPhoneBackupCoreChecks/main.swift` — **修改**。新增合并/解析/参数测试。

---

## Task 1: 将 PhotoDevice 迁入 Core 并扩展字段

**Files:**
- Create: `Sources/IPhoneBackupCore/PhotoDevice.swift`
- Modify: `Sources/IPhoneBackup/Models/BackupModels.swift`
- Modify: `Sources/IPhoneBackup/ViewModels/BackupViewModel.swift`（加 import）
- Modify: `Sources/IPhoneBackup/Views/ContentView.swift`（加 import）

这是一个重构任务（搬移类型），通过编译与既有测试通过来验证。

- [ ] **Step 1: 在 Core 新建 PhotoDevice.swift**

```swift
import Foundation

public enum DeviceConnection: String, Equatable, Sendable {
    case usb
    case wifi

    public var label: String {
        switch self {
        case .usb: return "USB"
        case .wifi: return "Wi-Fi"
        }
    }
}

public struct PhotoDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var productKind: String
    public var transport: String
    public var itemCount: Int
    public var isReady: Bool
    public var isRestricted: Bool
    public var connection: DeviceConnection
    public var udid: String?

    public init(
        id: String,
        name: String,
        productKind: String,
        transport: String,
        itemCount: Int,
        isReady: Bool,
        isRestricted: Bool,
        connection: DeviceConnection = .usb,
        udid: String? = nil
    ) {
        self.id = id
        self.name = name
        self.productKind = productKind
        self.transport = transport
        self.itemCount = itemCount
        self.isReady = isReady
        self.isRestricted = isRestricted
        self.connection = connection
        self.udid = udid
    }

    public var detail: String {
        var parts: [String] = []
        parts.append(connection.label)
        if !productKind.isEmpty {
            parts.append(productKind)
        }
        if !transport.isEmpty, transport != connection.label {
            parts.append(transport)
        }
        if itemCount > 0 {
            parts.append("\(itemCount) 个项目")
        }
        if isRestricted {
            parts.append("需要解锁并信任")
        }
        return parts.isEmpty ? "等待设备内容" : parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: 从 BackupModels.swift 删除 PhotoDevice**

删除 `Sources/IPhoneBackup/Models/BackupModels.swift` 第 3–28 行的整个 `struct PhotoDevice { ... }`（含其 `detail`）。保留文件中的 `BackupProgressState` 与 `BackupLogEntry` 不动。删除后文件顶部仍为 `import Foundation`。

- [ ] **Step 3: 为引用 PhotoDevice 的 app 文件补充 import**

在 `Sources/IPhoneBackup/ViewModels/BackupViewModel.swift` 顶部，现有：

```swift
import AppKit
import Foundation
```

改为：

```swift
import AppKit
import Foundation
import IPhoneBackupCore
```

在 `Sources/IPhoneBackup/Views/ContentView.swift` 顶部，现有：

```swift
import SwiftUI
```

改为：

```swift
import SwiftUI
import IPhoneBackupCore
```

（`ImageCapturePhotoImporter.swift` 已 `import IPhoneBackupCore`，其 `PhotoDevice(...)` 调用未传 `connection`/`udid`，依赖默认值 `.usb`/`nil`，无需修改。）

- [ ] **Step 4: 编译验证**

Run: `swift build`
Expected: `Build complete!`，无报错。

- [ ] **Step 5: 跑既有测试确认无回归**

Run: `swift run IPhoneBackupCoreChecks`
Expected: 输出 `IPhoneBackupCoreChecks passed`

- [ ] **Step 6: 提交**

```bash
git add Sources/IPhoneBackupCore/PhotoDevice.swift Sources/IPhoneBackup/Models/BackupModels.swift Sources/IPhoneBackup/ViewModels/BackupViewModel.swift Sources/IPhoneBackup/Views/ContentView.swift
git commit -m "refactor: move PhotoDevice into Core with connection/udid fields"
```

---

## Task 2: 设备合并纯函数 + 测试

**Files:**
- Create: `Sources/IPhoneBackupCore/BackupDeviceMerger.swift`
- Test: `Tests/IPhoneBackupCoreChecks/main.swift`

- [ ] **Step 1: 写失败测试**

在 `Tests/IPhoneBackupCoreChecks/main.swift` 中，`expectEqual` 函数定义之后、`testKeepsOriginalFilenameWhenItHasNotBeenUsed` 之前，新增：

```swift
func makeDevice(_ name: String, connection: DeviceConnection, udid: String? = nil) -> PhotoDevice {
    PhotoDevice(
        id: "\(connection.rawValue)-\(name)",
        name: name,
        productKind: "iPhone",
        transport: connection.label,
        itemCount: 0,
        isReady: true,
        isRestricted: false,
        connection: connection,
        udid: udid
    )
}

func testMergePrefersUSBForSameName() {
    let usb = [makeDevice("Max 的 iPhone", connection: .usb)]
    let wifi = [makeDevice("Max 的 iPhone", connection: .wifi, udid: "UDID1")]

    let merged = BackupDeviceMerger.merge(usb: usb, wifi: wifi)

    expectEqual(merged.count, 1, "same name deduped to one")
    expectEqual(merged[0].connection, .usb, "USB wins for same name")
}

func testMergeKeepsDistinctDevicesSorted() {
    let usb = [makeDevice("Zoe iPhone", connection: .usb)]
    let wifi = [makeDevice("Amy iPhone", connection: .wifi, udid: "UDID2")]

    let merged = BackupDeviceMerger.merge(usb: usb, wifi: wifi)

    expectEqual(merged.count, 2, "distinct names both kept")
    expectEqual(merged[0].name, "Amy iPhone", "sorted by name ascending")
    expectEqual(merged[1].name, "Zoe iPhone", "sorted by name ascending")
}

func testMergeHandlesEmptyInputs() {
    expectEqual(BackupDeviceMerger.merge(usb: [], wifi: []).count, 0, "empty merge is empty")

    let onlyWifi = BackupDeviceMerger.merge(usb: [], wifi: [makeDevice("A", connection: .wifi, udid: "U")])
    expectEqual(onlyWifi.count, 1, "wifi-only kept")
    expectEqual(onlyWifi[0].connection, .wifi, "wifi-only keeps wifi connection")
}
```

并在文件底部 `testKeepsOriginalFilenameWhenItHasNotBeenUsed()` 调用之前加入：

```swift
testMergePrefersUSBForSameName()
testMergeKeepsDistinctDevicesSorted()
testMergeHandlesEmptyInputs()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run IPhoneBackupCoreChecks`
Expected: 编译失败，报 `cannot find 'BackupDeviceMerger' in scope`

- [ ] **Step 3: 实现合并函数**

创建 `Sources/IPhoneBackupCore/BackupDeviceMerger.swift`：

```swift
import Foundation

public enum BackupDeviceMerger {
    /// 合并 USB 与 Wi-Fi 设备：按设备名去重，USB 优先，结果按名称升序排序。
    public static func merge(usb: [PhotoDevice], wifi: [PhotoDevice]) -> [PhotoDevice] {
        var byName: [String: PhotoDevice] = [:]
        for device in wifi {
            byName[device.name] = device
        }
        for device in usb {
            byName[device.name] = device
        }
        return byName.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run IPhoneBackupCoreChecks`
Expected: 输出 `IPhoneBackupCoreChecks passed`

- [ ] **Step 5: 提交**

```bash
git add Sources/IPhoneBackupCore/BackupDeviceMerger.swift Tests/IPhoneBackupCoreChecks/main.swift
git commit -m "feat: add device merge with USB priority dedup"
```

---

## Task 3: idevice_id 输出解析 + 测试

**Files:**
- Create: `Sources/IPhoneBackupCore/NetworkDeviceParsing.swift`
- Test: `Tests/IPhoneBackupCoreChecks/main.swift`

- [ ] **Step 1: 写失败测试**

在 `Tests/IPhoneBackupCoreChecks/main.swift` 中 `testMergeHandlesEmptyInputs` 之后新增：

```swift
func testParseNetworkUDIDsBasic() {
    let output = "00008030-0011AABB\n00008101-0022CCDD\n"

    let udids = NetworkDeviceParsing.parseUDIDs(from: output)

    expectEqual(udids, ["00008030-0011AABB", "00008101-0022CCDD"], "two udids parsed")
}

func testParseNetworkUDIDsStripsSuffixAndBlankLines() {
    let output = "  00008030-0011AABB (Network)  \n\n   \n00008101-0022CCDD\n"

    let udids = NetworkDeviceParsing.parseUDIDs(from: output)

    expectEqual(udids, ["00008030-0011AABB", "00008101-0022CCDD"], "suffix and blank lines handled")
}

func testParseNetworkUDIDsEmpty() {
    expectEqual(NetworkDeviceParsing.parseUDIDs(from: "").count, 0, "empty output -> no udids")
    expectEqual(NetworkDeviceParsing.parseUDIDs(from: "\n  \n").count, 0, "whitespace-only -> no udids")
}
```

并在文件底部测试调用区，`testMergeHandlesEmptyInputs()` 之后加入：

```swift
testParseNetworkUDIDsBasic()
testParseNetworkUDIDsStripsSuffixAndBlankLines()
testParseNetworkUDIDsEmpty()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run IPhoneBackupCoreChecks`
Expected: 编译失败，报 `cannot find 'NetworkDeviceParsing' in scope`

- [ ] **Step 3: 实现解析函数**

创建 `Sources/IPhoneBackupCore/NetworkDeviceParsing.swift`：

```swift
import Foundation

public enum NetworkDeviceParsing {
    /// 解析 `idevice_id -n` 输出为 UDID 列表。
    /// 每行可能形如 "UDID" 或 "UDID (Network)"，取每行首段；忽略空行；去重保序。
    public static func parseUDIDs(from output: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let token = line.split(separator: " ").first.map(String.init) ?? line
            let udid = token.trimmingCharacters(in: .whitespaces)
            guard !udid.isEmpty, !seen.contains(udid) else { continue }
            seen.insert(udid)
            result.append(udid)
        }
        return result
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run IPhoneBackupCoreChecks`
Expected: 输出 `IPhoneBackupCoreChecks passed`

- [ ] **Step 5: 提交**

```bash
git add Sources/IPhoneBackupCore/NetworkDeviceParsing.swift Tests/IPhoneBackupCoreChecks/main.swift
git commit -m "feat: add idevice_id network output parsing"
```

---

## Task 4: idevicebackup2 参数拼装 + 测试

**Files:**
- Create: `Sources/IPhoneBackupCore/BackupCommandArguments.swift`
- Test: `Tests/IPhoneBackupCoreChecks/main.swift`

- [ ] **Step 1: 写失败测试**

在 `Tests/IPhoneBackupCoreChecks/main.swift` 中 `testParseNetworkUDIDsEmpty` 之后新增：

```swift
func testBackupArgsUSBHasNoNetworkFlags() {
    let args = BackupCommandArguments.backup(workPath: "/tmp/work", udid: nil, useNetwork: false)

    expectEqual(args, ["backup", "--full", "/tmp/work"], "usb backup args have no -n/-u")
}

func testBackupArgsWiFiAddsNetworkAndUDID() {
    let args = BackupCommandArguments.backup(workPath: "/tmp/work", udid: "UDID9", useNetwork: true)

    expectEqual(args, ["-n", "-u", "UDID9", "backup", "--full", "/tmp/work"], "wifi backup args prepend -n -u")
}

func testUnbackArgsNeverIncludeNetworkFlags() {
    let args = BackupCommandArguments.unback(workPath: "/tmp/work")

    expectEqual(args, ["unback", "/tmp/work"], "unback is local-only, no -n/-u")
}
```

并在文件底部测试调用区，`testParseNetworkUDIDsEmpty()` 之后加入：

```swift
testBackupArgsUSBHasNoNetworkFlags()
testBackupArgsWiFiAddsNetworkAndUDID()
testUnbackArgsNeverIncludeNetworkFlags()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift run IPhoneBackupCoreChecks`
Expected: 编译失败，报 `cannot find 'BackupCommandArguments' in scope`

- [ ] **Step 3: 实现参数拼装**

创建 `Sources/IPhoneBackupCore/BackupCommandArguments.swift`：

```swift
import Foundation

public enum BackupCommandArguments {
    /// 完整备份阶段参数。网络模式下前置全局选项 `-n` 与 `-u <UDID>`。
    public static func backup(workPath: String, udid: String?, useNetwork: Bool) -> [String] {
        var args: [String] = []
        if useNetwork {
            args.append("-n")
        }
        if let udid, !udid.isEmpty {
            args.append(contentsOf: ["-u", udid])
        }
        args.append(contentsOf: ["backup", "--full", workPath])
        return args
    }

    /// 解包阶段是本地操作，永不附加网络/设备选项。
    public static func unback(workPath: String) -> [String] {
        ["unback", workPath]
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift run IPhoneBackupCoreChecks`
Expected: 输出 `IPhoneBackupCoreChecks passed`

- [ ] **Step 5: 提交**

```bash
git add Sources/IPhoneBackupCore/BackupCommandArguments.swift Tests/IPhoneBackupCoreChecks/main.swift
git commit -m "feat: add idevicebackup2 argument builder"
```

---

## Task 5: 在 FullBackupPhotoExporter 接入网络参数

**Files:**
- Modify: `Sources/IPhoneBackup/Services/FullBackupPhotoExporter.swift`

无硬件无法单测，靠编译验证。

- [ ] **Step 1: 改 export 签名并透传到 runExport**

`Sources/IPhoneBackup/Services/FullBackupPhotoExporter.swift` 顶部已有 `import IPhoneBackupCore`，确认存在；若无则添加。

将现有方法（第 28–42 行）：

```swift
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
```

替换为：

```swift
    func export(to destinationURL: URL, udid: String? = nil, useNetwork: Bool = false) {
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
            self?.runExport(toolURL: toolURL, destinationURL: destinationURL, udid: udid, useNetwork: useNetwork)
        }
    }
```

- [ ] **Step 2: 改 runExport 使用参数拼装器**

将 `runExport` 的签名（第 50 行）：

```swift
    private func runExport(toolURL: URL, destinationURL: URL) {
```

改为：

```swift
    private func runExport(toolURL: URL, destinationURL: URL, udid: String?, useNetwork: Bool) {
```

将其中的两处 `run(...)` 调用：

```swift
            try run(toolURL, arguments: ["backup", "--full", workURL.path], phase: "完整备份")
```

改为：

```swift
            try run(
                toolURL,
                arguments: BackupCommandArguments.backup(workPath: workURL.path, udid: udid, useNetwork: useNetwork),
                phase: "完整备份"
            )
```

以及：

```swift
            try run(toolURL, arguments: ["unback", workURL.path], phase: "解包备份")
```

改为：

```swift
            try run(
                toolURL,
                arguments: BackupCommandArguments.unback(workPath: workURL.path),
                phase: "解包备份"
            )
```

- [ ] **Step 3: 编译验证**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: 提交**

```bash
git add Sources/IPhoneBackup/Services/FullBackupPhotoExporter.swift
git commit -m "feat: support network mode in full backup exporter"
```

---

## Task 6: 新增 NetworkDeviceDiscovery 服务

**Files:**
- Create: `Sources/IPhoneBackup/Services/NetworkDeviceDiscovery.swift`

无硬件无法单测，靠编译验证；实际发现在 Task 8 实机验证。

- [ ] **Step 1: 创建服务文件**

创建 `Sources/IPhoneBackup/Services/NetworkDeviceDiscovery.swift`：

```swift
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
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 提交**

```bash
git add Sources/IPhoneBackup/Services/NetworkDeviceDiscovery.swift
git commit -m "feat: add Wi-Fi device discovery via libimobiledevice"
```

---

## Task 7: ViewModel 合并双来源并改写导出触发

**Files:**
- Modify: `Sources/IPhoneBackup/ViewModels/BackupViewModel.swift`

- [ ] **Step 1: 新增成员属性与服务实例**

在 `BackupViewModel` 类体中，现有：

```swift
    private let importer = ImageCapturePhotoImporter()
    private let fullBackupExporter = FullBackupPhotoExporter()
```

改为：

```swift
    private let importer = ImageCapturePhotoImporter()
    private let fullBackupExporter = FullBackupPhotoExporter()
    private let networkDiscovery = NetworkDeviceDiscovery()

    private var usbDevices: [PhotoDevice] = []
    private var wifiDevices: [PhotoDevice] = []
```

- [ ] **Step 2: 新增合并方法**

在 `BackupViewModel` 类体内（例如 `selectedDevice` 计算属性之前）新增：

```swift
    private func rebuildDevices() {
        devices = BackupDeviceMerger.merge(usb: usbDevices, wifi: wifiDevices)
        if selectedDeviceID == nil {
            selectedDeviceID = devices.first?.id
        } else if let selected = selectedDeviceID, !devices.contains(where: { $0.id == selected }) {
            selectedDeviceID = devices.first?.id
        }
    }
```

- [ ] **Step 3: 改 importer.onDevicesChanged 走合并**

在 `init()` 中，现有：

```swift
        importer.onDevicesChanged = { [weak self] devices in
            Task { @MainActor in
                self?.devices = devices
                if self?.selectedDeviceID == nil {
                    self?.selectedDeviceID = devices.first?.id
                } else if let selected = self?.selectedDeviceID, !devices.contains(where: { $0.id == selected }) {
                    self?.selectedDeviceID = devices.first?.id
                }
            }
        }
```

替换为：

```swift
        importer.onDevicesChanged = { [weak self] devices in
            Task { @MainActor in
                self?.usbDevices = devices
                self?.rebuildDevices()
            }
        }
```

- [ ] **Step 4: 接入无线发现回调并启动**

在 `init()` 中 `importer.startScanning()` 调用之前，新增：

```swift
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
```

- [ ] **Step 5: 改写 startExport 区分连接方式**

将现有 `startExport()`（约第 113–122 行）：

```swift
    func startExport() {
        guard let selectedDeviceID, let destinationURL else { return }
        if fullBackupExporter.isAvailable {
            appendLog(level: .info, "检测到完整备份工具，将优先导出备份协议中的全部照片")
            fullBackupExporter.export(to: destinationURL)
        } else {
            appendLog(level: .warning, "未检测到完整备份工具，只能使用 macOS 相机接口，可能漏掉 iCloud/备份协议中的资源")
            importer.exportDevice(id: selectedDeviceID, to: destinationURL)
        }
    }
```

替换为：

```swift
    func startExport() {
        guard let selectedDeviceID, let destinationURL, let device = selectedDevice else { return }

        switch device.connection {
        case .wifi:
            guard fullBackupExporter.isAvailable else {
                appendLog(level: .error, "无线导出需要 idevicebackup2；请执行 brew install libimobiledevice 后重试")
                return
            }
            appendLog(level: .info, "通过 Wi-Fi 导出 \(device.name) 的完整备份")
            fullBackupExporter.export(to: destinationURL, udid: device.udid, useNetwork: true)
        case .usb:
            if fullBackupExporter.isAvailable {
                appendLog(level: .info, "检测到完整备份工具，将优先导出备份协议中的全部照片")
                fullBackupExporter.export(to: destinationURL, udid: device.udid, useNetwork: false)
            } else {
                appendLog(level: .warning, "未检测到完整备份工具，只能使用 macOS 相机接口，可能漏掉 iCloud/备份协议中的资源")
                importer.exportDevice(id: selectedDeviceID, to: destinationURL)
            }
        }
    }
```

- [ ] **Step 6: 编译验证**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: 跑既有测试确认无回归**

Run: `swift run IPhoneBackupCoreChecks`
Expected: 输出 `IPhoneBackupCoreChecks passed`

- [ ] **Step 8: 提交**

```bash
git add Sources/IPhoneBackup/ViewModels/BackupViewModel.swift
git commit -m "feat: merge USB and Wi-Fi devices and route export by connection"
```

---

## Task 8: 设备行连接方式徽章（UI）

**Files:**
- Modify: `Sources/IPhoneBackup/Views/ContentView.swift`

- [ ] **Step 1: 在 deviceRow 增加连接徽章**

在 `Sources/IPhoneBackup/Views/ContentView.swift` 的 `deviceRow(_:)` 方法中，现有：

```swift
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                Text(viewModel.detailText(for: device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
```

替换为：

```swift
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                    connectionBadge(device.connection)
                }
                Text(viewModel.detailText(for: device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
```

- [ ] **Step 2: 新增 connectionBadge 辅助视图**

在 `ContentView` 的「小组件与辅助」分区，`iconBadge(_:)` 方法之后新增：

```swift
    private func connectionBadge(_ connection: DeviceConnection) -> some View {
        HStack(spacing: 3) {
            Image(systemName: connection == .wifi ? "wifi" : "cable.connector")
                .font(.system(size: 9, weight: .bold))
            Text(connection.label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Theme.accent.opacity(0.16))
        )
    }
```

- [ ] **Step 3: 编译验证**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: 实机运行验证**

Run: `bash script/build_and_run.sh run`
然后截图确认：设备栏中设备名后出现橙色 `Wi-Fi` / `USB` 胶囊徽章；无线设备（手机解锁、同一 Wi-Fi、已开 Wi-Fi 同步时）能出现在列表中。

Expected: app 正常启动；徽章按连接方式正确显示。

- [ ] **Step 5: 提交**

```bash
git add Sources/IPhoneBackup/Views/ContentView.swift
git commit -m "feat: show connection type badge in device list"
```

---

## Self-Review 记录

- **Spec 覆盖**：数据模型(Task 1)、网络发现服务(Task 6)、ViewModel 合并(Task 7)、导出网络参数(Task 4+5)、触发逻辑(Task 7)、UI 徽章(Task 8)、错误处理(Task 6 缺工具日志 / Task 7 wifi 无工具报错)、测试(Task 2/3/4) 均有对应任务。✓
- **占位符扫描**：无 TBD/TODO，所有代码步骤含完整代码。✓
- **类型一致性**：`PhotoDevice` 字段（`connection`/`udid`）、`DeviceConnection.label`、`BackupDeviceMerger.merge`、`NetworkDeviceParsing.parseUDIDs`、`BackupCommandArguments.backup/unback`、`export(to:udid:useNetwork:)` 在各任务间签名一致。✓
- **依赖顺序**：Task 1（类型）→ 2/3/4（依赖 Core 类型的纯函数）→ 5/6（依赖 4/3 的服务）→ 7（依赖 2/5/6）→ 8（依赖 1 的枚举）。✓
