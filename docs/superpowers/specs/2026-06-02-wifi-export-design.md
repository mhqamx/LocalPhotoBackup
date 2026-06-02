# Wi-Fi 无线导出相册 — 设计文档

- 日期：2026-06-02
- 分支：`redesign-visual`
- 状态：已确认，待写实现计划

## 背景与目标

当前 app 只能通过 USB 数据线导出 iPhone 相册，存在两条导出路径：

1. **ImageCaptureCore**（`ICDeviceBrowser`，`ICDeviceLocationTypeMask.local`）— 系统相机接口
2. **idevicebackup2**（libimobiledevice）— 完整备份协议

目标：新增**无线（Wi-Fi）导出**能力，让用户在不插线的情况下也能备份相册。

### 关键约束（Apple 安全机制）

完全零配置的无线导出**不可能**。Apple 要求 iPhone 至少通过 USB **配对/信任电脑一次**，并在 Finder 勾选「通过 Wi-Fi 同步此 iPhone」。之后，只要手机与电脑处于**同一 Wi-Fi 网络**，即可全程无线导出，无需再插线。

因此本功能的定位是：**一次性 USB 配对 → 之后无线导出**。本 app 为自用，设备已配对授权，前提满足。

## 方案选择

采用**方案 1：扩展现有双子系统（增量式）**。

- 保留 ImageCaptureCore 扫描 USB 设备（现状不动，零回归）
- 新增轻量网络发现服务，基于 libimobiledevice 发现无线设备
- ViewModel 合并两个来源为统一设备栏

未采用方案 2（全面切到 libimobiledevice）：会重写 USB 路径、引入回归风险，且强依赖 libimobiledevice。

### 设备标识差异（需处理的核心细节）

两套发现机制给出的设备标识不同：

- USB 设备来自 ImageCaptureCore，`uuidString` 是 macOS 内部 GUID
- Wi-Fi 设备来自 `idevice_id -n`，给出 libimobiledevice 真实 **UDID**

两者对不上。同一台手机若同时插线 + 开 Wi-Fi 同步，会被两个子系统各发现一次。**按设备名去重**，并在导出时对 Wi-Fi 设备用 `idevicebackup2 -n -u <UDID>` 精确指定。

## 详细设计

### 1. 数据模型（`Models/BackupModels.swift`）

`PhotoDevice` 新增字段：

- `connection: Connection`，枚举 `.usb` / `.wifi`，驱动设备栏标签
- `udid: String?`，libimobiledevice 真实 UDID；Wi-Fi 设备必有，USB 设备为 `nil`

`detail` 计算属性带上连接方式文案。

### 2. 新服务（`Services/NetworkDeviceDiscovery.swift`）

- 后台定时（约 5s 一轮，**不重叠执行**）运行 `idevice_id -n` 获取网络 UDID 列表
- 对每个 UDID 运行 `ideviceinfo -n -u <UDID> -k DeviceName`（及 `ProductType`）获取设备名/型号
- 产出 `[PhotoDevice]`（`connection: .wifi`），经回调交给 ViewModel
- 启动前检测 `idevice_id` 是否存在；不存在则**静默跳过**并打一条 info 日志，提示 `brew install libimobiledevice`
- 回调风格与现有服务一致（`onDevicesChanged` / `onLog`）

工具查找路径与 `FullBackupPhotoExporter` 一致：`/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin`。

### 3. ViewModel 合并逻辑（`ViewModels/BackupViewModel.swift`）

- 分别持有 `usbDevices`（ImageCaptureCore）和 `wifiDevices`（新服务）
- 合并成已发布的 `devices`：**按设备名去重，USB 优先**（同名手机同时存在时只显示 USB 那条）
- 合并函数抽成**纯函数**（放入 `IPhoneBackupCore` 以便单测），输入两个设备数组，输出去重排序后的数组
- 选中逻辑不变（按 `id`）；设备列表变化时维持现有选中保护逻辑

### 4. 导出路径（`Services/FullBackupPhotoExporter.swift`）

- `export(to:)` 改为 `export(to:udid:useNetwork:)`
- `useNetwork == true` 时，**仅在 `backup` 阶段**附加 `-n -u <UDID>`；`unback` 与文件整理是本地操作，不加网络参数
- 命令形如：`idevicebackup2 -n -u <UDID> backup --full <dir>`
- 参数拼装抽成纯函数以便单测

### 5. 触发逻辑（`startExport`）

- 选中设备 `connection == .wifi`：
  - **强制要求** `idevicebackup2` 可用；不可用则报错，**不回退**相机接口（相机接口不支持无线）
  - 调用 `export(to:udid: device.udid, useNetwork: true)`
- 选中设备 `connection == .usb`：维持现状（优先完整备份，否则 ImageCaptureCore）

### 6. 界面（`Views/ContentView.swift`）

- 沿用现有黑橙暗色设计
- 设备行增加小标签徽章：📶 `Wi-Fi` / 🔌 `USB`（橙色徽章风格，与现有图标徽章一致）
- 详情区标题/副标题体现当前连接方式
- 布局结构不变

### 7. 错误处理

- `idevice_id` 未安装 → 不出现 Wi-Fi 设备 + 一条安装提示日志（仅一次，避免刷屏）
- 无线设备导出中掉线 → `idevicebackup2` 返回非零退出码，走现有错误日志路径
- 同名去重避免重复设备条目
- 网络发现命令超时/失败 → 当轮跳过，不影响 USB 设备显示

### 8. 测试

纯逻辑单测，加入 `Tests/IPhoneBackupCoreChecks`：

- `mergeDevices(usb:wifi:)`：去重与 USB 优先级（同名、仅 USB、仅 Wi-Fi、空集）
- `idevice_id -n` 输出解析：多 UDID / 空输出 / 含杂行/空行
- 网络模式命令参数拼装：确认 `-n -u <UDID>` 只出现在 `backup` 阶段，`unback` 不含

硬件相关部分（实际发现、实际无线备份）无法自动化，靠 app 实机验证。

## 非目标（YAGNI）

- 不实现零配置无线（Apple 不允许）
- 不在 app 内做 USB 配对/启用 Wi-Fi 同步的引导（用户已通过 Finder 完成）
- 不替换或重写现有 USB 导出路径
- 不做无线传输的断点续传/自定义传输协议（沿用 idevicebackup2 行为）
