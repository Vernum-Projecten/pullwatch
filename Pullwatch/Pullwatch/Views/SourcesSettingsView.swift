import AppKit
import PullwatchCore
import SwiftUI

/// Het tabblad Bronnen: elke externe bron met wat hij levert, het adres dat Pullwatch aanroept,
/// een link naar de site en een schakelaar; daaronder de verbindingen zonder schakelaar (de
/// servers van de accounts, inloggen, profielfoto's, de updatecheck) en Kopieer overzicht.
struct SourcesSettingsView: View {
    let model: AppModel
    /// Naar het tabblad Algemeen, waar de updatecheck aan of uit staat.
    let showGeneral: () -> Void

    @State private var copied = false

    /// De taal van de app, voor de verbindingen en het gekopieerde overzicht.
    private var locale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "nl")
    }

    var body: some View {
        let connections = SourcesOverview.otherConnections(config: model.config, locale: locale)
        Form {
            Section("Kwetsbaarheden") {
                ForEach(DataSource.all.filter { $0.group == .vulnerabilities }) { source in
                    SourceRow(source: source, isOn: isOn(source.id))
                }
            }
            Section("Versies") {
                ForEach(DataSource.all.filter { $0.group == .versions }) { source in
                    SourceRow(source: source, isOn: isOn(source.id))
                }
            }
            Section {
                LabeledContent {
                    HStack {
                        if model.versionCheck != nil { ProgressView().controlSize(.small) }
                        Button("Nu checken") { Task { await model.checkVersions() } }
                            .disabled(model.versionCheck != nil || !model.refreshingRepos.isEmpty)
                    }
                } label: {
                    Text("Geldt vanaf de volgende check")
                    Text("Een schakelaar omzetten start geen check. Wat eerder van een bron kwam die nu uit staat, telt niet meer als actueel.")
                }
            }
            Section {
                // De updatecheck is altijd de laatste rij (`SourcesOverview.otherConnections`).
                ForEach(Array(connections.dropLast().enumerated()), id: \.offset) { _, connection in
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
                    Button {
                        copy()
                    } label: {
                        Label("Kopieer overzicht", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                } label: {
                    Text("Overzicht als tekst")
                    Text("Alle bronnen met hun stand en adres, om in een mail of bericht te plakken.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func isOn(_ id: DataSourceID) -> Binding<Bool> {
        Binding(get: { model.config.isEnabled(id) }, set: { model.setSourceEnabled(id, $0) })
    }

    private func copy() {
        let text = SourcesOverview.text(config: model.config, appVersion: AppModel.currentVersion, date: .now, locale: locale)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
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
                    Label("De enige bron voor kwetsbaarheden in packages bij GitHub- en GitLab-repo's.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
