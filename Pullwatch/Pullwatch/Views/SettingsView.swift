import PullwatchCore
import SwiftUI

/// Het Instellingen-venster (de Settings-scene): Accounts, Meldingen en Algemeen. Alles wordt meteen
/// bewaard, zoals in Mac-instellingen gebruikelijk; alleen een nieuw account heeft Toevoegen.
struct SettingsView: View {
    let model: AppModel

    enum Pane: String { case accounts, notifications, general }

    @State private var pane: Pane = {
        #if DEBUG
        // Voor schermafbeeldingen: met welk tabblad het venster opent.
        UserDefaults.standard.string(forKey: "PullwatchSettingsPane").flatMap(Pane.init) ?? .accounts
        #else
        .accounts
        #endif
    }()

    var body: some View {
        TabView(selection: $pane) {
            Tab("Accounts", systemImage: "person.2", value: Pane.accounts) {
                AccountsSettingsView(model: model)
            }
            Tab("Meldingen", systemImage: "bell.badge", value: Pane.notifications) {
                NotificationsSettingsView(model: model)
                    #if DEBUG
                    .onAppear { SnapshotCamera.shootScrolling("settings-notifications", windowId: "com_apple_SwiftUI_Settings_window", pages: 3) }
                    #endif
            }
            Tab("Algemeen", systemImage: "gearshape", value: Pane.general) {
                GeneralSettingsView(model: model)
                    #if DEBUG
                    .onAppear { SnapshotCamera.shoot("settings-general", windowId: "com_apple_SwiftUI_Settings_window") }
                    #endif
            }
        }
        .frame(width: 760, height: 580)
    }
}

// MARK: - Accounts

private struct AccountsSettingsView: View {
    let model: AppModel
    @State private var selection: UUID?
    /// Een nieuw account in het toevoeg-venster; staat pas in de config na Toevoegen.
    @State private var draft: Account?
    /// Het nieuwe account is een GitHub-account op GitHub Enterprise.
    @State private var draftIsEnterprise = false
    @State private var confirmsRemoval = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                AccountList(accounts: model.config.accounts, selection: $selection) {
                    if selection != nil { confirmsRemoval = true }
                }
                Divider()
                AccountListButtons(canRemove: selection != nil, add: add) { confirmsRemoval = true }
            }
            .frame(width: 250)

            Divider()

            Group {
                if let id = selection, let account = model.config.accounts.first(where: { $0.id == id }) {
                    AccountEditor(model: model, original: account).id(id)
                } else {
                    ContentUnavailableView {
                        Label("Geen account gekozen", systemImage: "person.crop.circle")
                    } description: {
                        Text("Kies links een account, of voeg er een toe met +.")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = model.config.accounts.first?.id } }
        #if DEBUG
        .onAppear { SnapshotCamera.shoot("settings-accounts", windowId: "com_apple_SwiftUI_Settings_window") }
        .onChange(of: selection) { _, _ in SnapshotCamera.shoot("settings-accounts-selected", windowId: "com_apple_SwiftUI_Settings_window") }
        #endif
        .sheet(item: $draft) { account in
            AddAccountSheet(model: model, draft: account, enterprise: draftIsEnterprise) { saved in
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
                selection = model.config.accounts.first?.id
            }
        } message: { account in
            Text("\(account.displayName) en de geschiedenis ervan verdwijnen uit Pullwatch. Op \(account.serviceName) verandert niets.")
        }
    }

    /// `enterprise`: GitHub Enterprise, waar de Pullwatch-app niet bestaat; daar eerst een token.
    private func add(_ kind: ProviderKind, enterprise: Bool) {
        draftIsEnterprise = enterprise
        draft = Account(kind: kind, organization: "", authMethod: enterprise ? .pat : model.defaultAuthMethod(for: kind))
    }
}

/// De accounts als kaarten: per inlog een kaart met foto, wie en de dienst, en daaronder de
/// plekken die hij volgt, elk op een eigen regel. De hele kaart is een knop (Tab, spatie);
/// de gekozen kaart heeft een blauwe rand. Delete verwijdert het gekozen account.
private struct AccountList: View {
    let accounts: [Account]
    @Binding var selection: UUID?
    let delete: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(accounts) { account in
                    AccountCard(account: account, isSelected: selection == account.id) {
                        selection = account.id
                    }
                }
            }
            .padding(10)
        }
        .onDeleteCommand(perform: delete)
        .accessibilityIdentifier("settings.accounts")
    }
}

private struct AccountCard: View {
    let account: Account
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    AccountAvatar(account: account, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: account.login.map { "@\($0)" } ?? account.organization)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if account.isPaused {
                            Text("\(account.serviceName), uitgezet", comment: "Dienst (GitHub, Azure DevOps, GitLab of de host van een eigen server); het account wordt niet opgehaald")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: account.serviceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                // De gevolgde plekken van een GitHub-inlog, elk op een eigen regel.
                if account.login != nil {
                    if account.owners.isEmpty {
                        Text("Volgt nog niets").font(.caption).foregroundStyle(.secondary)
                            .padding(.leading, 36)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(account.owners, id: \.self) { owner in
                                Label {
                                    Text(verbatim: owner).font(.callout).lineLimit(1)
                                } icon: {
                                    AccountAvatar(gitHubLogin: owner, size: 16)
                                }
                            }
                        }
                        .padding(.leading, 36)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isSelected ? 2 : 1) }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("settings.account.\(account.id)")
    }
}

