import PullwatchCore
import SwiftUI

/// De packages van een repo op de repo-pagina: één sectie per workspace (alleen de naam erbij als
/// er meer dan één is), met Direct open en Transitief, Herkomst onbekend en Dev ingeklapt.
struct RepoPackagesSections: View {
    let versions: RepoVersions
    /// `PackageUse.key` van de packages die in Afhankelijkheden staan.
    var knownPackages: Set<String> = []
    var showPackage: ((String) -> Void)? = nil

    var body: some View {
        let workspaces = versions.packageWorkspaces.filter { !$0.isEmpty }
        if workspaces.isEmpty {
            Section("Packages") {
                Text("Geen packages met een vaste versie gevonden").foregroundStyle(.secondary)
            }
        } else {
            ForEach(workspaces) { workspace in
                Section {
                    PackageGroup(title: "Direct", packages: workspace.direct, startsExpanded: true,
                                 help: "Packages die je project zelf vraagt",
                                 knownPackages: knownPackages, showPackage: showPackage)
                    PackageGroup(title: "Transitief", packages: workspace.transitive,
                                 help: "Packages die alleen via een ander package binnenkomen",
                                 knownPackages: knownPackages, showPackage: showPackage)
                    PackageGroup(title: "Herkomst onbekend", packages: workspace.unknown,
                                 help: "Zonder manifest in dezelfde map is niet te zien of je project deze packages zelf vraagt",
                                 knownPackages: knownPackages, showPackage: showPackage)
                    PackageGroup(title: "Dev", packages: workspace.dev,
                                 help: "Alleen nodig om te ontwikkelen en te testen, niet in wat je uitlevert",
                                 knownPackages: knownPackages, showPackage: showPackage)
                } header: {
                    HStack {
                        Text("Packages")
                        Spacer()
                        if workspaces.count > 1 {
                            Label(Workspace.name(workspace.workspace), systemImage: "folder")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// Een inklapbare groep packages ("Direct (12)"). Ingeklapt worden de rijen niet gebouwd: een
/// transitieve groep kan honderden packages hebben.
private struct PackageGroup: View {
    let title: LocalizedStringResource
    let packages: [WorkspacePackage]
    var startsExpanded = false
    let help: LocalizedStringResource
    let knownPackages: Set<String>
    let showPackage: ((String) -> Void)?

    @State private var isExpanded: Bool?

    private var startsOpen: Bool {
        #if DEBUG
        if SnapshotCamera.expandsAll { return true }
        #endif
        return startsExpanded
    }

    var body: some View {
        if !packages.isEmpty {
            DisclosureGroup(isExpanded: Binding(get: { isExpanded ?? startsOpen }, set: { isExpanded = $0 })) {
                if isExpanded ?? startsOpen {
                    ForEach(packages) { package in
                        WorkspacePackageRow(
                            package: package,
                            showPackage: knownPackages.contains(package.id) ? showPackage : nil
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                    Text(verbatim: "(\(packages.count))").foregroundStyle(.secondary)
                }
                .help(Text(help))
            }
        }
    }
}

/// Eén package in een workspace. Met één install: naam, versie en keten op één regel; met meer
/// versies een regel per versie met de keten erbij, en "3 versies" bij de naam.
private struct WorkspacePackageRow: View {
    let package: WorkspacePackage
    let showPackage: ((String) -> Void)?

    var body: some View {
        if package.installs.count == 1, let install = package.installs.first {
            LabeledContent {
                Text(verbatim: install.version).monospacedDigit()
            } label: {
                name
                if let provenance = Provenance.text(scope: install.scope, via: install.via), install.scope != .direct {
                    Text(verbatim: provenance)
                        .accessibilityLabel(Text(verbatim: Provenance.spoken(scope: install.scope, via: install.via) ?? provenance))
                }
            }
            .help(Text(verbatim: install.source))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                name
                ForEach(package.installs, id: \.self) { install in
                    InstallLine(version: install.version, scope: install.scope, via: install.via, isDev: install.kind == .dev)
                        .padding(.leading, 12)
                        .help(Text(verbatim: install.source))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var name: some View {
        HStack(spacing: 6) {
            if let showPackage {
                Button(package.name) { showPackage(package.name) }
                    .buttonStyle(.link)
                    .help("Toon dit package in Afhankelijkheden, met alle repo's die het gebruiken")
            } else {
                Text(verbatim: package.name)
            }
            if package.repoVersions.count > 1 {
                Text("\(package.repoVersions.count) versies", comment: "Aantal verschillende versies van een package in deze repo")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(Text(verbatim: package.repoVersions.joined(separator: ", ")))
            }
        }
    }
}
