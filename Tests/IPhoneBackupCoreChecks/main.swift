import Foundation
import IPhoneBackupCore

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

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

func testKeepsOriginalFilenameWhenItHasNotBeenUsed() {
    let namer = BackupFileNamer()

    let result = namer.filename(forOriginalName: "IMG_0001.HEIC")

    expectEqual(result, "IMG_0001.HEIC", "keeps original filename")
}

func testAddsNumericSuffixForDuplicateNames() {
    let namer = BackupFileNamer()

    expectEqual(namer.filename(forOriginalName: "IMG_0001.HEIC"), "IMG_0001.HEIC", "first duplicate name")
    expectEqual(namer.filename(forOriginalName: "IMG_0001.HEIC"), "IMG_0001 2.HEIC", "second duplicate name")
    expectEqual(namer.filename(forOriginalName: "IMG_0001.HEIC"), "IMG_0001 3.HEIC", "third duplicate name")
}

func testSanitizesPathSeparatorsAndBlankNames() {
    let namer = BackupFileNamer()

    expectEqual(namer.filename(forOriginalName: "../DCIM/"), "iPhone Photo", "blank unsafe name fallback")
    expectEqual(namer.filename(forOriginalName: "Vacation/Clip.mov"), "Vacation Clip.mov", "path separator sanitization")
    expectEqual(namer.filename(forOriginalName: ""), "iPhone Photo 2", "second fallback name")
}

func testBuildsStableDateFolderName() {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = 2026
    components.month = 6
    components.day = 2
    components.hour = 8
    components.minute = 30

    let policy = BackupDateFolderPolicy(calendar: components.calendar!, timeZone: components.timeZone!)

    expectEqual(policy.folderName(for: components.date!), "2026-06-02", "stable date folder")
}

func testSkipsExistingDateFolder() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("IPhoneBackupCoreChecks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("2026-06-02", isDirectory: true),
        withIntermediateDirectories: true
    )

    let policy = BackupDateFolderPolicy(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)

    expectEqual(policy.shouldSkipDateFolder(named: "2026-06-02", under: root), true, "existing date folder should be skipped")
    expectEqual(policy.shouldSkipDateFolder(named: "2026-06-03", under: root), false, "missing date folder should export")
}

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

func testCameraExportPolicyOnlyQueuesPrimaryMediaFiles() {
    let policy = BackupCameraFilePolicy()

    expectEqual(
        policy.shouldQueueDownload(originalFilename: "IMG_0001.HEIC", fallbackName: nil),
        true,
        "heic photo should be queued"
    )
    expectEqual(
        policy.shouldQueueDownload(originalFilename: "IMG_0002.MOV", fallbackName: nil),
        true,
        "movie should be queued"
    )
    expectEqual(
        policy.shouldQueueDownload(originalFilename: "IMG_0003.DNG", fallbackName: nil),
        true,
        "raw image should be queued"
    )
    expectEqual(
        policy.shouldQueueDownload(originalFilename: "IMG_0001.AAE", fallbackName: nil),
        false,
        "apple adjustment sidecar should not be queued as a primary download"
    )
    expectEqual(
        policy.shouldQueueDownload(originalFilename: nil, fallbackName: "IMG_0001.XMP"),
        false,
        "metadata sidecar fallback name should not be queued"
    )
    expectEqual(
        policy.shouldQueueDownload(originalFilename: "IMG_0001.AA", fallbackName: nil),
        false,
        "non-photo sidecar should not be queued"
    )
}

func testCameraFailurePolicyStopsAfterConsecutiveFailures() {
    let policy = BackupCameraFailurePolicy(maxConsecutiveFailures: 3)

    expectEqual(policy.shouldStop(consecutiveFailures: 1), false, "first failure should not stop export")
    expectEqual(policy.shouldStop(consecutiveFailures: 2), false, "second failure should not stop export")
    expectEqual(policy.shouldStop(consecutiveFailures: 3), true, "third consecutive failure should stop export")
    expectEqual(policy.shouldStop(consecutiveFailures: 4), true, "failures past the threshold should stop export")
}

