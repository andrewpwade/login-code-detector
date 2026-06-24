import LoginCodeDetectorCore
import SwiftUI

/// Menu bar popover UI showing connection status, the latest detected code, and recent code history.
struct MenuContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusBanner

            if let lastNotification = viewModel.lastNotification {
                latestCodeCard(lastNotification)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Received in last 30 minutes")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.recentNotifications.count)")
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if viewModel.recentNotifications.isEmpty {
                            Text("No codes yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
                        } else {
                            ForEach(viewModel.recentNotifications, id: \.id) { notification in
                                recentCodeRow(notification)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            Toggle("Auto-copy codes", isOn: autoCopyBinding)

            HStack {
                Button("Preferences") {
                    openSettings()
                    Task { @MainActor in
                        AppActivation.activate()
                    }
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: AppUIConstants.menuWidth, height: AppUIConstants.menuHeight, alignment: .topLeading)
        .onAppear {
            viewModel.load()
        }
    }

    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: viewModel.isRunning ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(viewModel.isRunning ? .green : .secondary)
                .font(.title3)
                .frame(width: 22)

            Text(viewModel.status)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func latestCodeCard(_ notification: CodeNotification) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last code")
                    .font(.headline)
                Spacer()
                Text(notification.code)
                    .font(.system(.body, design: .monospaced))
                Button("Copy") {
                    viewModel.copyLastCode()
                }
            }

            HStack(spacing: 8) {
                Text(notification.sender)
                    .lineLimit(1)
                Text("•")
                    .foregroundStyle(.secondary)
                Text(relativeTimeString(for: notification.receivedAt))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func recentCodeRow(_ notification: CodeNotification) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(notification.code)
                    .font(.system(.body, design: .monospaced))
                Spacer(minLength: 0)
                Button("Copy") {
                    viewModel.copyCode(notification)
                }
                .buttonStyle(.borderless)
            }

            Text(notification.subject.isEmpty ? "(no subject)" : notification.subject)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(notification.sender)
                    .lineLimit(1)
                Text("•")
                    .foregroundStyle(.secondary)
                Text(relativeTimeString(for: notification.receivedAt))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func relativeTimeString(for date: Date) -> String {
        let interval = max(0, Int(Date().timeIntervalSince(date)))
        switch interval {
        case 0..<60:
            return "\(interval) second\(interval == 1 ? "" : "s") ago"
        case 60..<3600:
            let minutes = interval / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        case 3600..<86400:
            let hours = interval / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        default:
            let days = interval / 86400
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    private var autoCopyBinding: Binding<Bool> {
        Binding(
            get: { viewModel.config.autoCopyToClipboard },
            set: { viewModel.setAutoCopyToClipboard($0) }
        )
    }
}
