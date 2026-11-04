import SwiftUI

/// De opdracht of JSON voor één client onder "Een agent instellen": waar het heen moet met een
/// kopieerknop, en de tekst zelf in een vlak om te selecteren, die afbreekt in plaats van af te
/// kappen. Leest geen model; de tekst komt binnen.
struct AgentSetupRow: View {
    let name: String
    let setup: String
    let placement: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(placement)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                CopyButton(title: "Kopieer", help: "Kopieer wat \(name) nodig heeft om Pullwatch te gebruiken") { setup }
                    .controlSize(.small)
            }
            Text(verbatim: setup)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 6))
                .accessibilityLabel(Text("Instelling voor \(name)"))
                .accessibilityValue(Text(verbatim: setup))
        }
        .padding(.vertical, 2)
    }
}
