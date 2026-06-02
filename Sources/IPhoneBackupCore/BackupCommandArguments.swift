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
