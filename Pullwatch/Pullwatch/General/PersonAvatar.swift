import SwiftUI

/// Een kleine ronde foto met een rand in de achtergrondkleur, zodat de foto's in een stapel
/// los van elkaar te zien zijn. Zonder foto het persoonssymbool. Leest niets uit de omgeving, dus
/// bruikbaar in een tabelcel.
struct PersonAvatar: View {
    let url: URL?
    var size: CGFloat = 16

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.background, in: .circle)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(.background, lineWidth: 1.5) }
        .accessibilityHidden(true)
    }
}
