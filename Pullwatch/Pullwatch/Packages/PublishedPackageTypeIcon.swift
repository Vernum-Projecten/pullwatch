import PullwatchCore
import SimpleIconsSwiftUI
import SwiftUI

/// Het teken van een soort package: het logo van het ecosysteem uit Simple Icons waar dat er is,
/// anders het SF Symbol. Het logo krijgt de maat van een symbool in het lettertype eromheen (een
/// verborgen symbool geeft de maat) en tekent in de voorgrondstijl, zodat het tussen de andere
/// symbolen past. Neemt alleen een waarde: het staat in een cel van de tabel
/// (`CellEnvironmentTests`).
struct PublishedPackageTypeIcon: View {
    let type: PublishedPackageType

    var body: some View {
        if let icon = type.simpleIcon {
            Image(systemName: "square")
                .hidden()
                .overlay {
                    SimpleIconView(icon)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(type.text)
                .accessibilityAddTraits(.isImage)
        } else {
            Image(systemName: type.symbol)
                .accessibilityLabel(type.text)
        }
    }
}
