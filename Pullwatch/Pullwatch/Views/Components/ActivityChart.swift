import Charts
import PullwatchCore
import SwiftUI

/// De vier reeksen in de activiteitsgrafiek, in de volgorde van de tabbladen op GitHub. Kleur en
/// icoon komen van `PRStatus`, zodat de grafiek dezelfde kleuren heeft als de rest van de app.
private enum ActivitySeries: CaseIterable {
    case opened, draft, merged, closed

    var status: PRStatus {
        switch self {
        case .opened: .open
        case .draft: .draft
        case .merged: .merged
        case .closed: .closed
        }
    }

    var color: Color { status.color }

    func title(saysCompleted: Bool) -> LocalizedStringResource {
        switch self {
        case .opened: "Geopend"
        case .draft: "Draft"
        case .merged: saysCompleted ? "Afgerond" : "Gemerged"
        case .closed: "Gesloten zonder merge"
        }
    }

    /// Geopend en draft samen zijn alle PR's die in de periode geopend zijn: een draft telt niet
    /// ook nog als geopend.
    func count(in bucket: ActivityBucket) -> Int {
        switch self {
        case .opened: bucket.openedReady
        case .draft: bucket.drafts
        case .merged: bucket.merged
        case .closed: bucket.closed
        }
    }
}

/// Per periode één gestapelde staaf: geopend, draft, gemerged en gesloten zonder merge.
struct ActivityChart: View {
    let stats: ActivityStats
    let period: StatsPeriod
    /// Azure DevOps: "Afgerond" in plaats van "Gemerged".
    var saysCompleted = false

    private struct Point: Identifiable {
        let start: Date
        let series: ActivitySeries
        let count: Int
        var id: String { "\(start.timeIntervalSince1970)-\(series)" }
    }

    private var points: [Point] {
        stats.buckets.flatMap { bucket in
            ActivitySeries.allCases.map { Point(start: bucket.start, series: $0, count: $0.count(in: bucket)) }
        }
    }

    /// De grafiek kent een reeks aan zijn vertaalde naam: zo noemen de legenda en VoiceOver de
    /// status, en hangt de betekenis nooit alleen aan de kleur.
    private func name(_ series: ActivitySeries) -> String {
        String(localized: series.title(saysCompleted: saysCompleted))
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Periode", point.start, unit: period.unit),
                y: .value("PR's", point.count)
            )
            .foregroundStyle(by: .value("Soort", name(point.series)))
            .accessibilityLabel(Text(point.series.title(saysCompleted: saysCompleted)))
            .accessibilityValue(Text(point.count, format: .number))
        }
        .chartForegroundStyleScale(domain: ActivitySeries.allCases.map(name), range: ActivitySeries.allCases.map(\.color))
        .chartXAxis {
            AxisMarks(values: .stride(by: period.unit, count: period.axisStride)) { _ in
                AxisGridLine()
                AxisValueLabel(format: period.axisFormat, centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .chartLegend(position: .bottom, alignment: .leading)
    }
}
