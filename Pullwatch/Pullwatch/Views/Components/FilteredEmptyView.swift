import AppKit
import PullwatchCore
import SwiftUI

/// Niets te zien door een filter of zoekterm, met een knop om ze te wissen.
struct FilteredEmptyView: View {
    let searchText: String
    let clear: () -> Void

    var body: some View {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView {
                Label("Niets met dit filter", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Wis filters", action: clear)
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }
}
