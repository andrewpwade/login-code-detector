import LoginCodeDetectorCore
import SwiftUI

/// Settings window UI for onboarding, connection settings, and advanced detection preferences.
struct PreferencesView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedPreferencesPane: PreferencesPane = .basic

    var body: some View {
        VStack(spacing: 0) {
            preferencesContent

            Divider()

            HStack(spacing: 10) {
                Text(viewModel.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Save") {
                    viewModel.save()
                }
                Button(viewModel.isRunning ? "Restart Watcher" : "Start Watcher") {
                    viewModel.start()
                }
                .disabled(viewModel.isVerifyingAccount)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.regularMaterial)
        }
        .onAppear {
            AppActivation.activate()
            viewModel.load()
        }
    }

    private var preferencesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Preferences", selection: $selectedPreferencesPane) {
                    Text("Basic").tag(PreferencesPane.basic)
                    Text("Advanced").tag(PreferencesPane.advanced)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320, alignment: .leading)

                switch selectedPreferencesPane {
                case .basic:
                    basicSettingsSection
                case .advanced:
                    advancedSettingsSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var basicSettingsSection: some View {
        settingsSection("Basic") {
            SettingsFormRow("IMAP username") {
                TextField("user@example.com", text: accountStringBinding(\.username))
                    .textContentType(.username)
            }
            SettingsFormRow("Password") {
                SecureField("Password", text: $viewModel.appPassword)
            }
            SettingsFormRow("IMAP server") {
                TextField("imap.example.com", text: accountStringBinding(\.host))
                    .textContentType(.URL)
            }
            SettingsFormRow("Port") {
                TextField("993", value: accountPortBinding, format: .number)
                    .frame(width: 96)
            }
            SettingsFormRow("Mailboxes") {
                TextField("INBOX, Receipts", text: accountMailboxesTextBinding)
            }
            SettingsFormRow("Auto-copy") {
                Toggle("Copy high-confidence codes automatically", isOn: $viewModel.config.autoCopyToClipboard)
            }
        }
    }

    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Detection") {
                SettingsFormRow("IMAP IDLE") {
                    Toggle("Use instant mailbox notifications when available", isOn: $viewModel.config.preferIMAPIdle)
                }
                SettingsFormRow("Polling fallback") {
                    HStack(spacing: 8) {
                        TextField("30", value: $viewModel.config.pollingIntervalSeconds, format: .number)
                            .frame(width: 96)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                SettingsFormRow("Startup lookback") {
                    HStack(spacing: 8) {
                        TextField("30", value: startupLookbackMinutesBinding, format: .number)
                            .frame(width: 96)
                        Text("minutes")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                SettingsFormRow("Allowlisted senders") {
                    TextField("security@example.com, no-reply@example.com", text: allowlistedSendersBinding)
                }
            }

            settingsSection("Maintenance") {
                SettingsFormRow("Mailbox state") {
                    HStack {
                        Button("Rescan Recent Mail") {
                            viewModel.rescanMailbox()
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var allowlistedSendersBinding: Binding<String> {
        Binding(
            get: { viewModel.config.allowlistedSenders.joined(separator: ", ") },
            set: { value in
                viewModel.config.allowlistedSenders = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var startupLookbackMinutesBinding: Binding<Double> {
        Binding(
            get: { max(30, viewModel.config.startupLookbackSeconds / 60) },
            set: { viewModel.config.startupLookbackSeconds = max(30, $0) * 60 }
        )
    }

    private var accountPortBinding: Binding<Int> {
        Binding(
            get: {
                firstAccount().port
            },
            set: { value in
                updateFirstAccount { account in
                    account.port = value
                }
            }
        )
    }

    private var accountMailboxesBinding: Binding<[String]> {
        Binding(
            get: {
                firstAccount().mailboxes
            },
            set: { value in
                updateFirstAccount { account in
                    account.mailboxes = value
                }
            }
        )
    }

    private var accountMailboxesTextBinding: Binding<String> {
        Binding(
            get: {
                firstAccount().mailboxes.joined(separator: ", ")
            },
            set: { value in
                updateFirstAccount { account in
                    account.mailboxes = value
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
        )
    }

    private func accountStringBinding(_ keyPath: WritableKeyPath<IMAPAccountConfig, String>) -> Binding<String> {
        Binding(
            get: {
                firstAccount()[keyPath: keyPath]
            },
            set: { value in
                updateFirstAccount { account in
                    account[keyPath: keyPath] = value
                }
            }
        )
    }

    private func firstAccount() -> IMAPAccountConfig {
        viewModel.config.accounts.first ?? IMAPAccountConfig()
    }

    private func updateFirstAccount(_ update: (inout IMAPAccountConfig) -> Void) {
        if viewModel.config.accounts.isEmpty {
            viewModel.config.accounts = [IMAPAccountConfig()]
        }
        update(&viewModel.config.accounts[0])
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }
}

struct GettingStartedWindowView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        GettingStartedView(
            step: viewModel.gettingStartedStep,
            username: accountStringBinding(\.username),
            password: $viewModel.appPassword,
            host: accountStringBinding(\.host),
            port: accountPortBinding,
            selectedMailboxes: accountMailboxesBinding,
            mailboxes: viewModel.availableMailboxes,
            status: viewModel.status,
            isProbing: viewModel.isProbingServer,
            isVerifying: viewModel.isVerifyingAccount,
            canVerify: viewModel.canDiscoverAccount,
            probeServer: viewModel.probeGettingStartedServer,
            verifyCredentials: viewModel.verifyGettingStartedCredentials,
            complete: viewModel.completeGettingStarted,
            finish: viewModel.finishGettingStarted
        )
        .onAppear {
            AppActivation.activate()
            viewModel.load()
        }
    }

    private var accountPortBinding: Binding<Int> {
        Binding(
            get: {
                firstAccount().port
            },
            set: { value in
                updateFirstAccount { account in
                    account.port = value
                }
            }
        )
    }

    private var accountMailboxesBinding: Binding<[String]> {
        Binding(
            get: {
                firstAccount().mailboxes
            },
            set: { value in
                updateFirstAccount { account in
                    account.mailboxes = value
                }
            }
        )
    }

    private func accountStringBinding(_ keyPath: WritableKeyPath<IMAPAccountConfig, String>) -> Binding<String> {
        Binding(
            get: {
                firstAccount()[keyPath: keyPath]
            },
            set: { value in
                updateFirstAccount { account in
                    account[keyPath: keyPath] = value
                }
            }
        )
    }

    private func firstAccount() -> IMAPAccountConfig {
        viewModel.config.accounts.first ?? IMAPAccountConfig()
    }

    private func updateFirstAccount(_ update: (inout IMAPAccountConfig) -> Void) {
        if viewModel.config.accounts.isEmpty {
            viewModel.config.accounts = [IMAPAccountConfig()]
        }
        update(&viewModel.config.accounts[0])
    }
}

/// Top-level panes exposed in the preferences UI.
private enum PreferencesPane: Hashable {
    case basic
    case advanced
}

/// Guided first-run setup UI for discovery, credential verification, and mailbox selection.
private struct GettingStartedView: View {
    let step: GettingStartedStep
    @State private var mailboxFilter = ""
    @Binding var username: String
    @Binding var password: String
    @Binding var host: String
    @Binding var port: Int
    @Binding var selectedMailboxes: [String]
    let mailboxes: [String]
    let status: String
    let isProbing: Bool
    let isVerifying: Bool
    let canVerify: Bool
    let probeServer: () -> Void
    let verifyCredentials: () -> Void
    let complete: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Getting Started")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            stepContent

            Spacer(minLength: 0)

            if step != .done {
                HStack(spacing: 10) {
                    if isProbing || isVerifying {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(status)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(buttonTitle) {
                        advance()
                    }
                    .disabled(isButtonDisabled)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack(spacing: 10) {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Done") {
                        advance()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 540, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .server:
            onboardingSection {
                SettingsFormRow("Email") {
                    TextField("user@example.com", text: $username)
                        .textContentType(.username)
                }
                SettingsFormRow("Password") {
                    SecureField("Password", text: $password)
                }
            }
        case .credentials:
            onboardingSection {
                SettingsFormRow("IMAP server") {
                    TextField("imap.example.com", text: $host)
                        .textContentType(.URL)
                }
                SettingsFormRow("Port") {
                    TextField("993", value: $port, format: .number)
                        .frame(width: 96)
                }
                SettingsFormRow("Email") {
                    Text(username)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                SettingsFormRow("Password") {
                    SecureField("Password", text: $password)
                }
            }
        case .folders:
            mailboxPicker
        case .done:
            doneContent
        }
    }

    private var doneContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup complete")
                .font(.title3.weight(.semibold))
            Text("Your IMAP account is configured and the watcher is running.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mailboxPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Search folders", text: $mailboxFilter)
                    .frame(maxWidth: 320)
                Text("\(selectedMailboxes.count) selected")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("INBOX") {
                    selectedMailboxes = mailboxes.filter { $0.uppercased() == "INBOX" }
                    if selectedMailboxes.isEmpty {
                        selectedMailboxes = ["INBOX"]
                    }
                }
                Button("All") {
                    selectedMailboxes = mailboxes
                }
                Button("None") {
                    selectedMailboxes = []
                }
            }

            List(filteredMailboxes, id: \.self) { mailbox in
                Toggle(isOn: mailboxSelectionBinding(mailbox)) {
                    Text(mailbox)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 260, maxHeight: 340)
        }
        .padding(16)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func onboardingSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var filteredMailboxes: [String] {
        let query = mailboxFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return mailboxes
        }
        return mailboxes.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func mailboxSelectionBinding(_ mailbox: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedMailboxes.contains { $0.caseInsensitiveCompare(mailbox) == .orderedSame }
            },
            set: { isSelected in
                if isSelected {
                    if !selectedMailboxes.contains(where: { $0.caseInsensitiveCompare(mailbox) == .orderedSame }) {
                        selectedMailboxes.append(mailbox)
                    }
                } else {
                    selectedMailboxes.removeAll { $0.caseInsensitiveCompare(mailbox) == .orderedSame }
                }
            }
        )
    }

    private var subtitle: String {
        switch step {
        case .server:
            return "Enter your email and app password"
        case .credentials:
            return "Enter the IMAP server manually"
        case .folders:
            return "Choose the mailboxes to watch"
        case .done:
            return "Your account is configured"
        }
    }

    private var buttonTitle: String {
        switch step {
        case .server:
            return "Find Server"
        case .credentials:
            return "Verify Login"
        case .folders:
            return "Start Watching"
        case .done:
            return ""
        }
    }

    private var isButtonDisabled: Bool {
        switch step {
        case .server:
            return username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || isProbing
        case .credentials:
            return !canVerify
        case .folders:
            return selectedMailboxes.isEmpty
        case .done:
            return false
        }
    }

    private func advance() {
        switch step {
        case .server:
            probeServer()
        case .credentials:
            verifyCredentials()
        case .folders:
            finish()
        case .done:
            complete()
        }
    }
}

/// Reusable row used by the settings forms.
private struct SettingsFormRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 120, alignment: .trailing)
                .foregroundStyle(.primary)

            content
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
