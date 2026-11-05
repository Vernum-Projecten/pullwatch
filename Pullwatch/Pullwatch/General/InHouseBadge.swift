import PullwatchCore
import SwiftUI

/// "In-house" naast de naam van een dependency die een gevolgde repository zelf publiceert, als
/// link naar die repository (of naar het package in het eigen register). Klein en secundair: het
/// zegt wie het publiceert en of de nieuwste versie uit het eigen register komt, de status staat
/// in zijn eigen kolom. Neemt alleen waarden, want hij staat in tabelcellen (Afhankelijkheden, het
/// tabblad Packages van een repo).
struct InHouseBadge: View {
    /// Een gebouw: van je eigen organisatie.
    static let symbol = "building.2"

    let inHouse: InHousePackage

    /// De hint bij een publiek package waarvan een account een package met dezelfde naam
    /// publiceert, dat deze repo niet gebruikt (`PackageMetadata.alsoPublishedBy`).
    static func alsoPublished(_ namesake: InHousePackage) -> Text {
        Text("Ook gepubliceerd door \(namesake.source) (hier niet gebruikt)",
             comment: "Repository of project dat een package met dezelfde naam publiceert; deze repo gebruikt het publieke package")
    }

    /// `alsoPublished` als tooltip, of niets.
    static func alsoPublishedHelp(_ namesake: InHousePackage?) -> Text {
        namesake.map(alsoPublished) ?? Text(verbatim: "")
    }

    /// De tooltip volgt de stand: alleen `.checked` zegt dat de nieuwste versie uit je eigen
    /// register komt; anders wie het publiceert en waarom het niet gecontroleerd is, met de reden
    /// van `SourceOff.inHouseNotChecked`. Elke zin is één string, zodat elke taal zijn eigen
    /// zinsbouw krijgt. `bundle` laat de tests een taal kiezen.
    static func help(_ inHouse: InHousePackage, bundle: Bundle = .main) -> String {
        let source = inHouse.source
        return switch inHouse.status {
        case .checked:
            String(localized: "Gepubliceerd door \(source): de nieuwste versie komt uit je eigen register.", bundle: bundle,
                   comment: "Repository of project dat een eigen package publiceert")
        case .sourceOff:
            String(localized: "Gepubliceerd door \(source), niet gecontroleerd: bron Packageregisters van je accounts staat uit.", bundle: bundle,
                   comment: "Repository of project dat een eigen package publiceert; de bron Packageregisters van je accounts (Instellingen, Bronnen) staat uit")
        case .needsPermission:
            String(localized: "Gepubliceerd door \(source), niet gecontroleerd: geen toegang tot het packageregister van dit account.", bundle: bundle,
                   comment: "Repository of project dat een eigen package publiceert; het token van het account mist het recht om het register te lezen")
        case .readFailed:
            String(localized: "Gepubliceerd door \(source), niet gecontroleerd: het packageregister van dit account gaf geen nieuwste versie.", bundle: bundle,
                   comment: "Repository of project dat een eigen package publiceert; het lezen van de versies uit het eigen register mislukte")
        case .unconfirmed:
            String(localized: "Gepubliceerd door \(source), niet gecontroleerd: het lockbestand haalt dit package uit je eigen register, maar dat register noemde het niet.", bundle: bundle,
                   comment: "Repository of project dat een eigen package publiceert volgens het lockbestand; het register van het account kon niet gelezen worden of noemde het package niet")
        }
    }

    var body: some View {
        if let link = inHouse.link {
            Link(destination: link) {
                InHouseLabel()
            }
            .help(Text(verbatim: Self.help(inHouse)))
            .accessibilityLabel(Text("In-house, gepubliceerd door \(inHouse.source)", comment: "Repository die een eigen package publiceert"))
        } else {
            InHouseLabel()
                .help(Text(verbatim: Self.help(inHouse)))
                .accessibilityLabel(Text("In-house, gepubliceerd door \(inHouse.source)", comment: "Repository die een eigen package publiceert"))
        }
    }
}

/// Het woord met zijn symbool, in de kleine secundaire stijl van een bijschrift.
private struct InHouseLabel: View {
    var body: some View {
        Label("In-house", systemImage: InHouseBadge.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}
