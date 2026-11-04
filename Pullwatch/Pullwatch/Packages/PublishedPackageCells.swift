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
    /// Zonder versie achteraan.
    var latestSortKey: String { package.latestVersion ?? "\u{10FFFF}" }
    /// Zonder datum achteraan bij nieuwste eerst.
    var publishedSortKey: Date { package.publishedAt ?? .distantPast }
    /// Een soort die de check niet herkent telt als onbekend, onder nul.
    var usedBySortKey: Int { isMatchable ? users.count : -1 }
}

/// Het symbool van de soort met de naam van het package.
struct PublishedPackageNameCell: View {
    let name: String
    let type: PublishedPackageType

    var body: some View {
        Label {
            Text(verbatim: name).fontWeight(.medium).lineLimit(1)
        } icon: {
            Image(systemName: type.symbol)
                .foregroundStyle(.secondary)
                .accessibilityLabel(type.text)
        }
        .help(type.text)
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

/// De nieuwste versie; als de kolom met de datum er niet staat, de datum in de tooltip.
struct PublishedPackageVersionCell: View {
    let version: String?
    let publishedAt: Date?
    var showsDateInHelp = false

    var body: some View {
        if let version {
            Text(verbatim: version)
                .monospacedDigit()
                .lineLimit(1)
                .help(showsDateInHelp
                      ? publishedAt.map { Text("Gepubliceerd \($0.formatted(.relative(presentation: .named)))", comment: "Relatieve datum") } ?? Text(verbatim: "")
                      : Text(verbatim: ""))
        } else {
            Text("Onbekend").foregroundStyle(.tertiary)
        }
    }
}

/// Wanneer de nieuwste versie verscheen, relatief.
struct PublishedPackageDateCell: View {
    let publishedAt: Date?

    var body: some View {
        if let publishedAt {
            Text(publishedAt, format: .relative(presentation: .named))
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
