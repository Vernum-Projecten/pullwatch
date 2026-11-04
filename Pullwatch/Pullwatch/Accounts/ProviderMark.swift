import AppKit
import PullwatchCore
import SwiftUI

/// Het beeld van een dienst (`ProviderKind.glyph`, bij Gitea `GiteaFlavour.glyph`) in een vierkant
/// vak van `size` punten: de logo's als vectorbeeld, onveranderd (geen tint, geen template; de
/// assetcatalogus kiest de lichte of donkere variant), en het SF Symbol van Azure DevOps even
/// groot. Zo staan alle tekens overal op dezelfde maat. Decoratief: de naam staat er altijd naast.
struct ProviderMark: View {
    let glyph: Glyph
    let scale: CGFloat
    var size: CGFloat

    init(glyph: Glyph, scale: CGFloat, size: CGFloat) {
        self.glyph = glyph
        self.scale = scale
        self.size = size
    }

    init(kind: ProviderKind, size: CGFloat) {
        glyph = kind.glyph
        scale = kind.glyphScale
        self.size = size
    }

    init(flavour: GiteaFlavour, size: CGFloat) {
        glyph = flavour.glyph
        scale = flavour.glyphScale
        self.size = size
    }

    init(account: Account, size: CGFloat) {
        glyph = account.glyph
        scale = account.glyphScale
        self.size = size
    }

    var body: some View {
        glyph.image
            .renderingMode(glyph.keepsItsColours ? .original : .template)
            .resizable()
            .scaledToFit()
            // Groter dan het vak waar het bestand doorzichtige ruimte om het teken heeft (GitLab).
            .frame(width: size * scale, height: size * scale)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    static func menuIcon(for kind: ProviderKind) -> Image {
        menuIcon(glyph: kind.glyph, scale: kind.glyphScale)
    }

    static func menuIcon(for flavour: GiteaFlavour) -> Image {
        menuIcon(glyph: flavour.glyph, scale: flavour.glyphScale)
    }

    /// Voor een menu-item: een menu tekent een plaatje op zijn eigen formaat, dus het logo als
    /// `NSImage` van 16 punten (vector, met de lichte en donkere variant), een SF Symbol zoals het is.
    private static func menuIcon(glyph: Glyph, scale: CGFloat) -> Image {
        switch glyph {
        case .system(let name):
            return Image(systemName: name)
        case .asset(let name):
            guard let logo = NSImage(named: name) else { return Image(systemName: "questionmark") }
            let side: CGFloat = 16
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