/// + met een pijltje (het opent een keuze: GitHub, Azure DevOps of GitLab) en − onder de lijst, zoals
/// in de Mac-instellingen.
private struct AccountListButtons: View {
    let canRemove: Bool
    let add: (_ kind: ProviderKind, _ enterprise: Bool) -> Void
    let remove: () -> Void

    /// GitHub twee keer: github.com en GitHub Enterprise.
    private static let choices: [(kind: ProviderKind, enterprise: Bool)] = [
        (.gitHub, false), (.gitHub, true), (.azureDevOps, false), (.gitLab, false),
    ]

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(Array(Self.choices.enumerated()), id: \.offset) { _, choice in
                    Button {
                        add(choice.kind, choice.enterprise)
                    } label: {
                        Label {
                            Text(verbatim: choice.enterprise ? "GitHub Enterprise" : choice.kind.name)
                        } icon: {
                            ProviderMark.menuIcon(for: choice.kind)
                        }
                    }
                }
            } label: {
                Label("Account toevoegen", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(height: 22)
                    .padding(.horizontal, 6)
            }
            .menuStyle(.button)
            .menuIndicator(.visible)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Account toevoegen")
            .accessibilityIdentifier("settings.addAccount")
            Divider().frame(height: 16)
            Button(action: remove) {
                Label("Account verwijderen", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(!canRemove)
            .help("Account verwijderen")
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

/// Een account toevoegen: Annuleren gooit het concept weg, Toevoegen bewaart het als het af is.
private struct AddAccountSheet: View {
    let model: AppModel
    let draft: Account
    let enterprise: Bool
    let onClose: (_ saved: Bool) -> Void
    @State private var saveAction = AccountSaveAction()

    var body: some View {
        VStack(spacing: 0) {
            AccountEditor(model: model, original: draft, enterprise: enterprise, saveAction: saveAction) { onClose(true) }
            Divider()
            HStack {
                Button("Annuleren", role: .cancel) {
                    model.discardDraft(draft.id)
                    onClose(false)
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                AddButton(action: saveAction)
            }
            .controlSize(.large)
            .padding(12)
        }
        .frame(width: 620, height: 640)
    }
}

// MARK: - Algemeen

private struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    @State private var logLevel = Log.minimum

    var body: some View {
        Form {
            Section {
                Picker("Kijk elke", selection: $model.pollInterval) {
                    ForEach(AppModel.pollIntervals, id: \.self) { seconds in
                        Text(Duration.seconds(seconds), format: .units(allowed: [.minutes], width: .wide)).tag(seconds)
                    }
                }
                Picker("Geschiedenis bewaren", selection: $model.historyRetention) {
                    ForEach(HistoryRetention.allCases, id: \.self) { retention in
                        Text(retention.label).tag(retention)
                    }
                }
            } header: {
                Text("Ophalen")
            } footer: {
                Text("Hoe vaak Pullwatch naar nieuwe pull requests en tags kijkt, en hoe lang de geschiedenis blijft staan.")
            }

            Section {
                Toggle("Elke dag afhankelijkheden en kwetsbaarheden checken", isOn: $model.checksVersionsDaily)
            } header: {
                Text("Afhankelijkheden en kwetsbaarheden")
            } footer: {
                Text("Eens per dag leest Pullwatch de taal-, framework- en packageversies van je gevolgde repo's. Welke meldingen dat geeft kies je onder Meldingen.")
            }

            Section {
                Toggle("Automatisch op updates controleren", isOn: $model.checksForUpdates)
                if model.installsUpdatesInApp {
                    Toggle(
                        "Updates automatisch installeren",
                        isOn: Binding(get: { model.installsUpdatesAutomatically }, set: { model.setInstallsUpdatesAutomatically($0) })
                    )
                    .disabled(!model.checksForUpdates)
                    .help("Pullwatch downloadt een update op de achtergrond en installeert hem als je de app afsluit.")
                    Toggle("Testversies aanbieden", isOn: $model.includesTestVersions)
                        .help("Ook pre-releases van Pullwatch, voordat ze voor iedereen uitkomen.")
                }
                LabeledContent {
                    HStack {
                        if model.isCheckingForUpdates { ProgressView().controlSize(.small) }
                        Button("Nu controleren") { Task { await model.checkForUpdates(manual: true) } }
                            .disabled(model.isCheckingForUpdates)
                    }
                } label: {
                    Text("Versie \(AppModel.currentVersion)")
                    if let message = model.updateCheckMessage {
                        Text(verbatim: message)
                    }
                }
            } header: {
                Text("Updates")
            }

            Section("Opstarten") {
                LaunchAtLoginToggle()
            }

            Section {
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
                }
                .onChange(of: logLevel) { _, level in Log.minimum = level }
            } header: {
                Text("Probleemoplossing")
            } footer: {
                Text("Vanaf dit niveau schrijft Pullwatch naar het systeemlog. In Console zoek je op nl.torrisi.pullwatch.")
            }
        }
        .formStyle(.grouped)
    }

    private func openConsole() {
        let console = URL(filePath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.openApplication(at: console, configuration: NSWorkspace.OpenConfiguration())
    }
}
