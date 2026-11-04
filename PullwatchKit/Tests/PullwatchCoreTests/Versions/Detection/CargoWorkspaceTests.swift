import Foundation
import Testing
@testable import PullwatchCore

/// Een Cargo-workspace zoals een echte repo hem heeft: een root met `[workspace]` en
/// `[workspace.dependencies]`, twee leden (een dat erft, een met een hernoemd package, een
/// dev-dependency, een build-dependency, een target-tabel en een git-dependency) en een Cargo.lock
/// met een transitief package dat een kwetsbaarheid heeft die in een nieuwere patch opgelost is.
@Suite struct CargoWorkspaceTests {
    static let root = """
        [workspace]
        resolver = "3"
        members = [
          "crates/app",
          "crates/cli",
        ]

        [workspace.package]
        rust-version = "1.85"

        [workspace.dependencies]
        serde = { version = "1.0.200", features = ["derive"] } # serialisatie
        tokio = { version = "1.38", default-features = false, features = [
          "rt-multi-thread",
          "macros",
        ] }
        app-core = { path = "crates/core" }
        """

    static let app = """
        [package]
        name = "app"
        version = "0.1.0"
        rust-version.workspace = true

        [dependencies]
        serde.workspace = true
        tokio = { workspace = true, features = ["net"] }
        reqwest = "0.12"
        app-core.workspace = true

        [target.'cfg(unix)'.dependencies]
        libc = "0.2.150"
        """

    static let cli = """
        [package]
        name = "cli"
        version = "0.1.0"

        [dependencies]
        args = { package = "clap", version = "~4.5.0" }
        mylib = { git = "https://example.com/mylib.git" }

        [dependencies.serde]
        workspace = true

        [dev-dependencies]
        insta = "=1.40.0"

        [build-dependencies]
        cc = ">=1.0, <1.2"
        """

    static let lock = """
        version = 4

        [[package]]
        name = "app"
        version = "0.1.0"
        dependencies = ["app-core", "libc", "reqwest", "serde", "tokio"]

        [[package]]
        name = "app-core"
        version = "0.1.0"

        [[package]]
        name = "cli"
        version = "0.1.0"
        dependencies = ["cc", "clap", "insta", "mylib", "serde"]

        [[package]]
        name = "cc"
        version = "1.1.30"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "clap"
        version = "4.5.20"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "insta"
        version = "1.40.0"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "libc"
        version = "0.2.155"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "mylib"
        version = "0.3.0"
        source = "git+https://example.com/mylib.git#0123456789abcdef"

        [[package]]
        name = "reqwest"
        version = "0.12.5"
        source = "registry+https://github.com/rust-lang/crates.io-index"
        dependencies = ["rustls", "serde"]

        [[package]]
        name = "rustls"
        version = "0.23.44"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "serde"
        version = "1.0.210"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "tokio"
        version = "1.40.0"
        source = "registry+https://github.com/rust-lang/crates.io-index"
        """

    static let files = [
        (path: "Cargo.toml", content: root), (path: "Cargo.lock", content: lock),
        (path: "crates/app/Cargo.toml", content: app), (path: "crates/cli/Cargo.toml", content: cli),
    ]

    static let latest = [
        "serde": "1.0.228", "tokio": "1.48.0", "reqwest": "0.13.1", "libc": "0.2.177", "clap": "4.6.0", "insta": "1.43.1",
        "cc": "1.1.31",
    ]

    let dependencies: [Dependency]

    init() {
        dependencies = DependencyDetector.installs(Self.files).dependencies
    }

    private func dependency(_ name: String) throws -> Dependency {
        try #require(dependencies.first { $0.name == name })
    }

    // MARK: - Gevraagde bereiken

    @Test(arguments: [
        ("serde", "1.0.200"), ("tokio", "1.38"), ("reqwest", "0.12"), ("libc", "0.2.150"), ("clap", "~4.5.0"), ("insta", "=1.40.0"),
        ("cc", ">=1.0, <1.2"),
    ])
    func `Reads the requirement of every direct crate from the member manifests`(name: String, requested: String) throws {
        let found = try dependency(name)
        #expect(found.scope == .direct)
        #expect(found.requested == requested)
    }

