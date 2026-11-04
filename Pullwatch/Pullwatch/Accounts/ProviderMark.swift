import AppKit
import PullwatchCore
import SwiftUI

/// Het beeld van een dienst (`ProviderKind.glyph`) op een vaste hoogte: een SF Symbol op die
/// lettergrootte, het GitHub-logo als vectorbeeld van die hoogte, onveranderd (geen tint, geen
/// template; de assetcatalogus kiest zwart of wit bij de weergave). Decoratief: de naam staat
/// er altijd naast.
struct ProviderMark: View {
    let kind: ProviderKind
    var size: CGFloat

    var body: some View {
        Group {
            switch kind.glyph {
            case .system(let name):
                Image(systemName: name).font(.system(size: size))
            case .asset(let name):
                Image(decorative: name)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: size)
            }
        }
        .accessibilityHidden(true)
    }

    /// Voor een menu-item: een menu tekent een plaatje op zijn eigen formaat, dus het logo als
    /// `NSImage` van 16 punten (vector, met de lichte en donkere variant), een SF Symbol zoals het is.
    static func menuIcon(for kind: ProviderKind) -> Image {
        switch kind.glyph {
        case .system(let name):
            return Image(systemName: name)
        case .asset(let name):
            guard let logo = NSImage(named: name)?.copy() as? NSImage else { return Image(systemName: "questionmark") }
            logo.size = NSSize(width: 16, height: 16 * logo.size.height / max(logo.size.width, 1))
            return Image(nsImage: logo)
        }
    }
}
