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
    @Environment(AccountsModel.self) private var accounts
    @Environment(HistoryModel.self) private var historyModel
    @Environment(OverviewModel.self) private var overview
    @Environment(AppRouter.self) private var router
    /// Alleen deze repo (`RepoSummary.id`), vanaf de repo-pagina; nil voor alles.
    var repoId: String? = nil

    @AppStorage("statsPeriod") private var period: StatsPeriod = .month
    @AppStorage("statsHideBots") private var hideBots = true
    @AppStorage("statsCountCoAuthors") private var countCoAuthors = false
    @State private var group: HistoryGroup.ID?
    @State private var author: String?

    private var repoSummary: RepoSummary? { repoId.flatMap { overview.repoSummariesById[$0] } }

    /// Azure DevOps noemt mergen "completed": zijn alle accounts in beeld van Azure DevOps, dan
    /// heet gemerged hier afgerond, zoals in de meldingen.
    private var saysCompleted: Bool {
        let ids: Set<UUID> =
            if let repoSummary { [repoSummary.accountId] }
            else if let group { [group.accountId] }
            else { Set(accounts.config.pollableAccounts.map(\.id)) }
        let kinds = accounts.config.accounts.filter { ids.contains($0.id) }.map(\.kind)
        return !kinds.isEmpty && kinds.allSatisfy { $0 == .azureDevOps }
    }

    var body: some View {
        let filter = ActivityFilter(group: group, author: author, repoId: repoId, hideBots: hideBots, countCoAuthors: countCoAuthors)
        let stats = historyModel.activityStats(period: period, filter: filter)
        // Auteurskeuze zonder auteursfilter, anders blijft alleen de gekozen auteur over.
        let withoutAuthor = ActivityFilter(group: group, repoId: repoId, hideBots: hideBots, countCoAuthors: countCoAuthors)
        let authors = author == nil ? stats.authors : historyModel.activityStats(period: period, filter: withoutAuthor).authors

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatTiles(stats: stats, saysCompleted: saysCompleted)
                if let author {
                    Button {
                        router.showHistory(.pullRequest, author: author, repo: repoSummary.map { HistoryRepo(accountId: $0.accountId, repo: $0.repo) })
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
                    Text("PR-activiteit").font(.headline)
                    ActivityChart(stats: stats, period: period, saysCompleted: saysCompleted)
                        .frame(height: 220)
                }
                HStack(alignment: .top, spacing: 24) {
                    RankingChart(
                        title: countCoAuthors ? "Auteurs en co-auteurs" : "Auteurs", items: Array(stats.authors.prefix(10)),
                        states: stats.authorStates, saysCompleted: saysCompleted, selected: author
                    ) { name in
                        author = author == name ? nil : name
                    }
                    if repoId == nil {
                        RankingChart(
                            title: "Drukste repo's", items: Array(stats.repos.prefix(10)),
                            states: stats.repoStates, saysCompleted: saysCompleted, selected: nil
                        ) { name in
                            if let summary = overview.repoSummaries.first(where: { $0.repo == name }) {
                                router.showRepo(id: summary.id)
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
                groups: repoId == nil ? overview.sidebar.pullRequestGroups : [],
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

/// De getallen boven de grafiek: eerst de vier statussen in de volgorde en kleuren van GitHub,
/// dan doorlooptijd en auteurs.
private struct StatTiles: View {
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

extension PRStatus {
    /// De status in één woord, voor de uitsplitsing per auteur of repo. Azure DevOps noemt
    /// gemerged afgerond.
    func stateName(saysCompleted: Bool) -> LocalizedStringResource {
        switch self {
        case .open: "Open"
        case .draft: "Draft"
        case .merged: saysCompleted ? "Afgerond" : "Gemerged"
        case .closed: "Gesloten"
        }
    }
}

extension PRStateCounts {
    func count(_ status: PRStatus) -> Int {
        switch status {
        case .open: open
        case .draft: draft
        case .merged: merged
        case .closed: closed
        }
    }
}

/// De vier reeksen in de activiteitsgrafiek, in de volgorde van de tabbladen op GitHub. Kleur en
/// icoon komen van `PRStatus`, zodat de grafiek dezelfde kleuren heeft als de rest van de app.
enum ActivitySeries: CaseIterable {
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

/// Hoe de PR's achter een staaf in de ranglijst nu staan, met het icoon en de kleur per status.
private struct StateBreakdown: View {
    let counts: PRStateCounts
    let saysCompleted: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) {
            ForEach(PRStatus.allCases.filter { counts.count($0) > 0 }, id: \.self) { status in
                GridRow {
                    status.glyph.image.foregroundStyle(status.color)
                    Text(counts.count(status), format: .number).monospacedDigit().gridColumnAlignment(.trailing)
                    Text(status.stateName(saysCompleted: saysCompleted))
                }
            }
        }
        .font(.caption)
    }
}

/// Een top tien als liggende staven; klikken op een staaf kiest die naam.
private struct RankingChart: View {
    let title: LocalizedStringResource
    let items: [RankedName]
    /// De huidige status van de PR's per naam, voor de tooltip.
    let states: [String: PRStateCounts]
    let saysCompleted: Bool
    let selected: String?
    let select: (String) -> Void

    /// De naam onder de muis en waar de muis staat.
    @State private var hover: (name: String, location: CGPoint)?
    @State private var tooltipSize: CGSize = .zero

    private func spokenStates(_ name: String) -> Text {
        let counts = states[name] ?? PRStateCounts()
        return saysCompleted
            ? Text("Open: \(counts.open), draft: \(counts.draft), afgerond: \(counts.merged), gesloten: \(counts.closed)")
            : Text("Open: \(counts.open), draft: \(counts.draft), gemerged: \(counts.merged), gesloten: \(counts.closed)")
    }

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
                    .accessibilityLabel(Text(verbatim: item.name))
                    .accessibilityValue(spokenStates(item.name))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartXScale(domain: 0...(Double(items.first?.count ?? 1) * 1.1))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    guard let frame = proxy.plotFrame else { return }
                                    let y = location.y - geometry[frame].origin.y
                                    if let name: String = proxy.value(atY: y) { select(name) }
                                }
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard let frame = proxy.plotFrame else { return }
                                        let y = location.y - geometry[frame].origin.y
                                        let name: String? = proxy.value(atY: y)
                                        hover = name.map { ($0, location) }
                                    case .ended:
                                        hover = nil
                                    }
                                }
                            if let hover, let counts = states[hover.name] {
                                tooltip(counts, at: hover.location, in: geometry.size)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(items.count) * 38 + 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// De uitsplitsing naast de muis, binnen de breedte van de grafiek: rechts van de muis, of
    /// links als hij daar niet past; onder de muis in de bovenste helft, anders erboven.
    private func tooltip(_ counts: PRStateCounts, at location: CGPoint, in size: CGSize) -> some View {
        let width = tooltipSize.width
        let height = tooltipSize.height
        let right = location.x + 14 + width / 2
        let x = right + width / 2 <= size.width ? right : max(width / 2, location.x - 14 - width / 2)
        let y = location.y < size.height / 2 ? location.y + 14 + height / 2 : location.y - 10 - height / 2
        return StateBreakdown(counts: counts, saysCompleted: saysCompleted)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tooltipSize = $0 }
            .position(x: x, y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
