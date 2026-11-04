import AppKit
import PullwatchCore
import SwiftUI

/// De tellingen bovenaan de repo-pagina, elk een filter: kwetsbaarheden, verouderde runtimes,
/// packages die je nu kunt bijwerken en die geblokkeerd zijn, en waarmee vergeleken is. In een
/// smal venster alleen symbool en aantal.
struct RepoCheckSummaryBar: View {
    let summary: RepoCheckSummary
    let isActive: (RepoPage.SummaryFilter) -> Bool
    let apply: (RepoPage.SummaryFilter) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                SummaryCounters(summary: summary, compact: false, isActive: isActive, apply: apply)
                Spacer(minLength: 0)
                ComparedWithLabel(tag: summary.comparedWith)
            }
            VStack(alignment: .leading, spacing: 4) {
                SummaryCounters(summary: summary, compact: false, isActive: isActive, apply: apply)
                ComparedWithLabel(tag: summary.comparedWith)
            }
            VStack(alignment: .leading, spacing: 4) {
                SummaryCounters(summary: summary, compact: true, isActive: isActive, apply: apply)
                ComparedWithLabel(tag: summary.comparedWith)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// De tellingen van de samenvatting, elk een knop die op dat filter zet.
private struct SummaryCounters: View {
    let summary: RepoCheckSummary
    let compact: Bool
    let isActive: (RepoPage.SummaryFilter) -> Bool
    let apply: (RepoPage.SummaryFilter) -> Void

    var body: some View {
        HStack(spacing: 6) {
            SummaryCounter(title: "Kwetsbaarheden", count: summary.vulnerabilities, symbol: "exclamationmark.shield.fill",
                           tint: .red, compact: compact, isOn: isActive(.vulnerabilities)) { apply(.vulnerabilities) }
            SummaryCounter(title: "Verouderd", count: summary.outdated, symbol: "clock.badge.exclamationmark.fill",
                           tint: .orange, compact: compact, isOn: isActive(.outdated)) { apply(.outdated) }
            SummaryCounter(title: "Kan bijwerken", count: summary.canUpdate, symbol: UpdateCategory.canUpdateNow.symbol,
                           tint: UpdateCategory.canUpdateNow.color, compact: compact, isOn: isActive(.canUpdate)) { apply(.canUpdate) }
            SummaryCounter(title: "Geblokkeerd", count: summary.blocked, symbol: UpdateCategory.blocked.symbol,
                           tint: UpdateCategory.blocked.color, compact: compact, isOn: isActive(.blocked)) { apply(.blocked) }
        }
    }
}

/// Eén teller: symbool, soort en aantal, als knop die het filter aan- en uitzet.
private struct SummaryCounter: View {
    let title: LocalizedStringResource
    let count: Int
    let symbol: String
    let tint: Color
    let compact: Bool
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Label {
                if !compact { Text(title) }
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(count > 0 ? tint : Color.secondary)
            }
        }
        .toggleStyle(.button)
        .disabled(count == 0)
        .help(Text(title))
        .accessibilityLabel(Text("\(String(localized: title)): \(count)", comment: "Soort bevinding, aantal"))
    }
}

/// "Vergeleken met v1.2.0": de laatste release waarmee de controle vergelijkt.
private struct ComparedWithLabel: View {
    let tag: String?

    var body: some View {
        if let tag {
            Text("Vergeleken met \(tag)", comment: "Tagnaam van de laatste release")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(Text("Het symbool in de kolom In release zegt of een kwetsbaarheid ook in deze tag zit"))
        }
    }
}
