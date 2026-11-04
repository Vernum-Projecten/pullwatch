import SwiftUI

/// Een rij in de zijbalk van Erkenningen: naam, versie en licentie. Leest geen model uit de
/// environment (een rij van een `List`), het venster geeft het onderdeel mee.
struct AcknowledgementRow: View {
    let component: Acknowledgement

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: component.name)
            Text("Versie \(component.version)", comment: "Versie van een onderdeel in Erkenningen")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: component.license)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .tag(component.id)
    }
}
