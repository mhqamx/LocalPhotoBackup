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
