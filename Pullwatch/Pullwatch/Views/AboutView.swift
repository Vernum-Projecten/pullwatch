import AppKit
import SwiftUI

/// Het Over-venster: icoon, naam en versie, wat Pullwatch doet, de links (code, release notes,
/// een probleem melden, licentie), wie het maakte en waar de versie- en kwetsbaarheidsgegevens
/// en de PR-iconen vandaan komen. Geopend via "Over Pullwatch" in het appmenu en de ℹ︎ in het
/// menupaneel.
struct AboutView: View {
    static let repository = URL(string: "https://github.com/alessandro823/pullwatch")!

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var build: String { info["CFBundleVersion"] as? String ?? "" }
    private var copyright: String { info["NSHumanReadableCopyright"] as? String ?? "" }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(verbatim: "Pullwatch").font(.title.weight(.semibold))
                Text("Versie \(AppModel.currentVersion) (\(build))", comment: "Versie, buildnummer")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("Nieuwe pull requests en tags uit GitHub en Azure DevOps in je menubalk.")
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                Label("Meldingen bij nieuwe PR's, tags en gemergde PR's", systemImage: "bell.badge")
                Label("Een doorzoekbare geschiedenis en statistieken per repository", systemImage: "clock.arrow.circlepath")
                Label("Checks op verouderde talen, frameworks en packages en bekende kwetsbaarheden", systemImage: "checkmark.shield")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 380, alignment: .leading)

            HStack(spacing: 14) {
                Link("GitHub", destination: Self.repository)
                Link("Release notes", destination: Self.repository.appending(path: "releases"))
                Link("Probleem melden", destination: Self.repository.appending(path: "issues/new"))
                Link("Licentie", destination: Self.repository.appending(path: "blob/main/LICENSE"))
            }
            .font(.callout)

            Divider().frame(maxWidth: 380)

            VStack(spacing: 4) {
                Text("Gemaakt door Alessandro Torrisi.")
                Text("Versies van endoflife.date, kwetsbaarheden van OSV.dev.")
                Text("Pull-request-iconen uit GitHubs Octicons, onder de MIT-licentie.")
                Text("Gratis en open source onder de Apache-licentie 2.0.")
                if !copyright.isEmpty {
                    Text(verbatim: copyright)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        #if DEBUG
        .onAppear { SnapshotCamera.shoot("about", windowId: WindowID.about.rawValue) }
        #endif
    }
}
