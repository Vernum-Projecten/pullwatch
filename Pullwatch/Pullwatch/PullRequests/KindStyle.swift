import PullwatchCore
import SwiftUI

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
    /// Het beeld van de dienst op de keuzekaarten, de accountkaarten en in het toevoeg-menu
    /// (zie NOTICE, Trademarks). GitHub: de Invertocat, onveranderd, zwart op licht en wit op
    /// donker (de assetcatalogus kiest), zoals GitHub toestaat ("Show integration",
    /// brand.github.com/foundations/logo). GitLab: het logomark uit de perskit van GitLab
    /// (gitlab-logo-500-rgb.svg), onveranderd en in volle kleur op licht en donker; een bewuste
    /// keuze van de eigenaar (fork-issue #174), terug te draaien met dit ene geval en de asset.
    /// Azure DevOps: Microsoft staat de Azure-iconen alleen toe in diagrammen en documentatie,
    /// dus een gevuld SF Symbol, even zwaar als de twee logo's.
    var glyph: Glyph {
        switch self {
        case .gitHub: .asset("GitHubMark")
        case .azureDevOps: .system("cloud.circle.fill")
        case .gitLab: .asset("GitLabMark")
        }
    }

    /// Het logo moet zijn eigen kleuren houden: nooit tinten of als template tekenen.
    var glyphKeepsItsColours: Bool {
        if case .asset = glyph { true } else { false }
    }

    /// Hoeveel groter het beeld getekend wordt dan zijn vak, zodat elk teken even groot oogt. Het
    /// bestand van GitLab houdt de vrije ruimte die GitLab eromheen voorschrijft in zijn canvas
    /// (het teken vult 41 procent van de breedte); die ruimte is doorzichtig en valt buiten het
    /// vak, het bestand zelf blijft onveranderd. De Invertocat en een SF Symbol vullen hun vak al.
    var glyphScale: CGFloat {
        switch self {
        case .gitLab: 2.3
        case .gitHub, .azureDevOps: 1
        }
    }
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
    /// het VoiceOver-label waar het icoon zonder tekst staat. In de rij met de plek erbij, als
    /// de dienst die geeft ("Pull request, in de wachtrij, plek 2").
    var glyphLabel: LocalizedStringResource {
        if prStatus == .queued, case .pullRequest(let pr) = self, let position = pr.mergeQueue?.position {
            return "Pull request, in de wachtrij, plek \(position)"
        }
        return prStatus?.spokenName ?? kind.pillText
    }

    /// De pill op de repo-pagina: de status zoals `PRState` hem noemt, en Queued apart zoals de
    /// StateLabel van GitHub. Een draft houdt de pill Open.
    var statePill: (text: LocalizedStringResource, tint: Color)? {
        switch prStatus {
        case .queued?: ("In wachtrij", PRStatus.queued.color)
        case .some: prState.map { ($0.label, $0.color) }
        case nil: nil
        }
    }
}
