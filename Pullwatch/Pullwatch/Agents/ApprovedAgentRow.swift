import SwiftUI

/// Een agent onder "Toegestane agents": een toegestane met een knop om hem van de lijst te halen,
/// of een die wacht met Sta toe en Sta niet toe. Leest geen model; naam en knoppen komen binnen.
struct ApprovedAgentRow: View {
    enum Status {
        case approved(remove: () -> Void)
        case waiting(allow: () -> Void, deny: () -> Void)
    }

    let displayName: String
    let status: Status

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: displayName)
                if case .waiting = status {
                    Text("Wacht op toestemming")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            switch status {
            case .approved(let remove):
                Button(action: remove) {
                    Label("Verwijder \(displayName)", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Haal \(displayName) van de lijst; Pullwatch vraagt het dan opnieuw")
            case .waiting(let allow, let deny):
                Button("Sta niet toe", action: deny)
                    .help("Koppel \(displayName) los, zonder iets te onthouden")
                Button("Sta toe", action: allow)
                    .buttonStyle(.borderedProminent)
                    .help("\(displayName) mag Pullwatch gebruiken")
            }
        }
    }
}
