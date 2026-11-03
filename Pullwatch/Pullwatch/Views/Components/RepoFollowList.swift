import PullwatchCore
import SwiftUI

extension Account {
    /// Volgt dit account de PR's van deze repo? Tags, completed en meldingen per soort staan op
    /// de repo-pagina in het hoofdvenster; hier alleen volgen ja of nee.
    subscript(follows repo: String) -> Bool {
        get { watch(for: repo).prs }
        set {
            var watch = watch(for: repo)
            watch.prs = newValue
            if newValue { watch.notifyPRs = true }
            setWatch(watch, for: repo)
        }
    }

    /// Nieuwe repo's (die er later bij komen) ook volgen.
    var followsNewRepositories: Bool {
        get { newRepoDefault == .prs }
        set { newRepoDefault = newValue ? .prs : .none }
    }
}

/// De repositories van een account, per eigenaar (of Azure DevOps-project) een sectie met
/// "Alle" in de kop, en per repo één vinkje Volgen. Hoort in een `Form`.
struct RepoFollowList: View {
    @Binding var account: Account
    /// Wat de dienst als repositories gaf; nil zolang ze laden.
    let available: [String]?
    let error: String?
    let reload: () -> Void
    @State private var search = ""

    var body: some View {
        Section {
            Toggle("Ook nieuwe repositories volgen", isOn: $account.followsNewRepositories)
            LabeledContent {
                HStack {
                    if available == nil { ProgressView().controlSize(.small) }
                    Button("Opnieuw laden", action: reload)
                        .disabled(available == nil)
                }
            } label: {
                TextField("Zoek een repository", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        } header: {
            Text("Repositories")
        } footer: {
            Text("Gevolgde repositories verschijnen in het menu, de geschiedenis en de meldingen. Tags en meldingen per soort zet je op de pagina van een repository.")
        }

        ForEach(groups, id: \.owner) { group in
            Section {
                ForEach(group.repos, id: \.self) { repo in
                    Toggle(isOn: $account[follows: repo]) {
                        Text(verbatim: repo.split(separator: "/", maxSplits: 1).last.map(String.init) ?? repo)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel(Text("Volg \(repo)"))
                }
            } header: {
                HStack {
                    if account.kind == .gitHub {
                        AccountAvatar(gitHubLogin: group.owner, size: 16)
                    }
                    Text(verbatim: group.owner)
                    Spacer()
                    Toggle("Alle", sources: group.repos.map { $account[follows: $0] }, isOn: \.self)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .accessibilityLabel(Text("Alle repositories van \(group.owner) volgen"))
                }
            }
        }
    }

    /// De repo's die er zijn en die al gevolgd werden, gezocht, per eigenaar in de volgorde van
    /// het account (eigen account eerst).
    private var groups: [(owner: String, repos: [String])] {
        let names = Account.mergedRepoNames(available: available ?? [], configured: Array(account.repoWatch.keys))
            .filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
        let byOwner = Dictionary(grouping: names) { $0.split(separator: "/", maxSplits: 1).first.map(String.init) ?? $0 }
        let order = account.owners
        return byOwner.keys.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs) ?? Int.max, right = order.firstIndex(of: rhs) ?? Int.max
            return left == right ? lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending : left < right
        }.map { (owner: $0, repos: byOwner[$0] ?? []) }
    }
}
