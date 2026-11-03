import PullwatchCore
import SwiftUI

/// Menu "Ga" met sneltoetsen: ⌘1–5 voor de onderdelen, ⌘F zoeken, ⌘R verversen, ⌘[ terug, ⌘O openen.
struct ShortcutCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Ga") {
            ForEach(Array([MainSection.pullRequests, .tags, .repos, .versions, .stats].enumerated()), id: \.element) { index, section in
                Button(section.title) {
                    model.mainSection = section
                    model.openMainWindow?()
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button("Zoeken") { model.searchFocusRequest += 1 }
                .keyboardShortcut("f")
            Button("Verversen") { model.refreshCurrent() }
                .keyboardShortcut("r")
            Button("Terug") { model.goBack() }
                .keyboardShortcut("[")
                .disabled(model.selectedRepoId == nil)
            Button("Open in browser") { model.openInBrowserRequest += 1 }
                .keyboardShortcut("o")
        }
    }
}

/// Geeft het zoekveld de focus bij ⌘F.
struct SearchFocus: ViewModifier {
    let model: AppModel
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: model.searchFocusRequest) { isFocused = true }
    }
}

extension View {
    func searchFocus(_ model: AppModel) -> some View {
        modifier(SearchFocus(model: model))
    }
}

/// Label boven een lijst voor een filter dat van elders kwam, met ✕ om het weg te halen.
struct FilterChip: View {
    let title: String
    let systemImage: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Filter weghalen")
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}
