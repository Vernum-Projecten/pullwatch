import AppKit
import SwiftUI

/// Binnenruimte van een rij in het menupaneel; koppen en andere regels krijgen dezelfde
/// inspringing, zodat alles uitlijnt zonder negatieve marges.
enum MenuMetrics {
    static let rowInset: CGFloat = 8
}

/// Welke rij van het menupaneel de aanwijzer nu raakt. Eén waarde voor het hele paneel in
/// plaats van een eigen status per rij: macOS mist bij snel bewegen soms het verlaten van een
/// rij, en dan zouden er twee tegelijk gemarkeerd blijven. Een rij zet zichzelf bij binnenkomen
/// en wist alleen als zij het nog is; bij sluiten of uit focus gaan van het paneel wordt alles
/// gewist (`resetsMenuHover()`).
@Observable
final class MenuHover {
    var row: AnyHashable?
}

extension EnvironmentValues {
    @Entry var menuHover: MenuHover?
}

/// Een rij in het menupaneel, zoals in Bedieningspaneel: bij aanwijzen een zachte, afgeronde
/// markering over de hele breedte, bij klikken iets sterker. De kleur volgt licht en donker
/// via `.primary`; geen animatie bij Beweging verminderen.
struct MenuRowButtonStyle: ButtonStyle {
    let id: AnyHashable

    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration, id: id)
    }

    private struct MenuRow: View {
        let configuration: Configuration
        let id: AnyHashable
        @Environment(\.menuHover) private var hover
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var isHovered: Bool { isEnabled && hover?.row == id }

        var body: some View {
            configuration.label
                .padding(.horizontal, MenuMetrics.rowInset)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Eén vaste vulling waarvan alleen de doorzichtigheid verandert: een getal laat
                // zich vloeiend animeren. Wisselen tussen twee stijlen (doorzichtig en grijs) gaf
                // eerst een felle flits, omdat SwiftUI die niet kan overvloeien.
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.primary)
                        .opacity(highlight)
                        // Alleen deze laag animeert; tekst en symbolen erboven veranderen meteen.
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlight)
                }
                .contentShape(.rect(cornerRadius: 8))
                .onHover { inside in
                    guard let hover else { return }
                    if inside {
                        hover.row = id
                    } else if hover.row == id {
                        hover.row = nil
                    }
                }
        }

        /// Hoe sterk de markering is: niets, aangewezen of ingedrukt.
        private var highlight: Double {
            if configuration.isPressed { return 0.14 }
            return isHovered ? 0.07 : 0
        }
    }
}

/// Een symboolknop in de kop van het menupaneel: bij aanwijzen een kleine ronde markering en
/// het symbool in de gewone tekstkleur. Deelt `MenuHover` met de rijen. Een bredere knop (de
/// agentknop met zijn aantal) krijgt dezelfde markering als capsule; een symbool alleen blijft rond.
struct MenuIconButtonStyle: ButtonStyle {
    let id: AnyHashable

    func makeBody(configuration: Configuration) -> some View {
        MenuIcon(configuration: configuration, id: id)
    }

    private struct MenuIcon: View {
        let configuration: Configuration
        let id: AnyHashable
        @Environment(\.menuHover) private var hover
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @ScaledMetric(relativeTo: .body) private var size = 26

        private var isHovered: Bool { isEnabled && hover?.row == id }

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .imageScale(.large)
                .foregroundStyle(isHovered || configuration.isPressed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(minWidth: size, minHeight: size)
                .background {
                    Capsule().fill(.primary).opacity(highlight)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlight)
                }
                .contentShape(.capsule)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { inside in
                    guard let hover else { return }
                    if inside {
                        hover.row = id
                    } else if hover.row == id {
                        hover.row = nil
                    }
                }
        }

        private var highlight: Double {
            if configuration.isPressed { return 0.16 }
            return isHovered ? 0.08 : 0
        }
    }
}

extension View {
    /// Geeft het paneel één `MenuHover` en wist die als het paneel verdwijnt of zijn focus
    /// verliest, zodat een markering nooit blijft hangen na opnieuw openen.
    func resetsMenuHover(_ hover: MenuHover) -> some View {
        environment(\.menuHover, hover)
            .onDisappear { hover.row = nil }
            .task {
                for await _ in NotificationCenter.default.notifications(named: NSWindow.didResignKeyNotification) {
                    hover.row = nil
                }
            }
    }
}
