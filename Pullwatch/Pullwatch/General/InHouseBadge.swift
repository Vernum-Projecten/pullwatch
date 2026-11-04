import PullwatchCore
import SwiftUI

/// "In-house" naast de naam van een dependency die een gevolgde repository zelf publiceert, als
/// link naar die repository (of naar het package in het eigen register). Klein en secundair: het
/// zegt waar de nieuwste versie vandaan komt, de status staat in zijn eigen kolom. Neemt alleen
/// waarden, want hij staat in tabelcellen (Afhankelijkheden, het tabblad Packages van een repo).
struct InHouseBadge: View {
    /// Een gebouw: van je eigen organisatie.
    static let symbol = "building.2"

    let inHouse: InHousePackage

    var body: some View {
        if let link = inHouse.link {
            Link(destination: link) {
                InHouseLabel()
            }
            .help(Text("Gepubliceerd door \(inHouse.source): de nieuwste versie komt uit je eigen register.",
                       comment: "Repository of project dat een eigen package publiceert"))
            .accessibilityLabel(Text("In-house, gepubliceerd door \(inHouse.source)", comment: "Repository die een eigen package publiceert"))
        } else {
            InHouseLabel()
                .help(Text("Gepubliceerd door \(inHouse.source): de nieuwste versie komt uit je eigen register.",
                           comment: "Repository of project dat een eigen package publiceert"))
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
