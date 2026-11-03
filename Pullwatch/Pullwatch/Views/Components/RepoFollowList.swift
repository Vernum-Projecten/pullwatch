import PullwatchCore
import SwiftUI

extension Account {
    /// Volgt dit account dit soort voor deze repo? Schrijft via `WatchSet[follows:]`, dus met
    /// dezelfde regels als de repo-pagina (gemerged hoort bij de PR's).
    subscript(repo: String, follows kind: WatchKind) -> Bool {
        get { watch(for: repo)[follows: kind] }
        set {
            var watch = watch(for: repo)
            watch[follows: kind] = newValue
            setWatch(watch, for: repo)
        }
    }

    subscript(repo: String, notifies kind: WatchKind) -> Bool {
        get { watch(for: repo)[notifies: kind] }
        set {
            var watch = watch(for: repo)
            watch[notifies: kind] = newValue
            setWatch(watch, for: repo)
        }
    }
}

extension WatchKind {
    /// Kolomtitel in de lijst.
    var columnTitle: LocalizedStringKey {
        switch self {
        case .pullRequests: "PR's"
        case .tags: "Tags"
        case .merged: "Gemerged"
        }
    }

    var help: LocalizedStringKey {
        switch self {
        case .pullRequests: "Nieuwe pull requests in het menu, de geschiedenis en de meldingen"
        case .tags: "Nieuwe tags in het menu, de geschiedenis en de meldingen"
        case .merged: "Een melding en een regel in de geschiedenis als een gevolgde PR gemerged wordt (in Azure DevOps heet dat completed)"
        }
    }

    func followLabel(_ repo: String) -> Text {
        switch self {
        case .pullRequests: Text("PR's van \(repo) volgen", comment: "Repo")
        case .tags: Text("Tags van \(repo) volgen", comment: "Repo")
        case .merged: Text("Gemergde PR's van \(repo) volgen", comment: "Repo")
        }
    }

    func allLabel(_ owner: String) -> Text {
        switch self {
        case .pullRequests: Text("Alle PR's van \(owner) volgen", comment: "Gebruiker of organisatie")
        case .tags: Text("Alle tags van \(owner) volgen", comment: "Gebruiker of organisatie")
        case .merged: Text("Alle gemergde PR's van \(owner) volgen", comment: "Gebruiker of organisatie")
        }
    }

    var notifyTitle: LocalizedStringKey {
        switch self {
        case .pullRequests: "Melding bij nieuwe PR's"
        case .tags: "Melding bij nieuwe tags"
        case .merged: "Melding als een PR gemerged wordt"
        }
    }
}

extension NewRepoDefault {
    var title: LocalizedStringKey {
        switch self {
        case .none: "Niet volgen"
        case .prs: "PR's"
        case .prsAndTags: "PR's en tags"
        }
    }
}

/// De repositories van een account: per eigenaar (of Azure DevOps-project) een sectie met per
/// repo drie vinkjes (PR's, tags, gemerged) in vaste kolommen, en in de kop per kolom "alle".
/// Meldingen per soort zitten in het contextmenu van een rij en op de repo-pagina. Hoort in
/// een `Form`.
struct RepoFollowList: View {
    @Binding var account: Account
    /// Wat de dienst als repositories gaf; blijft staan tijdens opnieuw laden.
    let available: [String]
    let isLoading: Bool
    let error: String?
    let reload: () -> Void
    /// Opent de pagina van een repo in het hoofdvenster; nil voor een account dat nog niet bewaard is.
    var openRepo: ((String) -> Void)?
    @State private var search = ""

