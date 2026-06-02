import SwiftUI
import IPhoneBackupCore

// MARK: - 视觉主题（黑 + 橙）

private enum Theme {
    /// 品牌强调橙
    static let accent = Color(red: 1.0, green: 0.45, blue: 0.10)
    static let accentSoft = Color(red: 1.0, green: 0.58, blue: 0.20)
    static let accentDeep = Color(red: 0.90, green: 0.32, blue: 0.04)

    /// 强调渐变（用于按钮、进度条、图标徽章）
    static let accentGradient = LinearGradient(
        colors: [accentSoft, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 详情区背景：近黑底 + 暖色微光
    static let canvas = LinearGradient(
        colors: [
            Color(red: 0.07, green: 0.07, blue: 0.08),
            Color(red: 0.10, green: 0.09, blue: 0.09)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 卡片填充
    static let card = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.08)

    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.55)
}

/// 统一的卡片容器外观
private struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
    }
}

private extension View {
    func panelCard() -> some View { modifier(PanelCard()) }
}

struct ContentView: View {
    @StateObject private var viewModel = BackupViewModel()

    var body: some View {
        NavigationSplitView {
            deviceSidebar
        } detail: {
            backupDetail
        }
        .navigationTitle("iPhone 相册备份")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.refreshSelectedDevice()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.selectedDeviceID == nil)

                Button {
                    viewModel.chooseDestination()
                } label: {
                    Label("选择导出位置", systemImage: "folder")
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    // MARK: - 侧边栏

    private var deviceSidebar: some View {
        List(selection: $viewModel.selectedDeviceID) {
            Section {
                if viewModel.devices.isEmpty {
                    emptyDeviceRow
                } else {
                    ForEach(viewModel.devices) { device in
                        deviceRow(device)
                            .tag(device.id)
                    }
                }
            } header: {
                Text("设备")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 260)
    }

    private var emptyDeviceRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.slash")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text("未发现 iPhone")
                    .font(.system(.headline, design: .rounded))
            }
            Text("请用 USB 连接 iPhone，解锁后在手机上选择信任此电脑。")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.vertical, 10)
    }

    private func deviceRow(_ device: PhotoDevice) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(device.isRestricted
                          ? AnyShapeStyle(Color.orange.opacity(0.18))
                          : AnyShapeStyle(Theme.accentGradient))
                    .frame(width: 38, height: 38)
                Image(systemName: device.isRestricted ? "lock.fill" : "iphone.gen3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(device.isRestricted ? Color.orange : .white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                Text(viewModel.detailText(for: device))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - 详情区

    private var backupDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                destinationRow
                progressSection
                actionRow
                logSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 620, minHeight: 480)
        .background(Theme.canvas.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 12, x: 0, y: 6)
                Image(systemName: viewModel.selectedDevice == nil ? "iphone.gen3.slash" : "photo.stack.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.selectedDevice?.name ?? "等待连接 iPhone")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(viewModel.selectedDeviceDetail)
                    .foregroundStyle(Theme.textSecondary)
                if let referenceCount = viewModel.selectedDeviceReferenceCount {
                    Text(referenceCount)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var destinationRow: some View {
        HStack(spacing: 14) {
            iconBadge("externaldrive.fill")
            VStack(alignment: .leading, spacing: 4) {
                Text("导出位置")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(viewModel.destinationURL?.path ?? "尚未选择，可以选择电脑文件夹或移动硬盘目录")
                    .foregroundStyle(Theme.textSecondary)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button {
                viewModel.chooseDestination()
            } label: {
                Label("选择", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .panelCard()
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.progress.summary)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if viewModel.progress.total > 0 {
                    Text("\(Int(viewModel.progress.fraction * 100))%")
                        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(Theme.accentGradient)
                        .frame(width: max(0, geo.size.width * viewModel.progress.fraction))
                        .animation(.easeInOut(duration: 0.3), value: viewModel.progress.fraction)
                }
            }
            .frame(height: 10)

            if !viewModel.progress.currentFilename.isEmpty {
                Text(viewModel.progress.currentFilename)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .panelCard()
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.startExport()
            } label: {
                Label("开始导出相册", systemImage: "square.and.arrow.down.fill")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!viewModel.canExport)

            Button {
                viewModel.cancelExport()
            } label: {
                Label("取消", systemImage: "xmark.circle.fill")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .disabled(!viewModel.progress.isRunning)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "text.append")
                    .foregroundStyle(Theme.accent)
                Text("日志")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }

            if viewModel.logs.isEmpty {
                Text("连接设备后会显示扫描和导出状态。")
                    .foregroundStyle(Theme.textSecondary)
                    .font(.callout)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.logs.enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: iconName(for: entry.level))
                                .foregroundStyle(color(for: entry.level))
                                .frame(width: 18)
                            Text(entry.message)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .font(.callout)
                        .padding(.vertical, 9)

                        if index < viewModel.logs.count - 1 {
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
        .panelCard()
    }

    // MARK: - 小组件与辅助

    private func iconBadge(_ systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 42, height: 42)
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    private func iconName(for level: BackupLogEntry.Level) -> String {
        switch level {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private func color(for level: BackupLogEntry.Level) -> Color {
        switch level {
        case .info:
            return Theme.textSecondary
        case .success:
            return .green
        case .warning:
            return Theme.accent
        case .error:
            return .red
        }
    }
}
