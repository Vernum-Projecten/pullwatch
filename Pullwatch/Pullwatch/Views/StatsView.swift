import Charts
import PullwatchCore
import SwiftUI

extension StatsPeriod {
    var title: LocalizedStringResource {
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

    /// Om de hoeveel periodes een label op de as komt: twaalf weken passen niet naast elkaar.
    var axisStride: Int {
        switch self {
        case .week: 2
        case .month, .year: 1
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

/// PR-activiteit over alle gevolgde repo's (of één repo): per periode, per auteur en per repo.
struct StatsView: View {
    let model: AppModel
    /// Alleen deze repo (`RepoSummary.id`), vanaf de repo-pagina; nil voor alles.
    var repoId: String? = nil

    @AppStorage("statsPeriod") private var period: StatsPeriod = .month
    @AppStorage("statsHideBots") private var hideBots = true
    @AppStorage("statsCountCoAuthors") private var countCoAuthors = false
    @State private var group: HistoryGroup.ID?
    @State private var author: String?

    private var repoSummary: RepoSummary? { repoId.flatMap { model.repoSummariesById[$0] } }

    var body: some View {
        let filter = ActivityFilter(group: group, author: author, repoId: repoId, hideBots: hideBots, countCoAuthors: countCoAuthors)
        let stats = model.activityStats(period: period, filter: filter)
        // Auteurskeuze zonder auteursfilter, anders blijft alleen de gekozen auteur over.
        let withoutAuthor = ActivityFilter(group: group, repoId: repoId, hideBots: hideBots, countCoAuthors: countCoAuthors)
        let authors = author == nil ? stats.authors : model.activityStats(period: period, filter: withoutAuthor).authors

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatTiles(
                    opened: stats.openedThisPeriod,
                    merged: stats.mergedThisPeriod,
                    medianLeadTime: stats.medianLeadTime,
                    activeAuthors: stats.activeAuthors
                )
                if let author {
                    Button {
                        model.showHistory(.pullRequest, author: author, repo: repoSummary.map { HistoryRepo(accountId: $0.accountId, repo: $0.repo) })
                    } label: {
                        Label {
                            Text("Toon de PR's van \(author)")
                        } icon: {
                            ItemKind.pullRequest.glyph.image
                        }
                    }
                    .buttonStyle(.link)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Geopend en gemerged").font(.headline)
                    ActivityChart(stats: stats, period: period)
                        .frame(height: 220)
                }
                HStack(alignment: .top, spacing: 24) {
                    RankingChart(title: countCoAuthors ? "Auteurs en co-auteurs" : "Auteurs", items: Array(stats.authors.prefix(10)), selected: author) { name in
                        author = author == name ? nil : name
                    }
                    if repoId == nil {
                        RankingChart(title: "Drukste repo's", items: Array(stats.repos.prefix(10)), selected: nil) { name in
                            if let summary = model.repoSummaries.first(where: { $0.repo == name }) {
                                model.showRepo(id: summary.id)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text("Statistieken"))
        .navigationSubtitle(repoSummary.map { Text(verbatim: $0.repo) } ?? Text("Alle gevolgde repo's"))
        .toolbar {
            StatsToolbar(
                period: $period,
                group: $group,
                author: $author,
                hideBots: $hideBots,
                countCoAuthors: $countCoAuthors,
                groups: repoId == nil ? model.sidebar.pullRequestGroups : [],
                authors: authors
            )
        }
    }
}

/// Periode, project, auteur en bots in de knoppenbalk.
private struct StatsToolbar: ToolbarContent {
    @Binding var period: StatsPeriod
    @Binding var group: HistoryGroup.ID?
    @Binding var author: String?
    @Binding var hideBots: Bool
    @Binding var countCoAuthors: Bool
    let groups: [HistoryGroup]
    let authors: [RankedName]

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Periode", selection: $period) {
                ForEach(StatsPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Periode van de grafiek")
        }
        ToolbarItemGroup {
            if !groups.isEmpty {
                Picker("Project", selection: $group) {
                    Text("Alle projecten").tag(HistoryGroup.ID?.none)
                    Divider()
                    ForEach(groups) { Text(verbatim: $0.name).tag(HistoryGroup.ID?.some($0.id)) }
                }
                .help("Alleen de PR's van dit project")
            }
            // Eén filtermenu voor wie meetelt: een auteur kiezen, bots wel of niet, co-auteurs wel of niet.
            Menu {
                Picker("Auteur", selection: $author) {
                    Text("Alle auteurs").tag(String?.none)
                    ForEach(authors) { Text(verbatim: $0.name).tag(String?.some($0.name)) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Bots verbergen", isOn: $hideBots)
                    .help("PR's van bots (naam[bot]) niet meetellen")
                Toggle("Co-auteurs meetellen", isOn: $countCoAuthors)
                    .help("Een PR telt ook voor iedereen die eraan meewerkte, naast wie hem opende")
            } label: {
                Label {
                    if let author {
                        Text(verbatim: author)
                    } else {
                        Text("Alle auteurs")
                    }
                } icon: {
                    Image(systemName: "person.2")
                }
                .labelStyle(.titleAndIcon)
            }
            .help("Alleen de PR's van deze auteur")
        }
    }
}

/// Vier getallen boven de grafiek.
private struct StatTiles: View {
    let opened: Int
    let merged: Int
    let medianLeadTime: TimeInterval?
    let activeAuthors: Int

    var body: some View {
        HStack(spacing: 10) {
            StatTile(label: "PR's geopend deze periode") { Text(opened, format: .number) }
            StatTile(label: "gemerged deze periode") { Text(merged, format: .number) }
            StatTile(label: "mediane doorlooptijd") {
                if let medianLeadTime {
                    LeadTimeText(interval: medianLeadTime)
                } else {
                    Text("onbekend")
                }
            }
            StatTile(label: "actieve auteurs deze periode") { Text(activeAuthors, format: .number) }
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

private struct StatTile<Value: View>: View {
    let label: LocalizedStringResource
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            value.font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// De twee reeksen in de activiteitsgrafiek. De grafiek kent ze als waarde van dit type, niet
/// als vertaalde tekst; de legenda toont de vertaalde naam.
enum ActivitySeries: CaseIterable, Plottable {
    case opened, merged

    var title: LocalizedStringResource {
        switch self {
        case .opened: "Geopend"
        case .merged: "Gemerged"
        }
    }

    var color: Color {
        switch self {
        case .opened: .blue
        case .merged: .green
        }
    }

    var primitivePlottable: String { String(localized: title) }

    init?(primitivePlottable: String) {
        guard let series = Self.allCases.first(where: { $0.primitivePlottable == primitivePlottable }) else { return nil }
        self = series
    }
}

/// Geopend naast gemerged per periode.
struct ActivityChart: View {
    let stats: ActivityStats
    let period: StatsPeriod

    private struct Point: Identifiable {
        let start: Date
        let series: ActivitySeries
        let count: Int
        var id: String { "\(start.timeIntervalSince1970)-\(series)" }
    }

    private var points: [Point] {
        stats.buckets.flatMap { bucket in
            [Point(start: bucket.start, series: .opened, count: bucket.opened),
             Point(start: bucket.start, series: .merged, count: bucket.merged)]
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
        .chartForegroundStyleScale(domain: ActivitySeries.allCases) { (series: ActivitySeries) in series.color }
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

/// Een top tien als liggende staven; klikken op een staaf kiest die naam.
private struct RankingChart: View {
    let title: LocalizedStringResource
    let items: [RankedName]
    let selected: String?
    let select: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("Geen PR's in deze periode").foregroundStyle(.secondary).font(.callout)
            } else {
                Chart(items) { item in
                    BarMark(
                        x: .value("PR's", item.count),
                        y: .value("Naam", item.name),
                        height: .fixed(8)
                    )
                    .foregroundStyle(item.name == selected || selected == nil ? Color.accentColor : Color.accentColor.opacity(0.35))
                    // De naam boven de staaf en het aantal erachter: lange namen passen zo altijd.
                    .annotation(position: .top, alignment: .leading, spacing: 3) {
                        Text(verbatim: item.name)
                            .font(.callout)
                            .fontWeight(item.name == selected ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(item.count, format: .number)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartXScale(domain: 0...(Double(items.first?.count ?? 1) * 1.1))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let frame = proxy.plotFrame else { return }
                                let y = location.y - geometry[frame].origin.y
                                if let name: String = proxy.value(atY: y) { select(name) }
                            }
                    }
                }
                .frame(height: CGFloat(items.count) * 38 + 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
