import PullwatchCore
import SwiftUI

/// Versies per package over alle gevolgde repo's: wat er nieuw is en welke repo's nog achterlopen.
struct PackagesView: View {
    let model: AppModel

    @State private var searchText = ""
    /// Wat bij openen als gezien gemarkeerd werd; die rijen krijgen geen stip meer. Vastgelegd bij
    /// openen, zodat de stippen zichtbaar blijven zolang je kijkt.
    @State private var seenAtOpen: [String: String] = [:]

    private func matches(_ summary: PackageSummary) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return summary.label.localizedCaseInsensitiveContains(query)
            || (summary.behind + summary.current).contains { $0.repo.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Zoek op package of repo…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .searchFocus(model)
                if let progress = model.versionCheck {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 100)
                    Text("Checken… \(progress.done)/\(progress.total) repo's")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Button("Nu checken") {
                        Task { await model.checkVersions() }
                    }
                    .help("Leest de versies in alle gevolgde repo's en zoekt de nieuwste versie op bij endoflife.date en de package-registers")
                }
            }
            if let report = model.versionReport {
                Text("Gecheckt \(report.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let summaries = model.packageSummaries.filter(matches)
                if summaries.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "Geen packages gevonden",
                            systemImage: "shippingbox",
                            description: Text("Check opnieuw om ook de packages van je repo's op te halen.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else {
                    List {
                        PackageSection(title: "Nieuwe versie beschikbaar", summaries: summaries.filter { $0.state == .updateAvailable },
                                       seen: seenAtOpen, expanded: true, model: model)
                        PackageSection(title: "Actueel", summaries: summaries.filter { $0.state == .current },
                                       seen: seenAtOpen, expanded: false, model: model)
                        PackageSection(title: "Niet te checken", summaries: summaries.filter { $0.state == .unchecked },
                                       seen: seenAtOpen, expanded: false, model: model)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: false))
                }
            } else {
                ContentUnavailableView(
                    "Nog niet gecheckt",
                    systemImage: "shippingbox",
                    description: Text("Zie welke runtimes en packages je repo's gebruiken en of er een nieuwere versie is.")
                )
            }
        }
        .padding(12)
        .onAppear {
            seenAtOpen = model.seenPackageVersions
            model.markPackagesSeen()
        }
        .onChange(of: model.packagesSearch, initial: true) { _, search in
            guard let search else { return }
            searchText = search
            model.packagesSearch = nil
        }
        .onChange(of: model.versionReport?.checkedAt) {
            // Nieuwe check terwijl je kijkt: wat nu nieuw is houdt zijn stip tot je terugkomt.
            model.markPackagesSeen()
        }
    }
}

private struct PackageSection: View {
    let title: LocalizedStringKey
    let summaries: [PackageSummary]
    let seen: [String: String]
    let model: AppModel
    @State private var isExpanded: Bool

    init(title: LocalizedStringKey, summaries: [PackageSummary], seen: [String: String], expanded: Bool, model: AppModel) {
        self.title = title
        self.summaries = summaries
        self.seen = seen
        self.model = model
        _isExpanded = State(initialValue: expanded)
    }

    private func isNew(_ summary: PackageSummary) -> Bool {
        summary.state == .updateAvailable && seen[summary.id] != summary.latest
    }

    var body: some View {
        if !summaries.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(summaries) { summary in
                    PackageRow(summary: summary, isNew: isNew(summary), model: model)
                }
            } header: {
                HStack(spacing: 4) {
                    Text(title)
                    Text(verbatim: "(\(summaries.count))")
                }
            }
        }
    }
}

private struct PackageRow: View {
    let summary: PackageSummary
    let isNew: Bool
    let model: AppModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(summary.behind) { user in
                    UserRow(user: user, model: model)
                }
                if !summary.current.isEmpty {
                    if let latest = summary.latest, !summary.behind.isEmpty {
                        Label(
                            summary.current.count == 1
                                ? String(localized: "1 repo al op \(latest)")
                                : String(localized: "\(summary.current.count) repo's al op \(latest)"),
                            systemImage: "checkmark"
                        )
                        .foregroundStyle(.green)
                        .help(summary.current.map(\.repo).joined(separator: "\n"))
                    } else {
                        ForEach(summary.current) { user in
                            UserRow(user: user, model: model)
                        }
                    }
                }
            }
            .font(.callout)
            .padding(.vertical, 2)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isNew ? Color.accentColor : .clear)
                    .frame(width: 6, height: 6)
                Text(summary.label).fontWeight(.semibold)
                Text(summary.kind)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5)))
                switch summary.state {
                case .updateAvailable:
                    Text("\(summary.latest ?? "") beschikbaar", comment: "Versienummer").foregroundStyle(.green).fontWeight(.medium)
                    Text(summary.behind.count == 1 ? String(localized: "1 repo loopt achter") : String(localized: "\(summary.behind.count) repo's lopen achter"))
                        .foregroundStyle(.secondary)
                case .current:
                    Text(verbatim: summary.latest ?? "").foregroundStyle(.secondary).monospacedDigit()
                    Text(summary.current.count == 1 ? String(localized: "gebruikt in 1 repo") : String(localized: "gebruikt in \(summary.current.count) repo's"))
                        .foregroundStyle(.secondary)
                case .unchecked:
                    Text("Nieuwste versie niet op te halen").foregroundStyle(.secondary)
                }
                Spacer()
                if let since = summary.since, summary.state == .updateAvailable {
                    Text(since, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(String(localized: "Sinds wanneer deze versie de nieuwste is"))
                }
            }
        }
    }
}

private struct UserRow: View {
    let user: PackageUser
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Button(user.repo) {
                model.showRepo(id: user.repoId)
            }
            .buttonStyle(.link)
            .help("Open de pagina van deze repo")
            Text(verbatim: user.version).monospacedDigit().foregroundStyle(.secondary)
            Text(verbatim: user.sources.joined(separator: ", ")).foregroundStyle(.tertiary).lineLimit(1)
        }
    }
}
