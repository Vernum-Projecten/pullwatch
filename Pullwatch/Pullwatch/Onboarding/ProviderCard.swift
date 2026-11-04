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

    let kind: ProviderKind
    let subtitle: LocalizedStringKey
    let actions: [Action]
    @ScaledMetric(relativeTo: .largeTitle) private var markSize = 36.0
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            ProviderMark(kind: kind, size: markSize)
                .padding(.bottom, 4)
            Text(verbatim: kind.name)
                .font(.headline)
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
        .accessibilityLabel(Text(verbatim: kind.name))
        .accessibilityIdentifier("onboarding.card.\(kind.rawValue)")
    }
}
