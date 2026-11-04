import PullwatchCore
import SwiftUI

// De cellen van de tabel in het onderdeel Packages. Ze nemen alleen waarden: AppKit tekent een cel
// soms buiten de environment van het venster (`CellEnvironmentTests`).

// Sleutels om op te sorteren; waarden, dus buiten de main actor bruikbaar (KeyPathComparator).
nonisolated extension PublishedPackageSummary {
    var nameSortKey: String { package.name.lowercased() }
    /// De repository voluit, anders de eigenaar (een Azure-project).
    var publisher: String { package.repository ?? package.owner }
    var publisherSortKey: String { publisher.lowercased() }
    /// Zonder versie achteraan, een zwevende tag (`main`) net daarvoor.
    var latestSortKey: String {
        switch package.latestKind {
        case .version: package.releasedVersion ?? package.latestVersion ?? "\u{10FFFF}"
        case .floatingTag: "\u{10FFFE}" + (package.latestVersion ?? "")
        case .untagged: "\u{10FFFF}"
        }
    }
    /// Zonder datum achteraan bij nieuwste eerst.
    var publishedSortKey: Date { package.releasedAt ?? .distantPast }
    /// Een soort die de check niet herkent telt als onbekend, onder nul.
    var usedBySortKey: Int { isMatchable ? users.count : -1 }
}

/// Het teken van de soort met de naam van het package, en een slot (privé) of gebouw (intern)
/// achter de naam.
struct PublishedPackageNameCell: View {
    let name: String
    let type: PublishedPackageType
    var visibility: PublishedPackage.Visibility?

    var body: some View {
        Label {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: name).fontWeight(.medium).lineLimit(1)
                PublishedPackageVisibilityIcon(visibility: visibility)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
        } icon: {
            PublishedPackageTypeIcon(type: type)
                .foregroundStyle(.secondary)
        }
        .help(type.text)
    }

    /// "ferroehr, privé": de zichtbaarheid hoort bij de naam.
    private var accessibilityName: Text {
        switch visibility {
        case .private?: Text("\(name), privé", comment: "VoiceOver: naam van een privé package")
        case .internal?: Text("\(name), intern", comment: "VoiceOver: naam van een intern package")
        case .public?, nil: Text(verbatim: name)
        }
    }
}

/// De repository die het package publiceert, voluit (eigenaar/naam); zonder repository (Azure
/// Artifacts) de eigenaar, het project, in het secundaire grijs.
struct PublishedPackagePublisherCell: View {
    let repository: String?
    let owner: String

    var body: some View {
        if let repository {
            Text(verbatim: repository).lineLimit(1)
        } else {
            Text(verbatim: owner)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Text("Niet aan een repository gekoppeld; gepubliceerd onder \(owner)", comment: "Eigenaar of Azure-project van een package"))
        }
    }
}

/// De nieuwste versie; als de kolom met de datum er niet staat, de datum in de tooltip. Bij een
/// container-image: het label `latest` als die tag op dezelfde image staat, anders een tooltip
/// waar `latest` naar wijst; zonder versietag de nieuwste tag in het grijs, zonder tag "Zonder tag".
struct PublishedPackageVersionCell: View {
    let version: String?
    let publishedAt: Date?
    var showsDateInHelp = false
    var kind: PublishedPackage.LatestKind = .version
    var latestTag: PublishedPackage.LatestTag = .absent
    /// Een pre-release die nieuwer is dan de getoonde stabiele versie.
    var newerPrerelease: String?

    var body: some View {
        switch (kind, version) {
        case (.version, let version?):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: version)
                    .monospacedDigit()
                    .lineLimit(1)
                if latestTag == .onLatestVersion {
                    LatestTagBadge()
                }
            }
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(latestTag == .onLatestVersion
                                ? Text("versie \(version), met de tag latest", comment: "VoiceOver: versie waar ook de tag latest op staat")
                                : Text("versie \(version)", comment: "VoiceOver: de nieuwste versie van een package"))
        case (.floatingTag, let tag?):
            Text(verbatim: tag)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Text("Geen versietag; dit is de nieuwste tag", comment: "Image zonder versietag: de nieuwste tag (main, latest) staat er"))
        case (.untagged, _):
            Text("Zonder tag", comment: "Image waarvan geen versie een tag heeft")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Text("Geen versie van deze image heeft een tag"))
        default:
            Text("Onbekend").foregroundStyle(.tertiary)
        }
    }

    /// Een nieuwere pre-release en waar `latest` naar wijst als dat niet de getoonde versie is,
    /// elk een eigen zin op een eigen regel; anders de datum.
    private var help: Text {
        let prerelease = newerPrerelease.map {
            String(localized: "Nieuwere pre-release: \($0)", comment: "Tooltip: een pre-release die nieuwer is dan de getoonde versie")
        }
        let lines = [prerelease, latestNote].compactMap { $0 }
        guard lines.isEmpty else { return Text(verbatim: lines.joined(separator: "\n")) }
        // Een tooltip verschijnt pas als de muis op de cel staat, en dan tekent de cel opnieuw: de
        // datum klopt dus op het moment dat je hem leest, zonder RelativeDateText.
        return showsDateInHelp
            ? publishedAt.map { Text("Gepubliceerd \($0.formatted(.relative(presentation: .named)))", comment: "Relatieve datum") } ?? Text(verbatim: "")
            : Text(verbatim: "")
    }

    /// Waar `latest` naar wijst als dat niet de getoonde versie is.
    private var latestNote: String? {
        switch latestTag {
        case .unversionedBuild:
            String(localized: "latest wijst naar een nieuwere build zonder versietag", comment: "latest is de naam van een tag; niet vertalen")
        case .otherVersion(let other):
            String(localized: "latest wijst naar \(other)", comment: "latest is de naam van een tag; niet vertalen")
        case .absent, .onLatestVersion:
            nil
        }
    }
}

/// Wanneer de nieuwste versie verscheen, relatief.
struct PublishedPackageDateCell: View {
    let publishedAt: Date?

    var body: some View {
        if let publishedAt {
            RelativeDateText(date: publishedAt)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Hoeveel gevolgde repo's het package gebruiken; een streep voor een soort die de check nog niet
/// herkent (container-images, Helm), want daar is het niet bekend, niet nul.
struct PublishedPackageUsersCell: View {
    let count: Int
    let isMatchable: Bool

    var body: some View {
        if isMatchable {
            Text(count, format: .number)
                .monospacedDigit()
                .foregroundStyle(count == 0 ? .tertiary : .primary)
                .accessibilityLabel(Text("Gebruikt door \(count) repo's", comment: "Aantal gevolgde repo's dat een eigen package gebruikt"))
        } else {
            Text(verbatim: "-")
                .foregroundStyle(.tertiary)
                .help(Text("Nog niet bekend: de check herkent dit soort package nog niet als dependency"))
                .accessibilityLabel(Text("Gebruik onbekend"))
        }
    }
}
