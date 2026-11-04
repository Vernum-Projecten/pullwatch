import PullwatchCore
import SwiftUI

/// Een kaart van een dienst in het welkomstvenster: het teken (`ProviderMark`, voor elke dienst
/// even groot), de naam, één regel uitleg en onderaan een knop per plek waar het account kan
/// staan (github.com of GitHub Enterprise, dev.azure.com, gitlab.com of een eigen server).
/// De knoppen zijn gewone systeemknoppen: indrukken, de focusring en Tab tussen de knoppen geeft
/// macOS; Return op een knop met focus kiest hem ook. De kaart licht op onder de muis, en met
/// één knop is de hele kaart klikbaar.
struct ProviderCard: View {
    /// Een knop op de kaart.
    struct Action: Identifiable {
        /// Ook de accessibility identifier, voor de UI-tests.
        let id: String
        let title: Text
        let help: LocalizedStringKey
        let accessibilityLabel: LocalizedStringKey
        let perform: () -> Void
    }

    /// De naam op de kaart, in elke taal hetzelfde.
    let title: String
    /// De tekens van de diensten op de kaart: één, of bij Gitea, Forgejo en Codeberg alle drie.
    let marks: [Mark]
    let subtitle: LocalizedStringKey
    let actions: [Action]
    /// Het deel achter `onboarding.card.` in de accessibility identifier.
    let identifier: String
    @ScaledMetric(relativeTo: .largeTitle) private var markSize = 36.0
    @State private var isHovered = false

    /// Het teken van één dienst (`ProviderMark`).
    struct Mark: Hashable {
        let glyph: Glyph
        let scale: CGFloat
    }

    init(kind: ProviderKind, subtitle: LocalizedStringKey, actions: [Action]) {
        title = kind.name
        marks = [Mark(glyph: kind.glyph, scale: kind.glyphScale)]
        self.subtitle = subtitle
        self.actions = actions
        identifier = kind.rawValue
    }

    /// Een kaart voor diensten die één API delen (Codeberg, Forgejo en Gitea): hun tekens naast
    /// elkaar, elk even groot als het teken op de andere kaarten.
    init(title: String, flavours: [GiteaFlavour], subtitle: LocalizedStringKey, actions: [Action], identifier: String) {
        self.title = title
        marks = flavours.map { Mark(glyph: $0.glyph, scale: $0.glyphScale) }
        self.subtitle = subtitle
        self.actions = actions
        self.identifier = identifier
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ForEach(marks, id: \.self) { mark in
                    ProviderMark(glyph: mark.glyph, scale: mark.scale, size: markSize)
                }
            }
            .padding(.bottom, 4)
            Text(verbatim: title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            // De knoppen onderaan; met minder knoppen blijft het teken bovenaan op één lijn met de andere kaarten.
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                ForEach(actions) { action in
                    Button(action: action.perform) {
                        action.title
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .onKeyPress(.return) {
                        action.perform()
                        return .handled
                    }
                    .help(action.help)
                    .accessibilityLabel(Text(action.accessibilityLabel))
                    .accessibilityIdentifier(action.id)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isHovered ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quaternary), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.separator) }
        .contentShape(.rect(cornerRadius: 12))
        .onTapGesture {
            // Met één knop is de hele kaart die knop; met twee kies je met de knoppen.
            if actions.count == 1 { actions[0].perform() }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier("onboarding.card.\(identifier)")
    }
}
