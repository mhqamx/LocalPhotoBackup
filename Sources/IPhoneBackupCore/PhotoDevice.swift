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
