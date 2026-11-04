import Charts
import PullwatchCore
import SwiftUI

/// Periode, project, auteur en bots in de knoppenbalk.
struct StatsToolbar: ToolbarContent {
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
