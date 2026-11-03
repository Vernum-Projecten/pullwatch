import PullwatchCore
import SwiftUI

/// Het inspectievenster van één advies: wat het is, hoe ernstig en volgens wie, elk id met zijn
/// pagina, de links, wat je moet bijwerken, elke geraakte install met zijn keten, en de knoppen
/// om het advies te openen of te kopiëren.
struct AdvisoryInspector: View {
    let row: VulnerabilityRow
    /// De gekozen install als een rij eronder geselecteerd is.
    let install: Vulnerability?
    let releaseTag: String?
    let showsWorkspace: Bool
    var showPackage: ((String) -> Void)? = nil

    var body: some View {
        Form {
            AdvisoryHeaderSection(row: row)
            AdvisorySeveritySection(row: row)
            AdvisoryIdentifiersSection(row: row)
            AdvisoryReferencesSection(references: row.first.references)
            AdvisoryFixSection(fixes: row.fixes)
            AdvisoryInstallsSection(row: row, selected: install, showsWorkspace: showsWorkspace, releaseTag: releaseTag)
            AdvisoryActionsSection(row: row, showPackage: showPackage)
        }
        .formStyle(.grouped)
    }
}

private struct AdvisoryHeaderSection: View {
    let row: VulnerabilityRow

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                SeverityLabel(level: row.severity)
                HStack(spacing: 6) {
                    Text(verbatim: row.primaryId)
                        .font(.headline)
                        .textSelection(.enabled)
                    SourceLabel(database: row.first.database)
                }
                if let summary = row.summary {
                    Text(verbatim: summary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Text(verbatim: row.package)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

/// De ernst, waar die vandaan komt, de CVSS-score met vector, en de zwakheden (CWE's).
private struct AdvisorySeveritySection: View {
    let row: VulnerabilityRow

    var body: some View {
        let assessment = row.assessment
        Section("Ernst") {
            // De ernst met waar die vandaan komt, en de CVSS-score als die er is.
            LabeledContent {
                if let score = assessment.score {
                    Text(verbatim: "CVSS \(score.formatted(.number.precision(.fractionLength(1))))")
                        .monospacedDigit()
                }
            } label: {
                Text(row.severity.label)
                Text(verbatim: assessment.note(for: row.first))
            }
            if let vector = assessment.vector {
                Text(verbatim: vector)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(row.gitHub?.cwes ?? [], id: \.id) { cwe in
                LabeledContent {
                    EmptyView()
                } label: {
                    Text(verbatim: cwe.id)
                    Text(verbatim: cwe.name)
                }
            }
        }
    }
}

/// Elk id van het lek als link naar zijn eigen database, verwante lekken, en de datums.
private struct AdvisoryIdentifiersSection: View {
    let row: VulnerabilityRow

    var body: some View {
        Section("Ids") {
            ForEach(row.identifiers, id: \.self) { id in
                AdvisoryIdRow(id: id)
            }
            ForEach(row.first.related, id: \.self) { id in
                AdvisoryIdRow(id: id, isRelated: true)
            }
            if let published = row.first.published ?? row.gitHub?.publishedAt {
                LabeledContent("Gepubliceerd") {
                    Text(published, format: .dateTime.day().month().year())
                }
            }
            if let modified = row.first.modified {
                LabeledContent("Gewijzigd") {
                    Text(modified, format: .dateTime.day().month().year())
                }
            }
        }
    }
}

/// Een id met de korte naam van zijn database, als link naar de pagina daar.
private struct AdvisoryIdRow: View {
    let id: String
    var isRelated = false

    var body: some View {
        LabeledContent {
            Link(destination: AdvisorySource.pageURL(id: id)) {
                Text(verbatim: (AdvisorySource.of(id: id) ?? .other).label)
            }
            .help(Text(verbatim: AdvisorySource.pageURL(id: id).absoluteString))
        } label: {
            Text(verbatim: id)
                .textSelection(.enabled)
            if isRelated {
                Text("Verwant")
            }
        }
    }
}

/// De links uit het record, de fix eerst.
private struct AdvisoryReferencesSection: View {
    let references: [VulnerabilityReference]

    var body: some View {
        if !references.isEmpty {
            Section("Links") {
                ForEach(references, id: \.self) { reference in
                    LabeledContent {
                        Link(destination: reference.url) {
                            Text(verbatim: reference.url.host(percentEncoded: false) ?? reference.url.absoluteString)
                                .lineLimit(1)
                        }
                        .help(Text(verbatim: reference.url.absoluteString))
                    } label: {
                        Text(reference.typeLabel)
                    }
                }
            }
        }
    }
}

/// Wat je moet bijwerken om het lek te dichten, met wat dat tegenhoudt.
private struct AdvisoryFixSection: View {
    let fixes: [VulnerabilityFix]

    var body: some View {
        Section("Oplossing") {
            ForEach(fixes, id: \.self) { fix in
                Label {
                    Text(fix.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: fix.symbol)
                        .foregroundStyle(fix.color)
                }
            }
        }
    }
}

/// Elke geraakte install: de versie en de versie met de oplossing, waar hij zit en via welke
/// packages hij binnenkomt.
private struct AdvisoryInstallsSection: View {
    let row: VulnerabilityRow
    let selected: Vulnerability?
    let showsWorkspace: Bool
    let releaseTag: String?

    var body: some View {
        Section {
            ForEach(row.advisory.installs, id: \.installId) { install in
                LabeledContent {
                    Text(verbatim: install.fixedIn.map { "\(install.version) → \($0)" } ?? install.version)
                        .monospacedDigit()
                } label: {
                    Text(verbatim: install.placeText(showsWorkspace: showsWorkspace))
                        .fontWeight(install == selected ? .semibold : .regular)
                    Text(verbatim: install.source)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: install.spoken(showsWorkspace: showsWorkspace)))
            }
            if let releaseTag, let inRelease = row.inRelease {
                LabeledContent(String(localized: "In \(releaseTag)", comment: "Kolomkop: zit het ook in deze tag")) {
                    Text(inRelease ? "Ja" : "Nee, alleen main")
                }
            }
        } header: {
            Text("Getroffen installs")
        }
    }
}

/// Open het advies, kopieer het, of toon het package in Afhankelijkheden.
private struct AdvisoryActionsSection: View {
    let row: VulnerabilityRow
    let showPackage: ((String) -> Void)?

    var body: some View {
        Section {
            HStack {
                Link(destination: row.pageURL) {
                    Label("Open advies", systemImage: "safari")
                }
                Spacer()
                Button {
                    Pasteboard.copy(row.clipboardText)
                } label: {
                    Label("Kopieer", systemImage: "doc.on.doc")
                }
                .help("Kopieer de ids, de ernst, de samenvatting en de oplossing naar het klembord")
            }
            if let showPackage {
                Button("Toon \(row.package) in Afhankelijkheden") { showPackage(row.package) }
                    .buttonStyle(.link)
            }
        }
    }
}

extension VulnerabilityRow {
    /// De pagina van het record in zijn eigen database.
    var pageURL: URL { first.pageURL }

    /// Het advies als platte tekst: ids, ernst, package, samenvatting, installs en oplossing.
    var clipboardText: String {
        var lines = [first.sourceLine(adding: [gitHub?.ghsaId, gitHub?.cveId])]
        lines.append("\(package) [\(first.severityText(gitHub) ?? String(localized: severity.label))]")
        lines.append(assessment.note(for: first))
        if let summary { lines.append(summary) }
        if let cweText = gitHub?.cweText { lines.append(cweText) }
        for install in advisory.installs {
            var line = install.fixedIn.map { "\(install.version) → \($0)" } ?? install.version
            if let how = install.provenanceLine { line += ", \(how)" }
            lines.append(line)
        }
        lines += fixes.compactMap(\.plainText)
        lines.append(pageURL.absoluteString)
        return lines.joined(separator: "\n")
    }
}
