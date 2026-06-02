import Foundation

struct PhotoDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var productKind: String
    var transport: String
    var itemCount: Int
    var isReady: Bool
    var isRestricted: Bool

    var detail: String {
        var parts: [String] = []
        if !productKind.isEmpty {
            parts.append(productKind)
        }
        if !transport.isEmpty {
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
