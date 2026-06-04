import Foundation
import ImageCaptureCore
import IPhoneBackupCore

final class ImageCapturePhotoImporter: NSObject {
    var onDevicesChanged: (([PhotoDevice]) -> Void)?
    var onProgressChanged: ((BackupProgressState) -> Void)?
    var onLog: ((BackupLogEntry.Level, String) -> Void)?
    var onExportFinished: ((Result<Int, Error>) -> Void)?

    private let browser = ICDeviceBrowser()
    private let dateFolderPolicy = BackupDateFolderPolicy()
    private var cameras: [String: ICCameraDevice] = [:]
    private var devices: [String: PhotoDevice] = [:]
    private var exportState: ExportState?

    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
        )!
    }

    func startScanning() {
        guard !browser.isBrowsing else { return }
        browser.start()
        onLog?(.info, "开始扫描通过 USB 连接的 iPhone 或相机设备")
    }

    func stopScanning() {
        guard browser.isBrowsing else { return }
        browser.stop()
    }

    func refreshDevice(id: String) {
        guard let camera = cameras[id] else { return }
        updateDevice(camera)
    }

    func exportDevice(id: String, to destinationURL: URL) {
        guard exportState == nil else {
            onLog?(.warning, "已有导出任务正在进行")
            return
        }
        guard let camera = cameras[id] else {
            onLog?(.error, "未找到所选设备")
            return
        }
        guard !camera.isAccessRestrictedAppleDevice else {
            onLog?(.error, "请先解锁 iPhone，并在手机上点按“信任此电脑”")
            return
        }

        let files = allExportableFiles(from: camera)
        guard !files.isEmpty else {
            onLog?(.warning, "设备中没有可导出的照片或视频")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true
            )
        } catch {
            onLog?(.error, "无法创建导出目录：\(error.localizedDescription)")
            return
        }

        let plannedItems = files.map { file in
            let originalFilename = file.originalFilename ?? file.name ?? "iPhone Photo"
            return ExportItem(
                file: file,
                mediaFolderName: mediaFolderName(for: originalFilename),
                dateFolderName: dateFolderName(for: file),
                originalFilename: originalFilename,
                destinationFilename: ""
            )
        }
        var namersByDateFolder: [String: BackupFileNamer] = [:]
        let plannedDownloads = plannedItems.map { item in
            let relativeFolder = "\(item.mediaFolderName)/\(item.dateFolderName)"
            let namer = namersByDateFolder[relativeFolder] ?? BackupFileNamer()
            namersByDateFolder[relativeFolder] = namer
            return ExportItem(
                file: item.file,
                mediaFolderName: item.mediaFolderName,
                dateFolderName: item.dateFolderName,
                originalFilename: item.originalFilename,
                destinationFilename: namer.filename(forOriginalName: item.originalFilename)
            )
        }
        let exportItems = plannedDownloads.filter {
            !FileManager.default.fileExists(atPath: destinationFileURL(for: $0, under: destinationURL).path)
        }
        let skippedCount = plannedDownloads.count - exportItems.count

        guard !exportItems.isEmpty else {
            onProgressChanged?(BackupProgressState(isRunning: false, completed: 0, total: plannedItems.count))
            onLog?(
                .success,
                "扫描到 \(plannedItems.count) 个项目，目标文件都已存在，本次无需导出"
            )
            return
        }

        let state = ExportState(camera: camera, items: exportItems, destinationURL: destinationURL)
        exportState = state
        onProgressChanged?(state.progress(currentFilename: ""))
        onLog?(
            .info,
            "扫描到 \(plannedItems.count) 个项目；跳过 \(skippedCount) 个已存在文件；准备导出新增 \(exportItems.count) 个项目到 \(destinationURL.path)"
        )
        downloadNextFile()
    }

    func cancelExport() {
        exportState?.camera.cancelDownload()
        exportState = nil
        onProgressChanged?(BackupProgressState())
        onLog?(.warning, "已取消当前导出任务")
    }

    private func downloadNextFile() {
        guard let state = exportState else { return }

        guard state.nextIndex < state.items.count else {
            let completed = state.completed
            exportState = nil
            onProgressChanged?(BackupProgressState(isRunning: false, completed: completed, total: completed))
            onLog?(.success, "导出完成，共 \(completed) 个项目")
            onExportFinished?(.success(completed))
            return
        }

        let item = state.items[state.nextIndex]
        let file = item.file
        let filename = state.filename(for: item)
        let relativeFolder = "\(item.mediaFolderName)/\(item.dateFolderName)"
        let targetDirectory = state.destinationURL
            .appendingPathComponent(item.mediaFolderName, isDirectory: true)
            .appendingPathComponent(item.dateFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: targetDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            state.failed += 1
            state.nextIndex += 1
            onLog?(.error, "无法创建日期目录 \(relativeFolder)：\(error.localizedDescription)")
            onProgressChanged?(state.progress(currentFilename: "\(relativeFolder)/\(filename)"))
            downloadNextFile()
            return
        }

        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: targetDirectory,
            .saveAsFilename: filename,
            .overwrite: false,
            .sidecarFiles: true
        ]

        onProgressChanged?(state.progress(currentFilename: "\(relativeFolder)/\(filename)"))
        _ = file.requestDownload(options: options) { [weak self] savedFilename, error in
            DispatchQueue.main.async {
                self?.handleDownloadedFile(file, requestedPath: "\(relativeFolder)/\(filename)", savedFilename: savedFilename, error: error)
            }
        }
    }

    private func handleDownloadedFile(
        _ file: ICCameraFile,
        requestedPath: String,
        savedFilename: String?,
        error: Error?
    ) {
        guard let state = exportState else { return }

        if let error {
            state.failed += 1
            onLog?(.error, "导出失败 \(requestedPath)：\(error.localizedDescription)")
        } else {
            state.completed += 1
            let finalName = savedFilename ?? requestedPath
            onLog?(.success, "已导出 \(finalName)")
        }

        state.nextIndex += 1
        onProgressChanged?(state.progress(currentFilename: requestedPath))
        downloadNextFile()
    }

    private func updateDevice(_ camera: ICCameraDevice) {
        let id = deviceID(for: camera)
        let device = PhotoDevice(
            id: id,
            name: camera.name ?? "未命名 iPhone",
            productKind: camera.productKind ?? "iPhone",
            transport: camera.transportType ?? "",
            itemCount: allExportableFiles(from: camera).count,
            isReady: camera.hasOpenSession && !camera.isAccessRestrictedAppleDevice,
            isRestricted: camera.isAccessRestrictedAppleDevice
        )
        devices[id] = device
        publishDevices()
    }

    private func removeDevice(_ device: ICDevice) {
        let id = deviceID(for: device)
        cameras[id] = nil
        devices[id] = nil
        publishDevices()
    }

    private func publishDevices() {
        let sorted = devices.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        onDevicesChanged?(sorted)
    }

    private func allExportableFiles(from camera: ICCameraDevice) -> [ICCameraFile] {
        var files = flattenFiles(camera.contents ?? [])
        if files.isEmpty, let directFiles = camera.mediaFiles as? [ICCameraFile] {
            files = directFiles
        }

        let filesWithSidecars = files.flatMap { file -> [ICCameraFile] in
            let sidecars = (file.sidecarFiles ?? []).compactMap { $0 as? ICCameraFile }
            return [file] + sidecars
        }

        return uniqueFiles(filesWithSidecars)
    }

    private func flattenFiles(_ items: [ICCameraItem]) -> [ICCameraFile] {
        items.flatMap { item -> [ICCameraFile] in
            if let file = item as? ICCameraFile {
                return [file]
            }
            if let folder = item as? ICCameraFolder {
                return flattenFiles(folder.contents ?? [])
            }
            return []
        }
    }

    private func uniqueFiles(_ files: [ICCameraFile]) -> [ICCameraFile] {
        var seen: Set<ObjectIdentifier> = []
        return files.filter { file in
            let id = ObjectIdentifier(file)
            guard !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    private func dateFolderName(for file: ICCameraFile) -> String {
        if let date = file.exifCreationDate ?? file.fileCreationDate ?? file.fileModificationDate {
            return dateFolderPolicy.folderName(for: date)
        }
        return "未知日期"
    }

    private func mediaFolderName(for filename: String) -> String {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if BackupPhotoFileOrganizer.videoExtensions.contains(fileExtension) {
            return "video"
        }
        return "pic"
    }

    private func destinationFileURL(for item: ExportItem, under destinationURL: URL) -> URL {
        destinationURL
            .appendingPathComponent(item.mediaFolderName, isDirectory: true)
            .appendingPathComponent(item.dateFolderName, isDirectory: true)
            .appendingPathComponent(item.destinationFilename)
    }

    private func deviceID(for device: ICDevice) -> String {
        device.uuidString ?? device.serialNumberString ?? device.name ?? UUID().uuidString
    }
}

extension ImageCapturePhotoImporter: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else { return }
        let id = deviceID(for: camera)
        cameras[id] = camera
        camera.delegate = self
        updateDevice(camera)
        onLog?(.info, "发现设备：\(camera.name ?? "未命名设备")")

        if !camera.hasOpenSession {
            camera.requestOpenSession()
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        onLog?(.warning, "设备已断开：\(device.name ?? "未命名设备")")
        removeDevice(device)
    }
}

