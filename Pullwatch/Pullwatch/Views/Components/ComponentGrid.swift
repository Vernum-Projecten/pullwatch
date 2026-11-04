import AppKit
import PullwatchCore
import SwiftUI

/// De talen, runtimes en frameworks als compact raster: naam, versie en een statussymbool. Met
/// `onlyOutdated` alleen wat achterloopt.
struct ComponentGrid: View {
    let components: [ComponentVersion]
    let release: ReleaseVersions?
    /// De bronnen die bij de check uit stonden (`RepoVersions.skippedSources`).
    var skippedSources: Set<DataSourceID> = []

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 24, alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(components, id: \.label) { component in
                let source = DataSourceID.releases(product: component.product)
                ComponentCell(
                    component: component, inRelease: release?.components.first { $0.label == component.label }, tag: release?.tag,
                    skippedSource: skippedSources.contains(source) ? source : nil
                )
            }
        }
    }
}

/// Eén taal, runtime of framework met zijn versie en status.
private struct ComponentCell: View {
    let component: ComponentVersion
    /// Hetzelfde onderdeel in de laatste release; nil zonder release of als het daar ontbreekt.
    let inRelease: ComponentVersion?
    let tag: String?
    /// De releasebron (endoflife.date, swift.org) stond uit: geen status, wel de vaste zin.
    var skippedSource: DataSourceID? = nil

    private var help: String {
        var lines = component.sources
        if let skippedSource { lines.insert(SourceOff.notChecked(skippedSource), at: 0) }
        if let inRelease, let tag, inRelease.version != component.version {
            lines.append(String(localized: "\(inRelease.version) in \(tag)", comment: "Versie in de laatste release, tagnaam"))
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(component.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: component.versionText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            // Met de releasebron uit geen status (die zou "onbekend" of oud zijn), wel het teken
            // dat er niet gecontroleerd is; de zin staat in de tooltip.
            Image(systemName: skippedSource == nil ? component.status.symbol : "slash.circle")
                .foregroundStyle(skippedSource == nil ? component.status.color : Color.secondary)
        }
        .help(Text(verbatim: help))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(component.label) \(component.versionText), \(skippedSource.map(SourceOff.notChecked) ?? String(localized: component.status.label))",
                                 comment: "Taal of framework, versie, status"))
    }
}

extension ComponentVersion {
    var versionText: String {
        guard let latest, status != .current else { return version }
        return "\(version) → \(latest)"
    }
}
