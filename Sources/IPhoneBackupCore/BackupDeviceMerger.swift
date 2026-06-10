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
