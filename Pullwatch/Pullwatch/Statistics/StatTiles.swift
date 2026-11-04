import Charts
import PullwatchCore
import SwiftUI

/// De getallen boven de grafiek: eerst de vier statussen in de volgorde en kleuren van GitHub,
/// dan doorlooptijd en auteurs.
struct StatTiles: View {
    let stats: ActivityStats
    let saysCompleted: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatTile(label: "PR's geopend deze periode", status: .open) { Text(stats.openedThisPeriod, format: .number) }
            StatTile(label: "open drafts nu", status: .draft) { Text(stats.openDrafts, format: .number) }
            StatTile(label: saysCompleted ? "afgerond deze periode" : "gemerged deze periode", status: .merged) {
                Text(stats.mergedThisPeriod, format: .number)
            }
            StatTile(label: "gesloten zonder merge deze periode", status: .closed) { Text(stats.closedThisPeriod, format: .number) }
            StatTile(label: "mediane doorlooptijd") {
                if let medianLeadTime = stats.medianLeadTime {
                    LeadTimeText(interval: medianLeadTime)
                } else {
                    Text("onbekend")
                }
            }
            StatTile(label: "actieve auteurs deze periode") { Text(stats.activeAuthors, format: .number) }
        }
    }
}

/// "5 uur", "1,8 dagen".
private struct LeadTimeText: View {
    let interval: TimeInterval

    var body: some View {
        if interval < 86_400 {
            Text("\(Int((interval / 3600).rounded())) uur")
        } else {
            Text("\((interval / 86_400).formatted(.number.precision(.fractionLength(1)))) dagen")
        }
    }
}

/// Eén tegel met een getal en zijn label, met het icoon van de PR-status ervoor.
private struct StatTile<Value: View>: View {
    let label: LocalizedStringResource
    /// De PR-status waar het getal over gaat: het icoon in de kleur van GitHub staat ervoor.
    var status: PRStatus? = nil
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let status {
                    status.glyph.image
                        .font(.title3)
                        .foregroundStyle(status.color)
                }
                value.font(.title2.bold()).monospacedDigit()
            }
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
