import Charts
import PullwatchCore
import SwiftUI

extension StatsPeriod {
    var title: LocalizedStringKey {
        switch self {
        case .week: "Week"
        case .month: "Maand"
        case .year: "Jaar"
        }
    }

    var unit: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .week: .dateTime.day().month(.abbreviated)
        case .month: .dateTime.month(.abbreviated)
        case .year: .dateTime.year()
        }
    }
}

/// PR-activiteit over alle gevolgde repo's: per periode, per auteur en per repo.
struct StatsView: View {
    let model: AppModel

    @AppStorage("statsPeriod") private var period: StatsPeriod = .month
    @AppStorage("statsHideBots") private var hideBots = true
    @State private var group: HistoryGroup.ID?
    @State private var author: String?

    private var accountNames: [UUID: String] {
        Dictionary(model.config.accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let repoId = model.statsRepoId
        let filter = ActivityFilter(group: group, author: author, repoId: repoId, hideBots: hideBots)
        let stats = ActivityStats.compute(history: model.history, period: period, filter: filter)
        // Auteurskeuze zonder auteursfilter, anders blijft alleen de gekozen auteur over.
        let authors = author == nil ? stats.authors
            : ActivityStats.compute(history: model.history, period: period,
                                    filter: ActivityFilter(group: group, repoId: repoId, hideBots: hideBots)).authors
        let groups = model.history.groups(.pullRequest, accountNames: accountNames)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Picker("Periode", selection: $period) {
                        ForEach(StatsPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Picker("Project", selection: $group) {
                        Text("Alle projecten").tag(HistoryGroup.ID?.none)
                        ForEach(groups) { Text($0.name).tag(HistoryGroup.ID?.some($0.id)) }
                    }
                    .fixedSize()
                    Picker("Auteur", selection: $author) {
                        Text("Alle auteurs").tag(String?.none)
                        ForEach(authors) { Text($0.name).tag(String?.some($0.name)) }
                    }
                    .fixedSize()
                    Toggle("Bots verbergen", isOn: $hideBots)
                    Spacer()
                }
                if let repoId, let summary = model.repoSummaries.first(where: { $0.id == repoId }) {
                    HStack(spacing: 6) {
                        Button {
                            model.showRepo(id: repoId)
                        } label: {
                            Label(summary.repo, systemImage: "folder")
                        }
                        .buttonStyle(.link)
                        .help("Terug naar de pagina van deze repo")
                        Button {
                            model.statsRepoId = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Toon alle repo's")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 10) {
                    StatTile(value: "\(stats.openedThisPeriod)", label: String(localized: "PR's geopend deze periode"))
                    StatTile(value: "\(stats.mergedThisPeriod)", label: String(localized: "gemerged deze periode"))
                    StatTile(value: stats.medianLeadTime.map(Self.duration) ?? "—", label: String(localized: "mediane doorlooptijd"))
                    StatTile(value: "\(stats.activeAuthors)", label: String(localized: "actieve auteurs deze periode"))
                }

                ActivityChart(stats: stats, period: period)
                    .frame(height: 220)

                HStack(alignment: .top, spacing: 20) {
                    RankingList(title: "Auteurs", items: Array(stats.authors.prefix(10)), selected: author) { name in
                        author = author == name ? nil : name
                    }
                    RankingList(title: "Drukste repo's", items: Array(stats.repos.prefix(10)), selected: nil) { name in
                        if let summary = model.repoSummaries.first(where: { $0.repo == name }) {
                            model.showRepo(id: summary.id)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    /// "5 uur", "1,8 dagen".
    static func duration(_ interval: TimeInterval) -> String {
        if interval < 86_400 {
            return String(localized: "\(Int((interval / 3600).rounded())) uur")
        }
        return String(localized: "\((interval / 86_400).formatted(.number.precision(.fractionLength(1)))) dagen")
    }
}

/// Geopend naast gemerged per periode.
struct ActivityChart: View {
    let stats: ActivityStats
    let period: StatsPeriod

    private struct Point: Identifiable {
        let start: Date
        let series: String
        let count: Int
        var id: String { "\(start.timeIntervalSince1970)-\(series)" }
    }

    private var points: [Point] {
        stats.buckets.flatMap { bucket in
            [Point(start: bucket.start, series: String(localized: "Geopend"), count: bucket.opened),
             Point(start: bucket.start, series: String(localized: "Gemerged"), count: bucket.merged)]
        }
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Periode", point.start, unit: period.unit),
                y: .value("PR's", point.count)
            )
            .foregroundStyle(by: .value("Soort", point.series))
            .position(by: .value("Soort", point.series))
        }
        .chartForegroundStyleScale([String(localized: "Geopend"): Color.blue, String(localized: "Gemerged"): Color.green])
        .chartXAxis {
            AxisMarks(values: stats.buckets.map(\.start)) { _ in
                AxisValueLabel(format: period.axisFormat, centered: true)
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

private struct RankingList: View {
    let title: LocalizedStringKey
    let items: [RankedName]
    let selected: String?
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
            if items.isEmpty {
                Text("Geen PR's in deze periode").foregroundStyle(.secondary).font(.callout)
            }
            let top = items.first?.count ?? 1
            ForEach(items) { item in
                Button {
                    action(item.name)
                } label: {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .fontWeight(item.name == selected ? .bold : .regular)
                            .lineLimit(1)
                            .frame(width: 170, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule().fill(Color.accentColor.opacity(0.8))
                                .frame(width: max(4, proxy.size.width * CGFloat(item.count) / CGFloat(max(top, 1))))
                        }
                        .frame(height: 8)
                        Text("\(item.count)").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
