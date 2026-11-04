import AppKit
import PullwatchCore
import SwiftUI

/// Het beeld van een dienst (`ProviderKind.glyph`) in een vierkant vak van `size` punten: het
/// GitHub- en het GitLab-logo als vectorbeeld, onveranderd (geen tint, geen template; de
/// assetcatalogus kiest de lichte of donkere variant), en het SF Symbol van Azure DevOps even
/// groot. Zo staan de drie tekens overal op dezelfde maat. Decoratief: de naam staat er altijd naast.
struct ProviderMark: View {
    let kind: ProviderKind
    var size: CGFloat

    var body: some View {
        kind.glyph.image
            .renderingMode(kind.glyphKeepsItsColours ? .original : .template)
            .resizable()
            .scaledToFit()
            // Groter dan het vak waar het bestand doorzichtige ruimte om het teken heeft (GitLab).
            .frame(width: size * kind.glyphScale, height: size * kind.glyphScale)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// Voor een menu-item: een menu tekent een plaatje op zijn eigen formaat, dus het logo als
    /// `NSImage` van 16 punten (vector, met de lichte en donkere variant), een SF Symbol zoals het is.
    static func menuIcon(for kind: ProviderKind) -> Image {
        switch kind.glyph {
        case .system(let name):
            return Image(systemName: name)
        case .asset(let name):
            guard let logo = NSImage(named: name) else { return Image(systemName: "questionmark") }
            let side: CGFloat = 16
            let scale = kind.glyphScale
            guard scale != 1 else {
                let copy = logo.copy() as? NSImage ?? logo
                copy.size = NSSize(width: side, height: side * logo.size.height / max(logo.size.width, 1))
                return Image(nsImage: copy)
            }
            // Het teken op dezelfde maat als de andere: het bestand groter, gecentreerd, getekend
            // bij elke weergave (dus scherp op elk scherm); de doorzichtige rand valt erbuiten.
            let icon = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                let drawn = rect.insetBy(dx: -rect.width * (scale - 1) / 2, dy: -rect.height * (scale - 1) / 2)
                logo.draw(in: drawn)
                return true
            }
            return Image(nsImage: icon)
        }
    }
}
