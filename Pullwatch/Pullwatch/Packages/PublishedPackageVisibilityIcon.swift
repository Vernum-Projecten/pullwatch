import PullwatchCore
import SwiftUI

// Hoe het onderdeel Packages de zichtbaarheid van een package toont. Waarden, geen UI-state.
nonisolated extension PublishedPackage.Visibility {
    /// Een slot voor privé, een gebouw voor intern (alleen leden van de organisatie); openbaar
    /// heeft geen symbool, dat is het gewone geval.
    var symbol: String? {
        switch self {
        case .private: "lock.fill"
        case .internal: "building.2.fill"
        case .public: nil
        }
    }

    /// Het woord voor het inspectievenster.
    var text: Text {
        switch self {
        case .public: Text("Openbaar")
        case .private: Text("Privé")
        case .internal: Text("Intern")
        }
    }

    /// De tooltip bij het symbool achter de naam.
    var help: Text {
        switch self {
        case .public: Text("Openbaar")
        case .private: Text("Privé")
        case .internal: Text("Intern: zichtbaar voor leden van de organisatie")
        }
    }
}

/// Het kleine symbool achter de naam van een privé of intern package; niets bij openbaar.
/// VoiceOver leest het mee in het label van de naam (`PublishedPackageNameCell`).
struct PublishedPackageVisibilityIcon: View {
    let visibility: PublishedPackage.Visibility?

    var body: some View {
        if let visibility, let symbol = visibility.symbol {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .help(visibility.help)
                .accessibilityHidden(true)
        }
    }
}

/// Het label `latest` achter een versie: de tag die meeschuift met de nieuwste build. Een kleine
/// capsule in het secundaire grijs, zodat hij niet met de kleuren van de stand concurreert;
/// "latest" is de naam van de tag en wordt niet vertaald.
struct LatestTagBadge: View {
    var body: some View {
        Text(verbatim: ContainerTag.latest)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// Het label "pre-release" achter een recente versie met een pre-release-achtervoegsel
/// ("21.0.0-rc9"), in dezelfde stille stijl als `LatestTagBadge`.
struct PrereleaseBadge: View {
    var body: some View {
        Text("pre-release", comment: "Label achter een versie die een pre-release is")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .accessibilityHidden(true)
    }
}
