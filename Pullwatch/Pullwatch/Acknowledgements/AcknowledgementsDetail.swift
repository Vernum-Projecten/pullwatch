import SwiftUI

/// Rechts in Erkenningen: naam, versie, licentie en website van het gekozen onderdeel, en daaronder
/// de volledige teksten (licentie, NOTICE) in een vaste-breedteletter, selecteerbaar. De teksten
/// blijven in hun oorspronkelijke Engels.
struct AcknowledgementsDetail: View {
    let component: Acknowledgement?
    let texts: [LicenseText]
    let isMissing: Bool

    var body: some View {
        if let component {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: component.name)
                            .font(.title2.weight(.semibold))
                        Text("Versie \(component.version)", comment: "Versie van een onderdeel in Erkenningen")
                            .foregroundStyle(.secondary)
                        Text("Licentie: \(component.license)", comment: "SPDX-licentie van een onderdeel in Erkenningen")
                            .foregroundStyle(.secondary)
                        Link("Website", destination: component.homepage)
                    }
                    .textSelection(.enabled)
                    ForEach(texts) { text in
                        VStack(alignment: .leading, spacing: 8) {
                            Divider()
                            Text(verbatim: text.file)
                                .font(.headline)
                            Text(verbatim: text.text)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            // Geen eigen titel: het venster heet Erkenningen, zoals in Apple's eigen apps, en de
            // naam van het onderdeel staat al als kop bovenaan.
        } else if isMissing {
            ContentUnavailableView("De erkenningen ontbreken in deze build", systemImage: "exclamationmark.triangle")
        } else {
            ContentUnavailableView("Kies een onderdeel", systemImage: "doc.text")
        }
    }
}
