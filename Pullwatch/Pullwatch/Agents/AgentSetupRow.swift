import SwiftUI

/// Eén client onder "Een agent instellen": naam, de opdracht of JSON om te selecteren, waar die
/// heen moet, en een kopieerknop. Leest geen model; de tekst komt binnen.
struct AgentSetupRow: View {
    let name: String
    let setup: String
    let placement: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: name)
                    .fontWeight(.medium)
                Text(placement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(
                    title: "Kopieer voor \(name)",
                    help: "Kopieer wat \(name) nodig heeft om Pullwatch te gebruiken",
                    iconOnly: true
                ) { setup }
            }
            Text(verbatim: setup)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
        }
        .padding(.vertical, 2)
    }
}
