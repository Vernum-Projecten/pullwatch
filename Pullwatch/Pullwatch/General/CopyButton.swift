import AppKit
import SwiftUI

/// Kopieert tekst naar het klembord en toont 1,5 seconde een vinkje als bevestiging. De tekst
/// wordt pas bij de klik gemaakt, niet bij elke keer tekenen.
struct CopyButton: View {
    let title: LocalizedStringKey
    let help: LocalizedStringKey
    /// Alleen het icoon, klein en zonder rand: voor achter een kopje.
    var iconOnly = false
    let text: () -> String

    @State private var copied = false

    var body: some View {
        let button = Button {
            Pasteboard.copy(text())
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(title, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .help(help)
        if iconOnly {
            button
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
        } else {
            button
        }
    }
}

/// De knop achter een kopje van de repo-pagina: kopieert dat kopje als opdracht voor een AI-agent
/// (`AgentBrief`, Markdown in het Engels).
struct AgentBriefButton: View {
    let brief: () -> String

    var body: some View {
        CopyButton(
            title: "Kopieer voor een AI-agent",
            help: "Kopieer dit kopje als opdracht in Markdown voor een AI-agent",
            iconOnly: true,
            text: brief
        )
    }
}
