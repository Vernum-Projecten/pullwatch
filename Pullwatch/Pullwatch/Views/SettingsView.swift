import PullwatchCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("Accounts", systemImage: "person.2") {
                AccountsSettingsView(model: model)
            }
            Tab("Algemeen", systemImage: "gearshape") {
                GeneralSettingsView(model: model)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }
}

private struct AccountsSettingsView: View {
    let model: AppModel
    @State private var selection: UUID?
    /// Een nieuw account in het toevoeg-venster; staat pas in de config na Toevoegen.
    @State private var draft: Account?
    @State private var confirmsRemoval = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(model.config.accounts, selection: $selection) { account in
                    HStack(spacing: 8) {
                        AccountAvatar(account: account, size: 28)
                        VStack(alignment: .leading) {
                            Text(verbatim: account.organization)
                            Text(verbatim: account.kind.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(account.id)
                }
                .onDeleteCommand { if selection != nil { confirmsRemoval = true } }
                HStack {
                    Menu {
                        Button("Azure DevOps") { add(.azureDevOps) }
                        Button("GitHub") { add(.gitHub) }
                    } label: {
                        Label("Account toevoegen", systemImage: "plus").labelStyle(.iconOnly)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .help("Account toevoegen")
                    Button {
                        confirmsRemoval = true
                    } label: {
                        Label("Account verwijderen", systemImage: "minus").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    .help("Account verwijderen")
                }
                .padding(6)
            }
            .frame(minWidth: 200, maxWidth: 240)

            Group {
                if let id = selection, let account = model.config.accounts.first(where: { $0.id == id }) {
                    AccountEditor(model: model, original: account).id(id)
                } else {
                    Text("Selecteer of voeg een account toe")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 440)
        }
        .sheet(item: $draft) { account in
            AddAccountSheet(model: model, draft: account) { saved in
                draft = nil
                if saved { selection = account.id }
            }
        }
        .confirmationDialog(
            "Account verwijderen?",
            isPresented: $confirmsRemoval,
            presenting: model.config.accounts.first { $0.id == selection }
        ) { account in
            Button("Verwijderen", role: .destructive) {
                model.removeAccount(account.id)
                selection = nil
            }
        } message: { account in
            Text("\(account.displayName) en de geschiedenis ervan verdwijnen uit Pullwatch. Op \(account.kind.name) verandert niets.")
        }
    }

    private func add(_ kind: ProviderKind) {
        draft = Account(kind: kind, organization: "", authMethod: model.defaultAuthMethod(for: kind))
    }
}

/// Een account toevoegen: Annuleren gooit het concept weg, Toevoegen bewaart het als het af is.
private struct AddAccountSheet: View {
    let model: AppModel
    let draft: Account
    let onClose: (_ saved: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            AccountEditor(model: model, original: draft) { onClose(true) }
            Divider()
            HStack {
                Button("Annuleren", role: .cancel) {
                    model.discardDraft(draft.id)
                    onClose(false)
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(12)
        }
        .frame(minWidth: 560, minHeight: 560)
    }
}

private struct GeneralSettingsView: View {
    let model: AppModel
    @State private var logLevel = Log.minimum

    private let intervals = [60, 120, 300, 600, 900]

    private func openConsole() {
        let console = URL(filePath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.openApplication(at: console, configuration: NSWorkspace.OpenConfiguration())
    }

    private func nearestInterval(_ value: Int) -> Int {
        intervals.min { abs($0 - value) < abs($1 - value) } ?? value
    }

    var body: some View {
        Form {
            Picker("Poll-interval", selection: Binding(
                get: { nearestInterval(model.config.clampedInterval) },
                set: { model.setPollInterval($0) }
            )) {
                ForEach(intervals, id: \.self) { seconds in
                    Text("\(seconds / 60) min").tag(seconds)
                }
            }
            Picker("Geschiedenis bewaren", selection: Binding(
                get: { model.config.historyRetention },
                set: { model.setHistoryRetention($0) }
            )) {
                ForEach(HistoryRetention.allCases, id: \.self) { retention in
                    Text(retention.label).tag(retention)
                }
            }
            Toggle("Versies en CVE's dagelijks checken", isOn: Binding(
                get: { model.config.autoVersionCheck },
                set: { model.setAutoVersionCheck($0) }
            ))
            .help("Eens per dag automatisch; melding als er bij een gevolgde repo een nieuwe CVE bijkomt")
            Toggle("Melding bij nieuwe versies", isOn: Binding(
                get: { model.config.notifyPackageUpdates },
                set: { model.setNotifyPackageUpdates($0) }
            ))
            .disabled(!model.config.autoVersionCheck)
            .help("Na de dagelijkse check: één melding als er een nieuwe versie is van iets dat je repo's gebruiken")
            Toggle("Automatisch op updates controleren", isOn: Binding(
                get: { model.config.checkForUpdates },
                set: { model.setCheckForUpdates($0) }
            ))
            .help("Kijkt eens per dag op GitHub of er een nieuwere Pullwatch is")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Versie \(AppModel.currentVersion)").foregroundStyle(.secondary)
                    if let message = model.updateCheckMessage {
                        Text(verbatim: message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.isCheckingForUpdates {
                    ProgressView().controlSize(.small)
                }
                Button("Nu controleren") { Task { await model.checkForUpdates(manual: true) } }
                    .disabled(model.isCheckingForUpdates)
            }
            LaunchAtLoginToggle()
            LabeledContent {
                HStack {
                    Picker("Logniveau", selection: $logLevel) {
                        ForEach(LogLevel.allCases) { level in
                            Text(verbatim: level.name).tag(level)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Open Console") { openConsole() }
                }
            } label: {
                Text("Logniveau")
                Text("Vanaf dit niveau schrijft Pullwatch naar het systeemlog. In Console zoek je op nl.torrisi.pullwatch.")
            }
            .onChange(of: logLevel) { _, level in Log.minimum = level }
        }
        .formStyle(.grouped)
    }
}
