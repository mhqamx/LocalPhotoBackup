import SwiftUI

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
    }

    private var deviceSidebar: some View {
        List(selection: $viewModel.selectedDeviceID) {
            Section("设备") {
                if viewModel.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("未发现 iPhone", systemImage: "iphone.slash")
                            .font(.headline)
                        Text("请用 USB 连接 iPhone，解锁后在手机上选择信任此电脑。")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(viewModel.devices) { device in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(device.name, systemImage: device.isRestricted ? "lock" : "iphone")
                                .font(.headline)
                            Text(viewModel.detailText(for: device))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(device.id)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 260)
    }

    private var backupDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            destinationRow
            progressSection
            actionRow
            Divider()
            logSection
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 480, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.selectedDevice?.name ?? "等待连接 iPhone")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(viewModel.selectedDeviceDetail)
                .foregroundStyle(.secondary)
            if let referenceCount = viewModel.selectedDeviceReferenceCount {
                Text(referenceCount)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var destinationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("导出位置")
                    .font(.headline)
                Text(viewModel.destinationURL?.path ?? "尚未选择，可以选择电脑文件夹或移动硬盘目录")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                viewModel.chooseDestination()
            } label: {
                Label("选择", systemImage: "folder")
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.progress.summary)
                    .font(.headline)
                Spacer()
                if viewModel.progress.total > 0 {
                    Text("\(Int(viewModel.progress.fraction * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: viewModel.progress.fraction)
            if !viewModel.progress.currentFilename.isEmpty {
                Text(viewModel.progress.currentFilename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Button {
                viewModel.startExport()
            } label: {
                Label("开始导出相册", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canExport)

            Button {
                viewModel.cancelExport()
            } label: {
                Label("取消", systemImage: "xmark.circle")
            }
            .disabled(!viewModel.progress.isRunning)

            Spacer()
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日志")
                .font(.headline)
            if viewModel.logs.isEmpty {
                Text("连接设备后会显示扫描和导出状态。")
                    .foregroundStyle(.secondary)
            } else {
                List(viewModel.logs) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: iconName(for: entry.level))
                            .foregroundStyle(color(for: entry.level))
                            .frame(width: 18)
                        Text(entry.message)
                            .lineLimit(2)
                        Spacer()
                    }
                    .font(.callout)
                }
                .listStyle(.plain)
            }
        }
    }

    private func iconName(for level: BackupLogEntry.Level) -> String {
        switch level {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    private func color(for level: BackupLogEntry.Level) -> Color {
        switch level {
        case .info:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
