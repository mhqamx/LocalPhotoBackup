import Foundation

struct BackupProgressState: Equatable {
    var isRunning = false
    var completed = 0
    var total = 0
    var currentFilename = ""

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var summary: String {
        guard isRunning else {
            return total > 0 ? "已准备 \(total) 个项目" : "尚未开始"
        }
        return "正在导出 \(completed)/\(total)"
    }
}

struct BackupLogEntry: Identifiable, Equatable {
    enum Level: String {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    let date = Date()
    var level: Level
    var message: String
}