    @Test func `A git dependency is no crates.io install and lends no requirement`() {
        #expect(!dependencies.contains { $0.name == "mylib" })
        #expect(!dependencies.contains { $0.name == "app-core" })
    }

    @Test func `A dev-dependency is dev and a build-dependency runtime`() throws {
        #expect(try dependency("insta").kind == .dev)
        #expect(try dependency("cc").kind == .runtime)
        #expect(try dependency("serde").kind == .runtime)
    }

    @Test func `The transitive crate keeps its parent and has no requirement of its own`() throws {
        let rustls = try dependency("rustls")
        #expect(rustls.scope == .transitive)
        #expect(rustls.via == ["reqwest"])
        #expect(rustls.requested == nil)
    }

    @Test func `Every Cargo.toml is read, the stack only from the root`() {
        #expect(DependencyDetector.isRelevant("crates/app/Cargo.toml"))
        #expect(!StackDetector.isRelevant("crates/app/Cargo.toml"))
    }

    // MARK: - Update-status

    @Test(arguments: [
        ("serde", "within_range"), ("tokio", "within_range"), ("libc", "within_range"), ("cc", "within_range"),
        ("reqwest", "needs_manifest_change"), ("clap", "needs_manifest_change"), ("insta", "needs_manifest_change"),
    ])
    func `Every direct crate gets a known update status`(name: String, status: String) throws {
        let found = try dependency(name)
        let update = found.install.update(ecosystem: "crates.io", name: name, latest: Self.latest[name])
        #expect(Self.word(update.status) == status)
        #expect(update.unknownReason == nil)
    }

    static func word(_ status: PackageUpdate.Status) -> String {
        switch status {
        case .upToDate: "up_to_date"
        case .withinRange: "within_range"
        case .needsManifestChange: "needs_manifest_change"
        case .blockedByPackage, .blockedByPeer, .blockedByRuntime: "blocked"
        case .unknown: "unknown"
        }
    }

    // MARK: - De transitieve crate met een kwetsbaarheid

    private func repo(parentAsks requirement: String) throws -> (RepoVersions, UpdateContext, Vulnerability) {
        let rustls = try dependency("rustls")
        let vulnerability = Vulnerability(
            id: "GHSA-2mjx-qc3c-rqvc", cve: nil, summary: "rustls bug", severity: "HIGH", ecosystem: "crates.io", package: "rustls",
            version: rustls.version, fixedIn: "0.23.45", source: rustls.source, workspace: rustls.workspace, scope: rustls.scope,
            via: rustls.via, requested: rustls.requested
        )
        let uses = DependencyDetector.direct(dependencies, manifests: ["crates.io": []])
        let direct = Set(uses.map(\.key))
        let others = dependencies.filter { !direct.contains("\($0.ecosystem):\($0.name)") }.map {
            PackageUse(ecosystem: $0.ecosystem, name: $0.name, installs: [$0.install])
        }
        let repo = RepoVersions(
            accountId: UUID(), repo: "acme/forms", components: [], vulnerabilities: [vulnerability], packages: uses, otherPackages: others
        )
        var reqwest: [String: VersionMetadata] = ["0.12.5": VersionMetadata(dependencies: ["rustls": requirement])]
        reqwest["0.12.6"] = VersionMetadata(dependencies: ["rustls": "^0.23.45"])
        let metadata = ["crates.io:reqwest": PackageMetadata(latest: "0.13.1", versions: reqwest)]
        return (repo, UpdateContext(repo: repo, metadata: metadata), vulnerability)
    }

    @Test func `A fix within the parent's requirement only changes the lock file`() throws {
        let (_, context, vulnerability) = try repo(parentAsks: "^0.23.10")
        let rustls = try dependency("rustls")
        #expect(context.requirement(ecosystem: "crates.io", name: "rustls", install: rustls.install) == "^0.23.10")
        #expect(vulnerability.fix(in: context) == .withinRange(package: "rustls", to: "0.23.45"))
    }

