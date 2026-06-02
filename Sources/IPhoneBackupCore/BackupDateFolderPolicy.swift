import Foundation

public struct BackupDateFolderPolicy {
    private var calendar: Calendar

    public init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func folderName(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return folderName(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    public func folderName(year: Int, month: Int, day: Int) -> String {
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func shouldSkipDateFolder(named folderName: String, under rootURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent(folderName, isDirectory: true).path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }
}
