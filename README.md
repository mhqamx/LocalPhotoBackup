# LocalPhotoBackup

一个本地运行的 macOS SwiftUI 小工具，用来把通过 USB 连接的 iPhone 或 iPad 相册导出到电脑文件夹、移动硬盘或 U 盘。

USB 导出使用 macOS `ImageCaptureCore` 相机接口，并保持稳定的本地目录格式。Wi-Fi 导出依赖 `libimobiledevice` 提供的 `idevicebackup2` 完整备份协议；没有安装该工具时，无线导出不可用。

## 功能

- 通过 USB 扫描已连接并已信任的 iPhone / iPad。
- 支持选择任意本地目录作为导出位置，包括移动硬盘。
- USB 使用 macOS 相机接口导出，保持本地文件夹格式。
- Wi-Fi 使用完整备份模式导出，需要安装 `idevicebackup2`。
- 按媒体类型和日期自动整理文件。
- 再次导出时跳过已经存在的目标文件，只导出新增内容，方便增量备份。
- 导出过程中显示进度、当前文件和日志。
- 支持取消正在进行的导出任务。

## 导出目录

导出的照片和视频会先按类型分到 `pic` 和 `video`，再按日期创建 `yyyy-MM-dd` 子文件夹。

```text
你的导出目录/
|-- pic/
|   |-- 2026-06-01/
|   `-- 2026-06-02/
`-- video/
    |-- 2026-06-01/
    `-- 2026-06-02/
```

如果目标位置里已经存在 `pic/2026-06-02/IMG_0001.HEIC`，再次导出时会跳过这个文件；同一天新增的其它照片或视频仍会继续导出。这个策略用于减少重复复制，适合隔一段时间补充备份。

## 环境要求

- macOS 14 或更高版本
- Swift 6 工具链
- Xcode Command Line Tools
- 一台可通过 USB 连接并信任当前 Mac 的 iPhone 或 iPad

推荐安装 `libimobiledevice`，这样应用可以使用完整备份模式：

```bash
brew install libimobiledevice
```

安装后确认 `idevicebackup2` 可用：

```bash
idevicebackup2 --help
```

## 使用方法

1. 用 USB 将 iPhone 或 iPad 连接到 Mac。
2. 解锁设备，并在设备上点按“信任此电脑”。
3. 运行应用。
4. 在工具栏里点击“选择导出位置”。
5. 点击“开始导出相册”。
6. 如果设备或系统弹出权限提示，按提示允许访问。

完整备份模式会在导出目录下临时创建 `.iphonebackup-mobilebackup` 工作目录，用于保存和解包移动设备备份。该目录可能占用较多空间，请确保导出磁盘有足够容量。

## 开发

克隆仓库后，在项目根目录运行：

```bash
swift build
```

运行核心逻辑检查：

```bash
swift run IPhoneBackupCoreChecks
```

构建并启动 macOS 应用：

```bash
./script/build_and_run.sh
```

脚本会把 SwiftPM 构建产物打包成 `dist/IPhoneBackup.app`，并通过 `open` 启动应用。

## 打包 DMG

生成可拖拽安装的 DMG：

```bash
./script/package_dmg.sh
```

脚本会执行 Release 构建，生成 `dist/IPhoneBackup.app`，再打包为 `dist/IPhoneBackup-0.1.0.dmg`。打开 DMG 后，把应用拖到 `Applications`，之后就可以从“应用程序”或 Launchpad 启动，不需要每次执行开发脚本。

当前脚本使用本机临时签名，适合自己电脑或本地使用。如果要发给其他人直接打开，通常还需要 Apple Developer ID 签名和 notarization。

## 隐私与提交注意事项

仓库源码不需要包含个人账号、邮箱、设备 UDID、本机绝对路径或访问令牌。构建产物和本地运行配置已经通过 `.gitignore` 排除，包括 `.build/`、`.swiftpm/`、`dist/` 和 `.codex/`。

提交前建议检查：

```bash
rg -n --hidden -S "<你的邮箱>|<你的本机用户名>|<访问令牌前缀>" -g '!/.git/**' -g '!/.build/**' -g '!/dist/**'
```

如果要公开仓库，建议在 GitHub 账号设置中启用隐藏邮箱，并将本仓库的 Git 作者邮箱设置为 noreply 地址，避免新的提交继续暴露个人邮箱。

## 项目结构

```text
Sources/
|-- IPhoneBackup/
|   |-- App/                 # SwiftUI app 入口
|   |-- Models/              # 设备、进度、日志模型
|   |-- Services/            # ImageCapture 和完整备份导出服务
|   |-- ViewModels/          # 主界面状态和导出流程
|   `-- Views/               # SwiftUI 界面
`-- IPhoneBackupCore/
    |-- BackupDateFolderPolicy.swift
    |-- BackupFileNamer.swift
    `-- BackupPhotoFileOrganizer.swift
```

核心整理逻辑放在 `IPhoneBackupCore`，方便通过命令行检查程序验证，不依赖 SwiftUI 界面。

## 注意事项

- 第一次完整备份可能比较慢，耗时取决于设备容量和 USB 速度。
- 如果 `idevicebackup2` 不可用，应用会提示并使用系统相机接口，导出数量可能明显偏少。
- 如果设备使用 iCloud 照片且本机只有占位资源，相机接口可能无法拿到所有原始文件。
- 文件名会尽量保留原名；遇到同名文件时会追加数字后缀。
- 这个工具面向本地手动备份，不会上传照片，也不包含云同步功能。
