import PullwatchCore
import SwiftUI

/// De vaste zinnen voor wat Pullwatch niet controleerde omdat een bron uit staat. Ze staan waar
/// anders "actueel" of een lege lijst zou staan: een bron die uit staat lijkt nooit op "in orde".
enum SourceOff {
    /// "Niet gecontroleerd: bron OSV.dev staat uit".
    static func notChecked(_ id: DataSourceID) -> String {
        let name = DataSource.source(id).name
        return String(localized: "Niet gecontroleerd: bron \(name) staat uit", comment: "Naam van een bron die uitgezet is (Instellingen, Bronnen)")
    }

    /// "Versie niet gecontroleerd: bron npm staat uit", voor packages van een register dat uit staat.
    static func versionNotChecked(_ id: DataSourceID) -> String {
        let name = DataSource.source(id).name
        return String(localized: "Versie niet gecontroleerd: bron \(name) staat uit", comment: "Naam van een register dat uitgezet is (Instellingen, Bronnen)")
    }

    /// "Details niet opgehaald: bron GitHub Advisory Database staat uit".
    static func detailsNotFetched(_ id: DataSourceID) -> String {
        let name = DataSource.source(id).name
        return String(localized: "Details niet opgehaald: bron \(name) staat uit", comment: "Naam van een bron die uitgezet is (Instellingen, Bronnen)")
    }

    /// De zin voor een bron uit de groep Versies: een register over versies van packages, een
    /// releasebron (endoflife.date, swift.org) over runtimes.
    static func versionsText(_ id: DataSourceID) -> String {
        isRegistry(id) ? versionNotChecked(id) : notChecked(id)
    }

    static func isRegistry(_ id: DataSourceID) -> Bool {
        id != .endOfLife && id != .swiftOrg && DataSource.source(id).group == .versions
    }

    /// De zin voor een eigen package waarvan de nieuwste versie niet uit het eigen register kwam;
    /// nil als die wel gelezen is. Nooit "actueel": de bron staat uit of het account mag niet lezen.
    static func inHouseNotChecked(_ inHouse: InHousePackage) -> String? {
        switch inHouse.status {
        case .checked: nil
        case .sourceOff: notChecked(.packageRegistries)
        case .needsPermission:
            String(localized: "Niet gecontroleerd: geen toegang tot het packageregister van dit account",
                   comment: "Een eigen package; het token van het account mist het recht om het register te lezen")
        }
    }

    /// Wat er voor een eigen package nodig is om het te controleren (de reden van de dienst); nil
    /// als er niets ontbreekt.
    static func inHouseHelp(_ inHouse: InHousePackage) -> String? {
        if case .needsPermission(let reason) = inHouse.status, !reason.isEmpty { return reason }
        return inHouseNotChecked(inHouse)
    }

    /// Het register achter een `PackageSummary.id` ("ecosysteem:naam") als dat in `disabled` staat.
    static func registry(ofPackage id: String, in disabled: Set<DataSourceID>) -> DataSourceID? {
        guard let colon = id.firstIndex(of: ":"),
              let registry = DataSourceID.registry(ecosystem: String(id[..<colon])),
              disabled.contains(registry) else { return nil }
        return registry
    }
}

extension RepoVersions {
    /// De bronnen die voor deze repo uit stonden, in de volgorde van het tabblad Bronnen.
    var skippedInOrder: [DataSourceID] {
        DataSource.all.map(\.id).filter(isUnchecked)
    }

    /// De overgeslagen bronnen uit de groep Versies (registers en releasebronnen).
    var skippedVersionSources: [DataSourceID] {
        skippedInOrder.filter { DataSource.source($0).group == .versions }
    }

    /// De bron van de beveiligingsgegevens van de dienst, als die uit stond.
    var skippedSecuritySource: DataSourceID? {
        [DataSourceID.gitHubSecurity, .azureDevOpsAdvancedSecurity].first(where: isUnchecked)
    }

    /// De releasebron van dit onderdeel, als die uit stond.
    func skippedReleaseSource(of component: ComponentVersion) -> DataSourceID? {
        let id = DataSourceID.releases(product: component.product)
        return isUnchecked(id) ? id : nil
    }
}

/// Een regel "Niet gecontroleerd: bron … staat uit" in een lijst.
struct SourceOffText: View {
    let text: String
    /// Oranje bij kwetsbaarheden en beveiliging, zoals `vulnerabilityError`; anders `.secondary`.
    var isWarning = false

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "slash.circle")
        }
        .foregroundStyle(isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
    }
}