func testUSBExportsUseImageCaptureFormatEvenWhenFullBackupIsAvailable() {
    let route = BackupExportRoute.route(for: .usb, fullBackupAvailable: true)

    expectEqual(route, .imageCapture, "usb export keeps master image capture format")
}

func testWiFiExportsUseFullBackupOnlyWhenAvailable() {
    expectEqual(
        BackupExportRoute.route(for: .wifi, fullBackupAvailable: true),
        .fullBackup(useNetwork: true),
        "wifi export uses network full backup when available"
    )
    expectEqual(
        BackupExportRoute.route(for: .wifi, fullBackupAvailable: false),
        .unavailable,
        "wifi export requires full backup tool"
    )
}

func testOrganizesBackupPhotosIntoMediaTypeAndDateFolders() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("IPhoneBackupOrganizerChecks-\(UUID().uuidString)")
    let source = root.appendingPathComponent("source", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: destination.appendingPathComponent("pic/2026-06-01", isDirectory: true),
        withIntermediateDirectories: true
    )
    try "already exported".write(
        to: destination.appendingPathComponent("pic/2026-06-01/2026_06_01_07_41_54_IMG_3097.JPG"),
        atomically: true,
        encoding: .utf8
    )
    try "old".write(
        to: source.appendingPathComponent("2026_06_01_07_41_54_IMG_3097.JPG"),
        atomically: true,
        encoding: .utf8
    )
    try "new".write(
        to: source.appendingPathComponent("2026_06_02_08_30_00_IMG_4000.HEIC"),
        atomically: true,
        encoding: .utf8
    )
    try "same day new".write(
        to: source.appendingPathComponent("2026_06_01_10_15_00_IMG_5000.HEIC"),
        atomically: true,
        encoding: .utf8
    )
    try "video".write(
        to: source.appendingPathComponent("2026_06_01_09_30_00_IMG_4001.MOV"),
        atomically: true,
        encoding: .utf8
    )

    let organizer = BackupPhotoFileOrganizer(
        datePolicy: BackupDateFolderPolicy(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
    )

    let summary = try organizer.organize(from: source, to: destination)

    expectEqual(summary.discovered, 4, "discovered media count")
    expectEqual(summary.copied, 3, "copied media count")
    expectEqual(summary.skippedExistingFiles, 1, "skipped existing file count")
    expectEqual(
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("pic/2026-06-02/2026_06_02_08_30_00_IMG_4000.HEIC").path),
        true,
        "new date picture exists"
    )
    expectEqual(
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("video/2026-06-01/2026_06_01_09_30_00_IMG_4001.MOV").path),
        true,
        "same date video is not skipped by existing picture date"
    )
    expectEqual(
        FileManager.default.fileExists(atPath: destination.appendingPathComponent("pic/2026-06-01/2026_06_01_10_15_00_IMG_5000.HEIC").path),
        true,
        "new same-day picture is exported even when the date folder already exists"
    )
}

testMergePrefersUSBForSameName()
testMergeKeepsDistinctDevicesSorted()
testMergeHandlesEmptyInputs()
testParseNetworkUDIDsBasic()
testParseNetworkUDIDsStripsSuffixAndBlankLines()
testParseNetworkUDIDsEmpty()
testBackupArgsUSBHasNoNetworkFlags()
testBackupArgsWiFiAddsNetworkAndUDID()
testUnbackArgsNeverIncludeNetworkFlags()
testCameraExportPolicyOnlyQueuesPrimaryMediaFiles()
testCameraFailurePolicyStopsAfterConsecutiveFailures()
testUSBExportsUseImageCaptureFormatEvenWhenFullBackupIsAvailable()
testWiFiExportsUseFullBackupOnlyWhenAvailable()
testKeepsOriginalFilenameWhenItHasNotBeenUsed()
testAddsNumericSuffixForDuplicateNames()
testSanitizesPathSeparatorsAndBlankNames()
testBuildsStableDateFolderName()
try testSkipsExistingDateFolder()
try testOrganizesBackupPhotosIntoMediaTypeAndDateFolders()

print("IPhoneBackupCoreChecks passed")
