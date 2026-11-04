import Foundation
import Testing
@testable import PullwatchCore

/// De versiecheck op een echte checkout, zonder netwerk: `PULLWATCH_REAL_REPO` wijst naar de map
/// (bv. een ondiepe kloon van een publieke Rust-workspace), `PULLWATCH_REAL_LATEST` eventueel naar
/// een JSON-bestand met de nieuwste versie per package (`{"serde": "1.0.228"}`). Zonder
/// `PULLWATCH_REAL_REPO` wordt de test overgeslagen. Hij print de tellingen per status, zodat een
/// wijziging aan de detectie op echte bestanden te meten is.
@Suite struct RealRepoCheckTests {
    static let folder = ProcessInfo.processInfo.environment["PULLWATCH_REAL_REPO"]

    @Test(.enabled(if: folder != nil, "PULLWATCH_REAL_REPO is niet gezet"))
    func `Counts the update statuses of a real checkout`() async throws {
        let root = URL(fileURLWithPath: try #require(Self.folder))
        var files: [String: String] = [:]
        var isFolder: ObjCBool = false
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path)
        where !path.hasPrefix(".git/") && !path.hasPrefix("target/") {
            guard FileManager.default.fileExists(atPath: root.appending(path: path).path, isDirectory: &isFolder),
                  !isFolder.boolValue else { continue }
            files[path] = ""
        }
        for path in VersionChecker.selectedFiles(files.keys.sorted()) {
            files[path] = try String(contentsOf: root.appending(path: path), encoding: .utf8)
        }
        let latest: [String: String] = try ProcessInfo.processInfo.environment["PULLWATCH_REAL_LATEST"].map {
            try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        } ?? [:]
        let provider = FileProvider(repos: ["real"], files: ["real": files])
        let scan = try await VersionChecker.scanWithRelease(repo: "real", provider: provider).main
        let repo = RepoVersions(
            accountId: UUID(), repo: "real", components: [], packages: scan.directDependencies, otherPackages: scan.otherPackages
        )

        var counts: [String: Int] = [:]
        var reasons: [String: Int] = [:]
        var examples: [String] = []
        let direct = Set(repo.packages.map(\.key))
        for use in repo.packages + repo.otherPackages {
            // Zoals de check: de nieuwste versie alleen voor packages die de repo zelf vraagt.
            let known = direct.contains(use.key) ? latest[use.name] : nil
            for install in use.installs {
                let update = install.update(ecosystem: use.ecosystem, name: use.name, latest: known)
                let status = "\(install.scope.rawValue) \(MCPUpdateWord.word(update.status))"
                counts[status, default: 0] += 1
                if let reason = update.unknownReason {
                    reasons["\(install.scope.rawValue) \(reason)", default: 0] += 1
                    if install.scope == .direct, examples.count < 15 {
                        examples.append("\(use.name) \(install.version) requested=\(install.requested ?? "-") \(reason)")
                    }
                }
                if install.scope == .direct {
                    counts["direct with a requirement", default: 0] += install.requested == nil ? 0 : 1
                    if install.requested == nil, examples.count < 15 { examples.append("\(use.name) \(install.version) without a requirement") }
                    counts["direct dev", default: 0] += install.kind == .dev ? 1 : 0
                }
            }
        }
        print("Real repo \(root.lastPathComponent): \(scan.dependencies.count) installs, \(repo.packages.count) direct packages, "
              + "\(repo.otherPackages.count) other packages")
        for (status, count) in counts.sorted(by: { $0.key < $1.key }) { print("  \(status): \(count)") }
        for (reason, count) in reasons.sorted(by: { $0.key < $1.key }) { print("  unknown because \(reason): \(count)") }
        for example in examples { print("  \(example)") }
        #expect(!scan.dependencies.isEmpty)
    }
}

/// De woorden van de MCP-tools, hier nagebouwd omdat PullwatchCore PullwatchMCP niet kent.
private enum MCPUpdateWord {
    static func word(_ status: PackageUpdate.Status) -> String {
        switch status {
        case .upToDate: "up_to_date"
        case .withinRange: "within_range"
        case .needsManifestChange: "needs_manifest_change"
        case .blockedByPackage, .blockedByPeer, .blockedByRuntime: "blocked"
        case .unknown: "unknown"
        }
    }
}