    @Test func `A fix outside the parent's requirement needs a newer parent first`() throws {
        let (_, context, vulnerability) = try repo(parentAsks: "=0.23.44")
        #expect(vulnerability.fix(in: context) == .blocked(
            package: "rustls", to: "0.23.45", by: .package(parent: "reqwest", parentRange: "=0.23.44", minimumParentVersion: "0.12.6")
        ))
    }

    @Test func `Without the parent's metadata the check asks for it`() throws {
        let (repo, _, _) = try repo(parentAsks: "^0.23.10")
        let report = VersionReport(checkedAt: .now, repos: [repo], latestPackages: [:], packageMetadata: [:])
        #expect(report.updateNeeds().packages.contains("crates.io:reqwest"))
    }

    // MARK: - Waarom onbekend

    @Test func `An unknown status names its real cause`() throws {
        let rustls = try dependency("rustls")
        #expect(rustls.install.update(ecosystem: "crates.io", name: "rustls", latest: nil).unknownReason == .latestNotLookedUp)
        let serde = try dependency("serde")
        #expect(serde.install.update(ecosystem: "crates.io", name: "serde", latest: nil).unknownReason == .noLatestVersion)
        let bare = PackageUpdate(ecosystem: "crates.io", name: "x", installed: "1.0.0", requested: nil, latest: "1.1.0")
        #expect(bare.status == .unknown)
        #expect(bare.unknownReason == .noRequirement)
        let unreadable = PackageUpdate(ecosystem: "crates.io", name: "x", installed: "1.0.0", requested: "latest", latest: "1.1.0")
        #expect(unreadable.unknownReason == .unreadableRequirement("latest"))
        let version = PackageUpdate(ecosystem: "crates.io", name: "x", installed: "nightly", requested: "1", latest: "1.1.0")
        #expect(version.unknownReason == .unreadableVersion)
        let known = PackageUpdate(ecosystem: "crates.io", name: "x", installed: "1.0.0", requested: "1", latest: "1.1.0")
        #expect(known.unknownReason == nil)
    }

    // MARK: - Cargo-eisen, 0.x en de rest

    @Test(arguments: [
        ("0.1.85", "0.1.85", true), ("0.1.85", "0.1.128", true), ("0.1.85", "0.2.0", false), ("0.1.85", "0.1.84", false),
        ("^0.1.85", "0.1.200", true), ("0.0.3", "0.0.3", true), ("0.0.3", "0.0.4", false), ("0.0", "0.0.9", true),
        ("0.0", "0.1.0", false), ("0", "0.9.9", true), ("0", "1.0.0", false), ("1.2", "1.9.0", true), ("1.2", "2.0.0", false),
        ("~0.2.3", "0.2.9", true), ("~0.2.3", "0.3.0", false), ("~1", "1.9.0", true), ("=0.1.85", "0.1.85", true),
        ("=0.1.85", "0.1.86", false), ("0.1.*", "0.1.200", true), ("0.1.*", "0.2.0", false), ("*", "3.0.0", true),
        (">=0.1, <0.3", "0.2.5", true), (">=0.1, <0.3", "0.3.0", false), ("1.0.200, 1.0.210", "1.0.228", true),
    ])
    func `Reads Cargo requirements`(requirement: String, version: String, allowed: Bool) throws {
        let range = try #require(CargoRequirement.parse(requirement))
        #expect(range.contains(version) == allowed)
    }

    @Test func `Several member requirements that fit the installed version all hold`() {
        let manifests = [
            "": DependencyDetector.cargoManifest("[workspace]\nmembers = [\"a\", \"b\"]\n"),
            "a": DependencyDetector.cargoManifest("[dependencies]\nserde = \"1.0.200\"\n"),
            "b": DependencyDetector.cargoManifest("[dependencies]\nserde = \"1.0.150\"\nold = \"0.1\"\n"),
        ]
        let declarations = DependencyDetector.cargoDeclarations(manifests)
        let serde = Dependency(ecosystem: "crates.io", name: "serde", version: "1.0.210", source: "Cargo.lock", workspace: "", scope: .direct)
        let found = DependencyDetector.cargoRequirement(of: serde, lockfolder: "", declarations: declarations, manifests: manifests)
        #expect(found.requested == "1.0.200, 1.0.150")
        #expect(found.kind == .runtime)
    }
}
