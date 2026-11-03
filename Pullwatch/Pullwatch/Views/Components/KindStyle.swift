import PullwatchCore
import SwiftUI

/// Kleine gekleurde pill: soort, PR-status, versiestatus, ernst, plek van een kwetsbaarheid of
/// een kort label in de repolijst. De enige pill in de app, zodat ze er overal hetzelfde uitzien.
struct Pill: View {
    let text: LocalizedStringResource
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// Een icoon: een SF Symbol, of een eigen symbool uit de assetcatalogus (de Octicons van GitHub
/// voor pull requests, als `.symbolset`, zodat ze meeschalen met de tekst en de tint volgen).
nonisolated enum Glyph: Hashable, Sendable {
    case system(String)
    case asset(String)

    /// Het plaatje, zonder eigen VoiceOver-tekst: de tekst ernaast (of een `accessibilityLabel`)
    /// zegt wat het is. Een eigen symbool leest anders zijn assetnaam voor.
    var image: Image {
        switch self {
        case .system(let name): Image(systemName: name)
        case .asset(let name): Image(decorative: name)
        }
    }
}

nonisolated extension ProviderKind {
    /// Het beeld van de dienst op de keuzekaarten en in het toevoeg-menu. Alleen GitHub staat een
    /// logo in een app toe ("Show integration", brand.github.com/foundations/logo): de
    /// Invertocat, onveranderd, zwart op licht en wit op donker (de assetcatalogus kiest). GitLab
    /// weigert zijn logo's in gebruikersinterfaces (Trademark Guidelines van GitLab Inc.) en
    /// Microsoft staat de Azure-iconen alleen toe in diagrammen en documentatie: daar een SF Symbol.
    var glyph: Glyph {
        switch self {
        case .gitHub: .asset("GitHubMark")
        case .azureDevOps: .system("cloud")
        case .gitLab: .system("arrow.triangle.merge")
        }
    }

    /// Het logo moet zijn eigen kleuren houden: nooit tinten of als template tekenen.
    var glyphKeepsItsColours: Bool { self == .gitHub }
}

// Vaste waarden (icoon, kleur, tekst), geen UI-state: overal bruikbaar, ook in tests.
nonisolated extension ItemKind {
    var color: Color {
        switch self {
        case .pullRequest: .blue
        case .tag: .orange
        }
    }

    /// Het icoon van de soort: de Octicon git-pull-request voor PR's, zoals GitHub, en het SF
    /// Symbol tag voor tags. Ook voor het onderdeel PR's in de zijbalk en de lege lijsten.
    var glyph: Glyph {
        switch self {
        case .pullRequest: PRStatus.open.glyph
        case .tag: .system("tag")
        }
    }

    var pillText: LocalizedStringResource {
        switch self {
        case .pullRequest: "PR"
        case .tag: "Tag"
        }
    }
}

// Vaste waarden (kleur, tekst), geen UI-state: overal bruikbaar, ook in tests.
nonisolated extension ReleaseInfo {
    /// Groen zoals een release op GitHub, oranje zoals een pre-release.
    var color: Color { isPrerelease ? .orange : .green }

    var label: LocalizedStringResource { isPrerelease ? "Pre-release" : "Release" }
}

// Vaste waarden (kleur, tekst), geen UI-state: overal bruikbaar, ook in tests. De kleuren zijn die
// van GitHub: open groen, gemerged paars, gesloten rood.
nonisolated extension PRState {
    var color: Color {
        switch self {
        case .open: .green
        case .merged: .purple
        case .closed: .red
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .open: "Open"
        case .merged: "Gemerged"
        case .closed: "Gesloten"
        }
    }
}

/// De status van een PR zoals GitHub hem toont, met een open draft apart van een gewone open PR.
/// Bepaalt op één plek het icoon, de kleur en de tekst.
nonisolated enum PRStatus: CaseIterable, Hashable, Sendable {
    case open, draft, merged, closed

    init(_ pr: PullRequest) {
        switch pr.state {
        case .open: self = pr.isDraft ? .draft : .open
        case .merged: self = .merged
        case .closed: self = .closed
        }
    }

    /// De Octicons van GitHub (MIT, zie NOTICE), op 16 px getekend: git-pull-request,
    /// git-pull-request-draft, git-merge en git-pull-request-closed.
    var glyph: Glyph {
        switch self {
        case .open: .asset("pr.open")
        case .draft: .asset("pr.draft")
        case .merged: .asset("pr.merged")
        case .closed: .asset("pr.closed")
        }
    }

    /// Zoals GitHub: een draft is grijs, de rest de kleur van zijn `PRState`.
    var color: Color {
        switch self {
        case .open: PRState.open.color
        case .draft: .gray
        case .merged: PRState.merged.color
        case .closed: PRState.closed.color
        }
    }

    /// Soort en status in woorden, voor de tooltip en VoiceOver waar alleen het icoon staat.
    var spokenName: LocalizedStringResource {
        switch self {
        case .open: "Pull request, open"
        case .draft: "Pull request, draft"
        case .merged: "Pull request, gemerged"
        case .closed: "Pull request, gesloten"
        }
    }
}

// Vaste waarden (icoon, kleur, tekst), geen UI-state: overal bruikbaar, ook in tests. Naast de
// kleuren van `PRStatus`, zodat ze niet uit elkaar lopen: groen en rood zijn die van open en
// gesloten, geel het amber van GitHub ("attention", licht #9A6700 en donker #D29922).
nonisolated extension CheckState {
    /// De Octicons van GitHub (MIT, zie NOTICE), op 16 px getekend: check, x en dot-fill.
    var glyph: Glyph {
        switch self {
        case .passed: .asset("checks.passed")
        case .failed: .asset("checks.failed")
        case .pending: .asset("checks.pending")
        }
    }

    var color: Color {
        switch self {
        case .passed: PRState.open.color
        case .failed: PRState.closed.color
        case .pending: Color("ChecksPending")
        }
    }
}

nonisolated extension CheckCounts {
    /// De telling in de cel: geslaagd (overgeslagen tellen mee) van het totaal, "8/8".
    var fraction: String { "\(succeeded)/\(total)" }

    /// Wat de cel zegt, in woorden, voor de tooltip en VoiceOver: "4 van 8 checks geslaagd,
    /// 1 mislukt en 3 bezig". Elke stand is een eigen zin met meervoud; de lijst maakt
    /// `ListFormatStyle` per taal.
    var spokenSummary: String {
        var parts = [String(localized: "\(succeeded) van \(total) checks geslaagd", comment: "Checks van een PR; geslaagd (overgeslagen tellen mee), totaal")]
        if failed > 0 { parts.append(String(localized: "\(failed) mislukt", comment: "Aantal mislukte checks van een PR")) }
        if pending > 0 { parts.append(String(localized: "\(pending) bezig", comment: "Aantal checks van een PR die nog lopen of wachten")) }
        if skipped > 0 { parts.append(String(localized: "\(skipped) overgeslagen", comment: "Aantal overgeslagen of neutrale checks van een PR")) }
        return parts.formatted(.list(type: .and))
    }
}

nonisolated extension HistoryEntry {
    /// De status van de PR, met drafts apart; `nil` voor tags.
    var prStatus: PRStatus? {
        switch self {
        case .pullRequest(let pr): PRStatus(pr)
        case .tag: nil
        }
    }

    /// Het icoon van dit item: dat van zijn PR-status, of het tag-symbool.
    var glyph: Glyph { prStatus?.glyph ?? kind.glyph }

    /// De kleur van dat icoon.
    var glyphColor: Color { prStatus?.color ?? kind.color }

    /// Wat dat icoon betekent, in woorden ("Pull request, gemerged" of "Tag"): de tooltip en
    /// het VoiceOver-label waar het icoon zonder tekst staat.
    var glyphLabel: LocalizedStringResource { prStatus?.spokenName ?? kind.pillText }
}
