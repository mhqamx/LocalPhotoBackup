import Foundation
import IPhoneBackupCore

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
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
    try "video".write(
        to: source.appendingPathComponent("2026_06_01_09_30_00_IMG_4001.MOV"),
        atomically: true,
        encoding: .utf8
    )

    let organizer = BackupPhotoFileOrganizer(
        datePolicy: BackupDateFolderPolicy(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
    )

    let summary = try organizer.organize(from: source, to: destination)

    expectEqual(summary.discovered, 3, "discovered media count")
    expectEqual(summary.copied, 2, "copied media count")
    expectEqual(summary.skippedExistingDate, 1, "skipped existing date count")
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
}

testKeepsOriginalFilenameWhenItHasNotBeenUsed()
testAddsNumericSuffixForDuplicateNames()
testSanitizesPathSeparatorsAndBlankNames()
testBuildsStableDateFolderName()
try testSkipsExistingDateFolder()
try testOrganizesBackupPhotosIntoMediaTypeAndDateFolders()

print("IPhoneBackupCoreChecks passed")
