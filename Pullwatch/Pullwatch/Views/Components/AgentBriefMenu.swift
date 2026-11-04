import AppKit
import PullwatchCore
import SwiftUI

/// Het submenu "Kopieer voor een AI-agent" in Meer: elk kopje van elk tabblad.
struct AgentBriefMenu: View {
    let briefs: RepoBriefs

    var body: some View {
        Menu("Kopieer voor een AI-agent") {
            Section(RepoTab.overview.title) {
                Button("Pull requests") { Pasteboard.copy(briefs.pullRequests()) }
                Button("PR's per maand") { Pasteboard.copy(briefs.pullRequestsPerMonth()) }
            }
            if briefs.summary.versions != nil {
                Section(RepoTab.check.title) {
                    Button(RepoTab.check.title) { briefs.vulnerabilities().map(Pasteboard.copy) }
                }
                Section(RepoTab.packages.title) {
                    Button("Packages met nieuwe versie") { Pasteboard.copy(briefs.packageUpdates()) }
                    let workspaces = briefs.workspaces
                    if workspaces.count == 1, let workspace = workspaces.first {
                        Button(RepoTab.packages.title) { Pasteboard.copy(briefs.packages(workspace)) }
                    } else {
                        ForEach(workspaces) { workspace in
                            Button(Workspace.name(workspace.workspace)) { Pasteboard.copy(briefs.packages(workspace)) }
                        }
                    }
                }
                Section(RepoTab.security.title) {
                    Button(briefs.provider == .gitHub ? "Beveiliging op GitHub" : "Advanced Security") {
                        Pasteboard.copy(briefs.security())
                    }
                }
            }
        }
        .help("Kopieer een kopje van deze pagina als opdracht in Markdown voor een AI-agent")
    }
}
