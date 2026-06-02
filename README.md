# LocalPhotoBackup

一个本地运行的 macOS SwiftUI 小工具，用来把通过 USB 连接的 iPhone 相册导出到电脑文件夹、移动硬盘或 U 盘。

项目优先使用 `libimobiledevice` 提供的 `idevicebackup2` 完整备份协议读取照片和视频，数量通常更接近爱思助手等工具里看到的“照片”总数。没有安装 `idevicebackup2` 时，应用会退回 macOS `ImageCaptureCore` 相机接口，但该接口通常只能看到 iPhone 暴露的 DCIM 子集，可能漏掉 iCloud 占位资源或完整备份里才有的文件。

## 功能

- 通过 USB 扫描已连接并已信任的 iPhone。
- 支持选择任意本地目录作为导出位置，包括移动硬盘。
- 优先使用完整备份模式导出更完整的相册资源。
- 在完整备份不可用时回退到 macOS 相机接口。
- 按媒体类型和日期自动整理文件。
- 再次导出时跳过已经存在的类型/日期目录，方便增量备份。
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

如果目标位置里已经存在 `pic/2026-06-02`，本次导出会跳过该日期下的照片；如果 `video/2026-06-02` 不存在，同一天的视频仍会继续导出。这个策略用于减少重复复制，适合隔一段时间补充备份。

## 环境要求

- macOS 14 或更高版本
- Swift 6 工具链
- Xcode Command Line Tools
- 一台可通过 USB 连接并信任当前 Mac 的 iPhone

推荐安装 `libimobiledevice`，这样应用可以使用完整备份模式：

```bash
brew install libimobiledevice
```

安装后确认 `idevicebackup2` 可用：

```bash
idevicebackup2 --help
```

## 使用方法

1. 用 USB 将 iPhone 连接到 Mac。
2. 解锁 iPhone，并在手机上点按“信任此电脑”。
3. 运行应用。
4. 在工具栏里点击“选择导出位置”。
5. 点击“开始导出相册”。
6. 如果手机或系统弹出权限提示，按提示允许访问。

完整备份模式会在导出目录下临时创建 `.iphonebackup-mobilebackup` 工作目录，用于保存和解包 iPhone 备份。该目录可能占用较多空间，请确保导出磁盘有足够容量。

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

- 第一次完整备份可能比较慢，耗时取决于 iPhone 容量和 USB 速度。
- 如果 `idevicebackup2` 不可用，应用会提示并使用系统相机接口，导出数量可能明显偏少。
- 如果 iPhone 使用 iCloud 照片且本机只有占位资源，相机接口可能无法拿到所有原始文件。
- 文件名会尽量保留原名；遇到同名文件时会追加数字后缀。
- 这个工具面向本地手动备份，不会上传照片，也不包含云同步功能。