    var body: some View {
        Section {
            Picker("Nieuwe repositories", selection: $account.newRepoDefault) {
                ForEach(NewRepoDefault.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            LabeledContent {
                HStack {
                    // Altijd op zijn plek, alleen zichtbaar tijdens het laden: zo verspringt de rij niet.
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isLoading ? 1 : 0)
                        .accessibilityHidden(!isLoading)
                        .accessibilityLabel(Text("Repositories laden"))
                    Button("Opnieuw laden", action: reload)
                        .disabled(isLoading)
                }
            } label: {
                TextField("Zoek een repository", text: $search, prompt: Text("Zoek een repository"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            if !account.followsAnything {
                // Pullwatch haalt alleen op wat je kiest; zonder keuze gebeurt er niets.
                Label("Je volgt nog niets. Vink hieronder aan wat Pullwatch moet ophalen.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Repositories")
        } footer: {
            Text("Gevolgde repositories verschijnen in het menu, de geschiedenis en de meldingen. Meldingen per soort zet je met een rechtermuisklik op een repository, of op de pagina ervan.")
        }

        ForEach(groups, id: \.owner) { group in
            Section {
                ForEach(group.repos, id: \.self) { repo in
                    RepoWatchRow(account: $account, repo: repo, openRepo: openRepo)
                }
            } header: {
                OwnerHeader(account: $account, owner: group.owner, repos: group.repos)
            }
        }
    }

    /// De repo's die er zijn en die al gevolgd werden, gezocht, per eigenaar in de volgorde van
    /// het account (eigen account eerst).
    private var groups: [(owner: String, repos: [String])] {
        let names = Account.mergedRepoNames(available: available, configured: Array(account.repoWatch.keys))
            .filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
        let byOwner = Dictionary(grouping: names) { $0.split(separator: "/", maxSplits: 1).first.map(String.init) ?? $0 }
        let order = account.owners
        return byOwner.keys.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs) ?? Int.max, right = order.firstIndex(of: rhs) ?? Int.max
            return left == right ? lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending : left < right
        }.map { (owner: $0, repos: byOwner[$0] ?? []) }
    }
}

/// Breedte van één kolom; groeit mee met de tekstgrootte, zodat kop en vinkjes recht onder
/// elkaar blijven staan.
private struct WatchColumn: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var width = 72

    func body(content: Content) -> some View {
        content.frame(width: width)
    }
}

/// Kop van een eigenaar: foto en naam, en per kolom de titel met een "alle"-vinkje (gemengd als
/// maar een deel gevolgd wordt). "Alle" geldt voor de repo's die de zoekopdracht toont.
private struct OwnerHeader: View {
    @Binding var account: Account
    let owner: String
    let repos: [String]

    var body: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 6) {
                if account.kind == .gitHub {
                    AccountAvatar(gitHubLogin: owner, size: 16)
                }
                Text(verbatim: owner)
            }
            Spacer()
            ForEach(WatchKind.allCases) { kind in
                VStack(spacing: 2) {
                    Text(kind.columnTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Toggle(sources: repos.map { $account[$0, follows: kind] }, isOn: \.self) {
                        kind.allLabel(owner)
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
                .modifier(WatchColumn())
                .help(kind.help)
            }
        }
    }
}

/// Eén repo: de naam en drie vinkjes. Gemerged kan alleen met PR's aan. Rechtermuisklik (en
/// VoiceOver-acties): de meldingen per soort en de pagina van de repo.
private struct RepoWatchRow: View {
    @Binding var account: Account
    let repo: String
    let openRepo: ((String) -> Void)?

    var body: some View {
        HStack {
            Text(verbatim: repo.split(separator: "/", maxSplits: 1).last.map(String.init) ?? repo)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            ForEach(WatchKind.allCases) { kind in
                Toggle(isOn: $account[repo, follows: kind]) {
                    kind.followLabel(repo)
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(kind == .merged && !account[repo, follows: .pullRequests])
                .modifier(WatchColumn())
                .help(kind.help)
            }
        }
        .contentShape(.rect)
        .contextMenu { menu }
        .accessibilityActions { menu }
    }

    @ViewBuilder private var menu: some View {
        ForEach(WatchKind.allCases) { kind in
            Toggle(kind.notifyTitle, isOn: $account[repo, notifies: kind])
                .disabled(!account[repo, follows: kind])
        }
        if let openRepo {
            Divider()
            Button("Open de pagina van de repo") { openRepo(repo) }
        }
    }
}
