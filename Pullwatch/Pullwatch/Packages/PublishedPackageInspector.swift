import PullwatchCore
import SwiftUI

/// Het inspectievenster van één gepubliceerd package: wat het is en wie het publiceert, de recente
/// versies met hun tag en de run die ze publiceerde, en welke gevolgde repo's op welke versie
/// zitten. Geen downloads of volledige geschiedenis: die staan bij het register, dat de knop opent.
struct PublishedPackageInspector: View {
    let summary: PublishedPackageSummary
    /// De naam van het account, als er meer accounts zijn.
    let accountName: String?
    /// Opent de pagina van een gevolgde repo (`RepoSummary.id`); nil als die niet in het overzicht staat.
    let openRepo: (String) -> Void
    /// Opent Tags en releases, gefilterd op de publicerende repo.
    let showTags: (() -> Void)?

    var body: some View {
        Form {
            PublishedPackageHeaderSection(package: summary.package, accountName: accountName)
            PublishedPackageVersionsSection(versions: summary.package.versions, showTags: showTags)
            PublishedPackageUsersSection(
                users: summary.users, isMatchable: summary.isMatchable, latest: summary.package.latestVersion, openRepo: openRepo
            )
            if let url = summary.package.webURL {
                Section {
                    Link(destination: url) {
                        Label("Open in het register", systemImage: "safari")
                    }
                    .help(Text("Open de pagina van het package bij het register (⌘O)"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PublishedPackageHeaderSection: View {
    let package: PublishedPackage
    let accountName: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(verbatim: package.name)
                        .font(.headline)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: package.type.symbol).foregroundStyle(.secondary)
                }
                package.type.text.foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            LabeledContent("Gepubliceerd door") {
                Text(verbatim: package.repository ?? package.owner).textSelection(.enabled)
            }
            LabeledContent("Nieuwste versie") {
                PublishedPackageVersionCell(
                    version: package.latestVersion, publishedAt: package.publishedAt, kind: package.latestKind, latestTag: package.latestTag
                )
            }
            if let visibility = package.visibility {
                LabeledContent("Zichtbaarheid") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if let symbol = visibility.symbol {
                            Image(systemName: symbol)
                                .imageScale(.small)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        visibility.text
                    }
                    .help(visibility.help)
                }
            }
            if let accountName {
                LabeledContent("Account") { Text(verbatim: accountName) }
            }
        }
    }
}

/// De recente versies, nieuwste eerst, elk met datum, tag en run als de dienst die noemt.
private struct PublishedPackageVersionsSection: View {
    let versions: [PublishedVersion]
    let showTags: (() -> Void)?

    var body: some View {
        Section("Recente versies") {
            if versions.isEmpty {
                Text("Geen versies bekend").foregroundStyle(.secondary)
            }
            ForEach(versions, id: \.version) { version in
                LabeledContent {
                    HStack(spacing: 8) {
                        if let tag = version.tag {
                            Button {
                                showTags?()
                            } label: {
                                Label { Text(verbatim: tag) } icon: { ItemKind.tag.glyph.image }
                            }
                            .buttonStyle(.link)
                            .disabled(showTags == nil)
                            .help(Text("Toon de tags van deze repo"))
                        }
                        if let run = version.runURL {
                            Link(destination: run) {
                                Image(systemName: "hammer")
                            }
                            .help(Text("Open de run die deze versie publiceerde"))
                            .accessibilityLabel(Text("Run"))
                        }
                        if let page = version.webURL {
                            Link(destination: page) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help(Text("Open deze versie bij het register"))
                            .accessibilityLabel(Text("Open deze versie bij het register"))
                        }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: version.version).monospacedDigit().textSelection(.enabled)
                        if version.isLatestTag {
                            LatestTagBadge()
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(version.isLatestTag
                                        ? Text("versie \(version.version), met de tag latest", comment: "VoiceOver: versie waar ook de tag latest op staat")
                                        : Text("versie \(version.version)", comment: "VoiceOver: de nieuwste versie van een package"))
                    if let date = version.publishedAt {
                        Text(date, format: .relative(presentation: .named))
                    }
                }
            }
        }
    }
}

/// Welke gevolgde repo's het package gebruiken en op welke versie; een klik opent de repo.
private struct PublishedPackageUsersSection: View {
    let users: [PublishedPackageUser]
    let isMatchable: Bool
    let latest: String?
    let openRepo: (String) -> Void

    var body: some View {
        Section {
            if !isMatchable {
                Text("Nog niet bekend: de check herkent dit soort package nog niet als dependency.")
                    .foregroundStyle(.secondary)
            } else if users.isEmpty {
                Text("Geen gevolgde repo gebruikt dit package.").foregroundStyle(.secondary)
            }
            ForEach(users) { user in
                LabeledContent {
                    Text(verbatim: user.versions.formatted(.list(type: .and)))
                        .monospacedDigit()
                        .foregroundStyle(user.version == latest ? .green : .orange)
                } label: {
                    Button {
                        openRepo(user.repoId)
                    } label: {
                        Text(verbatim: user.repo)
                    }
                    .buttonStyle(.link)
                    .help(Text("Open de pagina van deze repo"))
                    if !user.isDirect {
                        Text("Alleen via andere packages")
                    }
                }
            }
        } header: {
            Text("Gebruikt door")
        }
    }
}
