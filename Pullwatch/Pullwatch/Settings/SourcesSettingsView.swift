import AppKit
import PullwatchCore
import SwiftUI

/// Het tabblad Bronnen: elke externe bron met wat hij levert, het adres dat Pullwatch aanroept,
/// een link naar de site en een schakelaar; daaronder de verbindingen zonder schakelaar (de
/// servers van de accounts, inloggen, profielfoto's, de updatecheck) en Kopieer overzicht.
struct SourcesSettingsView: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(VersionsModel.self) private var versions
    /// Naar het tabblad Algemeen, waar de updatecheck aan of uit staat.
    let showGeneral: () -> Void

    /// De taal van de app, voor de verbindingen en het gekopieerde overzicht.
    private var locale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "nl")
    }

    var body: some View {
        let config = accounts.config
        let connections = SourcesOverview.otherConnections(config: config, locale: locale).map(Connection.init)
        Form {
            SourceGroupSection(title: "Kwetsbaarheden", group: .vulnerabilities)
            SourceGroupSection(title: "Versies", group: .versions)
            SourceGroupSection(title: "Pull requests", group: .pullRequests)
            Section {
                LabeledContent {
                    HStack {
                        if versions.versionCheck != nil { ProgressView().controlSize(.small) }
                        Button("Nu checken") { versions.startCheck() }
                            .disabled(versions.versionCheck != nil || !versions.refreshingRepos.isEmpty)
                    }
                } label: {
                    Text("Geldt vanaf de volgende check")
                    Text("Een schakelaar omzetten start geen check. Wat eerder van een bron kwam die nu uit staat, telt niet meer als actueel.")
                }
            }
            Section {
                // De updatecheck is altijd de laatste rij (`SourcesOverview.otherConnections`).
                ForEach(connections.dropLast()) { connection in
                    ConnectionRow(name: connection.name, urls: connection.urls, detail: connection.detail)
                }
                if let update = connections.last {
                    ConnectionRow(name: update.name, urls: update.urls, detail: update.detail) {
                        Button("Naar Algemeen", action: showGeneral)
                            .help("Automatisch op updates controleren staat in het tabblad Algemeen")
                    }
                }
            } header: {
                Text("Overige verbindingen")
            } footer: {
                Text("Deze verbindingen hebben geen eigen schakelaar: een account zet je uit in Accounts, de updatecheck in Algemeen.")
            }
            Section {
                LabeledContent {
                    CopyButton(title: "Kopieer overzicht", help: "Kopieer het overzicht van alle bronnen naar het klembord") {
                        SourcesOverview.text(config: accounts.config, appVersion: AppModel.currentVersion, date: .now, locale: locale)
                    }
                } label: {
                    Text("Overzicht als tekst")
                    Text("Alle bronnen met hun stand en adres, om in een mail of bericht te plakken.")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Een verbinding uit `SourcesOverview.otherConnections`, met een id uit naam en adressen.
    private struct Connection: Identifiable {
        let name: String
        let urls: [URL]
        let detail: String

        var id: String { ([name] + urls.map(\.absoluteString)).joined(separator: "\n") }

        init(_ connection: (name: String, urls: [URL], detail: String)) {
            name = connection.name
            urls = connection.urls
            detail = connection.detail
        }
    }
}

/// Eén groep van de catalogus (`DataSource.all`), elke bron met zijn schakelaar.
private struct SourceGroupSection: View {
    @Environment(AccountsModel.self) private var accounts
    let title: LocalizedStringKey
    let group: DataSourceGroup

    var body: some View {
        Section(title) {
            ForEach(DataSource.all.filter { $0.group == group }) { source in
                SourceRow(source: source, isOn: Bindable(accounts)[sourceEnabled: source.id])
            }
        }
    }
}

/// Eén bron: naam, wat hij levert, het adres (selecteerbaar), een link naar de site en de schakelaar.
private struct SourceRow: View {
    let source: DataSource
    @Binding var isOn: Bool

    var body: some View {
        LabeledContent {
            Toggle(source.name, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: source.name)
                Text(source.summary).foregroundStyle(.secondary)
                if source.id == .osv {
                    Label("De enige bron voor kwetsbaarheden in packages bij repo's op GitHub, GitLab, Bitbucket, Gitea, Forgejo en Codeberg.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if source.id == .ciChecks {
                    Text("Bij GitHub Enterprise en een eigen GitLab-, Gitea- of Forgejo-server vraagt Pullwatch de checks aan die server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(verbatim: source.endpoints.map(\.absoluteString).joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Link("Website", destination: source.site)
                        .font(.caption)
                        .help(Text(verbatim: source.site.absoluteString))
                }
            }
        }
    }
}

/// Een verbinding zonder schakelaar: naam, wat Pullwatch er doet (met de stand) en de adressen.
private struct ConnectionRow<Trailing: View>: View {
    let name: String
    let urls: [URL]
    let detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        LabeledContent {
            trailing()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name)
                Text(verbatim: detail).foregroundStyle(.secondary)
                Text(verbatim: urls.map(\.absoluteString).joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

extension ConnectionRow where Trailing == EmptyView {
    init(name: String, urls: [URL], detail: String) {
        self.init(name: name, urls: urls, detail: detail) { EmptyView() }
    }
}