extension ImageCapturePhotoImporter: ICCameraDeviceDelegate {
    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            onLog?(.error, "打开设备会话失败：\(error.localizedDescription)")
        } else if let camera = device as? ICCameraDevice {
            onLog?(.success, "已连接 \(camera.name ?? "设备")")
            updateDevice(camera)
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        if let error {
            onLog?(.warning, "设备会话已关闭：\(error.localizedDescription)")
        }
        if let camera = device as? ICCameraDevice {
            updateDevice(camera)
        }
    }

    func didRemove(_ device: ICDevice) {
        removeDevice(device)
    }

    func deviceDidBecomeReady(_ device: ICDevice) {
        if let camera = device as? ICCameraDevice {
            updateDevice(camera)
        }
    }

    func device(_ device: ICDevice, didReceiveStatusInformation status: [ICDeviceStatus: Any]) {
        if let message = status[.localizedStatusNotificationKey] as? String ?? status[.statusNotificationKey] as? String {
            onLog?(.info, message)
        }
    }

    func device(_ device: ICDevice, didEncounterError error: Error?) {
        if let error {
            onLog?(.error, error.localizedDescription)
        }
    }

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        updateDevice(camera)
    }

    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
        updateDevice(camera)
    }

    func cameraDevice(
        _ camera: ICCameraDevice,
        didReceiveThumbnail thumbnail: CGImage?,
        for item: ICCameraItem,
        error: Error?
    ) {}

    func cameraDevice(
        _ camera: ICCameraDevice,
        didReceiveMetadata metadata: [AnyHashable: Any]?,
        for item: ICCameraItem,
        error: Error?
    ) {}

    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        updateDevice(camera)
    }

    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        updateDevice(camera)
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        updateDevice(device)
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        if let camera = device as? ICCameraDevice {
            onLog?(.success, "\(camera.name ?? "设备") 已授权访问")
            updateDevice(camera)
        }
    }

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        if let camera = device as? ICCameraDevice {
            onLog?(.warning, "\(camera.name ?? "设备") 已锁定，请解锁并信任此电脑")
            updateDevice(camera)
        }
    }
}

private struct ExportItem {
    let file: ICCameraFile
    let mediaFolderName: String
    let dateFolderName: String
    let originalFilename: String
    let destinationFilename: String
}

private final class ExportState {
    let camera: ICCameraDevice
    let items: [ExportItem]
    let destinationURL: URL
    var nextIndex = 0
    var completed = 0
    var failed = 0

    init(camera: ICCameraDevice, items: [ExportItem], destinationURL: URL) {
        self.camera = camera
        self.items = items
        self.destinationURL = destinationURL
    }

    func filename(for item: ExportItem) -> String {
        item.destinationFilename
    }

    func progress(currentFilename: String) -> BackupProgressState {
        BackupProgressState(
            isRunning: nextIndex < items.count,
            completed: completed,
            total: items.count,
            currentFilename: currentFilename
        )
    }
}
