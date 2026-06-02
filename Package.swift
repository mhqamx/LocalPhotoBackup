// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IPhoneBackup",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "IPhoneBackupCore",
            targets: ["IPhoneBackupCore"]
        ),
        .executable(
            name: "IPhoneBackup",
            targets: ["IPhoneBackup"]
        ),
        .executable(
            name: "IPhoneBackupCoreChecks",
            targets: ["IPhoneBackupCoreChecks"]
        )
    ],
    targets: [
        .target(
            name: "IPhoneBackupCore"
        ),
        .executableTarget(
            name: "IPhoneBackup",
            dependencies: ["IPhoneBackupCore"]
        ),
        .executableTarget(
            name: "IPhoneBackupCoreChecks",
            dependencies: ["IPhoneBackupCore"],
            path: "Tests/IPhoneBackupCoreChecks"
        )
    ],
    swiftLanguageModes: [.v5]
)
